//  IMConversationListViewController.m

#import "IMConversationListViewController.h"
#import "IMChatViewController.h"
#import "IMLoginViewController.h"
#import "IMHTTPService.h"
#import "IMSocketManager.h"
#import "IMSessionStore.h"
#import "IMDatabase.h"
#import "IMConversation.h"
#import "IMMenuAction.h"
#import "IMAnimator.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import "UILabel+IMAvatar.h"
#import "IMLog.h"
#import "IMUserSearchViewController.h"
#import "IMGroupMemberPickerViewController.h"
#import "IMGroupInfo.h"

#pragma mark - 会话 Cell（Telegram 风格：圆形头像 + 名称/最后一条 + 时间 + 未读蓝胶囊）

static CGFloat const kIMAvatarSize = 52;
static CGFloat const kIMRowLeading = 16;

@interface IMConversationCell : UITableViewCell
- (void)configureWithConversation:(IMConversation *)c mine:(BOOL)mine;
@end

@implementation IMConversationCell {
    UILabel *_avatar;
    UILabel *_name;
    UILabel *_last;
    UILabel *_time;
    UILabel *_check;   // 最后一条是我发的 → 时间左侧显示 ✓✓（绿）
    UILabel *_badge;
    UIView *_dot;      // 手动"标未读"小圆点（无未读数时显示，M4.5）
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

        _check = [UILabel new];
        _check.translatesAutoresizingMaskIntoConstraints = NO;
        _check.font = [UIFont systemFontOfSize:13];
        _check.textColor = IMTheme.checkRead;
        _check.text = @"✓✓";
        [self.contentView addSubview:_check];

        _badge = [UILabel new];
        _badge.translatesAutoresizingMaskIntoConstraints = NO;
        _badge.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _badge.textColor = UIColor.whiteColor;
        _badge.textAlignment = NSTextAlignmentCenter;
        _badge.backgroundColor = IMTheme.unreadBadge; // Telegram 未读用蓝色胶囊（区别于绿在线点/绿勾）
        _badge.layer.cornerRadius = 10;
        _badge.layer.masksToBounds = YES;
        [self.contentView addSubview:_badge];

        _dot = [UIView new];
        _dot.translatesAutoresizingMaskIntoConstraints = NO;
        _dot.backgroundColor = IMTheme.unreadBadge;
        _dot.layer.cornerRadius = 5;
        _dot.layer.masksToBounds = YES;
        _dot.hidden = YES;
        [self.contentView addSubview:_dot];

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

            [_check.trailingAnchor constraintEqualToAnchor:_time.leadingAnchor constant:-4],
            [_check.centerYAnchor constraintEqualToAnchor:_time.centerYAnchor],

            [_last.leadingAnchor constraintEqualToAnchor:_name.leadingAnchor],
            [_last.topAnchor constraintEqualToAnchor:_name.bottomAnchor constant:4],
            [_last.trailingAnchor constraintLessThanOrEqualToAnchor:_badge.leadingAnchor constant:-8],

            [_badge.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_badge.centerYAnchor constraintEqualToAnchor:_last.centerYAnchor],
            [_badge.heightAnchor constraintEqualToConstant:20],
            _badgeWidth,

            [_dot.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_dot.centerYAnchor constraintEqualToAnchor:_last.centerYAnchor],
            [_dot.widthAnchor constraintEqualToConstant:10],
            [_dot.heightAnchor constraintEqualToConstant:10],
        ]];
    }
    return self;
}

- (void)configureWithConversation:(IMConversation *)c mine:(BOOL)mine {
    // 撤回预览（M4-1，后端已脱敏 content）：优先显示"撤回了一条消息"，不加"昵称:"前缀（微信式）。
    NSString *recalledPreview = nil;
    if (c.lastRecalled) {
        NSString *who = mine ? @"你" : (c.isGroup ? (c.lastFromNickname.length > 0 ? c.lastFromNickname : (c.lastFrom ?: @"")) : @"对方");
        recalledPreview = [NSString stringWithFormat:@"%@撤回了一条消息", who];
    }
    // 富媒体预览（M4-6）：图片/视频/文件显示占位标签而非 URL（微信式，不加昵称前缀）。
    if (!recalledPreview) {
        NSDictionary *mediaNames = @{ @"image": @"[图片]", @"video": @"[视频]", @"file": @"[文件]",
                                      @"chat_record": @"[聊天记录]",
                                      @"audio": @"[语音]", @"location": @"[位置]" }; // 语音/位置等类型落地后自动生效
        recalledPreview = mediaNames[c.lastContentType ?: @""];
    }
    if (c.isGroup) {
        // 群项：群名/群头像；预览"昵称: 内容"；不显示 presence/✓✓（群无对端已读位点）。
        NSString *display = c.name.length > 0 ? c.name : @"群聊";
        [_avatar im_setAvatarURL:c.avatarURL seed:c.convID displayName:display];
        _name.text = display;
        if (recalledPreview) {
            _last.text = recalledPreview;
        } else if (c.lastContent.length > 0) {
            NSString *who = mine ? @"我" : (c.lastFromNickname.length > 0 ? c.lastFromNickname : (c.lastFrom ?: @""));
            _last.text = who.length > 0 ? [NSString stringWithFormat:@"%@: %@", who, c.lastContent] : c.lastContent;
        } else {
            _last.text = @"（无消息）";
        }
    } else {
        NSString *display = c.peerNickname.length ? c.peerNickname : c.peer; // 显示名/首字母与通讯录一致
        [_avatar im_setAvatarURL:c.peerAvatarURL seed:c.peer displayName:display]; // 有头像渲图，否则首字母圈
        _name.text = display;
        _last.text = recalledPreview ?: (c.lastContent.length > 0 ? c.lastContent : @"（无消息）");
    }
    // 会话管理指示（M4.5）：置顶 pin.fill 前缀、免打扰 bell.slash.fill 后缀（SF Symbol，随字号对齐）。
    [self decorateName:(_name.text ?: @"") pinned:(c.pinnedAt > 0) muted:c.muted];
    // 置顶行背景轻微区分（微信/Telegram 式，深浅色皆适配）。
    self.contentView.backgroundColor = c.pinnedAt > 0 ? [IMTheme.accent colorWithAlphaComponent:0.10] : UIColor.clearColor;
    _time.text = [IMTheme timeStringFromMillis:c.timestamp];
    // 最后一条是我发的才显示勾：对端已读到该条 → 绿 ✓✓；否则 → 灰单勾 ✓（已送达/未读）。
    // 已读判定用后端返回的对端已读位点 peer_read_seq（CHAT_UX §8）。群项不显示（无对端位点）。
    BOOL showCheck = !c.isGroup && mine && c.lastContent.length > 0;
    _check.hidden = !showCheck;
    if (showCheck) {
        BOOL read = c.latestConvSeq > 0 && c.latestConvSeq <= c.peerReadSeq;
        _check.text = read ? @"✓✓" : @"✓";
        _check.textColor = read ? IMTheme.checkRead : IMTheme.textSecondary;
    }
    // 未读计数徽标 + 手动"标未读"圆点：免打扰会话转灰（微信/Telegram 式弱提示），否则蓝色。
    UIColor *unreadColor = c.muted ? UIColor.systemGrayColor : IMTheme.unreadBadge;
    _badge.backgroundColor = unreadColor;
    _dot.backgroundColor = unreadColor;
    if (c.unread > 0) {
        // 真实未读数：蓝色胶囊带数字。
        _badge.hidden = NO;
        _dot.hidden = YES;
        _badge.text = c.unread > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)c.unread];
        _badgeWidth.constant = MAX(20, [_badge sizeThatFits:CGSizeMake(CGFLOAT_MAX, 20)].width + 12);
    } else if (c.markedUnread) {
        // 手动"标未读"：无未读数（读位点已推进），仅显小圆点提示（微信式，无数字）。
        _badge.hidden = YES;
        _badgeWidth.constant = 0;
        _dot.hidden = NO;
    } else {
        _badge.hidden = YES;
        _badgeWidth.constant = 0;
        _dot.hidden = YES;
    }
}

/// 用 SF Symbol 装饰会话名：置顶 pin.fill 前缀、免打扰 bell.slash.fill 后缀（随字号对齐，紧凑间距）。
- (void)decorateName:(NSString *)display pinned:(BOOL)pinned muted:(BOOL)muted {
    if (!pinned && !muted) { _name.text = display; return; } // 无装饰：走普通文本，避免多余开销
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    CGFloat cap = _name.font.capHeight; // 图标垂直居中于 cap 高度，与文字基线对齐
    NSMutableAttributedString *s = [NSMutableAttributedString new];
    if (pinned) {
        UIImage *pin = [[UIImage systemImageNamed:@"pin.fill" withConfiguration:cfg]
                        imageWithTintColor:IMTheme.accent renderingMode:UIImageRenderingModeAlwaysOriginal];
        if (pin) {
            NSTextAttachment *a = [NSTextAttachment new];
            a.image = pin;
            a.bounds = CGRectMake(0, (cap - pin.size.height) / 2.0, pin.size.width, pin.size.height);
            [s appendAttributedString:[NSAttributedString attributedStringWithAttachment:a]];
            [s appendAttributedString:[[NSAttributedString alloc] initWithString:@" "]]; // 窄空格，避免"间隔太远"
        }
    }
    [s appendAttributedString:[[NSAttributedString alloc] initWithString:display]];
    if (muted) {
        [s appendAttributedString:[[NSAttributedString alloc] initWithString:@" "]];
        UIImage *bell = [[UIImage systemImageNamed:@"bell.slash.fill" withConfiguration:cfg]
                         imageWithTintColor:IMTheme.textSecondary renderingMode:UIImageRenderingModeAlwaysOriginal];
        if (bell) {
            NSTextAttachment *a = [NSTextAttachment new];
            a.image = bell;
            a.bounds = CGRectMake(0, (cap - bell.size.height) / 2.0, bell.size.width, bell.size.height);
            [s appendAttributedString:[NSAttributedString attributedStringWithAttachment:a]];
        }
    }
    [s addAttributes:@{ NSFontAttributeName: _name.font, NSForegroundColorAttributeName: IMTheme.textPrimary }
              range:NSMakeRange(0, s.length)];
    _name.attributedText = s;
}

@end

@interface IMConversationListViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, strong) NSArray<IMConversation *> *conversations;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, assign) BOOL visible; // 在屏时才响应新消息刷新（避免进聊天页时无谓拉取）
@property (nonatomic, strong) NSMutableSet<NSString *> *trackedConvIDs; // 已登记增量同步的会话（每会话只登记一次）
@property (nonatomic, assign) BOOL authPromptActive;  // 鉴权失效提示框正显示中（防叠框）
@property (nonatomic, assign) BOOL authDismissed;     // 用户已选"取消"留看缓存 → 本会话不再提示
@end

@implementation IMConversationListViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        _conversations = @[];
        _trackedConvIDs = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"会话";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    // 右上角 ＋：点击在按钮正下方弹出菜单（UIMenu，系统锚定+箭头），三项——新建群聊 / 添加好友 / 扫一扫。
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus"] menu:[self composeMenu]];

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
    self.emptyLabel.text = @"还没有会话，点右上角 ＋ 新建群聊或添加好友";
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
    self.visible = YES;
    // 保持长连接在会话列表常驻：收到任意会话新消息即实时刷新未读/最后一条（不必切 Tab）。
    [IMSocketManager.sharedManager connectToHost:self.host userID:self.userID];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onSocketMessage:)
                                               name:IMSocketDidReceiveMessageNotification object:nil];
    // 已读回执（对端已读→我发的✓✓；本人多端已读→未读清零）也触发列表刷新。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onSocketMessage:)
                                               name:IMSocketDidReceiveReadNotification object:nil];
    // 群变更（邀请/移除/退群/改名）→ 列表刷新（被移出的群随服务端订阅删除而消失）。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onSocketMessage:)
                                               name:IMSocketDidReceiveGroupEventNotification object:nil];
    // 会话级设置变更（置顶/免打扰/标未读/删除会话，M4.5）→ 列表刷新（本人其他端操作的多端同步）。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onSocketMessage:)
                                               name:IMSocketDidUpdateConversationNotification object:nil];
    // 连接状态变化 → 标题显示 连接中/未连接（取代"任何失败都弹框"）。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onSocketState:)
                                               name:IMSocketDidChangeStateNotification object:nil];
    [self updateTitleForState:IMSocketManager.sharedManager.state];
    [self reload];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.visible = NO;
    [NSNotificationCenter.defaultCenter removeObserver:self name:IMSocketDidReceiveMessageNotification object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self name:IMSocketDidReceiveReadNotification object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self name:IMSocketDidReceiveGroupEventNotification object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self name:IMSocketDidUpdateConversationNotification object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self name:IMSocketDidChangeStateNotification object:nil];
}

/// 连接状态 → 标题后缀（连接中/未连接），网络问题不再弹框。
- (void)onSocketState:(NSNotification *)note {
    [self updateTitleForState:(IMSocketState)[note.userInfo[@"state"] integerValue]];
}

- (void)updateTitleForState:(IMSocketState)state {
    switch (state) {
        case IMSocketStateConnecting:   self.title = @"会话（连接中…）"; break;
        case IMSocketStateDisconnected: self.title = @"会话（未连接）"; break;
        default:                        self.title = @"会话"; break;
    }
}

/// 收到新消息（任意会话）→ 节流刷新列表（合并连发的多条，避免每条都拉一次）。
- (void)onSocketMessage:(NSNotification *)note {
    if (!self.visible) { return; }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil];
    [self performSelector:@selector(reload) withObject:nil afterDelay:0.4];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

#pragma mark - 数据

- (void)reload {
    IMHTTPService.sharedService.host = self.host;
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (token.length == 0) {
            // 鉴权失败（账号没了/密码错/token 失效）→ 退回登录页重新登录；
            // 网络失败（连不上）→ 不弹框，标题已显"未连接"，靠 socket 自动重连。
            if (IMIsAuthErrorCode(error.code)) {
                [self promptAuthExpired:error.localizedDescription];
            }
            return;
        }
        self.token = token;
        [IMHTTPService.sharedService conversationsWithToken:token completion:^(NSArray<IMConversation *> *convs, NSError *err) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            if (err) {
                // 登录已成功、拉会话失败多为网络抖动 → 不弹框（保留当前列表，靠下次刷新/重连恢复）。
                IMLog(@"拉取会话失败（忽略，不弹框）：%@", err.localizedDescription);
                return;
            }
            self.conversations = convs ?: @[];
            self.emptyLabel.hidden = self.conversations.count > 0;
            [self.tableView reloadData];
            [self trackConversationsForSync]; // 登记会话用于（重）连后增量同步，补拉离线消息
        }];
    }];
}

/// 把会话登记到长连接的增量同步集（每会话仅一次）：以本地已存最大 conv_seq 为起点，
/// （重）连后自动 sync_req 补拉离线消息。修复"登录后停在会话列表，对端离线期间发的消息不入库，
/// 之后开聊天页因 synced 已被实时消息推过而漏拉"。
- (void)trackConversationsForSync {
    for (IMConversation *c in self.conversations) {
        if (c.convID.length == 0 || [self.trackedConvIDs containsObject:c.convID]) { continue; }
        [self.trackedConvIDs addObject:c.convID];
        int64_t synced = [IMDatabase.sharedDatabase maxConvSeqForConv:c.convID];
        [IMSocketManager.sharedManager trackConversation:c.convID syncedSeq:synced];
    }
}

- (void)showError:(NSString *)message {
    IMLog(@"%@", message);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

/// 鉴权失效（账号不存在/密码错/被封/token 失效）→ 弹框让用户选：重新登录 / 取消(留看本地缓存)。
/// 只提示一次（authPromptActive 防叠框、authDismissed 防刷屏），不强制踢走。
- (void)promptAuthExpired:(NSString *)reason {
    if (self.authPromptActive || self.authDismissed) { return; }
    self.authPromptActive = YES;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"登录已失效"
        message:[NSString stringWithFormat:@"%@。可重新登录；或取消，继续查看本地聊天记录。", reason]
        preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"重新登录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        weakSelf.authPromptActive = NO;
        [weakSelf bounceToLogin];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
        weakSelf.authPromptActive = NO;
        weakSelf.authDismissed = YES;                 // 本会话不再提示，留看缓存
        [IMSocketManager.sharedManager disconnect];   // 停止自动重连风暴
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

/// 真正退回登录页（断连 + 替换根控制器）。
- (void)bounceToLogin {
    UIWindow *window = self.view.window;
    if (!window) { return; }
    [IMSocketManager.sharedManager disconnect];
    [IMSessionStore clear]; // 鉴权失效退回登录：清持久化会话，避免下次启动又静默重登失败
    IMLoginViewController *login = [IMLoginViewController new];
    window.rootViewController = [[UINavigationController alloc] initWithRootViewController:login];
}

#pragma mark - 交互

/// 右上角 ＋ 的下拉菜单：新建群聊 / 添加好友 / 扫一扫（扫一扫待开发，先占位提示）。
- (UIMenu *)composeMenu {
    __weak typeof(self) weakSelf = self;
    UIAction *newGroup = [UIAction actionWithTitle:@"新建群聊"
        image:[UIImage systemImageNamed:@"person.3"] identifier:nil
        handler:^(__kindof UIAction *a) { [weakSelf startNewGroup]; }];
    UIAction *addFriend = [UIAction actionWithTitle:@"添加好友"
        image:[UIImage systemImageNamed:@"person.badge.plus"] identifier:nil
        handler:^(__kindof UIAction *a) { [weakSelf openAddFriend]; }];
    UIAction *scan = [UIAction actionWithTitle:@"扫一扫"
        image:[UIImage systemImageNamed:@"qrcode.viewfinder"] identifier:nil
        handler:^(__kindof UIAction *a) { [weakSelf im_showToast:@"扫一扫功能开发中"]; }];
    return [UIMenu menuWithTitle:@"" children:@[newGroup, addFriend, scan]];
}

/// 新建群聊：选好友 → 起群名 → 建群 → 直接进入新群会话（复用通讯录群聊页同一流程）。
- (void)startNewGroup {
    __weak typeof(self) weakSelf = self;
    IMGroupMemberPickerViewController *picker =
        [[IMGroupMemberPickerViewController alloc] initWithHost:self.host userID:self.userID
                                                    excludedIDs:nil confirmTitle:@"创建"
                                                         onDone:^(NSArray<NSString *> *selectedIDs) {
            [weakSelf promptGroupNameForMembers:selectedIDs];
        }];
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)promptGroupNameForMembers:(NSArray<NSString *> *)memberIDs {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"群名" message:@"1~30 字"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"给群起个名字"; }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *name = [alert.textFields.firstObject.text
                          stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [weakSelf createGroupNamed:name members:memberIDs];
    }]];
    [self.navigationController.topViewController presentViewController:alert animated:YES completion:nil];
}

- (void)createGroupNamed:(NSString *)name members:(NSArray<NSString *> *)memberIDs {
    UIViewController *top = self.navigationController.topViewController;
    if (name.length == 0) { [top im_showToast:@"请输入群名"]; return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [top im_showToast:@"未登录"]; return; }
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService createGroupWithToken:token name:name memberIDs:memberIDs
                                           completion:^(IMGroupInfo *group, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (error || !group) {
            [self.navigationController.topViewController im_showToast:
                [NSString stringWithFormat:@"建群失败：%@", error.localizedDescription ?: @"未知错误"]];
            return;
        }
        // 回到会话列表，再直接进入新群会话。
        [self.navigationController popToViewController:self animated:NO];
        IMChatViewController *chat = [[IMChatViewController alloc] initWithHost:self.host userID:self.userID
                                                                    groupConvID:group.convID groupName:group.name
                                                                        readSeq:0 unread:0];
        [self.navigationController pushViewController:chat animated:YES];
    }];
}

/// 添加好友：进找人页（搜索 uid/手机号 → 申请）。
- (void)openAddFriend {
    IMUserSearchViewController *search = [[IMUserSearchViewController alloc] initWithHost:self.host userID:self.userID];
    [self.navigationController pushViewController:search animated:YES];
}

- (void)openChatWithPeer:(NSString *)peer {
    if (peer.length == 0 || [peer isEqualToString:self.userID]) {
        [self showError:@"请输入有效且不同于自己的对方 uid"];
        return;
    }
    // 从「发起会话」进入：新会话无已读位点/未读/对端已读位点。
    IMChatViewController *chat = [[IMChatViewController alloc] initWithHost:self.host userID:self.userID
                                                                    peerID:peer readSeq:0 unread:0 peerReadSeq:0];
    [self.navigationController pushViewController:chat animated:YES];
}

/// 从会话列表进入：带 read_seq + unread + peer_read_seq，供聊天页定位未读分割线 + 可见即读起点 + 进会话即显对端已读（CHAT_UX §3/§6/§8）。
- (void)openChatWithConversation:(IMConversation *)c {
    if (c.isGroup) {
        IMChatViewController *chat = [[IMChatViewController alloc] initWithHost:self.host userID:self.userID
                                                                    groupConvID:c.convID groupName:c.name
                                                                        readSeq:c.readSeq unread:c.unread];
        [self.navigationController pushViewController:chat animated:YES];
        return;
    }
    if (c.peer.length == 0 || [c.peer isEqualToString:self.userID]) { return; }
    IMChatViewController *chat = [[IMChatViewController alloc] initWithHost:self.host userID:self.userID
                                                                    peerID:c.peer readSeq:c.readSeq unread:c.unread
                                                               peerReadSeq:c.peerReadSeq];
    [self.navigationController pushViewController:chat animated:YES];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.conversations.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMConversationCell *cell = [tableView dequeueReusableCellWithIdentifier:@"conv" forIndexPath:indexPath];
    IMConversation *c = self.conversations[indexPath.row];
    [cell configureWithConversation:c mine:[c.lastFrom isEqualToString:self.userID]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self openChatWithConversation:self.conversations[indexPath.row]];
}

#pragma mark - 行操作（左滑 + 长按菜单，共用同一动作源避免漂移）

/// 单一来源：一条会话的操作集（M4.5 全接后端）：置顶↔取消置顶 / 免打扰↔取消 / 设为已读↔标为未读 / 删除。
/// 置顶/免打扰/已读未读是切换对：按会话当前状态显示对应文案（与 Web menus.ts 对齐）。
- (NSArray<IMMenuAction *> *)conversationActionsFor:(IMConversation *)c {
    __weak typeof(self) ws = self;
    NSMutableArray<IMMenuAction *> *actions = [NSMutableArray array];
    BOOL pinned = c.pinnedAt > 0;
    [actions addObject:[IMMenuAction actionWithId:@"pin" title:(pinned ? @"取消置顶" : @"置顶")
                                            image:(pinned ? @"pin.slash" : @"pin") handler:^{
        [ws setConversation:c pinned:!pinned];
    }]];
    [actions addObject:[IMMenuAction actionWithId:@"mute" title:(c.muted ? @"取消免打扰" : @"免打扰")
                                            image:(c.muted ? @"bell" : @"bell.slash") handler:^{
        [ws setConversation:c muted:!c.muted];
    }]];
    if (c.unread > 0 || c.markedUnread) {
        [actions addObject:[IMMenuAction actionWithId:@"markRead" title:@"设为已读" image:@"checkmark.circle" handler:^{
            [ws markConversationRead:c];
        }]];
    } else {
        [actions addObject:[IMMenuAction actionWithId:@"markUnread" title:@"标为未读" image:@"circle" handler:^{
            [ws markConversationUnread:c];
        }]];
    }
    [actions addObject:[IMMenuAction destructiveActionWithId:@"delete" title:@"删除" image:@"trash" handler:^{
        [ws deleteConversation:c];
    }]];
    return actions;
}

/// 设为已读：推进已读位点（清未读数）+ 清除手动"标未读"标记；成功后刷新列表。
- (void)markConversationRead:(IMConversation *)c {
    if (c.convID.length == 0) { return; }
    if (c.unread > 0) {
        [IMSocketManager.sharedManager markReadConv:c.convID upToConvSeq:c.latestConvSeq];
    }
    // 手动"标未读"需经设置接口清除（与已读位点正交）；否则仅本地清未读数刷新该行。
    if (c.markedUnread && self.token.length > 0) {
        __weak typeof(self) ws = self;
        [IMHTTPService.sharedService updateConversationSettingsWithToken:self.token convID:c.convID
            pinnedAt:c.pinnedAt muted:c.muted markedUnread:NO completion:^(NSError *error) {
                if (error) { [ws im_showToast:error.localizedDescription]; return; }
                [ws reload];
            }];
        return;
    }
    c.unread = 0;
    NSUInteger idx = [self.conversations indexOfObject:c];
    if (idx != NSNotFound) {
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:idx inSection:0]]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

/// 标为未读：手动置红点（不改已读位点，不计数）；成功后刷新列表。
- (void)markConversationUnread:(IMConversation *)c {
    [self updateSettingsForConversation:c pinnedAt:c.pinnedAt muted:c.muted markedUnread:YES fail:@"标记失败"];
}

/// 置顶/取消置顶：pinned_at=现在ms/0（服务端据此把置顶会话排列表顶）。
- (void)setConversation:(IMConversation *)c pinned:(BOOL)pinned {
    int64_t pinnedAt = pinned ? (int64_t)([NSDate date].timeIntervalSince1970 * 1000.0) : 0;
    [self updateSettingsForConversation:c pinnedAt:pinnedAt muted:c.muted markedUnread:c.markedUnread fail:@"置顶失败"];
}

/// 免打扰/取消免打扰：muted 切换（弱提示，不改未读）。
- (void)setConversation:(IMConversation *)c muted:(BOOL)muted {
    [self updateSettingsForConversation:c pinnedAt:c.pinnedAt muted:muted markedUnread:c.markedUnread fail:@"设置失败"];
}

/// 会话设置写入的统一入口：PUT 设置 → 成功后重拉列表（服务端已含置顶排序 + 权威状态）。
- (void)updateSettingsForConversation:(IMConversation *)c
                             pinnedAt:(int64_t)pinnedAt muted:(BOOL)muted markedUnread:(BOOL)markedUnread
                                 fail:(NSString *)fail {
    if (c.convID.length == 0 || self.token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService updateConversationSettingsWithToken:self.token convID:c.convID
        pinnedAt:pinnedAt muted:muted markedUnread:markedUnread completion:^(NSError *error) {
            if (error) { [ws im_showToast:error.localizedDescription ?: fail]; return; }
            [ws reload];
        }];
}

/// 删除会话（仅本人，服务端记 cleared_at 不删消息）：成功后重拉列表（会话隐藏，对方再发即复现）。
- (void)deleteConversation:(IMConversation *)c {
    if (c.convID.length == 0 || self.token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService deleteConversationWithToken:self.token convID:c.convID completion:^(NSError *error) {
        if (error) { [ws im_showToast:error.localizedDescription ?: @"删除失败"]; return; }
        [ws reload];
    }];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= (NSInteger)self.conversations.count) { return nil; }
    IMConversation *c = self.conversations[indexPath.row];
    NSMutableArray<UIContextualAction *> *contextual = [NSMutableArray array];
    for (IMMenuAction *action in [self conversationActionsFor:c]) {
        UIContextualActionStyle style = action.destructive ? UIContextualActionStyleDestructive
                                                           : UIContextualActionStyleNormal;
        void (^handler)(void) = action.handler;
        UIContextualAction *ca = [UIContextualAction contextualActionWithStyle:style title:action.title
            handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
                if (handler) { handler(); }
                done(YES);
            }];
        if (action.systemImageName.length > 0) { ca.image = [UIImage systemImageNamed:action.systemImageName]; }
        if ([action.actionId isEqualToString:@"markRead"]) { ca.backgroundColor = IMTheme.accent; }
        else if (!action.destructive) { ca.backgroundColor = UIColor.systemGrayColor; }
        [contextual addObject:ca];
    }
    return [UISwipeActionsConfiguration configurationWithActions:contextual];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
    contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    if (indexPath.row >= (NSInteger)self.conversations.count) { return nil; }
    IMConversation *c = self.conversations[indexPath.row];
    NSArray<IMMenuAction *> *actions = [self conversationActionsFor:c];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
            return [IMMenuAction menuWithActions:actions];
        }];
}

@end
