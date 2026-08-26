//
//  IMVoiceBubbleCell.m
//

#import "IMVoiceBubbleCell.h"
#import "IMWaveformView.h"
#import "IMVoicePlayer.h"
#import "IMMessageModel.h"
#import "IMTheme.h"
#import "IMTimeUtil.h"
#import "IMVoiceTranscriber.h" // 复用缓存自动展开转写面板（cell 复用后不丢文字，2026-08-27 修）
#import "UILabel+IMAvatar.h"

@interface IMVoiceBubbleCell () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) IMWaveformView *waveform;
@property (nonatomic, strong) UILabel *durationLabel;  ///< 底行左：仅时长 "0:12"（播放中显剩余）
@property (nonatomic, strong) UILabel *timeLabel;      ///< 底行右：消息时间 "HH:mm ✓/✓✓"（对齐 IMBubbleCell 口径）
@property (nonatomic, strong) UIView *unplayedDot;
@property (nonatomic, strong) UILabel *senderLabel;
@property (nonatomic, strong) UILabel *dayHeader;
@property (nonatomic, strong) UILabel *scrubTip;   ///< scrub 拖拽时的时间气泡（"0:07 / 0:12"）
@property (nonatomic, strong) UIButton *speedPill; ///< 播放中显：1x / 1.5x / 2x（会话级记忆）
@property (nonatomic, strong) UIView *transcriptPanel;    ///< 转写面板（贴气泡下方，收起=hidden）
@property (nonatomic, strong) UIView *transcriptRule;     ///< 面板左侧蓝色引用线（与引用条视觉语系一致）
@property (nonatomic, strong) UILabel *transcriptLabel;
@property (nonatomic, strong) UILabel *transcriptFooter;  ///< 隐私边界说明（直接写在界面上）
@property (nonatomic, strong) NSLayoutConstraint *transcriptTopSpacing;

@property (nonatomic, copy, nullable) NSString *currentID;
@property (nonatomic, copy, nullable) NSString *currentConvID;
@property (nonatomic, assign) int64_t totalDurationMillis;
@property (nonatomic, assign) BOOL mine;

@property (nonatomic, strong) NSLayoutConstraint *bubbleLeadingLeft;   ///< 对方消息：左对齐（头像右）
@property (nonatomic, strong) NSLayoutConstraint *bubbleTrailingRight; ///< 自己消息：右对齐
@property (nonatomic, strong) NSLayoutConstraint *bubbleWidth;         ///< 按 duration 线性长；每次 configure 只改 constant，不再追加约束
@property (nonatomic, strong) NSLayoutConstraint *bubbleMaxTrailing;   ///< 对方气泡右侧最小留白（防长语音贴屏边）
@property (nonatomic, strong) NSLayoutConstraint *bubbleMinLeading;    ///< 自己气泡左侧最小留白
@property (nonatomic, strong) NSLayoutConstraint *scrubTipCenterX;
@property (nonatomic, assign) BOOL scrubbing;
@property (nonatomic, strong) UIButton *statusBadge;   ///< 发送失败红 !（§5.5：failed → 红标+点击重试；仅 mine）
@property (nonatomic, strong) UILabel *readMark;       ///< 气泡右下 ✓/✓✓（mine 已发出后显；单聊按 peerReadSeq 变色，群聊只显 ✓）
@property (nonatomic, assign) BOOL showsPauseIcon;     ///< 播放键当前图标缓存：30fps 进度 tick 只在状态切换时才 setImage
@property (nonatomic, strong) NSLayoutConstraint *panelLeadingMine;
@property (nonatomic, strong) NSLayoutConstraint *panelTrailingMine;
@property (nonatomic, strong) NSLayoutConstraint *panelLeadingPeer;
@property (nonatomic, strong) NSLayoutConstraint *panelTrailingPeer;
@property (nonatomic, strong) NSLayoutConstraint *dayHeaderHeight;
@property (nonatomic, strong) NSLayoutConstraint *senderTopSpacing;
@end

@implementation IMVoiceBubbleCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    UIView *cv = self.contentView;

    _dayHeader = [UILabel new];
    _dayHeader.translatesAutoresizingMaskIntoConstraints = NO;
    _dayHeader.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    _dayHeader.textColor = IMTheme.textSecondary;
    _dayHeader.textAlignment = NSTextAlignmentCenter;
    _dayHeader.hidden = YES;
    [cv addSubview:_dayHeader];

    _senderLabel = [UILabel new];
    _senderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _senderLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    _senderLabel.textColor = IMTheme.textSecondary;
    _senderLabel.hidden = YES;
    [cv addSubview:_senderLabel];
    [self installSenderRoleBadgeForNameLabel:_senderLabel];

    _bubble = [UIView new];
    _bubble.translatesAutoresizingMaskIntoConstraints = NO;
    _bubble.layer.masksToBounds = YES;
    [cv addSubview:_bubble];

    _playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _playButton.translatesAutoresizingMaskIntoConstraints = NO;
    _playButton.backgroundColor = IMTheme.accent;
    _playButton.tintColor = UIColor.whiteColor;
    _playButton.layer.cornerRadius = 17;
    UIImageSymbolConfiguration *pcfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold];
    [_playButton setImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:pcfg] forState:UIControlStateNormal];
    [_playButton addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    [_bubble addSubview:_playButton];

    _waveform = [IMWaveformView new];
    _waveform.translatesAutoresizingMaskIntoConstraints = NO;
    [_bubble addSubview:_waveform];

    _durationLabel = [UILabel new];
    _durationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _durationLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    _durationLabel.textColor = IMTheme.textSecondary;
    [_bubble addSubview:_durationLabel];

    // 右下时间 + 勾（2026-08-27 修：与 IMBubbleCell 口径统一——语音气泡右下角必须显消息 HH:mm）。
    _timeLabel = [UILabel new];
    _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _timeLabel.font = [UIFont systemFontOfSize:11];
    _timeLabel.textColor = IMTheme.textSecondary;
    _timeLabel.textAlignment = NSTextAlignmentRight;
    [_bubble addSubview:_timeLabel];

    _unplayedDot = [UIView new];
    _unplayedDot.translatesAutoresizingMaskIntoConstraints = NO;
    _unplayedDot.backgroundColor = UIColor.systemRedColor;
    _unplayedDot.layer.cornerRadius = 3.5;
    _unplayedDot.hidden = YES;
    [_bubble addSubview:_unplayedDot];

    // 倍速胶囊（P1）：仅播放中出现（默认 alpha 0）。会话级记忆，从 IMVoicePlayer 取当前 rate。
    _speedPill = [UIButton buttonWithType:UIButtonTypeSystem];
    _speedPill.translatesAutoresizingMaskIntoConstraints = NO;
    _speedPill.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightBold];
    _speedPill.layer.cornerRadius = 8;
    _speedPill.layer.masksToBounds = YES;
    _speedPill.contentEdgeInsets = UIEdgeInsetsMake(2, 6, 2, 6);
    _speedPill.alpha = 0;
    _speedPill.userInteractionEnabled = NO;
    [_speedPill addTarget:self action:@selector(speedTapped) forControlEvents:UIControlEventTouchUpInside];
    [_bubble addSubview:_speedPill];

    // scrub tip（P1）：拖拽波形时浮出的 "0:07 / 0:12" 时间气泡（深底白字）。
    _scrubTip = [UILabel new];
    _scrubTip.translatesAutoresizingMaskIntoConstraints = NO;
    _scrubTip.font = [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightSemibold];
    _scrubTip.textColor = UIColor.whiteColor;
    _scrubTip.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.9];
    _scrubTip.layer.cornerRadius = 6;
    _scrubTip.layer.masksToBounds = YES;
    _scrubTip.textAlignment = NSTextAlignmentCenter;
    _scrubTip.alpha = 0;
    [_bubble addSubview:_scrubTip];

    // 转写面板（P1）：贴气泡下方，收起=hidden。左侧蓝色引用线 + 文本 + 尾行小字。
    _transcriptPanel = [UIView new];
    _transcriptPanel.translatesAutoresizingMaskIntoConstraints = NO;
    _transcriptPanel.hidden = YES;
    [cv addSubview:_transcriptPanel];
    _transcriptRule = [UIView new];
    _transcriptRule.translatesAutoresizingMaskIntoConstraints = NO;
    _transcriptRule.backgroundColor = IMTheme.accent;
    _transcriptRule.layer.cornerRadius = 1.25;
    [_transcriptPanel addSubview:_transcriptRule];
    _transcriptLabel = [UILabel new];
    _transcriptLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _transcriptLabel.font = [UIFont systemFontOfSize:14];
    _transcriptLabel.textColor = IMTheme.textPrimary;
    _transcriptLabel.numberOfLines = 0;
    [_transcriptPanel addSubview:_transcriptLabel];
    _transcriptFooter = [UILabel new];
    _transcriptFooter.translatesAutoresizingMaskIntoConstraints = NO;
    _transcriptFooter.font = [UIFont systemFontOfSize:10];
    _transcriptFooter.textColor = IMTheme.textSecondary;
    // 识别已从端上改到服务端（VOICE_TRANSCRIBE_DESIGN）：文案必须跟着改，
    // 否则界面上写着"仅本地保存"而实际结果存在服务端，是**错误的隐私承诺**。
    _transcriptFooter.text = @"📝 由服务器识别，结果可能不完全准确";
    [_transcriptPanel addSubview:_transcriptFooter];

    // 发送失败红 !（§5.5）：气泡左侧外（mine 气泡右对齐），点击=重试。默认隐藏。
    _statusBadge = [UIButton buttonWithType:UIButtonTypeSystem];
    _statusBadge.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *failCfg = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold];
    [_statusBadge setImage:[UIImage systemImageNamed:@"exclamationmark.circle.fill" withConfiguration:failCfg] forState:UIControlStateNormal];
    _statusBadge.tintColor = UIColor.systemRedColor;
    _statusBadge.hidden = YES;
    [_statusBadge addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];
    [cv addSubview:_statusBadge];

    // 群头由基类 _avatar 承载：leading/bottom 由本 cell 补约束。
    _avatar.translatesAutoresizingMaskIntoConstraints = NO;
    [cv addSubview:_avatar];

    [self setupConstraints];

    // 长按菜单由聊天页统一挂 UIContextMenuInteraction 到 previewTargetView（见 IMChatViewController+Menu.m
    // attachMessageContextMenuToCell:）——本 cell 不自加长按手势，避免与系统交互重复触发。

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onPlayerChanged:)
                                                 name:IMVoicePlayerDidChangeStateNotification object:nil];
}

- (void)setupConstraints {
    UIView *cv = self.contentView;
    _dayHeaderHeight = [_dayHeader.heightAnchor constraintEqualToConstant:0];
    _senderTopSpacing = [_senderLabel.topAnchor constraintEqualToAnchor:_unreadDivider.bottomAnchor constant:4];

    _bubbleLeadingLeft = [_bubble.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:8];
    _bubbleTrailingRight = [_bubble.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-10];
    _bubbleWidth = [_bubble.widthAnchor constraintEqualToConstant:180];
    _bubbleWidth.active = YES;
    _bubbleMaxTrailing = [_bubble.trailingAnchor constraintLessThanOrEqualToAnchor:cv.trailingAnchor constant:-60];
    _bubbleMinLeading = [_bubble.leadingAnchor constraintGreaterThanOrEqualToAnchor:cv.leadingAnchor constant:60];

    [NSLayoutConstraint activateConstraints:@[
        // 未读分割线（基类）：顶到 contentView 顶。
        [_unreadDivider.topAnchor constraintEqualToAnchor:cv.topAnchor],
        [_unreadDivider.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor],
        [_unreadDivider.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor],
        // 日期分隔：贴在未读分割线下。
        [_dayHeader.topAnchor constraintEqualToAnchor:_unreadDivider.bottomAnchor],
        [_dayHeader.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor],
        [_dayHeader.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor],
        _dayHeaderHeight,
        // 发送者昵称（仅群聊对端）
        _senderTopSpacing,
        [_senderLabel.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:8],
        // 头像：连续段末条显示；底与气泡底同高
        [_avatar.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:10],
        [_avatar.widthAnchor constraintEqualToConstant:32],
        [_avatar.heightAnchor constraintEqualToConstant:32],
        [_avatar.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor],
        // 气泡定位（左右锚随 mine 切换，见 configure）。高度 75pt = 8(上) + 24(波形) + 4 + 14(时长行)
        // + 3 + 14(时间行) + 8(下)。播放键**居中于「波形+时长行」这一组**（不含独立时间行），
        // 2026-08-27 用户拍板：波形与时长要与左侧 ▶ 视觉居中。
        [_bubble.topAnchor constraintEqualToAnchor:_senderLabel.bottomAnchor constant:2],
        [_bubble.heightAnchor constraintEqualToConstant:75],
        // 转写面板（默认 hidden 且 top spacing=0，不占额外高度）。show 时 spacing=8。
        [_transcriptPanel.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-4],
        // 与气泡同侧对齐（configure 时按 mine 切）
        [_transcriptRule.leadingAnchor constraintEqualToAnchor:_transcriptPanel.leadingAnchor],
        [_transcriptRule.topAnchor constraintEqualToAnchor:_transcriptPanel.topAnchor constant:2],
        [_transcriptRule.bottomAnchor constraintEqualToAnchor:_transcriptPanel.bottomAnchor constant:-2],
        [_transcriptRule.widthAnchor constraintEqualToConstant:2.5],
        [_transcriptLabel.leadingAnchor constraintEqualToAnchor:_transcriptRule.trailingAnchor constant:9],
        [_transcriptLabel.trailingAnchor constraintEqualToAnchor:_transcriptPanel.trailingAnchor],
        [_transcriptLabel.topAnchor constraintEqualToAnchor:_transcriptPanel.topAnchor],
        [_transcriptFooter.leadingAnchor constraintEqualToAnchor:_transcriptLabel.leadingAnchor],
        [_transcriptFooter.trailingAnchor constraintEqualToAnchor:_transcriptLabel.trailingAnchor],
        [_transcriptFooter.topAnchor constraintEqualToAnchor:_transcriptLabel.bottomAnchor constant:5],
        [_transcriptFooter.bottomAnchor constraintEqualToAnchor:_transcriptPanel.bottomAnchor],
        // 气泡内元素（用户 2026-08-27 新布局：▶ 居左垂直居中 · 中间 vertical stack 波形/时长·时间行）
        [_playButton.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:6],
        // ▶ 居中于「波形 + 时长行」组：组高 = 24(波形) + 4(gap) + 14(时长) = 42 → 半高 21。
        // 用固定常量而非 centerY 对齐 bubble：时间行是独立第三行，不该把居中轴往下拽。
        [_playButton.centerYAnchor constraintEqualToAnchor:_waveform.topAnchor constant:21],
        [_playButton.widthAnchor constraintEqualToConstant:34],
        [_playButton.heightAnchor constraintEqualToConstant:34],
        [_waveform.leadingAnchor constraintEqualToAnchor:_playButton.trailingAnchor constant:9],
        [_waveform.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-10],
        [_waveform.topAnchor constraintEqualToAnchor:_bubble.topAnchor constant:8],
        [_waveform.heightAnchor constraintEqualToConstant:24],
        // 时长行：左=时长（播放中显剩余），右端=倍速胶囊（播放中淡入）。高度固定以锁死 ▶ 的居中轴。
        [_durationLabel.leadingAnchor constraintEqualToAnchor:_waveform.leadingAnchor],
        [_durationLabel.topAnchor constraintEqualToAnchor:_waveform.bottomAnchor constant:4],
        [_durationLabel.heightAnchor constraintEqualToConstant:14],
        [_durationLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_speedPill.leadingAnchor constant:-4],
        // 时间行（2026-08-27 用户拍板独立一行，iOS/Web 拉齐）：右对齐 "HH:mm ✓/✓✓"。
        [_timeLabel.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-10],
        [_timeLabel.topAnchor constraintEqualToAnchor:_durationLabel.bottomAnchor constant:3],
        [_timeLabel.heightAnchor constraintEqualToConstant:14],
        [_unplayedDot.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-10],
        [_unplayedDot.topAnchor constraintEqualToAnchor:_bubble.topAnchor constant:6],
        [_unplayedDot.widthAnchor constraintEqualToConstant:7],
        [_unplayedDot.heightAnchor constraintEqualToConstant:7],
        // 倍速胶囊：时长行右端（原右上位置与波形横向重叠——2026-08-27 修 #1）。16pt 高避免贴到时间行。
        [_speedPill.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-8],
        [_speedPill.centerYAnchor constraintEqualToAnchor:_durationLabel.centerYAnchor],
        [_speedPill.heightAnchor constraintEqualToConstant:16],
        // scrub tip：波形正上方 4pt；水平 centerX 由拖拽时动态更新
        [_scrubTip.centerYAnchor constraintEqualToAnchor:_waveform.topAnchor constant:-10],
        [_scrubTip.heightAnchor constraintEqualToConstant:16],
        [_scrubTip.widthAnchor constraintGreaterThanOrEqualToConstant:60],
    ]];
    // scrub tip 的 centerX：以 waveform 左缘为起点、动态 offset。默认放中间（避免约束缺失）。
    _scrubTipCenterX = [_scrubTip.centerXAnchor constraintEqualToAnchor:_waveform.leadingAnchor constant:0];
    _scrubTipCenterX.active = YES;
    [NSLayoutConstraint activateConstraints:@[
        [_statusBadge.trailingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:-6],
        [_statusBadge.centerYAnchor constraintEqualToAnchor:_bubble.centerYAnchor],
        [_statusBadge.widthAnchor constraintEqualToConstant:28],
        [_statusBadge.heightAnchor constraintEqualToConstant:28],
    ]];
    _transcriptTopSpacing = [_transcriptPanel.topAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:0];
    _transcriptTopSpacing.active = YES;
    // 转写面板与气泡同侧对齐——两对约束按 mine toggle。
    _panelTrailingMine = [_transcriptPanel.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor];
    _panelLeadingMine = [_transcriptPanel.leadingAnchor constraintGreaterThanOrEqualToAnchor:cv.leadingAnchor constant:60];
    _panelLeadingPeer = [_transcriptPanel.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor];
    _panelTrailingPeer = [_transcriptPanel.trailingAnchor constraintLessThanOrEqualToAnchor:cv.trailingAnchor constant:-60];

    // 波形拖拽 scrub（P1）：pan 手势。>=4pt 阈值避免与列表滚动打架。
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(scrubPan:)];
    pan.maximumNumberOfTouches = 1;
    pan.delegate = self;
    [_waveform addGestureRecognizer:pan];
    _waveform.userInteractionEnabled = YES;
}

- (UIView *)previewTargetView { return self.bubble; }

- (void)configureWithMessage:(IMMessageModel *)message
                        mine:(BOOL)mine
                   dayHeader:(NSString *)dayHeader
          showsUnreadDivider:(BOOL)showsDivider
                  senderName:(NSString *)senderName
                  senderRole:(IMGroupRole)senderRole
                    hasPlayed:(BOOL)hasPlayed
                 peerReadSeq:(int64_t)peerReadSeq
              isGroupContext:(BOOL)isGroupContext {
    self.mine = mine;
    self.currentID = IMVoicePlayerPlayableIDForMessage(message);
    self.currentConvID = message.convID;
    self.totalDurationMillis = message.duration > 0 ? message.duration : 0;
    [self applySpeedLabel:[[IMVoicePlayer sharedPlayer] rateForConvID:message.convID]];

    [self applyUnreadDivider:showsDivider];
    if (dayHeader.length > 0) {
        self.dayHeader.hidden = NO;
        self.dayHeader.text = dayHeader;
        self.dayHeaderHeight.constant = 24;
    } else {
        self.dayHeader.hidden = YES;
        self.dayHeaderHeight.constant = 0;
    }

    BOOL showsSender = !mine && senderName.length > 0;
    self.senderLabel.hidden = !showsSender;
    self.senderTopSpacing.constant = (showsSender ? (dayHeader.length > 0 ? 6 : 4) : 0);
    if (showsSender) { [self applySenderName:senderName role:senderRole toNameLabel:self.senderLabel]; }

    [IMTheme applyBubbleDirectionStyle:self.bubble mine:mine];
    // 气泡对齐：mine → 右；对方 → 左（贴头像右）。
    // 右侧/左侧的最小留白约束在 setupConstraints 建好，此处只 toggle active——避免复用 cell 时约束越加越多。
    self.bubbleLeadingLeft.active = !mine;
    self.bubbleTrailingRight.active = mine;
    self.bubbleMaxTrailing.active = !mine;
    self.bubbleMinLeading.active = mine;

    // 转写面板与气泡同侧对齐——toggle 已建约束，永不累加。
    self.panelLeadingMine.active = mine;
    self.panelTrailingMine.active = mine;
    self.panelLeadingPeer.active = !mine;
    self.panelTrailingPeer.active = !mine;
    // 复用 cell 时先收起转写面板，再查缓存自动展开——**cell 复用不再丢转写文字**（2026-08-27 修：
    // 曾靠宿主重新触发才展开，滚出屏再回来就消失；缓存本机永久，configure 里同步查询即可）。
    // 缓存 key = **音频路径**，与服务端 im_voice_transcript 主键同口径（转写按音频内容去重）。
    // 这替换掉了 2026-08-26 那版 per-uid+conv+mid 的 key —— 它的读写两侧 owner 取法不一致，
    // 群聊里必然对不上（写入用登录 uid，读取用 message.to，而群聊 to 为 nil）。
    // 本地折叠过（长按「取消转文字」）的条目不自动展开。
    IMVoiceTranscriber *tr = [IMVoiceTranscriber sharedTranscriber];
    NSString *cachedText = [tr isCollapsedMessageID:self.currentID] ? nil : [tr cachedTextForContent:message.content];
    [self layoutTranscriptText:cachedText loading:NO]; // 复用路径不触发整表重算（见方法注释）
    // scrub 残留清理：上一次未走 Ended 的 scrubTip 若还在 alpha=1，reuse 到别的 cell 会看到"幽灵时间条"。
    self.scrubTip.alpha = 0; self.scrubbing = NO;
    // 倍速胶囊 alpha 由 applyPlayerState 应用；复用先隐藏，避免闪一下上一条的胶囊。
    self.speedPill.alpha = 0; self.speedPill.userInteractionEnabled = NO;

    // 波形数据
    self.waveform.amplitudes = [IMWaveformView amplitudesFromBase64:message.waveform];
    self.waveform.progress = 0;
    // 波形配色：己方在浅绿气泡上用 bubbleMeText 高对比；对方在白/深灰气泡上用 accent 描 active、
    // inactive 用 textSecondary alpha 0.28（曾 0.45 偏深，画完后 active/inactive 都是灰蓝一片
    // 看不出扫过；2026-08-27 修 #6）。
    if (mine) {
        self.waveform.activeColor = IMTheme.bubbleMeText;
        self.waveform.inactiveColor = [IMTheme.bubbleMeText colorWithAlphaComponent:0.32];
        self.playButton.backgroundColor = [UIColor colorWithRed:0.12 green:0.48 blue:0.18 alpha:1.0];
    } else {
        self.waveform.activeColor = IMTheme.accent;
        self.waveform.inactiveColor = [IMTheme.textSecondary colorWithAlphaComponent:0.28];
        self.playButton.backgroundColor = IMTheme.accent;
    }
    // 气泡宽度按 duration 线性长（最少 160pt，最多 240pt——metaLabel 现要装"0:12·14:32 ✓✓"更宽，下限提高防挤，2026-08-27 修 #4）。
    CGFloat dur = MAX(1.0, message.duration / 1000.0);
    self.bubbleWidth.constant = MIN(240.0, MAX(160.0, 96.0 + dur * 3.6));

    // 底行拆两半：durationLabel（左）= 时长；timeLabel（右）= 消息时间 + 状态勾。
    // 2026-08-27 修 #1：时间必须在右下角对齐 IMBubbleCell。
    self.durationLabel.text = IMFormatVoiceDuration(self.totalDurationMillis);
    self.timeLabel.attributedText = [self rightMetaAttributedForMessage:message mine:mine
                                                             peerReadSeq:peerReadSeq
                                                          isGroupContext:isGroupContext];
    // 未播红点仅对方消息 + 本机未播过时显；hasPlayed 由宿主传入（已 mine || 查询 IMVoicePlayer 已播集合）。
    self.unplayedDot.hidden = mine || hasPlayed;
    // 发送失败红 !（§5.5「不静默失败」）：曾 ack 失败置 Failed 落库但气泡外观与成功完全一致（2026-08-26 修）。
    self.statusBadge.hidden = !(mine && message.status == IMMessageStatusFailed);

    // 同步当前播放器状态（切页/复用时保持进度）。
    IMVoicePlayerState st = [[IMVoicePlayer sharedPlayer] stateForMessageID:self.currentID];
    [self applyPlayerState:st progress:[[IMVoicePlayer sharedPlayer] progressForMessageID:self.currentID]];
}

- (NSString *)formatDur:(int64_t)ms { return IMFormatVoiceDuration(ms); }

/// 右下 meta（timeLabel 富文本）：与 IMBubbleCell.attributedMetaForMessage 完全同口径——
/// 对方 = "HH:mm"；己方发送中 = "发送中…"；己方失败 = "未发送 ✗"（红，被拒收 note 存在时只显时间）；
/// 己方已 ack = "HH:mm ✓" 或 "HH:mm ✓✓"（✓✓ 绿）。语音时长由左侧 durationLabel 独立承载。
- (NSAttributedString *)rightMetaAttributedForMessage:(IMMessageModel *)message mine:(BOOL)mine
                                          peerReadSeq:(int64_t)peerReadSeq isGroupContext:(BOOL)isGroupContext {
    UIFont *font = [UIFont systemFontOfSize:11];
    UIColor *secondary = IMTheme.textSecondary;
    NSDictionary *base = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: secondary };
    NSString *timeStr = [IMTheme timeStringFromMillis:message.timestamp]; // HH:mm

    if (!mine) {
        return [[NSAttributedString alloc] initWithString:(timeStr ?: @"") attributes:base];
    }
    if (message.status == IMMessageStatusSending) {
        return [[NSAttributedString alloc] initWithString:@"发送中…" attributes:base];
    }
    if (message.status == IMMessageStatusFailed) {
        if (message.note.length > 0) {
            return [[NSAttributedString alloc] initWithString:(timeStr ?: @"") attributes:base];
        }
        return [[NSAttributedString alloc] initWithString:@"未发送 ✗"
                                              attributes:@{ NSFontAttributeName: font,
                                                            NSForegroundColorAttributeName: UIColor.systemRedColor }];
    }
    if (message.convSeq > 0) {
        BOOL doubleTick = !isGroupContext && message.convSeq <= peerReadSeq;
        NSString *checks = doubleTick ? @"✓✓" : @"✓";
        NSString *plain = timeStr.length > 0 ? [NSString stringWithFormat:@"%@ %@", timeStr, checks] : checks;
        NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:plain attributes:base];
        NSRange r = [plain rangeOfString:checks options:NSBackwardsSearch];
        if (r.location != NSNotFound) {
            [s addAttribute:NSForegroundColorAttributeName value:(doubleTick ? IMTheme.checkRead : secondary) range:r];
        }
        return s;
    }
    return [[NSAttributedString alloc] initWithString:(timeStr ?: @"") attributes:base];
}

- (void)applyGroupAvatarURL:(NSString *)url seed:(NSString *)seed name:(NSString *)name showAvatar:(BOOL)showAvatar gutter:(BOOL)gutter {
    _avatar.hidden = !showAvatar;
    if (showAvatar) {
        [_avatar im_setAvatarURL:url seed:seed displayName:name];
    }
}

- (void)playTapped { if (self.onPlayTap) { self.onPlayTap(); } }
- (void)retryTapped { if (self.onRetryTap) { self.onRetryTap(); } }

/// 纯布局应用，**不通知 tableView**——`configure` 复用路径专用。
/// 2026-08-27 性能修：configure 原先直接调 applyTranscriptText:，而它内部 beginUpdates/endUpdates；
/// 即每个语音 cell 出队都在 cellForRow 内部强制整表重算行高 —— 语音消息一多，滑动肉眼卡顿。
- (void)layoutTranscriptText:(nullable NSString *)text loading:(BOOL)loading {
    BOOL shows = loading || (text.length > 0);
    self.transcriptPanel.hidden = !shows;
    self.transcriptTopSpacing.constant = shows ? 8 : 0;
    if (shows) {
        self.transcriptLabel.text = loading ? @"识别中…" : text;
        self.transcriptFooter.hidden = loading; // 识别中不显尾行
    }
}

/// 宿主主动触发（长按「转文字」→ 识别中/完成）：改布局后才需通知 tableView 重算行高。
- (void)applyTranscriptText:(NSString *)text loading:(BOOL)loading {
    [self layoutTranscriptText:text loading:loading];
    UITableView *tv = [self findTableView];
    if (tv) {
        [tv beginUpdates];
        [tv endUpdates];
    }
}

- (nullable UITableView *)findTableView {
    UIView *v = self.superview;
    while (v && ![v isKindOfClass:[UITableView class]]) { v = v.superview; }
    return (UITableView *)v;
}

#pragma mark - Scrub + Speed (P1)

// pan 与 UIScrollView 冲突：只有起始位移横向占优、且是"正在播/暂停"这条消息时才拿下手势
// （否则让 tableView 正常滚动）。同时用 4pt 阈值避免误触。
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)r shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return NO; // scrub 独占
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)r {
    if (![r isKindOfClass:[UIPanGestureRecognizer class]]) { return YES; }
    if (!self.currentID) { return NO; }
    IMVoicePlayerState st = [[IMVoicePlayer sharedPlayer] stateForMessageID:self.currentID];
    // 未加载/未播过的语音也允许拖拽——但需 duration>0 才有意义
    if (st == IMVoicePlayerStateIdle) { return NO; }
    CGPoint v = [(UIPanGestureRecognizer *)r velocityInView:self.waveform];
    return fabs(v.x) >= fabs(v.y); // 横向占优才接管
}

- (void)scrubPan:(UIPanGestureRecognizer *)g {
    if (!self.currentID) { return; }
    CGPoint pt = [g locationInView:self.waveform];
    CGFloat w = CGRectGetWidth(self.waveform.bounds);
    if (w <= 0) { return; }
    double p = MAX(0.0, MIN(1.0, pt.x / w));
    switch (g.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged: {
            if (!self.scrubbing) {
                self.scrubbing = YES;
                self.scrubTip.alpha = 0;
                [UIView animateWithDuration:0.14 animations:^{ self.scrubTip.alpha = 1.0; }];
            }
            self.waveform.progress = p;
            self.scrubTipCenterX.constant = pt.x;
            int64_t cur = (int64_t)(p * self.totalDurationMillis);
            self.scrubTip.text = [NSString stringWithFormat:@"  %@ / %@  ", [self formatDur:cur], [self formatDur:self.totalDurationMillis]];
            [[IMVoicePlayer sharedPlayer] seek:p forMessageID:self.currentID];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            self.scrubbing = NO;
            [UIView animateWithDuration:0.18 animations:^{ self.scrubTip.alpha = 0; }];
            break;
        }
        default: break;
    }
}

- (void)speedTapped {
    // 1x → 1.5x → 2x → 1x 循环。
    float cur = [[IMVoicePlayer sharedPlayer] rateForConvID:self.currentConvID];
    float next = (cur == 1.0f) ? 1.5f : ((cur == 1.5f) ? 2.0f : 1.0f);
    [[IMVoicePlayer sharedPlayer] setRate:next forConvID:self.currentConvID];
    [self applySpeedLabel:next];
    // rotateX 翻页 160ms（与设计文档 §6.1 tokens 一致）
    CATransform3D t = CATransform3DMakeRotation(M_PI_2, 1, 0, 0);
    self.speedPill.titleLabel.layer.transform = t;
    [UIView animateWithDuration:0.16 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.speedPill.titleLabel.layer.transform = CATransform3DIdentity;
    } completion:nil];
}

- (void)applySpeedLabel:(float)rate {
    NSString *t = (rate == 1.5f) ? @"1.5x" : ((rate == 2.0f) ? @"2x" : @"1x");
    [self.speedPill setTitle:t forState:UIControlStateNormal];
    UIColor *tint = self.mine ? IMTheme.bubbleMeText : IMTheme.accent; // 与波形同一取色逻辑（深浅色模式自适应）
    [self.speedPill setTitleColor:tint forState:UIControlStateNormal];
    self.speedPill.backgroundColor = [tint colorWithAlphaComponent:0.14];
}


- (void)onPlayerChanged:(NSNotification *)n {
    NSString *mid = n.userInfo[@"messageID"];
    if (!mid || ![mid isEqualToString:self.currentID]) { return; }
    IMVoicePlayerState state = [n.userInfo[@"state"] integerValue];
    double progress = [n.userInfo[@"progress"] doubleValue];
    [self applyPlayerState:state progress:progress];
    if (state == IMVoicePlayerStatePlaying) { self.unplayedDot.hidden = YES; }
}

- (void)applyPlayerState:(IMVoicePlayerState)state progress:(double)progress {
    // 图标只在状态切换时 setImage：本方法由 30fps 进度 tick 驱动，每帧重建符号+触发按钮布局纯属浪费。
    BOOL wantPause = (state == IMVoicePlayerStatePlaying);
    if (wantPause != self.showsPauseIcon || !self.playButton.currentImage) {
        self.showsPauseIcon = wantPause;
        UIImageSymbolConfiguration *pcfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold];
        NSString *sym = wantPause ? @"pause.fill" : @"play.fill";
        [self.playButton setImage:[UIImage systemImageNamed:sym withConfiguration:pcfg] forState:UIControlStateNormal];
    }
    if (!self.scrubbing) { self.waveform.progress = progress; }
    if (state == IMVoicePlayerStatePlaying || state == IMVoicePlayerStatePaused) {
        // 播放中/暂停显剩余时间（覆盖 attributed meta——播放态就不需要 ✓✓，专注剩余）。
        int64_t remaining = MAX(0, self.totalDurationMillis - (int64_t)(progress * self.totalDurationMillis));
        self.durationLabel.text = [self formatDur:remaining];
    } else {
        // 播完/复位：恢复综合 meta（时长 · 时间 ✓✓）——由 configure 生成的 attributed 无法在 tick 中重建
        // 因为缺 message 引用；这里只显时长兜底（重进会话或下一次 configure 会重新生成完整 meta）。
        self.durationLabel.text = [self formatDur:self.totalDurationMillis];
        if (!self.scrubbing) { self.waveform.progress = 0; }
    }
    // 倍速胶囊：仅播放/暂停中可见可点。
    BOOL playing = (state == IMVoicePlayerStatePlaying || state == IMVoicePlayerStatePaused);
    if (playing != self.speedPill.userInteractionEnabled) {
        self.speedPill.userInteractionEnabled = playing;
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            self.speedPill.alpha = playing ? 1.0 : 0.0;
        } completion:nil];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
