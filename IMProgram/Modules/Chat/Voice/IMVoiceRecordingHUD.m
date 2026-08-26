//
//  IMVoiceRecordingHUD.m
//

#import "IMVoiceRecordingHUD.h"
#import "IMTheme.h"
#import "IMTimeUtil.h"

@interface IMVoiceRecordingHUD ()
@property (nonatomic, strong) UIView *pill;
@property (nonatomic, strong) UIView *redDot;
@property (nonatomic, strong) UILabel *timerLabel;
@property (nonatomic, strong) UILabel *slideHint;
@property (nonatomic, strong) NSLayoutConstraint *slideOffsetConstraint;
@property (nonatomic, assign) BOOL cancelReady;
@property (nonatomic, assign) CGFloat lastOffset;
@property (nonatomic, assign) BOOL wantsVisible; ///< setVisible: 的最新意图，供过期动画回调自查
@end

@implementation IMVoiceRecordingHUD

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // 不透明底（2026-08-26 修）：曾 clearColor → 盖在输入栏上时底下的 ＋/输入框/🎙 全部透出重叠。
        self.backgroundColor = IMTheme.surface;
        self.hidden = YES;
        self.alpha = 0;
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    _pill = [UIView new];
    _pill.translatesAutoresizingMaskIntoConstraints = NO;
    _pill.backgroundColor = IMTheme.pageBackground; // 主题 token（曾硬编码粉底，深色模式刺眼）
    _pill.layer.cornerRadius = 18;
    _pill.layer.borderWidth = 1.0;
    _pill.layer.borderColor = IMTheme.separator.CGColor;
    [self addSubview:_pill];

    _redDot = [UIView new];
    _redDot.translatesAutoresizingMaskIntoConstraints = NO;
    _redDot.backgroundColor = UIColor.systemRedColor;
    _redDot.layer.cornerRadius = 4;
    [_pill addSubview:_redDot];

    _timerLabel = [UILabel new];
    _timerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _timerLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
    _timerLabel.textColor = IMTheme.textPrimary;
    _timerLabel.text = @"0:00";
    [_pill addSubview:_timerLabel];

    _slideHint = [UILabel new];
    _slideHint.translatesAutoresizingMaskIntoConstraints = NO;
    _slideHint.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
    _slideHint.textColor = IMTheme.textSecondary;
    _slideHint.text = @"‹ 向左滑动取消";
    _slideHint.textAlignment = NSTextAlignmentCenter;
    [_pill addSubview:_slideHint];

    // 设计 §5.2：hint 居 pill 中心，跟指位移 ×0.4 阻尼渐隐；命中取消阈值后仍居中显"松开 取消"+ 整条转红。
    // 用户 2026-08-27 复议：hint 必须居中（曾改为 timer.trailing+16 挂靠导致"松开 取消"不居中）。
    _slideOffsetConstraint = [_slideHint.centerXAnchor constraintEqualToAnchor:_pill.centerXAnchor constant:0];

    [NSLayoutConstraint activateConstraints:@[
        [_pill.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
        [_pill.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [_pill.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
        [_pill.heightAnchor constraintEqualToConstant:36],
        [_redDot.leadingAnchor constraintEqualToAnchor:_pill.leadingAnchor constant:14],
        [_redDot.centerYAnchor constraintEqualToAnchor:_pill.centerYAnchor],
        [_redDot.widthAnchor constraintEqualToConstant:8],
        [_redDot.heightAnchor constraintEqualToConstant:8],
        [_timerLabel.leadingAnchor constraintEqualToAnchor:_redDot.trailingAnchor constant:8],
        [_timerLabel.centerYAnchor constraintEqualToAnchor:_pill.centerYAnchor],
        _slideOffsetConstraint,
        [_slideHint.centerYAnchor constraintEqualToAnchor:_pill.centerYAnchor],
    ]];

    // 红点持续脉冲（不是纯循环——录制状态下始终跳动，暂停后停）。
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulse.fromValue = @1.0;
    pulse.toValue = @0.4;
    pulse.duration = 0.7;
    pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    [_redDot.layer addAnimation:pulse forKey:@"pulse"];
}

/// 淡入/淡出。**wantsVisible 记住最新意图**：淡出动画未完时又被要求显示（松手后立刻再次按住录音），
/// 旧动画的完成回调仍会带着 visible=NO 触发，无条件 hidden=YES 就会把刚显示的条子隐掉。
- (void)setVisible:(BOOL)visible animated:(BOOL)animated {
    self.wantsVisible = visible;
    if (visible) { self.hidden = NO; }
    void (^apply)(void) = ^{ self.alpha = visible ? 1.0 : 0.0; };
    if (animated) {
        [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:apply completion:^(BOOL _) {
            if (!visible && !self.wantsVisible) { self.hidden = YES; }
        }];
    } else {
        apply();
        if (!visible) { self.hidden = YES; }
    }
}

- (void)updateAmplitude:(float)amplitude elapsedMillis:(int64_t)elapsedMillis {
    self.timerLabel.text = IMFormatVoiceDuration(elapsedMillis);
    // 振幅微驱动红点缩放，给用户即时反馈。
    CGFloat scale = 1.0 + MIN(0.6, MAX(0, amplitude) * 0.9);
    self.redDot.transform = CGAffineTransformMakeScale(scale, scale);
}

- (void)setCancelReady:(BOOL)cancelReady {
    if (_cancelReady == cancelReady) { return; }
    _cancelReady = cancelReady;
    // 命中阈值必须把 hint 拉回 pill 正中（此前 slideOffset 已把 constant 设成负数偏左，仅靠切文案不会自动居中，
    // 2026-08-27 修：用户报"松开 取消"仍偏左）。回退到非红态时保留最后一次 offset，由 setSlideOffset 继续驱动。
    if (cancelReady) { self.slideOffsetConstraint.constant = 0; }
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        if (cancelReady) {
            self.pill.backgroundColor = UIColor.systemRedColor;
            self.pill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
            self.slideHint.text = @"松开 取消";
            self.slideHint.textColor = UIColor.whiteColor;
            self.timerLabel.textColor = UIColor.whiteColor;
            self.slideHint.alpha = 1.0;
            [self layoutIfNeeded]; // 让 constant=0 的位移随动画一起呈现（否则会跳变）
        } else {
            self.pill.backgroundColor = IMTheme.pageBackground;
            self.pill.layer.borderColor = IMTheme.separator.CGColor;
            self.slideHint.text = @"‹ 向左滑动取消";
            self.slideHint.textColor = IMTheme.textSecondary;
            self.timerLabel.textColor = IMTheme.textPrimary;
        }
    } completion:nil];
}

- (void)setSlideOffset:(CGFloat)offsetX {
    if (offsetX == _lastOffset) { return; }
    _lastOffset = offsetX;
    // 设计 §5.2：hint 跟指位移 ×0.4 阻尼；进度条式渐隐（alpha 随左移线性降到 0.2 兜底），
    // 未过阈值时保持可读；命中取消阈值后 hint 严格居中（constant=0），不再随 pan 抖动。
    if (self.cancelReady) {
        self.slideOffsetConstraint.constant = 0;
        self.slideHint.alpha = 1.0;
        return;
    }
    CGFloat clamped = MAX(-140, MIN(0, offsetX));
    self.slideOffsetConstraint.constant = clamped * 0.4;
    CGFloat alpha = 1.0 + clamped / 140.0; // 0→1, -140→0
    self.slideHint.alpha = MAX(0.2, MIN(1.0, alpha));
}

@end
