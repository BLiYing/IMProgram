//
//  IMVoiceRecordingHUD.m
//

#import "IMVoiceRecordingHUD.h"
#import "IMTheme.h"

@interface IMVoiceRecordingHUD ()
@property (nonatomic, strong) UIView *pill;
@property (nonatomic, strong) UIView *redDot;
@property (nonatomic, strong) UILabel *timerLabel;
@property (nonatomic, strong) UILabel *slideHint;
@property (nonatomic, strong) NSLayoutConstraint *slideOffsetConstraint;
@property (nonatomic, assign) BOOL cancelReady;
@property (nonatomic, assign) CGFloat lastOffset;
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

- (void)setVisible:(BOOL)visible animated:(BOOL)animated {
    if (visible) { self.hidden = NO; }
    void (^apply)(void) = ^{ self.alpha = visible ? 1.0 : 0.0; };
    if (animated) {
        [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:apply completion:^(BOOL _) {
            if (!visible) { self.hidden = YES; }
        }];
    } else {
        apply();
        if (!visible) { self.hidden = YES; }
    }
}

- (void)updateAmplitude:(float)amplitude elapsedMillis:(int64_t)elapsedMillis {
    NSInteger s = MAX(0, (NSInteger)(elapsedMillis / 1000));
    self.timerLabel.text = [NSString stringWithFormat:@"%ld:%02ld", (long)(s / 60), (long)(s % 60)];
    // 振幅微驱动红点缩放，给用户即时反馈。
    CGFloat scale = 1.0 + MIN(0.6, MAX(0, amplitude) * 0.9);
    self.redDot.transform = CGAffineTransformMakeScale(scale, scale);
}

- (void)setCancelReady:(BOOL)cancelReady {
    if (_cancelReady == cancelReady) { return; }
    _cancelReady = cancelReady;
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        if (cancelReady) {
            self.pill.backgroundColor = UIColor.systemRedColor;
            self.pill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
            self.slideHint.text = @"松开 取消";
            self.slideHint.textColor = UIColor.whiteColor;
            self.timerLabel.textColor = UIColor.whiteColor;
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
    self.slideOffsetConstraint.constant = MAX(-140, MIN(0, offsetX));
    // 未过阈值时按位移比例渐隐提示文本（进度条效果）。
    if (!self.cancelReady) {
        CGFloat alpha = 1.0 + offsetX / 140.0;
        self.slideHint.alpha = MAX(0.2, MIN(1.0, alpha));
    } else {
        self.slideHint.alpha = 1.0;
    }
}

@end
