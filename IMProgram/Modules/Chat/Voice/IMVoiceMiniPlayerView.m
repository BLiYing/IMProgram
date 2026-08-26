//
//  IMVoiceMiniPlayerView.m
//

#import "IMVoiceMiniPlayerView.h"
#import "IMMessageModel.h"
#import "IMTheme.h"
#import "IMTimeUtil.h"
#import "IMWaveformView.h"
#import "IMVoicePlayer.h"

@interface IMVoiceMiniPlayerView ()
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) IMWaveformView *waveform;
@property (nonatomic, strong) UILabel *metaLabel; ///< "0:12 · 14:32 ✓✓" —— 波形下方一行
@property (nonatomic, copy, nullable) NSString *messageID;
@property (nonatomic, assign) int64_t totalDurationMillis;
@property (nonatomic, assign) BOOL mine;
@property (nonatomic, assign) int64_t peerReadSeq;
@property (nonatomic, assign) BOOL isGroupContext;
@property (nonatomic, assign) int64_t timestampMillis;
@property (nonatomic, assign) int64_t convSeq;
@property (nonatomic, assign) IMMessageStatus messageStatus;
@property (nonatomic, assign) BOOL showsPauseIcon;
@end

@implementation IMVoiceMiniPlayerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self buildUI];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onPlayerChanged:)
                                                     name:IMVoicePlayerDidChangeStateNotification object:nil];
    }
    return self;
}

- (void)buildUI {
    _playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _playButton.translatesAutoresizingMaskIntoConstraints = NO;
    _playButton.backgroundColor = IMTheme.accent;
    _playButton.tintColor = UIColor.whiteColor;
    _playButton.layer.cornerRadius = 17;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold];
    [_playButton setImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:cfg] forState:UIControlStateNormal];
    [_playButton addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_playButton];

    _waveform = [IMWaveformView new];
    _waveform.translatesAutoresizingMaskIntoConstraints = NO;
    _waveform.activeColor = IMTheme.accent;
    _waveform.inactiveColor = [IMTheme.textSecondary colorWithAlphaComponent:0.28];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(playTapped)];
    [_waveform addGestureRecognizer:tap];
    _waveform.userInteractionEnabled = YES;
    [self addSubview:_waveform];

    _metaLabel = [UILabel new];
    _metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _metaLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    _metaLabel.textColor = IMTheme.textSecondary;
    [self addSubview:_metaLabel];

    // 布局（用户 2026-08-27 拍板）：▶ 居左 · 中央 vertical(波形/meta) 与 ▶ 垂直居中对齐。
    // meta 在波形下方 = 时长 · 时间 · ✓/✓✓（mine 已发出才有勾）。
    [NSLayoutConstraint activateConstraints:@[
        [_playButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_playButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_playButton.widthAnchor constraintEqualToConstant:34],
        [_playButton.heightAnchor constraintEqualToConstant:34],
        [_waveform.leadingAnchor constraintEqualToAnchor:_playButton.trailingAnchor constant:10],
        [_waveform.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_waveform.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor],
        [_waveform.heightAnchor constraintEqualToConstant:24],
        [_metaLabel.leadingAnchor constraintEqualToAnchor:_waveform.leadingAnchor],
        [_metaLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],
        [_metaLabel.topAnchor constraintEqualToAnchor:_waveform.bottomAnchor constant:4],
        [_metaLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor],
        // 中央 stack 与 ▶ 垂直居中：波形+meta 组合的中点对齐 playButton 中心。
        [_waveform.centerYAnchor constraintEqualToAnchor:_playButton.centerYAnchor constant:-9],
        [self.heightAnchor constraintGreaterThanOrEqualToConstant:44],
    ]];
}

- (void)configureWithMessage:(IMMessageModel *)message {
    [self configureWithMessage:message mine:NO peerReadSeq:0 isGroupContext:NO];
}

- (void)configureWithMessage:(IMMessageModel *)message mine:(BOOL)mine peerReadSeq:(int64_t)peerReadSeq isGroupContext:(BOOL)isGroupContext {
    self.messageID = IMVoicePlayerPlayableIDForMessage(message);
    self.totalDurationMillis = MAX((int64_t)0, message.duration);
    self.mine = mine;
    self.peerReadSeq = peerReadSeq;
    self.isGroupContext = isGroupContext;
    self.timestampMillis = message.timestamp;
    self.convSeq = message.convSeq;
    self.messageStatus = message.status;
    self.waveform.amplitudes = [IMWaveformView amplitudesFromBase64:message.waveform];
    self.waveform.progress = 0;
    if (mine) {
        self.waveform.activeColor = IMTheme.bubbleMeText;
        self.waveform.inactiveColor = [IMTheme.bubbleMeText colorWithAlphaComponent:0.32];
        self.playButton.backgroundColor = [UIColor colorWithRed:0.12 green:0.48 blue:0.18 alpha:1.0];
    } else {
        self.waveform.activeColor = IMTheme.accent;
        self.waveform.inactiveColor = [IMTheme.textSecondary colorWithAlphaComponent:0.28];
        self.playButton.backgroundColor = IMTheme.accent;
    }
    self.metaLabel.attributedText = [self metaAttributed];
    IMVoicePlayerState st = [[IMVoicePlayer sharedPlayer] stateForMessageID:self.messageID];
    [self applyState:st progress:[[IMVoicePlayer sharedPlayer] progressForMessageID:self.messageID]];
}

/// 只显时长——mini 场景（收藏行 / 详情页语音 tab）用户 2026-08-27 拍板：右侧不再叠消息时间与勾，
/// 详情页语音 tab 每行本就有独立的"年月日时:分"辅助行、收藏行也有 favDate，重复即噪音。
- (NSAttributedString *)metaAttributed {
    UIFont *font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    NSString *durStr = IMFormatVoiceDuration(self.totalDurationMillis);
    NSDictionary *base = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: IMTheme.textSecondary };
    return [[NSAttributedString alloc] initWithString:durStr attributes:base];
}

- (void)playTapped { if (self.onPlayTap) { self.onPlayTap(); } }

- (void)onPlayerChanged:(NSNotification *)n {
    NSString *mid = n.userInfo[@"messageID"];
    if (!mid || ![mid isEqualToString:self.messageID]) { return; }
    [self applyState:(IMVoicePlayerState)[n.userInfo[@"state"] integerValue]
            progress:[n.userInfo[@"progress"] doubleValue]];
}

- (void)applyState:(IMVoicePlayerState)state progress:(double)progress {
    BOOL wantPause = (state == IMVoicePlayerStatePlaying);
    if (wantPause != self.showsPauseIcon || !self.playButton.currentImage) {
        self.showsPauseIcon = wantPause;
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold];
        NSString *sym = wantPause ? @"pause.fill" : @"play.fill";
        [self.playButton setImage:[UIImage systemImageNamed:sym withConfiguration:cfg] forState:UIControlStateNormal];
    }
    BOOL active = (state == IMVoicePlayerStatePlaying || state == IMVoicePlayerStatePaused);
    self.waveform.progress = active ? progress : 0;
    // 播放中在 meta 里覆盖时长为"剩余 · 时间 · 勾"—— attributed 需要重建。
    if (active) {
        int64_t remaining = MAX((int64_t)0, self.totalDurationMillis - (int64_t)(progress * self.totalDurationMillis));
        int64_t saved = self.totalDurationMillis;
        self.totalDurationMillis = remaining;
        self.metaLabel.attributedText = [self metaAttributed];
        self.totalDurationMillis = saved;
    } else {
        self.metaLabel.attributedText = [self metaAttributed];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
