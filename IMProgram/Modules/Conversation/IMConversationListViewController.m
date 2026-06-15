//  IMConversationListViewController.m

#import "IMConversationListViewController.h"
#import "IMChatViewController.h"
#import "IMHTTPService.h"
#import "IMConversation.h"
#import "IMTheme.h"
#import "IMLog.h"

#pragma mark - 会话 Cell（Telegram 风格：圆形头像 + 名称/最后一条 + 时间 + 未读蓝胶囊）

static CGFloat const kIMAvatarSize = 52;
static CGFloat const kIMRowLeading = 16;

@interface IMConversationCell : UITableViewCell
- (void)configureWithConversation:(IMConversation *)c;
@end

@implementation IMConversationCell {
    UILabel *_avatar;
    UILabel *_name;
    UILabel *_last;
    UILabel *_time;
    UILabel *_badge;
    NSLayoutConstraint *_badgeWidth;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textColor = UIColor.whiteColor;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
        _avatar.layer.cornerRadius = kIMAvatarSize / 2;
        _avatar.layer.masksToBounds = YES;
        [self.contentView addSubview:_avatar];

        _name = [UILabel new];
        _name.translatesAutoresizingMaskIntoConstraints = NO;
        _name.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        _name.textColor = IMTheme.textPrimary;
        [self.contentView addSubview:_name];

        _last = [UILabel new];
        _last.translatesAutoresizingMaskIntoConstraints = NO;
        _last.font = [UIFont systemFontOfSize:15];
        _last.textColor = IMTheme.textSecondary;
        [self.contentView addSubview:_last];

        _time = [UILabel new];
        _time.translatesAutoresizingMaskIntoConstraints = NO;
        _time.font = [UIFont systemFontOfSize:13];
        _time.textColor = IMTheme.textSecondary;
        _time.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:_time];

        _badge = [UILabel new];
        _badge.translatesAutoresizingMaskIntoConstraints = NO;
        _badge.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _badge.textColor = UIColor.whiteColor;
        _badge.textAlignment = NSTextAlignmentCenter;
        _badge.backgroundColor = IMTheme.accent; // Telegram 未读用蓝色胶囊
        _badge.layer.cornerRadius = 10;
        _badge.layer.masksToBounds = YES;
        [self.contentView addSubview:_badge];

        [_time setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_time setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        _badgeWidth = [_badge.widthAnchor constraintEqualToConstant:0];

        UILayoutGuide *g = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kIMRowLeading],
            [_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:kIMAvatarSize],
            [_avatar.heightAnchor constraintEqualToConstant:kIMAvatarSize],

            [_name.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:12],
            [_name.topAnchor constraintEqualToAnchor:_avatar.topAnchor constant:2],
            [_name.trailingAnchor constraintLessThanOrEqualToAnchor:_time.leadingAnchor constant:-8],

            [_time.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_time.centerYAnchor constraintEqualToAnchor:_name.centerYAnchor],

            [_last.leadingAnchor constraintEqualToAnchor:_name.leadingAnchor],
            [_last.topAnchor constraintEqualToAnchor:_name.bottomAnchor constant:4],
            [_last.trailingAnchor constraintLessThanOrEqualToAnchor:_badge.leadingAnchor constant:-8],

            [_badge.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_badge.centerYAnchor constraintEqualToAnchor:_last.centerYAnchor],
            [_badge.heightAnchor constraintEqualToConstant:20],
            _badgeWidth,
        ]];
    }
    return self;
}

- (void)configureWithConversation:(IMConversation *)c {
    _avatar.text = c.peer.length >= 2 ? [c.peer substringFromIndex:c.peer.length - 2] : c.peer;
    _avatar.backgroundColor = [IMTheme avatarColorForSeed:c.peer];
    _name.text = c.peer;
    _last.text = c.lastContent.length > 0 ? c.lastContent : @"（无消息）";
    _time.text = [IMTheme timeStringFromMillis:c.timestamp];
    if (c.unread > 0) {
        _badge.hidden = NO;
        _badge.text = c.unread > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)c.unread];
        _badgeWidth.constant = MAX(20, [_badge sizeThatFits:CGSizeMake(CGFLOAT_MAX, 20)].width + 12);
    } else {
        _badge.hidden = YES;
        _badgeWidth.constant = 0;
    }
}

@end

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
    self.tableView.rowHeight = 76;
    // 分隔线左缩进对齐文字（不压头像下方），Telegram/微信式。
    self.tableView.separatorInset = UIEdgeInsetsMake(0, kIMRowLeading + kIMAvatarSize + 12, 0, 0);
    [self.tableView registerClass:IMConversationCell.class forCellReuseIdentifier:@"conv"];
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
    IMConversationCell *cell = [tableView dequeueReusableCellWithIdentifier:@"conv" forIndexPath:indexPath];
    [cell configureWithConversation:self.conversations[indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self openChatWithConversation:self.conversations[indexPath.row]];
}

@end
