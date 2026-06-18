//  UIViewController+IMToast.m

#import "UIViewController+IMToast.h"
#import "IMAnimator.h"
#import "IMTheme.h"

@implementation UIViewController (IMToast)

- (void)im_showToast:(NSString *)text {
    if (text.length == 0) { return; }
    UIView *host = self.view;
    if (!host) { return; }

    // 容器（圆角胶囊底） + 内嵌 label（用约束做内边距，UILabel 自身不响应 layoutMargins）。
    UIView *pill = [UIView new];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.85]; // 语义色自适配深浅色
    pill.layer.cornerRadius = IMTheme.radiusCard + 6;
    pill.layer.masksToBounds = YES;
    pill.userInteractionEnabled = NO;
    [host addSubview:pill];

    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    label.textColor = [UIColor.systemBackgroundColor colorWithAlphaComponent:1.0]; // 与 labelColor 底反差
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    [pill addSubview:label];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [pill.centerXAnchor constraintEqualToAnchor:host.centerXAnchor],
        [pill.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-IMTheme.space4 * 3],
        [pill.leadingAnchor constraintGreaterThanOrEqualToAnchor:host.leadingAnchor constant:IMTheme.space4 * 2],
        [pill.trailingAnchor constraintLessThanOrEqualToAnchor:host.trailingAnchor constant:-IMTheme.space4 * 2],

        [label.topAnchor constraintEqualToAnchor:pill.topAnchor constant:IMTheme.space3],
        [label.bottomAnchor constraintEqualToAnchor:pill.bottomAnchor constant:-IMTheme.space3],
        [label.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:IMTheme.space4],
        [label.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-IMTheme.space4],
    ]];

    [IMAnimator springPopIn:pill];
    [UIView animateWithDuration:0.3 delay:1.6 options:UIViewAnimationOptionCurveEaseIn animations:^{
        pill.alpha = 0;
        pill.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        [pill removeFromSuperview];
    }];
}

- (void)im_showComingSoon:(NSString *)title {
    [self im_showToast:[NSString stringWithFormat:@"%@（开发中）", title ?: @""]];
}

@end
