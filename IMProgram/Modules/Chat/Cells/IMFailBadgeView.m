//
//  IMFailBadgeView.m
//

#import "IMFailBadgeView.h"

static const CGFloat kIMFailBadgeDiameter = 18;

/// 命中区外扩：18pt 圆点按 HIG 太小按不中。**右侧只放 4pt**——红❗与气泡只隔 6pt，
/// 右边放宽到 10pt 会盖进气泡边缘、把本该落在气泡上的点击吃掉。
static const UIEdgeInsets kIMFailBadgeTouchOutset = { .top = 11, .left = 11, .bottom = 11, .right = 4 };

@implementation IMFailBadgeView {
    UILabel *_mark;
}

+ (CGFloat)diameter { return kIMFailBadgeDiameter; }

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = UIColor.systemRedColor;
        self.layer.cornerRadius = kIMFailBadgeDiameter / 2;
        self.layer.masksToBounds = YES;
        self.hidden = YES;              // 默认不占位：由 cell 在 failed 时开
        self.userInteractionEnabled = NO; // 随 tappable 打开
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = @"发送失败，点按重发";
        self.accessibilityTraits = UIAccessibilityTraitButton;

        _mark = [UILabel new];
        _mark.translatesAutoresizingMaskIntoConstraints = NO;
        _mark.text = @"!";
        _mark.font = [UIFont boldSystemFontOfSize:13];
        _mark.textColor = UIColor.whiteColor;
        _mark.textAlignment = NSTextAlignmentCenter;
        _mark.userInteractionEnabled = NO;
        [self addSubview:_mark];

        [NSLayoutConstraint activateConstraints:@[
            [self.widthAnchor constraintEqualToConstant:kIMFailBadgeDiameter],
            [self.heightAnchor constraintEqualToConstant:kIMFailBadgeDiameter],
            [_mark.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_mark.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
        [self addTarget:self action:@selector(im_tapped) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)setTappable:(BOOL)tappable {
    _tappable = tappable;
    self.userInteractionEnabled = tappable; // NO 时事件穿透给气泡，而不是被一个不响应的控件吞掉
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return CGRectContainsPoint(UIEdgeInsetsInsetRect(self.bounds, (UIEdgeInsets){
        -kIMFailBadgeTouchOutset.top, -kIMFailBadgeTouchOutset.left,
        -kIMFailBadgeTouchOutset.bottom, -kIMFailBadgeTouchOutset.right }), point);
}

- (void)im_tapped {
    if (self.onTap) { self.onTap(); }
}

@end
