//  IMGroupListViewController.m

#import "IMGroupListViewController.h"
#import "IMLocalization.h"
#import "IMGroupCreateViewController.h"
#import "IMChatViewController.h"
#import "IMHTTPService.h"
#import "IMSocketManager.h"
#import "IMReconnectReloader.h"
#import "IMGroupInfo.h"
#import "IMDatabase.h"
#import "IMDatabase+RosterCache.h"
#import "UILabel+IMAvatar.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import "IMAccountIdentity.h"
#import "IMRemarkStore.h"
#import "IMLog.h"
#import "IMNavigationButton.h"

#pragma mark - 群行 Cell（首字母/头像圈 + 群名 + 群主副标题）

static CGFloat const kIMGroupAvatarSize = 44;

@interface IMGroupRowCell : UITableViewCell
- (void)configureWithGroup:(IMGroupInfo *)group mine:(BOOL)mine;
@end

@implementation IMGroupRowCell {
    UILabel *_avatar;
    UILabel *_name;
    UILabel *_sub;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textColor = UIColor.whiteColor;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        _avatar.layer.cornerRadius = kIMGroupAvatarSize / 2;
        _avatar.layer.masksToBounds = YES;
        [self.contentView addSubview:_avatar];

        _name = [UILabel new];
        _name.translatesAutoresizingMaskIntoConstraints = NO;
        _name.font = [UIFont systemFontOfSize:17];
        _name.textColor = IMTheme.textPrimary;
        [self.contentView addSubview:_name];

        _sub = [UILabel new];
        _sub.translatesAutoresizingMaskIntoConstraints = NO;
        _sub.font = [UIFont systemFontOfSize:13];
        _sub.textColor = IMTheme.textSecondary;
        [self.contentView addSubview:_sub];

        UILayoutGuide *g = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
            [_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:kIMGroupAvatarSize],
            [_avatar.heightAnchor constraintEqualToConstant:kIMGroupAvatarSize],
            [_name.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:IMTheme.space3],
            [_name.topAnchor constraintEqualToAnchor:_avatar.topAnchor constant:2],
            [_name.trailingAnchor constraintLessThanOrEqualToAnchor:g.trailingAnchor],
            [_sub.leadingAnchor constraintEqualToAnchor:_name.leadingAnchor],
            [_sub.topAnchor constraintEqualToAnchor:_name.bottomAnchor constant:2],
            [_sub.trailingAnchor constraintLessThanOrEqualToAnchor:g.trailingAnchor],
        ]];
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}

- (void)configureWithGroup:(IMGroupInfo *)group mine:(BOOL)mine {
    [_avatar im_setAvatarURL:group.avatarURL seed:group.convID displayName:group.name];
    _name.text = group.name.length > 0 ? group.name : IMLocalized(@"common.group_chat");
    // 群主名走全端统一口径 `备注 → 昵称 → @username → 未命名用户`。
    // **不能直接显示 group.owner**——那是 10 位随机内部 ID（IMServer/docs/design/
    // ACCOUNT_IDENTITY_REDESIGN.md §7.5「内部 ID 零 UI 露出」）。
    if (mine) {
        _sub.text = IMLocalized(@"group.list.i_am_owner");
    } else {
        NSString *ownerName = [IMRemarkStore.sharedStore displayNameForUser:group.owner
                                                                   fallback:IMDisplayName(group.ownerNickname, group.ownerUsername)];
        _sub.text = IMLocalizedFormat(@"group.list.owner", ownerName ?: @"");
    }
}

@end

#pragma mark - 群列表页

@interface IMGroupListViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, strong) NSArray<IMGroupInfo *> *groups;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong, nullable) IMDatabaseAccountContext *databaseContext; // 任务5：本地缓存账号隔离
@property (nonatomic, strong) IMReconnectReloader *reconnectReloader;              // 重连即取权威（可见时）
@end

@implementation IMGroupListViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        // 任务5：本地缓存优先——先用上次落库的群组种子渲染，断网也能看到，联网成功再权威覆盖。
        IMDatabaseAccountContext *context = IMDatabase.sharedDatabase.currentAccountContext;
        _databaseContext = [context.ownerUserID isEqualToString:userID] ? context : nil;
        __block NSArray<IMGroupInfo *> *cachedGroups = @[];
        [IMDatabase.sharedDatabase performWithAccountContext:_databaseContext block:^(IMDatabase *database) {
            cachedGroups = database.cachedGroups;
        }];
        _groups = cachedGroups;
        self.hidesBottomBarWhenPushed = YES;
        // 重连即取权威列表（断网期间看的是缓存种子）。仅可见时刷新。
        __weak typeof(self) ws = self;
        _reconnectReloader = [[IMReconnectReloader alloc] initWithReloadBlock:^{ [ws reload]; }];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"common.group_chat");
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    // 与通讯录入口保持一致，交给系统导航栏生成标准 Liquid Glass 按钮和按压反馈。
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus"]
                                         style:UIBarButtonItemStylePlain
                                        target:self action:@selector(createTapped)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 64;
    [self.tableView registerClass:IMGroupRowCell.class forCellReuseIdentifier:@"group"];
    [self.view addSubview:self.tableView];

    self.emptyLabel = [UILabel new];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = IMLocalized(@"group.list.empty_hint");
    self.emptyLabel.textColor = IMTheme.textSecondary;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.reconnectReloader.visible = YES;
    [self reload];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    self.reconnectReloader.visible = NO;
}

- (void)reload {
    IMHTTPService.sharedService.host = self.host;
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (token.length == 0) {
            IMLog(@"群聊列表刷新登录失败（保留当前内容）：%@", error.localizedDescription ?: @"未知错误");
            return;
        }
        [IMHTTPService.sharedService groupsWithToken:token completion:^(NSArray<IMGroupInfo *> *groups, NSError *err) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            if (err) {
                IMLog(@"群聊列表刷新失败（保留当前内容）：%@", err.localizedDescription ?: @"未知错误");
                return;
            }
            self.groups = groups ?: @[];
            self.emptyLabel.hidden = self.groups.count > 0;
            [self.tableView reloadData];
            // 任务5：权威群组列表落库，供下次断网离线首屏。空数组也写（当前账号无群）。
            NSArray<IMGroupInfo *> *snapshot = self.groups;
            [IMDatabase.sharedDatabase performWithAccountContext:self.databaseContext block:^(IMDatabase *database) {
                [database replaceCachedGroups:snapshot];
            }];
        }];
    }];
}

#pragma mark - 建群（选好友「下一步」→ 建群资料页 → POST → 进群聊）

/// 两步流的编排收在 IMGroupCreateViewController（会话列表页那个入口用的是同一个），
/// 本页只提供"建完之后去哪"。原先这里有一份「alert 输群名 + POST」的实现，
/// 与 IMConversationListViewController 里那份几乎逐字重复，已一并删除。
- (void)createTapped {
    __weak typeof(self) weakSelf = self;
    [IMGroupCreateViewController startInNavigationController:self.navigationController
                                                        host:self.host userID:self.userID
                                                   onCreated:^(IMGroupInfo *group) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        // 回到群列表页并直接进入新群会话。
        [self.navigationController popToViewController:self animated:NO];
        [self reload];
        [self openGroupChat:group];
    }];
}

- (void)openGroupChat:(IMGroupInfo *)group {
    [IMChatViewController openInNavigationController:self.navigationController
                                                host:self.host userID:self.userID
                                         groupConvID:group.convID groupName:group.name
                                             readSeq:0 unread:0
                                        groupReadSeq:0 // 群列表入口无会话快照，全员已读位点由再次从会话列表进入时播种
                                      groupAvatarURL:group.avatarURL]; // 透传头像免闪首字母
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.groups.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMGroupRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"group" forIndexPath:indexPath];
    IMGroupInfo *g = self.groups[indexPath.row];
    [cell configureWithGroup:g mine:[g.owner isEqualToString:self.userID]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self openGroupChat:self.groups[indexPath.row]];
}

@end
