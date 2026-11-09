//  UIViewController+IMToast.m

#import "UIViewController+IMToast.h"
#import "IMAnimator.h"
#import "IMTheme.h"
#import "IMLocalization.h"

BOOL IMToastDedup(NSString *text, CFTimeInterval now, NSString *__strong *lastText, CFTimeInterval *lastAt,
                  CFTimeInterval window) {
    if (*lastText && [*lastText isEqualToString:text] && now - *lastAt >= 0 && now - *lastAt < window) {
        return NO;
    }
    *lastText = [text copy];
    *lastAt = now;
    return YES;
}

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

    [NSLayoutConstraint activateConstraints:@[
        [pill.centerXAnchor constraintEqualToAnchor:host.centerXAnchor],
        // 贴键盘上沿：键盘收起时 keyboardLayoutGuide 即安全区底部（与原位置一致）；键盘弹着时（聊天页编辑被拦、
        // 发送失败这类提示出现时输入框往往正聚焦）贴安全区底会整个藏在键盘后面，用户看不到原因。
        [pill.bottomAnchor constraintEqualToAnchor:host.keyboardLayoutGuide.topAnchor constant:-IMTheme.space4 * 3],
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
    [self im_showToast:IMLocalizedFormat(@"common.coming_soon", title ?: @"")];
}

+ (void)im_showGlobalToast:(NSString *)text {
    UIViewController *top = [self im_topVisibleViewController];
    [top im_showToast:text];
}

/// 从前台 key window 的 rootViewController 钻到当前可见的控制器（穿透 presented / nav / tab）。
+ (nullable UIViewController *)im_topVisibleViewController {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) { continue; }
        if (![scene isKindOfClass:UIWindowScene.class]) { continue; }
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) { keyWindow = w; break; }
        }
        if (keyWindow) { break; }
    }
    UIViewController *vc = keyWindow.rootViewController;
    while (YES) {
        if (vc.presentedViewController) { vc = vc.presentedViewController; continue; }
        if ([vc isKindOfClass:UINavigationController.class]) {
            UIViewController *v = ((UINavigationController *)vc).visibleViewController;
            if (v && v != vc) { vc = v; continue; }
        }
        if ([vc isKindOfClass:UITabBarController.class]) {
            UIViewController *v = ((UITabBarController *)vc).selectedViewController;
            if (v && v != vc) { vc = v; continue; }
        }
        break;
    }
    return vc;
}

@end
