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

/// 全 app 搜索框统一圆角 = IMLiquidNavigationBar 中间标题玻璃胶囊圆角（24），使所有搜索框（会话内、全局、
/// 找人、会话列表、@面板…）观感一致。
static const CGFloat kIMSearchFieldCornerRadius = 24;

/// 把任意 UISearchBar 的输入框统一成 kIMSearchFieldCornerRadius 圆角（continuous）。仅统一圆角，不改其底色/风格。
NS_INLINE void IMApplyUnifiedSearchFieldStyle(UISearchBar *searchBar) {
    if (!searchBar) { return; }
    if (@available(iOS 13.0, *)) {
        UISearchTextField *field = searchBar.searchTextField;
        field.layer.cornerRadius = kIMSearchFieldCornerRadius;
        field.layer.cornerCurve = kCACornerCurveContinuous;
        field.clipsToBounds = YES;
    }
}

NS_ASSUME_NONNULL_END
