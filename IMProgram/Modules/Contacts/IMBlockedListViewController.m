//  IMBlockedListViewController.m
//  隐私与安全 · 已屏蔽的用户（对齐 Telegram：标题「已屏蔽的用户」+ 顶部说明 + 左滑取消屏蔽 + 空态三层）。
//  设计见 IMServer/docs/PRIVACY_SECURITY_DESIGN.md §3；草图 §2。

#import "IMBlockedListViewController.h"
#import "IMContactCells.h"
#import "IMHTTPService.h"
#import "IMUserCard.h"
#import "IMTheme.h"
#import "IMLog.h"

@interface IMBlockedListViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy, nullable) NSString *token;
@property (nonatomic, strong) NSArray<IMUserCard *> *blocked;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *emptyView;   ///< 空态三层：图标 + 大标题 + 副标题
@end

@implementation IMBlockedListViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        _blocked = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"已屏蔽的用户"; // 对齐 Telegram 中文版
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    // Inset-Grouped 承载列表；顶部说明走 section footer（放 section 0 的 footer 太远，用 tableHeaderView 更贴近首行）。
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 60; // §5.3 头像 44 + padding
    [self.tableView registerClass:IMContactCell.class forCellReuseIdentifier:@"blocked"];
    self.tableView.tableHeaderView = [self buildHeaderView];
    [self.view addSubview:self.tableView];

    // 空态覆盖层（列表为空时显）。
    self.emptyView = [self buildEmptyView];
    self.emptyView.hidden = YES;
    [self.view addSubview:self.emptyView];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.emptyView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.emptyView.topAnchor      constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.emptyView.bottomAnchor   constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

#pragma mark - Header / Empty

/// tableHeaderView：一行灰字说明（对齐 Telegram），与列表顶端 8pt 留白。
- (UIView *)buildHeaderView {
    UIView *host = [UIView new];
    host.frame = CGRectMake(0, 0, self.view.bounds.size.width, 60);
    UILabel *hint = [UILabel new];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    hint.numberOfLines = 0;
    hint.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; // 13pt
    hint.textColor = UIColor.secondaryLabelColor;
    hint.text = @"已屏蔽的用户不能给你发消息，也看不到你的资料。";
    [host addSubview:hint];
    [NSLayoutConstraint activateConstraints:@[
        [hint.leadingAnchor  constraintEqualToAnchor:host.leadingAnchor  constant:32],
        [hint.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-32],
        [hint.topAnchor      constraintEqualToAnchor:host.topAnchor      constant:12],
        [hint.bottomAnchor   constraintEqualToAnchor:host.bottomAnchor   constant:-12],
    ]];
    // header 允许 autoresize 高度（避免 iOS 早期版本 tableHeaderView 不自适应）。
    [host setNeedsLayout];
    [host layoutIfNeeded];
    CGFloat h = [host systemLayoutSizeFittingSize:CGSizeMake(self.view.bounds.size.width, UILayoutFittingCompressedSize.height)].height;
    host.frame = CGRectMake(0, 0, self.view.bounds.size.width, h);
    return host;
}

/// 空态三层：SF `nosign` 72pt gray3 + 20pt semibold 大标题 + 13pt 副标题。
- (UIView *)buildEmptyView {
    UIView *host = [UIView new];
    host.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *icon = [UIImageView new];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:72 weight:UIImageSymbolWeightRegular];
    icon.image = [[UIImage systemImageNamed:@"nosign"] imageByApplyingSymbolConfiguration:cfg];
    icon.tintColor = UIColor.systemGray3Color;
    [host addSubview:icon];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
    title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    title.textColor = UIColor.labelColor;
    title.text = @"暂无已屏蔽的用户";
    [host addSubview:title];

    UILabel *sub = [UILabel new];
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    sub.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    sub.textColor = UIColor.secondaryLabelColor;
    sub.text = @"你在通讯录或聊天页拉黑对方后，会出现在这里。";
    sub.numberOfLines = 0;
    sub.textAlignment = NSTextAlignmentCenter;
    [host addSubview:sub];

    [NSLayoutConstraint activateConstraints:@[
        [icon.centerXAnchor constraintEqualToAnchor:host.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:host.centerYAnchor constant:-40],

        [title.centerXAnchor constraintEqualToAnchor:host.centerXAnchor],
        [title.topAnchor     constraintEqualToAnchor:icon.bottomAnchor constant:16],

        [sub.leadingAnchor  constraintEqualToAnchor:host.leadingAnchor  constant:30],
        [sub.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-30],
        [sub.topAnchor      constraintEqualToAnchor:title.bottomAnchor  constant:6],
    ]];
    return host;
}

#pragma mark - 数据

- (void)reload {
    IMHTTPService.sharedService.host = self.host;
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (token.length == 0) {
            IMLog(@"已屏蔽用户刷新登录失败（保留当前内容）：%@", error.localizedDescription ?: @"未知错误");
            return;
        }
        self.token = token;
        [IMHTTPService.sharedService friendsWithToken:token status:@"blocked" completion:^(NSArray<IMUserCard *> *list, NSError *err) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            if (err) {
                IMLog(@"已屏蔽用户刷新失败（保留当前内容）：%@", err.localizedDescription ?: @"未知错误");
                return;
            }
            self.blocked = list ?: @[];
            [self reloadPresentation];
        }];
    }];
}

- (void)reloadPresentation {
    BOOL empty = self.blocked.count == 0;
    self.emptyView.hidden = !empty;
    self.tableView.hidden = empty; // 空态时隐 tableView，避免与说明 header 抢视觉焦点
    [self.tableView reloadData];
}

- (void)unblockPeer:(NSString *)peerID completion:(nullable void (^)(BOOL ok))completion {
    if (self.token.length == 0 || peerID.length == 0) {
        if (completion) { completion(NO); }
        return;
    }
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService friendActionWithToken:self.token action:@"unblock" peerID:peerID completion:^(NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { if (completion) { completion(NO); } return; }
        if (error) {
            [self showError:[NSString stringWithFormat:@"取消屏蔽失败：%@", error.localizedDescription]];
            if (completion) { completion(NO); }
            return;
        }
        if (completion) { completion(YES); }
        [self reload]; // 拿服务端权威数据回来（顺带更新空态）
    }];
}

- (void)showError:(NSString *)message {
    IMLog(@"%@", message);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.blocked.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMContactCell *cell = [tableView dequeueReusableCellWithIdentifier:@"blocked" forIndexPath:indexPath];
    IMUserCard *c = self.blocked[indexPath.row];
    [cell configureWithCard:c subtitle:c.userID];
    // 行内旧的「解除」按钮改为不显——用左滑取消屏蔽（Telegram 一致）；点行进单聊资料页更自然。
    [cell setActionTitle:nil enabled:NO action:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= (NSInteger)self.blocked.count) { return nil; }
    NSString *peerID = self.blocked[indexPath.row].userID;
    __weak typeof(self) ws = self;
    UIContextualAction *unblock = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                          title:@"取消屏蔽"
                                                                        handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull done)(BOOL)) {
        [ws unblockPeer:peerID completion:^(BOOL ok) { done(ok); }];
    }];
    unblock.backgroundColor = UIColor.systemRedColor;
    UISwipeActionsConfiguration *cfg = [UISwipeActionsConfiguration configurationWithActions:@[unblock]];
    cfg.performsFirstActionWithFullSwipe = YES;
    return cfg;
}

@end
