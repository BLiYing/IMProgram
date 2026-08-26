//
//  UIView+IMFade.m
//

#import "UIView+IMFade.h"
#import <objc/runtime.h>

/// 最新一次 im_setVisible: 的意图，供过期动画的完成回调自查。
static const void *kIMFadeWantsVisibleKey = &kIMFadeWantsVisibleKey;

@implementation UIView (IMFade)

- (void)im_setVisible:(BOOL)visible
             animated:(BOOL)animated
             duration:(NSTimeInterval)duration
              damping:(CGFloat)damping {
    objc_setAssociatedObject(self, kIMFadeWantsVisibleKey, @(visible), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (visible) { self.hidden = NO; }
    void (^apply)(void) = ^{ self.alpha = visible ? 1.0 : 0.0; };
    void (^settle)(void) = ^{
        if (visible) { return; }
        // 动画期间又被要求显示 → 这次回调已过期，别把刚点亮的 UI 隐掉。
        if ([objc_getAssociatedObject(self, kIMFadeWantsVisibleKey) boolValue]) { return; }
        self.hidden = YES;
    };
    if (!animated) { apply(); settle(); return; }
    UIViewAnimationOptions opts = UIViewAnimationOptionAllowUserInteraction;
    if (damping > 0) {
        [UIView animateWithDuration:duration delay:0 usingSpringWithDamping:damping initialSpringVelocity:0.5
                            options:opts animations:apply completion:^(BOOL finished) { settle(); }];
    } else {
        [UIView animateWithDuration:duration delay:0 options:opts animations:apply completion:^(BOOL finished) { settle(); }];
    }
}

@end
