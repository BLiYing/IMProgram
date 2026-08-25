//
//  IMVoiceBubbleCell.m
//

#import "IMVoiceBubbleCell.h"
#import "IMWaveformView.h"
#import "IMVoicePlayer.h"
#import "IMMessageModel.h"
#import "IMTheme.h"
#import "UILabel+IMAvatar.h"

@interface IMVoiceBubbleCell ()
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) IMWaveformView *waveform;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UIView *unplayedDot;
@property (nonatomic, strong) UILabel *senderLabel;
@property (nonatomic, strong) UILabel *dayHeader;

@property (nonatomic, copy, nullable) NSString *currentID;
@property (nonatomic, assign) int64_t totalDurationMillis;
@property (nonatomic, assign) BOOL mine;

@property (nonatomic, strong) NSLayoutConstraint *bubbleLeadingLeft;   ///< 对方消息：左对齐（头像右）
@property (nonatomic, strong) NSLayoutConstraint *bubbleTrailingRight; ///< 自己消息：右对齐
@property (nonatomic, strong) NSLayoutConstraint *bubbleWidth;         ///< 按 duration 线性长；每次 configure 只改 constant，不再追加约束
@property (nonatomic, strong) NSLayoutConstraint *bubbleMaxTrailing;   ///< 对方气泡右侧最小留白（防长语音贴屏边）
@property (nonatomic, strong) NSLayoutConstraint *bubbleMinLeading;    ///< 自己气泡左侧最小留白
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

    _unplayedDot = [UIView new];
    _unplayedDot.translatesAutoresizingMaskIntoConstraints = NO;
    _unplayedDot.backgroundColor = UIColor.systemRedColor;
    _unplayedDot.layer.cornerRadius = 3.5;
    _unplayedDot.hidden = YES;
    [_bubble addSubview:_unplayedDot];

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
        // 气泡定位（左右锚随 mine 切换，见 configure）
        [_bubble.topAnchor constraintEqualToAnchor:_senderLabel.bottomAnchor constant:2],
        [_bubble.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-4],
        [_bubble.heightAnchor constraintEqualToConstant:52],
        // 气泡内元素
        [_playButton.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:6],
        [_playButton.centerYAnchor constraintEqualToAnchor:_bubble.centerYAnchor],
        [_playButton.widthAnchor constraintEqualToConstant:34],
        [_playButton.heightAnchor constraintEqualToConstant:34],
        [_waveform.leadingAnchor constraintEqualToAnchor:_playButton.trailingAnchor constant:9],
        [_waveform.centerYAnchor constraintEqualToAnchor:_bubble.centerYAnchor],
        [_waveform.heightAnchor constraintEqualToConstant:28],
        [_waveform.trailingAnchor constraintEqualToAnchor:_durationLabel.leadingAnchor constant:-8],
        [_durationLabel.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-10],
        [_durationLabel.centerYAnchor constraintEqualToAnchor:_bubble.centerYAnchor constant:5],
        [_unplayedDot.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-10],
        [_unplayedDot.topAnchor constraintEqualToAnchor:_bubble.topAnchor constant:6],
        [_unplayedDot.widthAnchor constraintEqualToConstant:7],
        [_unplayedDot.heightAnchor constraintEqualToConstant:7],
    ]];
}

- (UIView *)previewTargetView { return self.bubble; }

- (void)configureWithMessage:(IMMessageModel *)message
                        mine:(BOOL)mine
                   dayHeader:(NSString *)dayHeader
          showsUnreadDivider:(BOOL)showsDivider
                  senderName:(NSString *)senderName
                  senderRole:(IMGroupRole)senderRole
                    hasPlayed:(BOOL)hasPlayed {
    self.mine = mine;
    self.currentID = IMVoicePlayerPlayableIDForMessage(message);
    self.totalDurationMillis = message.duration > 0 ? message.duration : 0;

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

    // 波形数据
    self.waveform.amplitudes = [IMWaveformView amplitudesFromBase64:message.waveform];
    self.waveform.progress = 0;
    if (mine) {
        self.waveform.activeColor = [UIColor colorWithRed:0.08 green:0.38 blue:0.12 alpha:1.0];
        self.waveform.inactiveColor = [UIColor colorWithWhite:0.15 alpha:0.28];
        self.playButton.backgroundColor = [UIColor colorWithRed:0.12 green:0.48 blue:0.18 alpha:1.0];
    } else {
        self.waveform.activeColor = IMTheme.accent;
        self.waveform.inactiveColor = [UIColor colorWithWhite:0.7 alpha:1.0];
        self.playButton.backgroundColor = IMTheme.accent;
    }
    // 气泡宽度按 duration 线性长（最少 130pt，最多 240pt——tokens 见 §6.1）。
    // 直接改 bubbleWidth.constant，不再动态追加约束（复用 cell 时会重复叠加）。
    CGFloat dur = MAX(1.0, message.duration / 1000.0);
    self.bubbleWidth.constant = MIN(240.0, MAX(130.0, 96.0 + dur * 3.6));

    self.durationLabel.text = [self formatDur:self.totalDurationMillis];
    // 未播红点仅对方消息 + 本机未播过时显；hasPlayed 由宿主传入（已 mine || 查询 IMVoicePlayer 已播集合）。
    self.unplayedDot.hidden = mine || hasPlayed;

    // 同步当前播放器状态（切页/复用时保持进度）。
    IMVoicePlayerState st = [[IMVoicePlayer sharedPlayer] stateForMessageID:self.currentID];
    [self applyPlayerState:st progress:[[IMVoicePlayer sharedPlayer] progressForMessageID:self.currentID]];
}

- (NSString *)formatDur:(int64_t)ms {
    NSInteger s = MAX(0, (NSInteger)(ms / 1000));
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(s / 60), (long)(s % 60)];
}

- (void)applyGroupAvatarURL:(NSString *)url seed:(NSString *)seed name:(NSString *)name showAvatar:(BOOL)showAvatar gutter:(BOOL)gutter {
    _avatar.hidden = !showAvatar;
    if (showAvatar) {
        [_avatar im_setAvatarURL:url seed:seed displayName:name];
    }
}

- (void)playTapped { if (self.onPlayTap) { self.onPlayTap(); } }

- (void)onPlayerChanged:(NSNotification *)n {
    NSString *mid = n.userInfo[@"messageID"];
    if (!mid || ![mid isEqualToString:self.currentID]) { return; }
    IMVoicePlayerState state = [n.userInfo[@"state"] integerValue];
    double progress = [n.userInfo[@"progress"] doubleValue];
    [self applyPlayerState:state progress:progress];
    if (state == IMVoicePlayerStatePlaying) { self.unplayedDot.hidden = YES; }
}

- (void)applyPlayerState:(IMVoicePlayerState)state progress:(double)progress {
    UIImageSymbolConfiguration *pcfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold];
    NSString *sym = (state == IMVoicePlayerStatePlaying) ? @"pause.fill" : @"play.fill";
    [self.playButton setImage:[UIImage systemImageNamed:sym withConfiguration:pcfg] forState:UIControlStateNormal];
    self.waveform.progress = progress;
    if (state == IMVoicePlayerStatePlaying || state == IMVoicePlayerStatePaused) {
        int64_t remaining = MAX(0, self.totalDurationMillis - (int64_t)(progress * self.totalDurationMillis));
        self.durationLabel.text = [self formatDur:remaining];
    } else {
        self.durationLabel.text = [self formatDur:self.totalDurationMillis];
        self.waveform.progress = 0;
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
