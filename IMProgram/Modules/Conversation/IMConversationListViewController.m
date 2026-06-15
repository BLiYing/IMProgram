//  IMConversationListViewController.m

#import "IMConversationListViewController.h"
#import "IMChatViewController.h"
#import "IMHTTPService.h"
#import "IMConversation.h"
#import "IMTheme.h"
#import "IMLog.h"

@interface IMConversationListViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, strong) NSArray<IMConversation *> *conversations;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation IMConversationListViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        _conversations = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"会话";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose
                                                      target:self action:@selector(newChatTapped)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 64;
    [self.view addSubview:self.tableView];

    self.emptyLabel = [UILabel new];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = @"还没有会话，点右上角 ✎ 输入对方 uid 发起";
    self.emptyLabel.textColor = IMTheme.textSecondary;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:IMTheme.space4 * 2],
        [self.emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-IMTheme.space4 * 2],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

#pragma mark - 数据

- (void)reload {
    IMHTTPService.sharedService.host = self.host;
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (token.length == 0) {
            [self showError:[NSString stringWithFormat:@"登录失败：%@", error.localizedDescription]];
            return;
        }
        self.token = token;
        [IMHTTPService.sharedService conversationsWithToken:token completion:^(NSArray<IMConversation *> *convs, NSError *err) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            if (err) {
                [self showError:[NSString stringWithFormat:@"拉取会话失败：%@", err.localizedDescription]];
                return;
            }
            self.conversations = convs ?: @[];
            self.emptyLabel.hidden = self.conversations.count > 0;
            [self.tableView reloadData];
        }];
    }];
}

- (void)showError:(NSString *)message {
    IMLog(@"%@", message);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 交互

- (void)newChatTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"发起会话" message:@"输入对方 uid"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"对方 uid";
        tf.keyboardType = UIKeyboardTypeNumberPad;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"发起" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *peer = [alert.textFields.firstObject.text
                          stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [weakSelf openChatWithPeer:peer];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openChatWithPeer:(NSString *)peer {
    if (peer.length == 0 || [peer isEqualToString:self.userID]) {
        [self showError:@"请输入有效且不同于自己的对方 uid"];
        return;
    }
    // 从「发起会话」进入：新会话无已读位点/未读。
    IMChatViewController *chat = [[IMChatViewController alloc] initWithHost:self.host userID:self.userID
                                                                    peerID:peer readSeq:0 unread:0];
    [self.navigationController pushViewController:chat animated:YES];
}

/// 从会话列表进入：带 read_seq + unread，供聊天页定位未读分割线（CHAT_UX §3）。
- (void)openChatWithConversation:(IMConversation *)c {
    if (c.peer.length == 0 || [c.peer isEqualToString:self.userID]) { return; }
    IMChatViewController *chat = [[IMChatViewController alloc] initWithHost:self.host userID:self.userID
                                                                    peerID:c.peer readSeq:c.readSeq unread:c.unread];
    [self.navigationController pushViewController:chat animated:YES];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.conversations.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"conv"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"conv"];
    }
    IMConversation *c = self.conversations[indexPath.row];
    cell.textLabel.text = c.peer;
    cell.detailTextLabel.text = c.lastContent.length > 0 ? c.lastContent : @"（无消息）";
    cell.detailTextLabel.textColor = IMTheme.textSecondary;
    // 未读红点：unread>0 时用红色圆角徽标替代右侧箭头。
    if (c.unread > 0) {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = [self badgeViewForCount:c.unread];
    } else {
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self openChatWithConversation:self.conversations[indexPath.row]];
}

/// 红色未读徽标（>99 显示 99+）。
- (UIView *)badgeViewForCount:(NSInteger)count {
    UILabel *badge = [UILabel new];
    badge.text = count > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)count];
    badge.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    badge.textColor = UIColor.whiteColor;
    badge.textAlignment = NSTextAlignmentCenter;
    badge.backgroundColor = [UIColor colorWithRed:0.898 green:0.224 blue:0.208 alpha:1]; // #e53935
    CGFloat h = 20, w = MAX(h, [badge sizeThatFits:CGSizeMake(CGFLOAT_MAX, h)].width + 12);
    badge.frame = CGRectMake(0, 0, w, h);
    badge.layer.cornerRadius = h / 2;
    badge.layer.masksToBounds = YES;
    return badge;
}

@end
