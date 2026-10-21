#import "IMDayPillView.h"
#import "IMTheme.h"

static const CGFloat kIMDayPillTopInset = 8;
static const CGFloat kIMDayPillHeight = 24;

@implementation IMDayPillView {
    UIView *_capsule;
    UILabel *_label;
    NSLayoutConstraint *_height;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.hidden = YES;
        _capsule = [UIView new];
        _capsule.translatesAutoresizingMaskIntoConstraints = NO;
        _capsule.layer.cornerRadius = kIMDayPillHeight / 2;
        _capsule.layer.masksToBounds = YES;
        [self addSubview:_capsule];
        _label = [UILabel new];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _label.textColor = IMTheme.datePillText;
        _label.textAlignment = NSTextAlignmentCenter;
        [_capsule addSubview:_label];
        _height = [self.heightAnchor constraintEqualToConstant:0];
        [NSLayoutConstraint activateConstraints:@[
            _height,
            [_capsule.topAnchor constraintEqualToAnchor:self.topAnchor constant:kIMDayPillTopInset],
            [_capsule.heightAnchor constraintEqualToConstant:kIMDayPillHeight],
            [_capsule.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_label.leadingAnchor constraintEqualToAnchor:_capsule.leadingAnchor constant:12],
            [_label.trailingAnchor constraintEqualToAnchor:_capsule.trailingAnchor constant:-12],
            [_label.centerYAnchor constraintEqualToAnchor:_capsule.centerYAnchor],
        ]];
    }
    return self;
}

- (void)applyText:(NSString *)text {
    BOOL shows = text.length > 0;
    self.hidden = !shows;
    if (shows) {
        _capsule.backgroundColor = [IMTheme.accent colorWithAlphaComponent:0.64];
        _label.textColor = IMTheme.datePillText;
    }
    _label.text = shows ? text : @"";
    _height.constant = shows ? kIMDayPillTopInset + kIMDayPillHeight : 0;
}

@end
