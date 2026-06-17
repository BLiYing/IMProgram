//  IMChatViewController.m

#import "IMChatViewController.h"
#import "IMChatBackgroundView.h"
#import "IMSocketManager.h"
#import "IMHTTPService.h"
#import "IMUserCard.h"
#import "IMProtocol.h"
#import "IMMessageModel.h"
#import "IMDatabase.h"
#import "IMTheme.h"
#import "IMLog.h"

#pragma mark - 气泡 Cell（Telegram 风格：圆角气泡 + 尾巴 + 气泡内时间/双勾）

/// 私有消息气泡 Cell：自己的消息靠右（浅绿），对方靠左（白）。
/// 顶部可选「日期分隔胶囊」+「未读消息」分割线；气泡内右下角时间，自己的消息按对端已读位点显示 ✓/✓✓（已读绿）。
@interface IMBubbleCell : UITableViewCell
- (void)configureWithMessage:(IMMessageModel *)message
                        mine:(BOOL)mine
                 peerReadSeq:(int64_t)peerReadSeq
                   dayHeader:(nullable NSString *)dayHeader
          showsUnreadDivider:(BOOL)showsDivider;
@end

@implementation IMBubbleCell {
    UIView  *_datePill;       // 日期分隔胶囊（居中浮于壁纸上）
    UILabel *_dateLabel;
    NSLayoutConstraint *_datePillTop;
    NSLayoutConstraint *_datePillHeight;
    UILabel *_divider;        // 「未读消息」分割线
    NSLayoutConstraint *_dividerHeight;
    UIView *_bubble;
    UILabel *_text;
    NSLayoutConstraint *_leading;
    NSLayoutConstraint *_trailing;
    UILabel *_failBadge;      // 发送失败：气泡左侧红色❗（微信式）
    UILabel *_sysNote;        // 被拒收等系统提示：气泡下方居中灰字
    NSLayoutConstraint *_bubbleBottom;   // 无系统行时：气泡贴 cell 底
    NSLayoutConstraint *_noteTop;        // 有系统行时：系统行接气泡底
    NSLayoutConstraint *_noteBottom;     // 有系统行时：系统行贴 cell 底
    NSLayoutConstraint *_failBadgeTrailing;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.clearColor;

        _datePill = [UIView new];
        _datePill.translatesAutoresizingMaskIntoConstraints = NO;
        _datePill.backgroundColor = IMTheme.datePillBg;
        _datePill.layer.cornerRadius = 12;
        _datePill.layer.masksToBounds = YES;
        [self.contentView addSubview:_datePill];

        _dateLabel = [UILabel new];
        _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _dateLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _dateLabel.textColor = IMTheme.datePillText;
        _dateLabel.textAlignment = NSTextAlignmentCenter;
        [_datePill addSubview:_dateLabel];

        _divider = [UILabel new];
        _divider.translatesAutoresizingMaskIntoConstraints = NO;
        _divider.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _divider.textColor = IMTheme.textSecondary;
        _divider.textAlignment = NSTextAlignmentCenter;
        _divider.text = @"未读消息";
        _divider.clipsToBounds = YES;
        [self.contentView addSubview:_divider];

        _bubble = [UIView new];
        _bubble.translatesAutoresizingMaskIntoConstraints = NO;
        _bubble.layer.cornerRadius = 18;
        _bubble.layer.masksToBounds = YES;
        [self.contentView addSubview:_bubble];

        _text = [UILabel new];
        _text.translatesAutoresizingMaskIntoConstraints = NO;
        _text.numberOfLines = 0;
        _text.font = [UIFont systemFontOfSize:17];
        [_bubble addSubview:_text];

        _failBadge = [UILabel new];
        _failBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _failBadge.text = @"!";
        _failBadge.textAlignment = NSTextAlignmentCenter;
        _failBadge.font = [UIFont boldSystemFontOfSize:13];
        _failBadge.textColor = UIColor.whiteColor;
        _failBadge.backgroundColor = UIColor.systemRedColor;
        _failBadge.layer.cornerRadius = 9;
        _failBadge.layer.masksToBounds = YES;
        _failBadge.hidden = YES;
        [self.contentView addSubview:_failBadge];

        _sysNote = [UILabel new];
        _sysNote.translatesAutoresizingMaskIntoConstraints = NO;
        _sysNote.font = [UIFont systemFontOfSize:12];
        _sysNote.textColor = IMTheme.textSecondary;
        _sysNote.textAlignment = NSTextAlignmentCenter;
        _sysNote.numberOfLines = 0;
        _sysNote.hidden = YES;
        [self.contentView addSubview:_sysNote];

        _leading = [_bubble.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12];
        _trailing = [_bubble.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
        _datePillTop = [_datePill.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:0];
        _datePillHeight = [_datePill.heightAnchor constraintEqualToConstant:0];
        _dividerHeight = [_divider.heightAnchor constraintEqualToConstant:0];
        [NSLayoutConstraint activateConstraints:@[
            _datePillTop,
            [_datePill.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            _datePillHeight,
            [_dateLabel.leadingAnchor constraintEqualToAnchor:_datePill.leadingAnchor constant:12],
            [_dateLabel.trailingAnchor constraintEqualToAnchor:_datePill.trailingAnchor constant:-12],
            [_dateLabel.centerYAnchor constraintEqualToAnchor:_datePill.centerYAnchor],

            [_divider.topAnchor constraintEqualToAnchor:_datePill.bottomAnchor],
            [_divider.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_divider.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            _dividerHeight,

            [_bubble.topAnchor constraintEqualToAnchor:_divider.bottomAnchor constant:2],
            [_bubble.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.75],

            // 红❗：钉在气泡左侧、垂直居中（仅自己失败时显示）。
            [_failBadge.widthAnchor constraintEqualToConstant:18],
            [_failBadge.heightAnchor constraintEqualToConstant:18],
            [_failBadge.centerYAnchor constraintEqualToAnchor:_bubble.centerYAnchor],

            // 系统行：横跨内容区居中。
            [_sysNote.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:24],
            [_sysNote.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-24],

            // 气泡内文本：时间+✓/✓✓ 作为小字尾巴拼进同一段富文本（不再用独立 label 叠加+空格占位，
            // 那种做法短消息时气泡不为尾随空格变宽→ meta 溢出圆角裁剪而看不见。现在 meta 一定随文本渲染）。
            [_text.topAnchor constraintEqualToAnchor:_bubble.topAnchor constant:6],
            [_text.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:12],
            [_text.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-12],
            [_text.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:-6],
        ]];

        // 可切换约束：无系统行→气泡贴 cell 底；有系统行→气泡接系统行、系统行贴底。
        _bubbleBottom = [_bubble.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3];
        _noteTop = [_sysNote.topAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:4];
        _noteBottom = [_sysNote.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6];
        _failBadgeTrailing = [_failBadge.trailingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:-6];
        _bubbleBottom.active = YES;
    }
    return self;
}

- (void)configureWithMessage:(IMMessageModel *)message
                        mine:(BOOL)mine
                 peerReadSeq:(int64_t)peerReadSeq
                   dayHeader:(NSString *)dayHeader
          showsUnreadDivider:(BOOL)showsDivider {
    BOOL showsDate = dayHeader.length > 0;
    _datePill.hidden = !showsDate;
    _dateLabel.text = dayHeader;
    _datePillHeight.constant = showsDate ? 24 : 0;
    _datePillTop.constant = showsDate ? 8 : 0;

    _divider.hidden = !showsDivider;
    _dividerHeight.constant = showsDivider ? 28 : 0;

    _bubble.backgroundColor = mine ? IMTheme.bubbleMe : IMTheme.bubbleThem;
    // 正文 + 小字尾巴（时间/✓/✓✓）拼成一段富文本，保证状态一定随气泡渲染。
    NSMutableAttributedString *body = [[NSMutableAttributedString alloc]
        initWithString:(message.content ?: @"")
            attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:17],
                          NSForegroundColorAttributeName: IMTheme.textPrimary }];
    NSAttributedString *meta = [self attributedMetaForMessage:message mine:mine peerReadSeq:peerReadSeq];
    if (meta.length > 0) {
        [body appendAttributedString:[[NSAttributedString alloc] initWithString:@"   "
            attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:11] }]]; // 与尾巴之间留点空隙
        [body appendAttributedString:meta];
    }
    _text.attributedText = body;

    // 发送失败：气泡左侧红❗（仅自己）；被拒收等→气泡下方居中系统行（微信式）。
    BOOL failed = mine && message.status == IMMessageStatusFailed;
    _failBadge.hidden = !failed;
    _failBadgeTrailing.active = failed;
    BOOL hasNote = message.note.length > 0;
    _sysNote.hidden = !hasNote;
    _sysNote.text = message.note;
    _bubbleBottom.active = !hasNote;
    _noteTop.active = hasNote;
    _noteBottom.active = hasNote;

    // 尾巴：自己靠右气泡的右下角不圆（成尾），对方靠左气泡的左下角不圆。
    _bubble.layer.maskedCorners = mine
        ? (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner)
        : (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner);

    _leading.active = !mine;
    _trailing.active = mine;
}

/// 气泡内右下角富文本：时间(灰)；自己消息追加状态勾——已送达 ✓(灰)/已读 ✓✓(绿)/发送中/失败。
- (NSAttributedString *)attributedMetaForMessage:(IMMessageModel *)message
                                            mine:(BOOL)mine
                                     peerReadSeq:(int64_t)peerReadSeq {
    UIFont *font = [UIFont systemFontOfSize:11];
    NSString *time = [IMTheme timeStringFromMillis:message.timestamp];
    UIColor *timeColor = IMTheme.bubbleMetaTime;
    NSDictionary *base = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: timeColor };

    if (!mine) {
        return [[NSAttributedString alloc] initWithString:time attributes:base];
    }
    if (message.status == IMMessageStatusSending) {
        return [[NSAttributedString alloc] initWithString:@"发送中…" attributes:base];
    }
    if (message.status == IMMessageStatusFailed) {
        // 被拒收（有系统行）→ 气泡内只显时间，失败由红❗+下方系统行表达；其余失败仍显"未发送 ✗"。
        if (message.note.length > 0) {
            return [[NSAttributedString alloc] initWithString:time attributes:base];
        }
        return [[NSAttributedString alloc] initWithString:@"未发送 ✗"
            attributes:@{ NSFontAttributeName: font, NSForegroundColorAttributeName: UIColor.systemRedColor }];
    }
    // 其余（Sent，或经多端抄送/同步收到的"自己消息"——其 status 为 Received）：
    // 只要拿到了 conv_seq 即视为已送达，按对端已读位点显示 ✓/✓✓。否则只显时间。
    if (message.convSeq > 0) {
        BOOL read = message.convSeq <= peerReadSeq;
        NSString *checks = read ? @"✓✓" : @"✓";
        NSString *plain = time.length > 0 ? [NSString stringWithFormat:@"%@ %@", time, checks] : checks;
        NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:plain attributes:base];
        NSRange r = [plain rangeOfString:checks options:NSBackwardsSearch];
        [s addAttribute:NSForegroundColorAttributeName value:(read ? IMTheme.checkRead : timeColor) range:r];
        return s;
    }
    return [[NSAttributedString alloc] initWithString:time attributes:base];
}

@end

#pragma mark - 聊天页

@interface IMChatViewController () <IMSocketManagerDelegate, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy) NSString *peerID;
@property (nonatomic, strong) NSMutableArray<IMMessageModel *> *messages;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *seenConvSeqs; // 按 conv_seq 去重，避免推送+同步重复
@property (nonatomic, copy) NSString *convID;
@property (nonatomic, assign) int64_t entryReadSeq;   // 进入前已读位点（定位未读分割线，进会话锁定一次）
@property (nonatomic, assign) NSInteger entryUnread;   // 进入时未读数
@property (nonatomic, assign) int64_t maxReadReported; // 已上报的最大已读 conv_seq（可见即读，单调不回退）
@property (nonatomic, assign) int64_t pendingReadSeq;  // 已滚入视口的最大 conv_seq（节流后上报）
@property (nonatomic, assign) int64_t peerReadSeq;     // 对端已读位点（用于「已读」双勾）
@property (nonatomic, assign) BOOL peerOnline;         // 对端在线
@property (nonatomic, assign) IMSocketState connState; // 连接态（与在线点共同决定标题）
@property (nonatomic, assign) BOOL didInitialPosition; // 已做进会话定位（只定位一次）
@property (nonatomic, assign) NSTimeInterval lastTypingSent; // typing 节流
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) NSLayoutConstraint *inputBottom;
@property (nonatomic, strong) UILabel *typingLabel;
@property (nonatomic, strong) NSLayoutConstraint *typingHeight;
@property (nonatomic, strong) UIButton *jumpButton;   // 右下角"↓N"回到最新
@property (nonatomic, strong) UILabel *jumpBadge;     // 按钮上的未读计数（=视口下方未读数）
@property (nonatomic, strong) UIView *inputBar;       // 输入栏容器
@end

@implementation IMChatViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID peerID:(NSString *)peerID
                     readSeq:(int64_t)readSeq unread:(NSInteger)unread peerReadSeq:(int64_t)peerReadSeq {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.hidesBottomBarWhenPushed = YES; // 进聊天页隐藏底部 TabBar（push 时全屏）
        _host = [host copy];
        _userID = [userID copy];
        _peerID = [peerID copy];
        _convID = IMConversationID(userID, peerID);
        _entryReadSeq = readSeq;
        _entryUnread = unread;
        _peerReadSeq = peerReadSeq;   // 进会话即用服务端已知对端已读位点播种（实时回执再往上推进）
        _maxReadReported = readSeq;   // 已读起点=进入前位点，仅在可见消息超过它时才上报
        _pendingReadSeq = readSeq;
        // 本地落库：进入即秒显历史。
        _messages = [[IMDatabase.sharedDatabase messagesForConv:_convID] mutableCopy];
        _seenConvSeqs = [NSMutableSet set];
        for (IMMessageModel *m in _messages) {
            if (m.convSeq > 0) { [_seenConvSeqs addObject:@(m.convSeq)]; }
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = [NSString stringWithFormat:@"与 %@ 聊天", self.peerID];
    [self setupUI];
    [self observeKeyboard];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    IMSocketManager.sharedManager.delegate = self;
    [IMSocketManager.sharedManager connectToHost:self.host userID:self.userID];
    // 登记本会话：以本地已存最大 conv_seq 为同步起点（断点续传），自动增量拉回缺失消息。
    int64_t synced = [IMDatabase.sharedDatabase maxConvSeqForConv:self.convID];
    [IMSocketManager.sharedManager trackConversation:self.convID syncedSeq:synced];
}

#pragma mark - 拉黑（微信式单向：拉黑者仍可发，故聊天页不拦输入；黑名单状态在通讯录管理）

// 微信式单向：拉黑者仍可给被拉黑者发消息（对方能收到），故聊天页不再拦输入/盖横幅。
// 是否拉黑、解除拉黑均在通讯录好友行（副标题"已拉黑" + 左滑"解除拉黑"）管理。

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // 在出现动画前、首次布局完成时即定位，避免"先显历史第一条→再滑到最新"的闪动。
    if (!self.didInitialPosition && self.messages.count > 0 && self.tableView.frame.size.height > 0) {
        [self positionInitialIfNeeded];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self positionInitialIfNeeded]; // 兜底：若 layout 时机未就绪（消息晚到），这里再定位一次
    // 可见即读：把定位后当前可见的消息标为已读（不滚动也算看到）。
    dispatch_async(dispatch_get_main_queue(), ^{ [self markVisibleRowsRead]; });
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController) {
        // 不断开长连接：返回会话列表后仍需常驻接收新消息以实时刷新未读（见 IMConversationListViewController）。
        // 仅交还 delegate，避免离开后本页继续处理消息。
        if (IMSocketManager.sharedManager.delegate == self) {
            IMSocketManager.sharedManager.delegate = nil;
        }
    }
}

#pragma mark - UI

- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.allowsSelection = NO;
    self.tableView.estimatedRowHeight = 56; // 估高更准 → 进会话滚到底更稳，减少自适应高度引起的偏移
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundView = [IMChatBackgroundView new]; // Telegram 绿主题壁纸
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.tableView registerClass:IMBubbleCell.class forCellReuseIdentifier:@"bubble"];
    [self.view addSubview:self.tableView];

    // 「对方正在输入」提示条（默认高度 0，typing 时展开）。
    self.typingLabel = [UILabel new];
    self.typingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.typingLabel.font = [UIFont systemFontOfSize:12];
    self.typingLabel.textColor = UIColor.secondaryLabelColor;
    self.typingLabel.text = @"对方正在输入…";
    self.typingLabel.clipsToBounds = YES;
    [self.view addSubview:self.typingLabel];

    UIView *inputBar = [UIView new];
    self.inputBar = inputBar;
    inputBar.translatesAutoresizingMaskIntoConstraints = NO;
    inputBar.backgroundColor = UIColor.secondarySystemBackgroundColor;
    [self.view addSubview:inputBar];

    self.inputField = [UITextField new];
    self.inputField.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputField.placeholder = @"输入消息…";
    self.inputField.font = [UIFont systemFontOfSize:16];
    self.inputField.returnKeyType = UIReturnKeySend;
    self.inputField.delegate = self;
    // 圆角胶囊输入框（Telegram 风格）。
    self.inputField.backgroundColor = UIColor.systemBackgroundColor;
    self.inputField.layer.cornerRadius = 18;
    self.inputField.layer.borderWidth = 1;
    self.inputField.layer.borderColor = UIColor.separatorColor.CGColor;
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 0)];
    self.inputField.leftView = pad;
    self.inputField.leftViewMode = UITextFieldViewModeAlways;
    [self.inputField addTarget:self action:@selector(inputChanged) forControlEvents:UIControlEventEditingChanged];
    [inputBar addSubview:self.inputField];

    // 圆形发送按钮（蓝底上箭头）。
    UIButton *sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightRegular];
    [sendButton setImage:[UIImage systemImageNamed:@"arrow.up.circle.fill" withConfiguration:cfg] forState:UIControlStateNormal];
    sendButton.tintColor = IMTheme.accent;
    [sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [inputBar addSubview:sendButton];

    // 右下角"↓N"悬浮跳转按钮（默认隐藏；滚离底部时出现，点按回到最新；CHAT_UX §7）。
    self.jumpButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.jumpButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *jcfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
    [self.jumpButton setImage:[UIImage systemImageNamed:@"chevron.down" withConfiguration:jcfg] forState:UIControlStateNormal];
    self.jumpButton.tintColor = IMTheme.textPrimary;
    self.jumpButton.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.jumpButton.layer.cornerRadius = 20;
    self.jumpButton.layer.shadowColor = UIColor.blackColor.CGColor;
    self.jumpButton.layer.shadowOpacity = 0.18;
    self.jumpButton.layer.shadowRadius = 4;
    self.jumpButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.jumpButton.hidden = YES;
    [self.jumpButton addTarget:self action:@selector(jumpTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.jumpButton];

    self.jumpBadge = [UILabel new];
    self.jumpBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.jumpBadge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.jumpBadge.textColor = UIColor.whiteColor;
    self.jumpBadge.backgroundColor = IMTheme.unreadBadge; // 与会话列表未读一致（蓝）
    self.jumpBadge.textAlignment = NSTextAlignmentCenter;
    self.jumpBadge.layer.cornerRadius = 9;
    self.jumpBadge.layer.masksToBounds = YES;
    self.jumpBadge.hidden = YES;
    [self.view addSubview:self.jumpBadge];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    self.inputBottom = [inputBar.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor];
    self.typingHeight = [self.typingLabel.heightAnchor constraintEqualToConstant:0];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.typingLabel.topAnchor],

        [self.typingLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.typingLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.typingLabel.bottomAnchor constraintEqualToAnchor:inputBar.topAnchor],
        self.typingHeight,

        [inputBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [inputBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.inputBottom,
        [inputBar.heightAnchor constraintEqualToConstant:56],

        [self.inputField.leadingAnchor constraintEqualToAnchor:inputBar.leadingAnchor constant:12],
        [self.inputField.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [self.inputField.heightAnchor constraintEqualToConstant:36],
        [self.inputField.trailingAnchor constraintEqualToAnchor:sendButton.leadingAnchor constant:-8],
        [sendButton.trailingAnchor constraintEqualToAnchor:inputBar.trailingAnchor constant:-12],
        [sendButton.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [sendButton.widthAnchor constraintEqualToConstant:36],
        [sendButton.heightAnchor constraintEqualToConstant:36],

        [self.jumpButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.jumpButton.bottomAnchor constraintEqualToAnchor:self.typingLabel.topAnchor constant:-12],
        [self.jumpButton.widthAnchor constraintEqualToConstant:40],
        [self.jumpButton.heightAnchor constraintEqualToConstant:40],
        [self.jumpBadge.centerXAnchor constraintEqualToAnchor:self.jumpButton.trailingAnchor constant:-5],
        [self.jumpBadge.centerYAnchor constraintEqualToAnchor:self.jumpButton.topAnchor constant:5],
        [self.jumpBadge.heightAnchor constraintEqualToConstant:18],
        [self.jumpBadge.widthAnchor constraintGreaterThanOrEqualToConstant:18],
    ]];

}

#pragma mark - 发送 / 接收

/// 输入变化 → 发「正在输入」（2s 节流，避免每次按键都发）。
- (void)inputChanged {
    if (self.inputField.text.length == 0) { return; }
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (now - self.lastTypingSent > 2.0) {
        self.lastTypingSent = now;
        [IMSocketManager.sharedManager sendTypingForConv:self.convID];
    }
}

- (void)sendTapped {
    NSString *text = [self.inputField.text stringByTrimmingCharactersInSet:
                      NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length == 0) { return; }

    __block NSString *clientMsgID = nil;
    __weak typeof(self) weakSelf = self;
    clientMsgID = [IMSocketManager.sharedManager sendText:text toUser:self.peerID
                                               completion:^(BOOL success, NSError *error, int64_t convSeq) {
        [weakSelf handleSendResult:success convSeq:convSeq error:error forClientMsgID:clientMsgID];
    }];

    IMMessageModel *m = [IMMessageModel new];
    m.clientMsgID = clientMsgID;
    m.convID = self.convID;
    m.to = self.peerID;
    m.content = text;
    m.from = self.userID;
    m.contentType = @"text";
    m.status = IMMessageStatusSending;
    m.timestamp = (int64_t)(NSDate.date.timeIntervalSince1970 * 1000); // 本地时间，气泡尾巴即时显示时间（与 Web 一致）
    [IMDatabase.sharedDatabase saveMessage:m]; // 落库（sending）
    [self.messages addObject:m];
    self.inputField.text = @"";
    [self appendReloadAndScroll];
}

- (void)handleSendResult:(BOOL)success convSeq:(int64_t)convSeq error:(NSError *)error forClientMsgID:(NSString *)clientMsgID {
    for (IMMessageModel *m in self.messages) {
        if ([m.clientMsgID isEqualToString:clientMsgID]) {
            m.status = success ? IMMessageStatusSent : IMMessageStatusFailed;
            // 被拉黑拒收（errcode 200102）→ 把服务端友好文案挂到 note，气泡下方居中显示（微信式）；
            // 其余失败（如 ack 超时）不挂 note，仍显"未发送 ✗"。
            m.note = (!success && error.code == 200102) ? error.localizedDescription : nil;
            m.convSeq = convSeq;
            [IMDatabase.sharedDatabase saveMessage:m]; // upsert：更新状态/conv_seq
            if (convSeq > 0) { [self.seenConvSeqs addObject:@(convSeq)]; } // 防 sync 重复回显自己发的
            break;
        }
    }
    [self.tableView reloadData];
}

#pragma mark - IMSocketManagerDelegate（主线程回调）

- (void)socketManager:(IMSocketManager *)manager didChangeState:(IMSocketState)state {
    self.connState = state;
    [self updateTitle];
    if (state == IMSocketStateConnected) {
        [self markVisibleRowsRead]; // 重连后把当前可见的补报一次已读（可见即读）
    }
}

/// 标题：在线点 + 对方 uid + 连接态。
- (void)updateTitle {
    NSString *dot = self.peerOnline ? @"🟢 " : @"";
    NSString *suffix = @"";
    switch (self.connState) {
        case IMSocketStateConnected:    suffix = self.peerOnline ? @"（在线）" : @""; break;
        case IMSocketStateConnecting:   suffix = @"（连接中…）"; break;
        case IMSocketStateDisconnected: suffix = @"（未连接）"; break;
    }
    self.title = [NSString stringWithFormat:@"%@%@%@", dot, self.peerID, suffix];
}

- (void)socketManager:(IMSocketManager *)manager didReceiveMessage:(IMMessageModel *)message {
    [IMDatabase.sharedDatabase saveMessage:message]; // 任何会话的消息都落库（按 conv_seq 幂等）
    if (![message.convID isEqualToString:self.convID]) { return; } // 非本会话不在此页显示
    // 同一条消息可能既被 new_msg 推送、又被 sync_resp 拉到，按 conv_seq 去重。
    if (message.convSeq > 0) {
        NSNumber *key = @(message.convSeq);
        if ([self.seenConvSeqs containsObject:key]) { return; }
        [self.seenConvSeqs addObject:key];
    }
    // 收到新消息：贴底才自动贴底；在上方看历史则不打断，累加到"↓N"（CHAT_UX §9）。
    BOOL wasNearBottom = [self isNearBottom];
    [self.messages addObject:message];
    [self.tableView reloadData];
    if (wasNearBottom) { [self scrollToBottomAnimated:YES]; }
    // 可见即读 + ↓N 刷新：贴底时新消息进视口即标已读；在上方看历史则不读、↓N 计数 +1（markVisibleRowsRead 内重算）。
    [self markVisibleRowsRead];
}

/// 对端已读到 upToConvSeq → 记录并刷新（已送达 → 已读）。
- (void)socketManager:(IMSocketManager *)manager didReadConv:(NSString *)convID by:(NSString *)from upToConvSeq:(int64_t)convSeq {
    if (![convID isEqualToString:self.convID] || [from isEqualToString:self.userID]) { return; }
    if (convSeq > self.peerReadSeq) {
        self.peerReadSeq = convSeq;
        [self.tableView reloadData];
    }
}

/// 对端正在输入 → 展开提示条，3s 后自动收起。
- (void)socketManager:(IMSocketManager *)manager didTypingInConv:(NSString *)convID by:(NSString *)from {
    if (![convID isEqualToString:self.convID] || [from isEqualToString:self.userID]) { return; }
    self.typingHeight.constant = 20;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideTyping) object:nil];
    [self performSelector:@selector(hideTyping) withObject:nil afterDelay:3.0];
}

- (void)hideTyping {
    self.typingHeight.constant = 0;
}

/// 对端在线状态变化 → 更新标题在线点。
- (void)socketManager:(IMSocketManager *)manager didChangePresenceForUser:(NSString *)user online:(BOOL)online {
    if (![user isEqualToString:self.peerID]) { return; }
    self.peerOnline = online;
    [self updateTitle];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendTapped];
    return NO;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"bubble" forIndexPath:indexPath];
    IMMessageModel *m = self.messages[indexPath.row];
    BOOL mine = [m.from isEqualToString:self.userID];
    BOOL showsDivider = (indexPath.row == [self firstUnreadRow]);
    [cell configureWithMessage:m mine:mine peerReadSeq:self.peerReadSeq
                     dayHeader:[self dayHeaderForRow:indexPath.row]
            showsUnreadDivider:showsDivider];
    return cell;
}

/// 按时间分组：每自然日首条消息上方显示日期分隔胶囊（今天/昨天/M月d日）。无效时间或同日返回 nil。
- (NSString *)dayHeaderForRow:(NSInteger)row {
    IMMessageModel *m = self.messages[row];
    if (m.timestamp <= 0) { return nil; } // 发送中（未拿到服务端时间）不显示日期
    if (row == 0) { return [IMTheme dayHeaderStringFromMillis:m.timestamp]; }
    IMMessageModel *prev = self.messages[row - 1];
    if ([IMTheme isMillis:m.timestamp sameDayAsMillis:prev.timestamp]) { return nil; }
    return [IMTheme dayHeaderStringFromMillis:m.timestamp];
}

#pragma mark - 长按消息菜单（复制 / 删除）

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
    contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    if (indexPath.row >= (NSInteger)self.messages.count) { return nil; }
    IMMessageModel *message = self.messages[indexPath.row];
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
            UIAction *copy = [UIAction actionWithTitle:@"复制"
                image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil
                handler:^(__kindof UIAction *a) {
                    UIPasteboard.generalPasteboard.string = message.content ?: @"";
                }];
            UIAction *del = [UIAction actionWithTitle:@"删除"
                image:[UIImage systemImageNamed:@"trash"] identifier:nil
                handler:^(__kindof UIAction *a) { [weakSelf deleteMessage:message]; }];
            del.attributes = UIMenuElementAttributesDestructive;
            return [UIMenu menuWithTitle:@"" children:@[copy, del]];
        }];
}

/// 本地删除一条消息（仅本端：从库 + 内存移除并刷新；不影响对端）。
- (void)deleteMessage:(IMMessageModel *)message {
    [IMDatabase.sharedDatabase deleteMessage:message];
    [self.messages removeObject:message];
    if (message.convSeq > 0) { [self.seenConvSeqs removeObject:@(message.convSeq)]; }
    [self.tableView reloadData];
}

/// 首条未读所在行：conv_seq > entryReadSeq 的第一条「对端」消息；无未读返回 -1。
- (NSInteger)firstUnreadRow {
    if (self.entryUnread <= 0) { return -1; }
    for (NSInteger i = 0; i < (NSInteger)self.messages.count; i++) {
        IMMessageModel *m = self.messages[i];
        if (m.convSeq > self.entryReadSeq && ![m.from isEqualToString:self.userID]) { return i; }
    }
    return -1;
}

/// 进会话定位（只做一次）：有未读则停在首条未读，否则到底（CHAT_UX §3）。
- (void)positionInitialIfNeeded {
    if (self.didInitialPosition || self.messages.count == 0) { return; }
    self.didInitialPosition = YES;
    NSInteger unreadRow = [self firstUnreadRow];
    NSInteger target = unreadRow >= 0 ? unreadRow : (NSInteger)self.messages.count - 1;
    UITableViewScrollPosition pos = unreadRow >= 0 ? UITableViewScrollPositionTop : UITableViewScrollPositionBottom;
    [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:target inSection:0]
                          atScrollPosition:pos animated:NO];
    // 定位后下一轮 runloop（偏移落定）再扫一遍可见行：推进已读 + 刷新 ↓N（未读整屏放得下则不显示）。
    dispatch_async(dispatch_get_main_queue(), ^{ [self markVisibleRowsRead]; });
}

/// 可见即读（CHAT_UX §6 完整语义）：扫描当前在视口内的行，取其最大 conv_seq；
/// 若超过已滚入位点则记录并节流上报（read_seq 单调推进，对端据此显示已读双勾、列表未读递减）。
- (void)markVisibleRowsRead {
    int64_t maxSeq = 0;
    for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
        if (ip.row < (NSInteger)self.messages.count) {
            int64_t s = self.messages[ip.row].convSeq;
            if (s > maxSeq) { maxSeq = s; }
        }
    }
    if (maxSeq > self.pendingReadSeq) {
        self.pendingReadSeq = maxSeq;
        // 节流：滚动停 0.3s 后才真正发，避免每像素一条 receipt。
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flushReadPosition) object:nil];
        [self performSelector:@selector(flushReadPosition) withObject:nil afterDelay:0.3];
    }
    [self updateJumpButton]; // 位点推进/新消息后刷新 ↓N 计数
}

/// 把节流累积的已读位点上报（仅在超过上次上报值时发）。
- (void)flushReadPosition {
    if (self.pendingReadSeq > self.maxReadReported) {
        self.maxReadReported = self.pendingReadSeq;
        [IMSocketManager.sharedManager markReadConv:self.convID upToConvSeq:self.maxReadReported];
    }
}

#pragma mark - 辅助

/// 自己发送：刷新 + 始终贴底（贴底后 ↓N 自动隐藏）。
- (void)appendReloadAndScroll {
    [self.tableView reloadData];
    [self scrollToBottomAnimated:YES];
    [self markVisibleRowsRead];
}

#pragma mark - ↓N 跳转按钮 / 自动滚动（CHAT_UX §7、§9）

- (void)scrollToBottomAnimated:(BOOL)animated {
    if (self.messages.count == 0) { return; }
    NSIndexPath *last = [NSIndexPath indexPathForRow:self.messages.count - 1 inSection:0];
    [self.tableView scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

/// 是否贴近底部（距底 < 80pt，计入底部安全区 inset）。
- (BOOL)isNearBottom {
    UIScrollView *sv = self.tableView;
    CGFloat distance = sv.contentSize.height - sv.contentOffset.y - sv.bounds.size.height + sv.adjustedContentInset.bottom;
    return distance < 80;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (self.tableView.contentSize.height <= 0) { return; }
    [self markVisibleRowsRead]; // 可见即读：滚到哪、读到哪（先推进 pendingReadSeq）
    [self updateJumpButton];    // 再据新位点刷新 ↓N 计数
}

/// 据当前滚动位置显示/隐藏"↓N"：贴底则隐藏；离底则显示，徽标=视口下方未读数（随滚动递减）。
- (void)updateJumpButton {
    if ([self isNearBottom]) {
        self.jumpButton.hidden = YES;
        self.jumpBadge.hidden = YES;
        return;
    }
    self.jumpButton.hidden = NO;
    NSInteger below = [self unreadBelowReadFrontier];
    if (below > 0) {
        self.jumpBadge.hidden = NO;
        self.jumpBadge.text = below > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)below];
    } else {
        self.jumpBadge.hidden = YES;
    }
}

/// 视口下方仍未读的对端消息数 = conv_seq 超过已滚入位点(pendingReadSeq)的对端消息数。
/// 随着向下滚动 pendingReadSeq 推进 → 该数递减，滚到底为 0。
- (NSInteger)unreadBelowReadFrontier {
    NSInteger n = 0;
    for (IMMessageModel *m in self.messages) {
        if (![m.from isEqualToString:self.userID] && m.convSeq > self.pendingReadSeq) { n++; }
    }
    return n;
}

- (void)jumpTapped {
    [self scrollToBottomAnimated:YES];
    [self updateJumpButton];
}

- (void)observeKeyboard {
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWillChange:)
                                               name:UIKeyboardWillChangeFrameNotification object:nil];
}

- (void)keyboardWillChange:(NSNotification *)note {
    CGRect endFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat overlap = CGRectGetHeight(self.view.bounds) - [self.view convertRect:endFrame fromView:nil].origin.y;
    self.inputBottom.constant = -MAX(0, overlap - self.view.safeAreaInsets.bottom);
    [self.view layoutIfNeeded];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

@end
