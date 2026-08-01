//  IMGlass.h
//  Apple Liquid Glass 兼容入口：iOS 26 使用官方 API，旧系统使用 UIKit 系统材质降级。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

NS_INLINE UIVisualEffect *IMGlassEffect(BOOL interactive) {
    if (@available(iOS 26.0, *)) {
        UIGlassEffect *effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
        effect.interactive = interactive;
        return effect;
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
}

NS_INLINE UIVisualEffectView *IMGlassEffectView(BOOL interactive) {
    return [[UIVisualEffectView alloc] initWithEffect:IMGlassEffect(interactive)];
}

NS_INLINE UIButtonConfiguration *IMGlassButtonConfiguration(void) {
    if (@available(iOS 26.0, *)) {
        return [UIButtonConfiguration glassButtonConfiguration];
    }
    return [UIButtonConfiguration grayButtonConfiguration];
}

NS_INLINE UIButtonConfiguration *IMProminentGlassButtonConfiguration(void) {
    if (@available(iOS 26.0, *)) {
        return [UIButtonConfiguration prominentGlassButtonConfiguration];
    }
    return [UIButtonConfiguration filledButtonConfiguration];
}

NS_ASSUME_NONNULL_END
