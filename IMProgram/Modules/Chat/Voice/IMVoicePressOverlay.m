//
//  IMVoicePressOverlay.m
//

#import "IMVoicePressOverlay.h"
#import "IMTheme.h"

static const CGFloat kBigCircleSize = 58.0;
static const CGFloat kLockWidth = 36.0;
static const CGFloat kLockHeight = 52.0;
static const CGFloat kLockOffsetY = 86.0;   ///< 锁钮中心相对 anchor 的上移量（≈ 大圆钮半径 + 56pt 间距）
static const CGFloat kLockNearRadius = 70.0;
static const CGFloat kLockSnapRadius = 34.0;

@interface IMVoicePressOverlay ()
@property (nonatomic, strong) UIView *ring;        ///< 振幅呼吸环（大圆钮底下）
@property (nonatomic, strong) UIView *bigCircle;
@property (nonatomic, strong) UIImageView *micIcon;
@property (nonatomic, strong) UIView *lockPill;
@property (nonatomic, strong) UIImageView *lockIcon;
@property (nonatomic, strong) UIImageView *lockArrow;
@property (nonatomic, assign) CGPoint anchor;
@property (nonatomic, assign) IMVoiceLockPhase phase;
@end

@implementation IMVoicePressOverlay

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO; // 纯展示：不截获手势（长按手势仍在语音钮上）
        self.hidden = YES;
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    _ring = [UIView new];
    _ring.backgroundColor = [IMTheme.accent colorWithAlphaComponent:0.22];
    _ring.layer.cornerRadius = (kBigCircleSize + 26) / 2.0;
    _ring.bounds = CGRectMake(0, 0, kBigCircleSize + 26, kBigCircleSize + 26);
    [self addSubview:_ring];

    _bigCircle = [UIView new];
    _bigCircle.backgroundColor = IMTheme.accent;
    _bigCircle.layer.cornerRadius = kBigCircleSize / 2.0;
    _bigCircle.bounds = CGRectMake(0, 0, kBigCircleSize, kBigCircleSize);
    _bigCircle.layer.shadowColor = UIColor.blackColor.CGColor;
    _bigCircle.layer.shadowOpacity = 0.18;
    _bigCircle.layer.shadowRadius = 10;
    _bigCircle.layer.shadowOffset = CGSizeMake(0, 4);
    [self addSubview:_bigCircle];

    UIImageSymbolConfiguration *micCfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    _micIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"mic.fill" withConfiguration:micCfg]];
    _micIcon.tintColor = UIColor.whiteColor;
    [_bigCircle addSubview:_micIcon];
    _micIcon.center = CGPointMake(kBigCircleSize / 2.0, kBigCircleSize / 2.0);

    _lockPill = [UIView new];
    _lockPill.backgroundColor = IMTheme.surfaceElevated;
    _lockPill.layer.cornerRadius = kLockWidth / 2.0;
    _lockPill.layer.borderWidth = 1.0;
    _lockPill.layer.borderColor = IMTheme.separator.CGColor;
    _lockPill.bounds = CGRectMake(0, 0, kLockWidth, kLockHeight);
    _lockPill.layer.shadowColor = UIColor.blackColor.CGColor;
    _lockPill.layer.shadowOpacity = 0.12;
    _lockPill.layer.shadowRadius = 8;
    _lockPill.layer.shadowOffset = CGSizeMake(0, 3);
    [self addSubview:_lockPill];

    UIImageSymbolConfiguration *lockCfg = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
    _lockIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock" withConfiguration:lockCfg]];
    _lockIcon.tintColor = IMTheme.textSecondary;
    [_lockPill addSubview:_lockIcon];
    _lockIcon.center = CGPointMake(kLockWidth / 2.0, 16);

    _lockArrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.up" withConfiguration:lockCfg]];
    _lockArrow.tintColor = IMTheme.textSecondary;
    [_lockPill addSubview:_lockArrow];
    _lockArrow.center = CGPointMake(kLockWidth / 2.0, kLockHeight - 16);

    // 上箭头呼吸（引导上滑）：上下 4pt 往复。
    CABasicAnimation *breathe = [CABasicAnimation animationWithKeyPath:@"position.y"];
    breathe.byValue = @(-4);
    breathe.duration = 0.7;
    breathe.autoreverses = YES;
    breathe.repeatCount = HUGE_VALF;
    [_lockArrow.layer addAnimation:breathe forKey:@"breathe"];
}

- (CGPoint)lockCenter { return CGPointMake(self.anchor.x, self.anchor.y - kLockOffsetY); }

- (void)presentAtAnchor:(CGPoint)anchor fingerPoint:(CGPoint)finger {
    self.anchor = anchor;
    self.phase = IMVoiceLockPhaseNone;
    self.hidden = NO;
    self.alpha = 1.0;
    self.bigCircle.center = anchor;
    self.ring.center = anchor;
    self.lockPill.center = [self lockCenter];
    self.lockPill.transform = CGAffineTransformIdentity;
    self.lockIcon.tintColor = IMTheme.textSecondary;
    self.bigCircle.backgroundColor = IMTheme.accent;
    // 弹出：大圆钮从 0.6 弹到 1.0（原地放大的錯觉），锁钮淡入。
    self.bigCircle.transform = CGAffineTransformMakeScale(0.6, 0.6);
    self.lockPill.alpha = 0;
    [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.6
                        options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self.bigCircle.transform = CGAffineTransformIdentity;
        self.lockPill.alpha = 1.0;
    } completion:nil];
    [self updateFingerPoint:finger];
}

- (IMVoiceLockPhase)updateFingerPoint:(CGPoint)finger {
    self.bigCircle.center = finger;
    self.ring.center = finger;
    CGPoint lc = [self lockCenter];
    CGFloat dist = hypot(finger.x - lc.x, finger.y - lc.y);
    IMVoiceLockPhase next = dist <= kLockSnapRadius ? IMVoiceLockPhaseLocked
                          : dist <= kLockNearRadius ? IMVoiceLockPhaseNear
                          : IMVoiceLockPhaseNone;
    if (next != self.phase) {
        self.phase = next;
        BOOL near = (next != IMVoiceLockPhaseNone);
        if (near) {
            UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc]
                initWithStyle:(next == IMVoiceLockPhaseLocked ? UIImpactFeedbackStyleRigid : UIImpactFeedbackStyleLight)];
            [fb impactOccurred];
        }
        [UIView animateWithDuration:0.16 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            self.lockPill.transform = near ? CGAffineTransformMakeScale(1.1, 1.1) : CGAffineTransformIdentity;
            self.lockIcon.tintColor = near ? IMTheme.accent : IMTheme.textSecondary;
        } completion:nil];
    }
    return next;
}

- (void)updateAmplitude:(float)amplitude {
    CGFloat scale = 1.0 + MIN(0.35, MAX(0, amplitude) * 0.5); // §5.2：scale 1.0→1.35 实时振幅驱动
    self.ring.transform = CGAffineTransformMakeScale(scale, scale);
}

- (void)setCancelHint:(BOOL)cancelReady {
    [UIView animateWithDuration:0.18 animations:^{
        self.bigCircle.backgroundColor = cancelReady ? UIColor.systemRedColor : IMTheme.accent;
    }];
}

- (void)dismissLocked {
    // 锁定确认：锁图标定格 accent、上箭头停呼吸，随后整体淡出。
    [self.lockArrow.layer removeAnimationForKey:@"breathe"];
    UIImageSymbolConfiguration *lockCfg = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
    self.lockIcon.image = [UIImage systemImageNamed:@"lock.fill" withConfiguration:lockCfg];
    self.lockIcon.tintColor = IMTheme.accent;
    [UIView animateWithDuration:0.22 delay:0.12 options:0 animations:^{ self.alpha = 0; }
                     completion:^(BOOL fin) { [self resetHidden]; }];
}

- (void)dismiss {
    [UIView animateWithDuration:0.18 animations:^{ self.alpha = 0; }
                     completion:^(BOOL fin) { [self resetHidden]; }];
}

- (void)resetHidden {
    self.hidden = YES;
    self.ring.transform = CGAffineTransformIdentity;
    UIImageSymbolConfiguration *lockCfg = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
    self.lockIcon.image = [UIImage systemImageNamed:@"lock" withConfiguration:lockCfg];
    // 呼吸箭头下次 present 前重挂（removeAnimation 后不自动恢复）。
    CABasicAnimation *breathe = [CABasicAnimation animationWithKeyPath:@"position.y"];
    breathe.byValue = @(-4);
    breathe.duration = 0.7;
    breathe.autoreverses = YES;
    breathe.repeatCount = HUGE_VALF;
    [self.lockArrow.layer addAnimation:breathe forKey:@"breathe"];
}

@end
