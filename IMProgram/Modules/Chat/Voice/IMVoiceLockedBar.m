//
//  IMVoiceLockedBar.m
//

#import "IMVoiceLockedBar.h"
#import "IMTheme.h"

@interface IMVoiceLockedBar ()
@property (nonatomic, strong) UIButton *deleteBtn;
@property (nonatomic, strong) UIView *pill;             ///< 中间胶囊：红点 + 计时 + 迷你波形
@property (nonatomic, strong) UIView *redDot;
@property (nonatomic, strong) UILabel *timer;
@property (nonatomic, strong) UIView *waveBox;
@property (nonatomic, strong) NSMutableArray<UIView *> *waveBars;
@property (nonatomic, strong) UIButton *pauseBtn;
@property (nonatomic, strong) UIButton *sendBtn;
@end

@implementation IMVoiceLockedBar

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
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
    _pill.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1.0];
    _pill.layer.cornerRadius = 17;
    _pill.layer.borderColor = [UIColor colorWithWhite:0.85 alpha:1.0].CGColor;
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
    NSInteger s = MAX((NSInteger)0, (NSInteger)(elapsedMillis / 1000));
    self.timer.text = [NSString stringWithFormat:@"%ld:%02ld", (long)(s / 60), (long)(s % 60)];
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
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    NSString *sym = paused ? @"play.fill" : @"pause.fill";
    [self.pauseBtn setImage:[UIImage systemImageNamed:sym withConfiguration:cfg] forState:UIControlStateNormal];
}

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
    // 由外部翻转 icon（外部知道 recorder 状态）
    UIImage *cur = [self.pauseBtn imageForState:UIControlStateNormal];
    NSString *sysName = [cur.description containsString:@"pause"] ? @"pause" : @"play";
    BOOL toPause = [sysName isEqualToString:@"pause"];
    if (self.onPauseResume) self.onPauseResume(toPause);
}
- (void)sendTapped { if (self.onSend) self.onSend(); }

@end
