//  IMConversationListViewController.m

#import "IMConversationListViewController.h"
#import "IMMainTabBarController.h" // im_refreshNavigationBar / kIMLiquidBarHeight
#import "IMChatViewController.h"
#import "IMQRScannerViewController.h"
#import "IMQRResultRouter.h"
#import "IMQRModels.h"
#import "IMHTTPService.h"
#import "IMSocketManager.h"
#import "IMDatabase.h"
#import "IMConversation.h"
#import "IMMenuAction.h"
#import "IMAnimator.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import "UILabel+IMAvatar.h"
#import "IMPresence.h"
#import "IMMediaUtil.h"
#import "IMPopoverCard.h"
#import "IMLog.h"
#import "IMUserSearchViewController.h"
#import "IMGroupMemberPickerViewController.h"
#import "IMGroupInfo.h"
#import "IMNavigationButton.h"
#import "IMMediaSendService.h"

#pragma mark - 会话 Cell（Telegram 风格：圆形头像 + 名称/最后一条 + 时间 + 未读蓝胶囊）

static CGFloat const kIMAvatarSize = 52;
static CGFloat const kIMRowLeading = 16;

@interface IMConversationCell : UITableViewCell
- (void)configureWithConversation:(IMConversation *)c mine:(BOOL)mine host:(NSString *)host;
/// 本地发送状态标（配置副标题**之后**调用）：sending → 副标题前缀 ↑ 圈；failed → 红色感叹号。
- (void)applyOutboxSending:(BOOL)sending failed:(BOOL)failed;
@end

@implementation IMConversationCell {
    UILabel *_avatar;
    UILabel *_name;
    UILabel *_last;
    UILabel *_time;
    UIStackView *_nameStateStack;
    UIStackView *_deliveryTimeStack;
    UIImageView *_pin;
    UIImageView *_mute;
    UILabel *_check;   // 最后一条是我发的 → 时间左侧显示 ✓✓（绿）
    UILabel *_badge;
    UIView *_dot;      // 手动"标未读"小圆点（无未读数时显示，M4.5）
    UIView *_onlineDot; // 在线态绿点（仅单聊、对端在线时，头像右下角，M-presence）
    NSLayoutConstraint *_badgeWidth;
}

- (void)applyOutboxSending:(BOOL)sending failed:(BOOL)failed {
    if ((!sending && !failed) || _last.text.length == 0) { return; }
    // 微信式：正在发送 → 副标题前置 ↑ 圈；有失败件 → 红色感叹号（同时存在时失败优先，更需要用户处理）。
    NSString *symbol = failed ? @"exclamationmark.circle.fill" : @"arrow.up.circle";
    UIColor *tint = failed ? UIColor.systemRedColor : IMTheme.accent;
    UIImage *icon = [[UIImage systemImageNamed:symbol
                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightMedium]]
                     imageWithTintColor:tint renderingMode:UIImageRenderingModeAlwaysOriginal];
    NSTextAttachment *att = [NSTextAttachment new];
    att.image = icon;
    CGFloat side = 14;
    att.bounds = CGRectMake(0, (_last.font.capHeight - side) / 2.0, side, side); // cap 高居中，不顶行高
    NSMutableAttributedString *s = [[NSAttributedString attributedStringWithAttachment:att] mutableCopy];
    [s appendAttributedString:[[NSAttributedString alloc]
        initWithString:[@" " stringByAppendingString:_last.text]
            attributes:@{ NSFontAttributeName: _last.font, NSForegroundColorAttributeName: _last.textColor }]];
    _last.attributedText = s;
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
        _name.lineBreakMode = NSLineBreakByTruncatingTail;
        [_name setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

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

        UIImageSymbolConfiguration *stateConfig =
            [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
        _pin = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"pin.fill" withConfiguration:stateConfig]];
        _mute = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bell.slash.fill" withConfiguration:stateConfig]];
        for (UIImageView *icon in @[_pin, _mute]) {
            icon.translatesAutoresizingMaskIntoConstraints = NO;
            icon.contentMode = UIViewContentModeScaleAspectFit;
            icon.tintColor = IMTheme.textSecondary;
            icon.hidden = YES;
            [icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            [icon setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            [NSLayoutConstraint activateConstraints:@[
                [icon.widthAnchor constraintEqualToConstant:14],
                [icon.heightAnchor constraintEqualToConstant:14],
            ]];
        }
        _nameStateStack = [[UIStackView alloc] initWithArrangedSubviews:@[_name, _pin, _mute]];
        _nameStateStack.translatesAutoresizingMaskIntoConstraints = NO;
        _nameStateStack.axis = UILayoutConstraintAxisHorizontal;
        _nameStateStack.alignment = UIStackViewAlignmentCenter;
        _nameStateStack.spacing = 4;
        [self.contentView addSubview:_nameStateStack];

        _check = [UILabel new];
        _check.translatesAutoresizingMaskIntoConstraints = NO;
        _check.font = [UIFont systemFontOfSize:13];
        _check.textColor = IMTheme.checkRead;
        _check.text = @"✓✓";
        [_check setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_check setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        _deliveryTimeStack = [[UIStackView alloc] initWithArrangedSubviews:@[_check, _time]];
        _deliveryTimeStack.translatesAutoresizingMaskIntoConstraints = NO;
        _deliveryTimeStack.axis = UILayoutConstraintAxisHorizontal;
        _deliveryTimeStack.alignment = UIStackViewAlignmentCenter;
        _deliveryTimeStack.spacing = 4;
        [self.contentView addSubview:_deliveryTimeStack];

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

        // 在线态绿点：贴头像右下角，外套一圈页面底色描边使其与头像分离（微信/Telegram 式）。
        _onlineDot = [UIView new];
        _onlineDot.translatesAutoresizingMaskIntoConstraints = NO;
        _onlineDot.backgroundColor = IMTheme.onlineDot;
        _onlineDot.layer.cornerRadius = 6;   // 12pt 外圈
        _onlineDot.layer.borderWidth = 2;
        // borderColor 每次 configure 复用时刷新（见下），此处不设——避免与其重复且掩盖真正的赋值点。
        _onlineDot.layer.masksToBounds = YES;
        _onlineDot.hidden = YES;
        [self.contentView addSubview:_onlineDot];

        [_time setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_time setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        _badgeWidth = [_badge.widthAnchor constraintEqualToConstant:0];

        UILayoutGuide *g = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kIMRowLeading],
            [_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:kIMAvatarSize],
            [_avatar.heightAnchor constraintEqualToConstant:kIMAvatarSize],

            [_nameStateStack.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:12],
            [_nameStateStack.topAnchor constraintEqualToAnchor:_avatar.topAnchor constant:2],
            [_nameStateStack.trailingAnchor constraintLessThanOrEqualToAnchor:_deliveryTimeStack.leadingAnchor constant:-8],

            [_deliveryTimeStack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_deliveryTimeStack.centerYAnchor constraintEqualToAnchor:_nameStateStack.centerYAnchor],

            [_last.leadingAnchor constraintEqualToAnchor:_nameStateStack.leadingAnchor],
            [_last.topAnchor constraintEqualToAnchor:_nameStateStack.bottomAnchor constant:4],
            [_last.trailingAnchor constraintLessThanOrEqualToAnchor:_badge.leadingAnchor constant:-8],

            [_badge.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_badge.centerYAnchor constraintEqualToAnchor:_last.centerYAnchor],
            [_badge.heightAnchor constraintEqualToConstant:20],
            _badgeWidth,

            [_dot.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_dot.centerYAnchor constraintEqualToAnchor:_last.centerYAnchor],
            [_dot.widthAnchor constraintEqualToConstant:10],
            [_dot.heightAnchor constraintEqualToConstant:10],

            // 头像是满圆（cornerRadius=size/2），故点心要落在圆周 4:30 方向上、而非方形包围盒的角（那样点会飘在圆外）。
            // 圆半径 26、45° 方向的边缘点约 (44,44)，12pt 点居中于此 → 相对 avatar 右/下边各内缩 2pt，使点跨坐在圆周上。
            [_onlineDot.trailingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:-2],
            [_onlineDot.bottomAnchor constraintEqualToAnchor:_avatar.bottomAnchor constant:-2],
            [_onlineDot.widthAnchor constraintEqualToConstant:12],
            [_onlineDot.heightAnchor constraintEqualToConstant:12],
        ]];
    }
    return self;
}

- (void)configureWithConversation:(IMConversation *)c mine:(BOOL)mine host:(NSString *)host {
    // 撤回预览（M4-1，后端已脱敏 content）：优先显示"撤回了一条消息"，不加"昵称:"前缀（微信式）。
    NSString *recalledPreview = nil;
    if (c.lastRecalled) {
        NSString *who = mine ? @"你" : (c.isGroup ? (c.lastFromNickname.length > 0 ? c.lastFromNickname : (c.lastFrom ?: @"")) : @"对方");
        recalledPreview = [NSString stringWithFormat:@"%@撤回了一条消息", who];
    }
    // 富媒体预览（M4-6）：图片/视频/文件显示占位标签而非 URL（微信式，不加昵称前缀）。
    if (!recalledPreview) {
        // 静态占位表（每 cell 都取，不必每次重建）；语音/位置等类型落地后自动生效。
        static NSDictionary *mediaNames;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            mediaNames = @{ @"image": @"[图片]", @"video": @"[视频]", @"file": @"[文件]",
                            @"chat_record": @"[聊天记录]",
                            @"audio": @"[语音]", @"location": @"[位置]" };
        });
        recalledPreview = mediaNames[c.lastContentType ?: @""];
    }
    if (c.isGroup) {
        // 群项：群名/群头像；预览"昵称: 内容"；不显示 presence/✓✓（群无对端已读位点）。
        NSString *display = c.name.length > 0 ? c.name : @"群聊";
        // 群头像可能是 /uploads 相对路径 → 补 host 成绝对 URL，否则 IMImageLoader 加载不了、只显首字母。
        [_avatar im_setAvatarURL:IMMediaFullURL(c.avatarURL, host) seed:c.convID displayName:display];
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
        // 对端头像同理补 host（data:/http 原样返回，相对路径补全）。
        [_avatar im_setAvatarURL:IMMediaFullURL(c.peerAvatarURL, host) seed:c.peer displayName:display]; // 有头像渲图，否则首字母圈
        _name.text = display;
        _last.text = recalledPreview ?: (c.lastContent.length > 0 ? c.lastContent : @"（无消息）");
    }
    // 群「@我」红字前缀（M4-8）：未读区间内被 @（含 @所有人）时，预览行前挂 [有人@我]。
    // 用富文本只染前缀、正文保持次要色；不再另加右侧红 @ 角标（左侧红字已足够醒目，见 GROUP_READ_UX_SKETCH §02）。
    if (c.isGroup && c.mentionUnread && _last.text.length > 0) {
        NSString *tag = @"[有人@我] ";
        NSMutableAttributedString *s = [[NSMutableAttributedString alloc]
            initWithString:[tag stringByAppendingString:_last.text]
                attributes:@{ NSForegroundColorAttributeName: IMTheme.textSecondary, NSFontAttributeName: _last.font }];
        [s addAttributes:@{ NSForegroundColorAttributeName: IMTheme.danger,
                            NSFontAttributeName: [UIFont systemFontOfSize:_last.font.pointSize weight:UIFontWeightSemibold] }
                   range:NSMakeRange(0, tag.length)];
        _last.attributedText = s;
    }
    // 群「待审入群申请」红字前缀（G3，仅群主/管理员下发 pendingCount）：进群管理才发现太深，顶到会话列表。
    if (c.isGroup && c.pendingCount > 0) {
        NSString *tag = [NSString stringWithFormat:@"[%ld 待审] ", (long)c.pendingCount];
        NSAttributedString *body = _last.attributedText.length ? _last.attributedText
            : [[NSAttributedString alloc] initWithString:(_last.text ?: @"")
                  attributes:@{ NSForegroundColorAttributeName: IMTheme.textSecondary, NSFontAttributeName: _last.font }];
        NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:tag
            attributes:@{ NSForegroundColorAttributeName: IMTheme.danger,
                          NSFontAttributeName: [UIFont systemFontOfSize:_last.font.pointSize weight:UIFontWeightSemibold] }];
        [s appendAttributedString:body];
        _last.attributedText = s;
    }
    // 在线态绿点：仅单聊且对端在线时显示（快照版；isOnline 按 onlineUntil 实时判，租约到期即隐）。群聊不显示。
    _onlineDot.hidden = c.isGroup || !c.peerPresence.isOnline;
    _onlineDot.layer.borderColor = IMTheme.pageBackground.CGColor; // CGColor 不随主题自动更新，每次复用刷新
    // 名称 → 置顶 → 免打扰：状态图标紧跟实际显示的名称，长名称只截断文字。
    _pin.hidden = c.pinnedAt <= 0;
    _mute.hidden = !c.muted;
    _pin.tintColor = IMTheme.textSecondary;
    _mute.tintColor = IMTheme.textSecondary;
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
    // **@我 破例**（M4-8）：被 @ 时即使群设了免打扰也回到高亮色——免打扰只压普通消息，不压 @我。
    UIColor *unreadColor = (c.muted && !c.mentionUnread) ? UIColor.systemGrayColor : IMTheme.unreadBadge;
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

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    // 绿点描边用 CGColor，明暗切换不会自动重取；主题变化时手动刷新（同一像素不重配时也生效）。
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous]) {
        _onlineDot.layer.borderColor = IMTheme.pageBackground.CGColor;
    }
}

@end

@interface IMConversationListViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, strong) IMDatabaseAccountContext *databaseContext;
@property (nonatomic, strong) NSArray<IMConversation *> *conversations;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, assign) BOOL visible; // 在屏时才响应新消息刷新（避免进聊天页时无谓拉取）
@property (nonatomic, strong) NSMutableSet<NSString *> *trackedConvIDs; // 已登记增量同步的会话（每会话只登记一次）
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *outboxStates; // conv → 0无/1发送中/2失败（去抖用）
@property (nonatomic, assign) IMSocketState connState; // 连接态（走副标题，同聊天页「在线」位置）
@end

@implementation IMConversationListViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        IMDatabaseAccountContext *context = IMDatabase.sharedDatabase.currentAccountContext;
        if (![context.ownerUserID isEqualToString:userID]) {
            IMLogDatabase(@"会话页账号与当前数据库上下文不一致 page_uid=%@ db_uid=%@",
                          userID, context.ownerUserID ?: @"(none)");
        }
        _databaseContext = [context.ownerUserID isEqualToString:userID] ? context : nil;
        __block NSArray<IMConversation *> *cached = @[];
        [IMDatabase.sharedDatabase performWithAccountContext:_databaseContext block:^(IMDatabase *database) {
            cached = database.cachedConversations;
        }];
        _conversations = cached;
        _trackedConvIDs = [NSMutableSet set];
    }
    return self;
}

- (BOOL)performDatabaseOperation:(void (^)(IMDatabase *database))operation {
    return [IMDatabase.sharedDatabase performWithAccountContext:self.databaseContext block:operation];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"会话";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    // 使用系统 UIBarButtonItem；iOS 26 会把标题、返回键和此按钮分成独立 Liquid Glass 控件。
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus"]
                                         style:UIBarButtonItemStylePlain
                                        target:self action:@selector(plusTapped:)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
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
    self.emptyLabel.hidden = self.conversations.count > 0;
    [self.view addSubview:self.emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:IMTheme.space4 * 2],
        [self.emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-IMTheme.space4 * 2],
    ]];
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.visible = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onSocketMessage:)
                                               name:IMSocketDidReceiveMessageNotification object:nil];
    // 已读回执（对端已读→我发的✓✓；本人多端已读→未读清零）也触发列表刷新。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onSocketMessage:)
                                               name:IMSocketDidReceiveReadNotification object:nil];
    // 群变更（邀请/移除/退群/改名）→ 列表刷新（被移出的群随服务端订阅删除而消失）。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onSocketMessage:)
                                               name:IMSocketDidReceiveGroupEventNotification object:nil];
    // G3 join_result（入群审批结果，只推申请人本人）→ 提示（申请人此刻非成员，列表刷新已由上一条兜底）。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onGroupEventForJoinResult:)
                                               name:IMSocketDidReceiveGroupEventNotification object:nil];
    // 会话级设置变更（置顶/免打扰/标未读/删除会话，M4.5）→ 列表刷新（本人其他端操作的多端同步）。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onSocketMessage:)
                                               name:IMSocketDidUpdateConversationNotification object:nil];
    // 连接状态变化 → 标题显示 连接中/未连接（取代"任何失败都弹框"）。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onSocketState:)
                                               name:IMSocketDidChangeStateNotification object:nil];
    // presence 帧 → 就地点亮/更新对应单聊行的在线绿点（对端上线即时可见，不必等重拉 /conversations）。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onPresenceChanged:)
                                               name:IMSocketDidReceivePresenceNotification object:nil];
    // 本地媒体/文件发送状态 → 副标题 ↑/! 标记刷新（进度通知每片一次，reloadData 对小列表足够便宜）。
    for (NSNotificationName n in @[IMMediaSendProgressDidChangeNotification, IMMediaSendMetaDidChangeNotification,
                                   IMMediaSendDidDispatchNotification, IMMediaSendDidFailNotification,
                                   IMMediaSendDidCancelNotification]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMediaSendStateChange:) name:n object:nil];
    }
    // 即使 HTTP 当前不可用，也先把 SQLite 中的会话登记给 socket；服务恢复后可立即按本地位点补拉。
    [self trackConversationsForSync];
    // 必须先监听再发起连接，避免快速连接时错过 Connecting/Connected 通知。
    [IMSocketManager.sharedManager connectToHost:self.host userID:self.userID];
    [self updateTitleForState:IMSocketManager.sharedManager.state];
    [self reload];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.visible = NO;
    for (NSNotificationName n in @[IMSocketDidReceiveMessageNotification, IMSocketDidReceiveReadNotification,
                                   IMSocketDidReceiveGroupEventNotification, IMSocketDidUpdateConversationNotification,
                                   IMSocketDidChangeStateNotification, IMSocketDidReceivePresenceNotification,
                                   IMMediaSendProgressDidChangeNotification, IMMediaSendMetaDidChangeNotification,
                                   IMMediaSendDidDispatchNotification, IMMediaSendDidFailNotification,
                                   IMMediaSendDidCancelNotification]) {
        [NSNotificationCenter.defaultCenter removeObserver:self name:n object:nil];
    }
}

/// 发送状态变化 → 仅当该会话的 ↑/! 标记真正翻转时才 reload（进度通知每片一次，逐次刷新纯浪费）。
- (void)onMediaSendStateChange:(NSNotification *)note {
    NSString *convID = note.userInfo[@"conv_id"];
    if (convID.length == 0) { return; }
    BOOL sending = [IMMediaSendService.shared inFlightMessagesInConv:convID].count > 0;
    BOOL failed = [IMMediaSendService.shared hasFailedOutboxInConv:convID];
    NSInteger state = failed ? 2 : (sending ? 1 : 0);
    if (!self.outboxStates) { self.outboxStates = [NSMutableDictionary dictionary]; }
    if ([self.outboxStates[convID] integerValue] == state) { return; }
    self.outboxStates[convID] = @(state);
    [self.tableView reloadData];
}

/// 连接状态 → 标题后缀（连接中/未连接），网络问题不再弹框。
- (void)onSocketState:(NSNotification *)note {
    IMSocketState state = (IMSocketState)[note.userInfo[@"state"] integerValue];
    [self updateTitleForState:state];
    if (state == IMSocketStateConnected && self.visible) {
        // 服务恢复后立即取得权威资料；失败仍保留本地列表，不弹窗。
        [self reload];
    }
}

/// 收到 presence 帧 → 就地更新对应单聊行的在线态并只刷这一行（对端上线即时点亮绿点，无需重拉 /conversations）。
/// 下线不由帧驱动（服务端不推 offline），仍靠 onlineUntil 到期 + 下次 reload 熄灭。
- (void)onPresenceChanged:(NSNotification *)note {
    NSString *user = note.userInfo[kIMPresenceUserKey];
    IMPresence *presence = note.userInfo[kIMPresenceKey];
    if (user.length == 0 || !presence) { return; }
    for (NSUInteger i = 0; i < self.conversations.count; i++) {
        IMConversation *c = self.conversations[i];
        if (c.isGroup || ![c.peer isEqualToString:user]) { continue; }
        c.peerPresence = presence;
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:i inSection:0]]
                              withRowAnimation:UITableViewRowAnimationNone];
        break; // 单聊对端唯一，命中即止
    }
}

- (void)updateTitleForState:(IMSocketState)state {
    // 标题恒为「会话」；连接态走副标题（同聊天页「在线」位置，无括号）。见 im_navigationSubtitle。
    self.connState = state;
    self.title = @"会话";
    // 当前工程隐藏了 UINavigationBar，标题实际由 IMMainNavigationController 的 Liquid Bar 绘制；
    // 只改 self.title/副标题不会触发其同步，必须显式请求刷新。
    [self im_refreshNavigationBar];
}

/// 连接态副标题：连接中 / 未连接（无括号）；已连接时不显示。供导航容器统一取用（与聊天页共用同一映射）。
- (NSString *)im_navigationSubtitle {
    return IMSocketStateSubtitle(self.connState);
}

/// 收到新消息（任意会话）→ 节流刷新列表（合并连发的多条，避免每条都拉一次）。
- (void)onSocketMessage:(NSNotification *)note {
    // 消息已在 SQLite 事务内同步了会话摘要。此前每来一条都**同步读库 + 全量 reloadData**——群消息/
    // 批量接收时会反复阻塞主线程做磁盘 SELECT 并整表重建，肉眼可见卡顿。改为节流：一次消息风暴只做
    // 一次本地读库 + reloadData（HTTP 权威收敛仍走下方的 0.4s reload）。
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshLocalConversations) object:nil];
    [self performSelector:@selector(refreshLocalConversations) withObject:nil afterDelay:0.12];
    if (!self.visible) { return; }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil];
    [self performSelector:@selector(reload) withObject:nil afterDelay:0.4];
}

/// 从本地库刷新会话列表（节流后的落地）：读缓存会话 + 整表刷新。
- (void)refreshLocalConversations {
    __block NSArray<IMConversation *> *cached = nil;
    if (![self performDatabaseOperation:^(IMDatabase *database) {
        cached = database.cachedConversations;
    }]) { return; }
    self.conversations = cached ?: @[];
    self.emptyLabel.hidden = self.conversations.count > 0;
    [self.tableView reloadData];
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
            // 已有本地登录态时，任何刷新失败都不弹窗、不跳登录页；连接状态由 WebSocket 标题统一表达。
            // 真正退出账号只能由用户主动操作，避免断网/服务重启打断离线浏览。
            IMLog(@"会话刷新登录失败（保留本地缓存）：%@", error.localizedDescription ?: @"未知错误");
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
            if (![self performDatabaseOperation:^(IMDatabase *database) {
                [database replaceCachedConversations:self.conversations];
            }]) { return; }
            self.emptyLabel.hidden = self.conversations.count > 0;
            [self.tableView reloadData];
            [self trackConversationsForSync]; // 登记会话用于（重）连后增量同步，补拉离线消息
            [self fetchHiddenCatchUpWithToken:token]; // 任务2：拉「仅为我删除」隐藏集并本地移除（多设备同步 catch-up）
        }];
    }];
}

/// 任务2：登录 catch-up——拉本账号「仅为我删除」隐藏集，逐条本地物理移除（补收敛离线期间在其它设备产生的删除）。
/// best-effort：失败静默；隐藏项量小，全量拉取。
- (void)fetchHiddenCatchUpWithToken:(NSString *)token {
    if (token.length == 0) { return; }
    [IMHTTPService.sharedService fetchHiddenWithToken:token completion:^(NSArray<NSDictionary *> *items, NSError *error) {
        if (error || items.count == 0) { return; }
        for (NSDictionary *it in items) {
            NSString *convID = [it[@"conv_id"] isKindOfClass:NSString.class] ? it[@"conv_id"] : nil;
            int64_t convSeq = [it[@"conv_seq"] longLongValue];
            if (convID.length > 0 && convSeq > 0) {
                [IMSocketManager.sharedManager removeLocalMessageInConv:convID targetConvSeq:convSeq];
            }
        }
    }];
}

/// 把会话登记到长连接的增量同步集（每会话仅一次）：以 SQLite 持久化的连续同步位置为起点，
/// （重）连后自动 sync_req 补拉离线消息。修复"登录后停在会话列表，对端离线期间发的消息不入库，
/// 之后开聊天页因 synced 已被实时消息推过而漏拉"。
- (void)trackConversationsForSync {
    for (IMConversation *c in self.conversations) {
        if (c.convID.length == 0 || [self.trackedConvIDs containsObject:c.convID]) { continue; }
        [self.trackedConvIDs addObject:c.convID];
        __block int64_t synced = 0;
        if (![self performDatabaseOperation:^(IMDatabase *database) {
            synced = [database syncedConvSeqForConv:c.convID];
        }]) { return; }
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

#pragma mark - 交互

/// 右上角 ＋ Telegram 式锚点菜单：新建群聊 / 添加好友 / 扫一扫（与详情「更多」复用同一组件）。
- (void)plusTapped:(UIBarButtonItem *)barButtonItem {
    if ([IMPopoverCard isPresentingInHostView:self.view]) { return; }
    __weak typeof(self) ws = self;
    NSArray<IMPopoverCardItem *> *items = @[
        [IMPopoverCardItem itemWithTitle:@"扫一扫" symbol:@"qrcode.viewfinder" destructive:NO handler:^{ [ws openScanner]; }],
        [IMPopoverCardItem itemWithTitle:@"新建群聊" symbol:@"person.3" destructive:NO handler:^{ [ws startNewGroup]; }],
        [IMPopoverCardItem itemWithTitle:@"添加好友" symbol:@"person.badge.plus" destructive:NO handler:^{ [ws openAddFriend]; }],
    ];
    [IMPopoverCard presentFromBarButtonItem:barButtonItem inHostView:self.view items:items];
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
        // 回到会话列表（清掉建群流程页；折叠入口对建群链无聊天页可截，故仍需这步手动 pop），再进入新群会话。
        [self.navigationController popToViewController:self animated:NO];
        [IMChatViewController openInNavigationController:self.navigationController
                                                    host:self.host userID:self.userID
                                             groupConvID:group.convID groupName:group.name
                                                 readSeq:0 unread:0
                                            groupReadSeq:0 // 刚建群，无历史消息/已读
                                          groupAvatarURL:group.avatarURL];
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
    [IMChatViewController openInNavigationController:self.navigationController
                                                host:self.host userID:self.userID
                                              peerID:peer readSeq:0 unread:0 peerReadSeq:0
                                        peerNickname:nil peerAvatarURL:nil];
}

#pragma mark - 二维码（扫一扫 / 扫码结果路由，QRCODE P0 + G3）

/// 扫一扫：全屏取景 + 相册识别 + 「我的二维码」页签；扫码页自行 resolve，结果交 IMQRResultRouter 落到已有页面。
- (void)openScanner {
    __weak typeof(self) ws = self;
    IMQRScannerViewController *scanner = [[IMQRScannerViewController alloc] initWithHost:self.host userID:self.userID];
    scanner.modalPresentationStyle = UIModalPresentationFullScreen;
    scanner.onResult = ^(IMQRResolved *resolved, NSString *raw, NSError *error) {
        if (!ws) { return; }
        if (error) { [IMQRResultRouter presentError:error fromController:ws]; return; }
        [IMQRResultRouter routeResolved:resolved raw:raw host:ws.host userID:ws.userID fromController:ws];
    };
    [self presentViewController:scanner animated:YES completion:nil];
}

/// G3：入群审批结果（只推申请人本人）→ 提示通过/拒绝。审批是异步的，申请人此刻很可能不在会话列表页，
/// 故走**顶层可见控制器**弹提示（否则 toast 挂在被覆盖的列表页上、用户看不见）。
- (void)onGroupEventForJoinResult:(NSNotification *)note {
    NSString *event = note.userInfo[kIMGroupEventKey];
    // G3：新入群申请（只推群主/管理员）→ 重拉会话列表刷新「待审 N」红字（离线漏帧则靠下次 reload 补回）。
    if ([event isEqualToString:@"join_request"]) { [self reload]; return; }
    if (![event isEqualToString:@"join_result"]) { return; }
    NSString *result = note.userInfo[kIMGroupResultKey];
    [UIViewController im_showGlobalToast:[result isEqualToString:@"approved"] ? @"你的入群申请已通过，进群聊天吧" : @"你的入群申请未通过"];
}

/// 从会话列表进入：带 read_seq + unread + peer_read_seq，供聊天页定位未读分割线 + 可见即读起点 + 进会话即显对端已读（CHAT_UX §3/§6/§8）。
- (void)openChatWithConversation:(IMConversation *)c {
    // 进会话即清手动"标未读"（IM 通行做法：打开视为已处理）；经 conv_update 多端同步，返回列表 reload 取权威态。
    if (c.markedUnread && self.token.length > 0) {
        [IMHTTPService.sharedService updateConversationSettingsWithToken:self.token convID:c.convID
            pinnedAt:c.pinnedAt muted:c.muted markedUnread:NO completion:^(NSError *error) { /* 忽略：返回时 viewWillAppear 会 reload */ }];
        // 本地即时镜像，避免返回瞬间闪一下旧红点。
        [self mirrorSettingsOnto:c pinnedAt:c.pinnedAt muted:c.muted markedUnread:NO];
    }
    if (c.isGroup) {
        [IMChatViewController openInNavigationController:self.navigationController
                                                    host:self.host userID:self.userID
                                             groupConvID:c.convID groupName:c.name
                                                 readSeq:c.readSeq unread:c.unread
                                            groupReadSeq:c.groupReadSeq
                                          groupAvatarURL:c.avatarURL]; // 透传群头像，右上按钮立即显真图、免闪首字母
        return;
    }
    if (c.peer.length == 0 || [c.peer isEqualToString:self.userID]) { return; }
    // 透传对端昵称/头像，供聊天页右上信息按钮打开的资料页显示。
    [IMChatViewController openInNavigationController:self.navigationController
                                                host:self.host userID:self.userID
                                              peerID:c.peer readSeq:c.readSeq unread:c.unread
                                         peerReadSeq:c.peerReadSeq
                                        peerNickname:c.peerNickname peerAvatarURL:c.peerAvatarURL];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.conversations.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMConversationCell *cell = [tableView dequeueReusableCellWithIdentifier:@"conv" forIndexPath:indexPath];
    IMConversation *c = self.conversations[indexPath.row];
    [cell configureWithConversation:c mine:[c.lastFrom isEqualToString:self.userID] host:self.host];
    // 本地发送状态（常驻发送服务）：发送中 ↑ / 失败红 !，随服务通知刷新（onMediaSendStateChange）。
    [cell applyOutboxSending:[IMMediaSendService.shared inFlightMessagesInConv:c.convID].count > 0
                      failed:[IMMediaSendService.shared hasFailedOutboxInConv:c.convID]];
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
                c.markedUnread = NO;
                c.unread = 0;
                if (![ws performDatabaseOperation:^(IMDatabase *database) {
                    [database markConversationFullyRead:c.convID upToConvSeq:c.latestConvSeq];
                    [database applyCachedSettingsForConversation:c.convID
                                                         pinnedAt:c.pinnedAt muted:c.muted markedUnread:NO];
                }]) { return; }
                NSUInteger idx = [ws.conversations indexOfObject:c];
                if (idx != NSNotFound) {
                    [ws.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:idx inSection:0]]
                                       withRowAnimation:UITableViewRowAnimationAutomatic];
                }
                [ws reload];
            }];
        return;
    }
    c.unread = 0;
    [self performDatabaseOperation:^(IMDatabase *database) {
        [database markConversationFullyRead:c.convID upToConvSeq:c.latestConvSeq];
    }];
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
    if (c.convID.length == 0 || self.token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService updateConversationSettingsWithToken:self.token convID:c.convID
        pinnedAt:pinnedAt muted:c.muted markedUnread:c.markedUnread completion:^(NSError *error) {
            if (error) { [ws im_showToast:error.localizedDescription ?: @"置顶失败"]; return; }
            [ws animateConversation:c pinnedAt:pinnedAt];
            // 服务端仍是最终排序来源；动画结束后静默拉取一次，收敛多端同时操作。
            [ws performSelector:@selector(reload) withObject:nil afterDelay:0.42];
        }];
}

/// 服务端确认置顶后，先按与服务端一致的规则在本地移动这一行，避免整表 reload 造成的突跳。
- (void)animateConversation:(IMConversation *)conversation pinnedAt:(int64_t)pinnedAt {
    NSUInteger oldIndex = [self.conversations indexOfObject:conversation];
    if (oldIndex == NSNotFound) { [self reload]; return; }

    conversation.pinnedAt = pinnedAt;
    NSArray<IMConversation *> *sorted = [self.conversations sortedArrayUsingComparator:^NSComparisonResult(IMConversation *a, IMConversation *b) {
        if ((a.pinnedAt > 0) != (b.pinnedAt > 0)) { return a.pinnedAt > 0 ? NSOrderedAscending : NSOrderedDescending; }
        if (a.pinnedAt > 0 && a.pinnedAt != b.pinnedAt) { return a.pinnedAt > b.pinnedAt ? NSOrderedAscending : NSOrderedDescending; }
        if (a.timestamp == b.timestamp) { return NSOrderedSame; }
        return a.timestamp > b.timestamp ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSUInteger newIndex = [sorted indexOfObject:conversation];
    self.conversations = sorted;
    [self performDatabaseOperation:^(IMDatabase *database) {
        [database applyCachedSettingsForConversation:conversation.convID
                                             pinnedAt:conversation.pinnedAt
                                                muted:conversation.muted
                                         markedUnread:conversation.markedUnread];
    }];
    self.emptyLabel.hidden = sorted.count > 0;

    NSIndexPath *from = [NSIndexPath indexPathForRow:(NSInteger)oldIndex inSection:0];
    NSIndexPath *to = [NSIndexPath indexPathForRow:(NSInteger)newIndex inSection:0];
    if (oldIndex == newIndex) {
        [self.tableView reloadRowsAtIndexPaths:@[to] withRowAnimation:UITableViewRowAnimationAutomatic];
        return;
    }
    [self.tableView performBatchUpdates:^{
        [self.tableView moveRowAtIndexPath:from toIndexPath:to];
    } completion:^(BOOL finished) {
        if (finished) { [self.tableView reloadRowsAtIndexPaths:@[to] withRowAnimation:UITableViewRowAnimationNone]; }
    }];
}

/// 免打扰/取消免打扰：muted 切换（弱提示，不改未读）。
- (void)setConversation:(IMConversation *)c muted:(BOOL)muted {
    [self updateSettingsForConversation:c pinnedAt:c.pinnedAt muted:muted markedUnread:c.markedUnread fail:@"设置失败"];
}

/// 把置顶/免打扰/标未读三态就地镜像到内存模型 + 本地库（乐观更新）；不刷新 UI，调用方各自选刷新方式。
/// 返回本地库写入是否成功（失败通常是账号已切换，调用方应据此中止后续刷新）。
/// 注：markConversationRead: 需把 markConversationFullyRead 与设置写在同一事务、并清 unread，
/// animateConversation: 需在写库同时做移行动画——两者各有额外语义，不并入本 helper。
- (BOOL)mirrorSettingsOnto:(IMConversation *)c pinnedAt:(int64_t)pinnedAt muted:(BOOL)muted markedUnread:(BOOL)markedUnread {
    c.pinnedAt = pinnedAt;
    c.muted = muted;
    c.markedUnread = markedUnread;
    return [self performDatabaseOperation:^(IMDatabase *database) {
        [database applyCachedSettingsForConversation:c.convID pinnedAt:pinnedAt muted:muted markedUnread:markedUnread];
    }];
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
            if (![ws mirrorSettingsOnto:c pinnedAt:pinnedAt muted:muted markedUnread:markedUnread]) { return; }
            [ws.tableView reloadData];
            [ws reload];
        }];
}

/// 删除会话（仅本人，服务端记 cleared_at 不删消息）：成功后仅动画删除该行（会话隐藏，对方再发即复现）。
/// 不再 reloadData + 立即 reload：整表重绘无删除动画（行突跳），紧接着的网络重拉又触发第二次 reloadData
/// （闪动）。改为单行 deleteRows 平滑移除；服务端权威收敛交给动画结束后的静默重拉（多端同步）。
- (void)deleteConversation:(IMConversation *)c {
    if (c.convID.length == 0 || self.token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService deleteConversationWithToken:self.token convID:c.convID completion:^(NSError *error) {
        if (error) { [ws im_showToast:error.localizedDescription ?: @"删除失败"]; return; }
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        // 取旧位置须在替换数据源之前；期间若有新消息重排导致 c 已不在列表，回退整表刷新。
        NSUInteger idx = [self.conversations indexOfObject:c];
        NSMutableArray<IMConversation *> *remaining = [self.conversations mutableCopy];
        [remaining removeObject:c];
        self.conversations = remaining;
        if (![self performDatabaseOperation:^(IMDatabase *database) {
            [database deleteCachedConversation:c.convID];
        }]) { return; }
        self.emptyLabel.hidden = remaining.count > 0;
        if (idx != NSNotFound) {
            [self.tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:(NSInteger)idx inSection:0]]
                                  withRowAnimation:UITableViewRowAnimationAutomatic];
        } else {
            [self.tableView reloadData];
        }
        // 服务端仍是最终来源；等删除动画结束后静默拉取一次收敛多端同时操作，避免与动画争抢重绘。
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil];
        [self performSelector:@selector(reload) withObject:nil afterDelay:0.42];
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
