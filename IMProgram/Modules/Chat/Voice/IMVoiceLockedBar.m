//
//  IMVoiceLockedBar.m
//

#import "IMVoiceLockedBar.h"
#import "IMTheme.h"
#import "IMTimeUtil.h"
#import "IMWaveformView.h" // §14 试听态：胶囊内显完整已录波形（可点即播）

@interface IMVoiceLockedBar ()
@property (nonatomic, strong) UIButton *deleteBtn;
@property (nonatomic, strong) UIView *pill;             ///< 中间胶囊：录制态=红点+计时+跑马灯；试听态=▶+计时+完整波形
@property (nonatomic, strong) UIView *redDot;
@property (nonatomic, strong) UILabel *timer;
@property (nonatomic, strong) UIView *waveBox;          ///< 录制态用（跑马灯 bars）
@property (nonatomic, strong) NSMutableArray<UIView *> *waveBars;
@property (nonatomic, strong) IMWaveformView *previewWave; ///< §14 试听态用：完整波形+进度扫过
@property (nonatomic, strong) UIImageView *previewPlayIcon; ///< §14 试听态左侧 ▶/❚❚（红点位置）
@property (nonatomic, strong) UIButton *pauseBtn;
@property (nonatomic, strong) UIButton *sendBtn;
@property (nonatomic, strong) UITapGestureRecognizer *pillTap; ///< 点胶囊触发试听（仅 previewMode 下有效）
@property (nonatomic, assign) BOOL pausedState; ///< 显式状态位（曾用 image.description 猜图标名——私有字符串依赖，随系统版本可能失效）
@property (nonatomic, assign) BOOL previewMode; ///< §14：中间胶囊是"跑马灯"还是"试听播放器"
@end

@implementation IMVoiceLockedBar

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // 不透明底（2026-08-26 修）：曾 clearColor → 锁定行与底下输入栏重叠显示。
        self.backgroundColor = IMTheme.surface;
        self.hidden = YES;
        self.alpha = 0;
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    _waveBars = [NSMutableArray array];
    // 三个圆钮 + 中间胶囊：与 VOICE_MESSAGE_DESIGN §5.3 tokens 一致（36pt 命中区）。
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    _deleteBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _deleteBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [_deleteBtn setImage:[UIImage systemImageNamed:@"trash" withConfiguration:cfg] forState:UIControlStateNormal];
    _deleteBtn.tintColor = UIColor.systemRedColor;
    _deleteBtn.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.12];
    _deleteBtn.layer.cornerRadius = 17;
    _deleteBtn.layer.borderWidth = 1;
    _deleteBtn.layer.borderColor = [UIColor.systemRedColor colorWithAlphaComponent:0.25].CGColor;
    [_deleteBtn addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_deleteBtn];

    _pauseBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _pauseBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [_pauseBtn setImage:[UIImage systemImageNamed:@"pause.fill" withConfiguration:cfg] forState:UIControlStateNormal];
    _pauseBtn.tintColor = IMTheme.textPrimary;
    _pauseBtn.backgroundColor = [IMTheme.textPrimary colorWithAlphaComponent:0.08];
    _pauseBtn.layer.cornerRadius = 17;
    [_pauseBtn addTarget:self action:@selector(pauseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_pauseBtn];

    _sendBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _sendBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *sendCfg = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightBold];
    [_sendBtn setImage:[UIImage systemImageNamed:@"arrow.up" withConfiguration:sendCfg] forState:UIControlStateNormal];
    _sendBtn.tintColor = UIColor.whiteColor;
    _sendBtn.backgroundColor = IMTheme.accent;
    _sendBtn.layer.cornerRadius = 17;
    [_sendBtn addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_sendBtn];

    _pill = [UIView new];
    _pill.translatesAutoresizingMaskIntoConstraints = NO;
    _pill.backgroundColor = IMTheme.pageBackground; // 主题 token（曾硬编码浅灰，深色模式刺眼）
    _pill.layer.cornerRadius = 17;
    _pill.layer.borderColor = IMTheme.separator.CGColor;
    _pill.layer.borderWidth = 1;
    [self addSubview:_pill];

    _redDot = [UIView new];
    _redDot.translatesAutoresizingMaskIntoConstraints = NO;
    _redDot.backgroundColor = UIColor.systemRedColor;
    _redDot.layer.cornerRadius = 4;
    [_pill addSubview:_redDot];

    _timer = [UILabel new];
    _timer.translatesAutoresizingMaskIntoConstraints = NO;
    _timer.font = [UIFont monospacedDigitSystemFontOfSize:12.5 weight:UIFontWeightSemibold];
    _timer.textColor = IMTheme.textPrimary;
    _timer.text = @"0:00";
    [_pill addSubview:_timer];

    _waveBox = [UIView new];
    _waveBox.translatesAutoresizingMaskIntoConstraints = NO;
    _waveBox.clipsToBounds = YES;
    [_pill addSubview:_waveBox];

    // 波形柱：从右向左流动的跑马灯（20 根，覆盖胶囊宽度）
    for (NSInteger i = 0; i < 20; i++) {
        UIView *b = [UIView new];
        b.translatesAutoresizingMaskIntoConstraints = NO;
        b.backgroundColor = IMTheme.accent;
        b.layer.cornerRadius = 1.5;
        [_waveBox addSubview:b];
        [self.waveBars addObject:b];
    }

    // §14 试听态：完整波形（默认隐；setPreviewMode:YES 时切显）+ ▶/❚❚ 图标（取代红点位置）。
    _previewWave = [IMWaveformView new];
    _previewWave.translatesAutoresizingMaskIntoConstraints = NO;
    _previewWave.activeColor = IMTheme.accent;
    _previewWave.inactiveColor = [IMTheme.textSecondary colorWithAlphaComponent:0.28];
    _previewWave.hidden = YES;
    [_pill addSubview:_previewWave];

    UIImageSymbolConfiguration *piCfg = [UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightBold];
    _previewPlayIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:piCfg]];
    _previewPlayIcon.translatesAutoresizingMaskIntoConstraints = NO;
    _previewPlayIcon.tintColor = UIColor.whiteColor;
    _previewPlayIcon.backgroundColor = IMTheme.accent;
    _previewPlayIcon.layer.cornerRadius = 10;
    _previewPlayIcon.layer.masksToBounds = YES;
    _previewPlayIcon.contentMode = UIViewContentModeCenter;
    _previewPlayIcon.hidden = YES;
    [_pill addSubview:_previewPlayIcon];

    // 点胶囊触发试听（仅 previewMode 有效；录制中的点击会被过滤）。
    _pillTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pillTapped)];
    [_pill addGestureRecognizer:_pillTap];

    [NSLayoutConstraint activateConstraints:@[
        [_deleteBtn.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
        [_deleteBtn.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_deleteBtn.widthAnchor constraintEqualToConstant:34],
        [_deleteBtn.heightAnchor constraintEqualToConstant:34],
        [_sendBtn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [_sendBtn.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_sendBtn.widthAnchor constraintEqualToConstant:34],
        [_sendBtn.heightAnchor constraintEqualToConstant:34],
        [_pauseBtn.trailingAnchor constraintEqualToAnchor:_sendBtn.leadingAnchor constant:-8],
        [_pauseBtn.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_pauseBtn.widthAnchor constraintEqualToConstant:34],
        [_pauseBtn.heightAnchor constraintEqualToConstant:34],
        [_pill.leadingAnchor constraintEqualToAnchor:_deleteBtn.trailingAnchor constant:8],
        [_pill.trailingAnchor constraintEqualToAnchor:_pauseBtn.leadingAnchor constant:-8],
        [_pill.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_pill.heightAnchor constraintEqualToConstant:34],
        [_redDot.leadingAnchor constraintEqualToAnchor:_pill.leadingAnchor constant:11],
        [_redDot.centerYAnchor constraintEqualToAnchor:_pill.centerYAnchor],
        [_redDot.widthAnchor constraintEqualToConstant:8],
        [_redDot.heightAnchor constraintEqualToConstant:8],
        [_timer.leadingAnchor constraintEqualToAnchor:_redDot.trailingAnchor constant:7],
        [_timer.centerYAnchor constraintEqualToAnchor:_pill.centerYAnchor],
        [_waveBox.leadingAnchor constraintEqualToAnchor:_timer.trailingAnchor constant:8],
        [_waveBox.trailingAnchor constraintEqualToAnchor:_pill.trailingAnchor constant:-10],
        [_waveBox.topAnchor constraintEqualToAnchor:_pill.topAnchor constant:6],
        [_waveBox.bottomAnchor constraintEqualToAnchor:_pill.bottomAnchor constant:-6],
        // 试听态覆盖：previewWave 同 waveBox 区域（同时占位，show/hide 切换）；previewPlayIcon 与 redDot 同位。
        [_previewWave.leadingAnchor constraintEqualToAnchor:_timer.trailingAnchor constant:8],
        [_previewWave.trailingAnchor constraintEqualToAnchor:_pill.trailingAnchor constant:-10],
        [_previewWave.topAnchor constraintEqualToAnchor:_pill.topAnchor constant:6],
        [_previewWave.bottomAnchor constraintEqualToAnchor:_pill.bottomAnchor constant:-6],
        [_previewPlayIcon.centerXAnchor constraintEqualToAnchor:_redDot.centerXAnchor],
        [_previewPlayIcon.centerYAnchor constraintEqualToAnchor:_redDot.centerYAnchor],
        [_previewPlayIcon.widthAnchor constraintEqualToConstant:20],
        [_previewPlayIcon.heightAnchor constraintEqualToConstant:20],
    ]];

    // 红点脉冲（同 IMVoiceRecordingHUD）
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulse.fromValue = @1.0;
    pulse.toValue = @0.4;
    pulse.duration = 0.7;
    pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    [_redDot.layer addAnimation:pulse forKey:@"pulse"];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self layoutWaveBars];
}

- (void)layoutWaveBars {
    CGFloat total = CGRectGetWidth(self.waveBox.bounds);
    CGFloat h = CGRectGetHeight(self.waveBox.bounds);
    if (total < 4 || h < 4) { return; }
    NSInteger n = self.waveBars.count;
    CGFloat pitch = total / (CGFloat)n; // 允许略挤
    CGFloat barW = MIN(3.0, pitch - 1.5);
    for (NSInteger i = 0; i < n; i++) {
        UIView *b = self.waveBars[i];
        CGFloat x = i * pitch;
        CGFloat curH = MAX(2.0, b.bounds.size.height ?: 2.0);
        b.frame = CGRectMake(x, (h - curH) * 0.5, barW, curH);
    }
}

- (void)updateAmplitude:(float)amplitude elapsedMillis:(int64_t)elapsedMillis {
    self.timer.text = IMFormatVoiceDuration(elapsedMillis);
    if (self.previewMode) { return; } // 试听态不由此更新（波形/计时由 applyPreviewPlaying: 驱动）
    // 从右向左流动：把左侧的高度往下移一格，最右新加当前采样高度。
    CGFloat h = CGRectGetHeight(self.waveBox.bounds);
    if (h < 4) { return; }
    for (NSInteger i = 0; i < (NSInteger)self.waveBars.count - 1; i++) {
        UIView *cur = self.waveBars[i];
        UIView *next = self.waveBars[i + 1];
        CGRect r = cur.frame; r.size.height = next.frame.size.height; r.origin.y = (h - r.size.height) * 0.5; cur.frame = r;
    }
    UIView *last = self.waveBars.lastObject;
    CGFloat newH = MAX(2.0, (CGFloat)amplitude * (h - 2.0));
    CGRect lr = last.frame; lr.size.height = newH; lr.origin.y = (h - newH) * 0.5; last.frame = lr;
}

- (void)setPausedIcon:(BOOL)paused {
    self.pausedState = paused;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    // 试听态右侧键 = ⏵（forward.fill 更符合"继续录制"语义）；录制态 = ⏸（pause.fill）。
    NSString *sym = paused ? (self.previewMode ? @"record.circle" : @"play.fill") : @"pause.fill";
    [self.pauseBtn setImage:[UIImage systemImageNamed:sym withConfiguration:cfg] forState:UIControlStateNormal];
    self.pauseBtn.tintColor = (paused && self.previewMode) ? UIColor.systemRedColor : IMTheme.textPrimary;
}

- (void)setPreviewMode:(BOOL)previewMode amplitudes:(NSArray<NSNumber *> *)amplitudes {
    self.previewMode = previewMode;
    self.redDot.hidden = previewMode;         // 录制指示消失
    self.waveBox.hidden = previewMode;        // 跑马灯隐
    self.previewWave.hidden = !previewMode;   // 完整波形显
    self.previewPlayIcon.hidden = !previewMode;
    self.previewWave.amplitudes = amplitudes;
    self.previewWave.progress = 0;
    [self applyPreviewPlaying:NO progress:0 totalMillis:0]; // 复位图标
    // 切态时同步刷右侧键 tint/图标（复用 setPausedIcon: 逻辑）
    [self setPausedIcon:self.pausedState];
    // 视觉提示：试听态胶囊底色微染 accent，让"这不是死条"更明显。
    self.pill.backgroundColor = previewMode
        ? [IMTheme.accent colorWithAlphaComponent:0.08]
        : IMTheme.pageBackground;
}

- (void)applyPreviewPlaying:(BOOL)playing progress:(double)progress totalMillis:(int64_t)totalMillis {
    if (!self.previewMode) { return; }
    UIImageSymbolConfiguration *piCfg = [UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightBold];
    self.previewPlayIcon.image = [UIImage systemImageNamed:(playing ? @"pause.fill" : @"play.fill") withConfiguration:piCfg];
    self.previewWave.progress = MAX(0.0, MIN(1.0, progress));
    if (totalMillis > 0 && playing) {
        int64_t remaining = MAX((int64_t)0, totalMillis - (int64_t)(progress * totalMillis));
        self.timer.text = IMFormatVoiceDuration(remaining);
    } else if (totalMillis > 0 && !playing) {
        self.timer.text = IMFormatVoiceDuration(totalMillis);
    }
}

- (void)pillTapped { if (self.previewMode && self.onPreviewToggle) { self.onPreviewToggle(); } }

- (void)setVisible:(BOOL)visible animated:(BOOL)animated {
    if (visible) { self.hidden = NO; }
    void (^apply)(void) = ^{ self.alpha = visible ? 1.0 : 0.0; };
    if (animated) {
        [UIView animateWithDuration:0.2 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.5
                            options:UIViewAnimationOptionAllowUserInteraction animations:apply completion:^(BOOL _) {
            if (!visible) { self.hidden = YES; }
        }];
    } else { apply(); if (!visible) { self.hidden = YES; } }
}

- (void)deleteTapped { if (self.onDelete) self.onDelete(); }
- (void)pauseTapped {
    // 三态切换（§14）：
    //   录制态点 ⏸ → toPause=YES：上层 recorder.pause + setPreviewMode:YES amplitudes:...（进入试听）
    //   试听态点 ⏵ → toPause=NO：上层停试听 + recorder.resume + setPreviewMode:NO（继续录制）
    BOOL toPause = !self.pausedState;
    if (self.onPauseResume) self.onPauseResume(toPause);
}
- (void)sendTapped { if (self.onSend) self.onSend(); }

@end
