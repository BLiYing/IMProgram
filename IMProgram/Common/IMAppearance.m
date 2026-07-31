//  IMAppearance.m

#import "IMAppearance.h"

NSNotificationName const IMAppearanceDidChangeNotification = @"IMAppearanceDidChangeNotification";

static NSString * const kIMAppearanceModeKey = @"im.appearance.mode";
static NSString * const kIMAppearanceThemeKey = @"im.appearance.theme";
static NSString * const kIMAppearanceWallpaperKey = @"im.appearance.wallpaper";
static NSString * const kIMAppearanceFontKey = @"im.appearance.chatFont";
static NSString * const kIMAppearanceRadiusKey = @"im.appearance.bubbleRadius";
static NSString * const kIMAppearanceAnimationsKey = @"im.appearance.animations";

static BOOL IMContainsString(NSArray<NSString *> *values, NSString *value) {
    return value.length > 0 && [values containsObject:value];
}

@implementation IMAppearance

+ (instancetype)shared {
    static IMAppearance *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ value = [IMAppearance new]; });
    return value;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
        NSInteger storedMode = [d objectForKey:kIMAppearanceModeKey] ? [d integerForKey:kIMAppearanceModeKey] : IMAppearanceModeSystem;
        _mode = MIN(IMAppearanceModeDark, MAX(IMAppearanceModeSystem, storedMode));
        NSString *storedTheme = [d stringForKey:kIMAppearanceThemeKey];
        _themeID = IMContainsString(@[@"classic", @"ocean", @"violet", @"midnight"], storedTheme) ? storedTheme : @"classic";
        NSString *storedWallpaper = [d stringForKey:kIMAppearanceWallpaperKey];
        _wallpaperID = IMContainsString(@[@"doodle", @"gradient", @"plain"], storedWallpaper) ? storedWallpaper : @"doodle";
        CGFloat storedFont = [d objectForKey:kIMAppearanceFontKey] ? [d doubleForKey:kIMAppearanceFontKey] : 17;
        _chatFontSize = MIN(22, MAX(14, storedFont));
        CGFloat storedRadius = [d objectForKey:kIMAppearanceRadiusKey] ? [d doubleForKey:kIMAppearanceRadiusKey] : 18;
        _bubbleRadius = MIN(24, MAX(6, storedRadius));
        _animationsEnabled = [d objectForKey:kIMAppearanceAnimationsKey] ? [d boolForKey:kIMAppearanceAnimationsKey] : YES;
    }
    return self;
}

- (void)setMode:(IMAppearanceMode)mode {
    _mode = MIN(IMAppearanceModeDark, MAX(IMAppearanceModeSystem, mode));
    [NSUserDefaults.standardUserDefaults setInteger:_mode forKey:kIMAppearanceModeKey];
    [self applyInterfaceStyle];
    [self notifyChange];
}

- (void)setThemeID:(NSString *)themeID {
    _themeID = IMContainsString(@[@"classic", @"ocean", @"violet", @"midnight"], themeID) ? [themeID copy] : @"classic";
    [NSUserDefaults.standardUserDefaults setObject:_themeID forKey:kIMAppearanceThemeKey];
    [self notifyChange];
}

- (void)setWallpaperID:(NSString *)wallpaperID {
    _wallpaperID = IMContainsString(@[@"doodle", @"gradient", @"plain"], wallpaperID) ? [wallpaperID copy] : @"doodle";
    [NSUserDefaults.standardUserDefaults setObject:_wallpaperID forKey:kIMAppearanceWallpaperKey];
    [self notifyChange];
}

- (void)setChatFontSize:(CGFloat)chatFontSize {
    _chatFontSize = MIN(22, MAX(14, chatFontSize));
    [NSUserDefaults.standardUserDefaults setDouble:_chatFontSize forKey:kIMAppearanceFontKey];
    [self notifyChange];
}

- (void)setBubbleRadius:(CGFloat)bubbleRadius {
    _bubbleRadius = MIN(24, MAX(6, bubbleRadius));
    [NSUserDefaults.standardUserDefaults setDouble:_bubbleRadius forKey:kIMAppearanceRadiusKey];
    [self notifyChange];
}

- (void)setAnimationsEnabled:(BOOL)animationsEnabled {
    _animationsEnabled = animationsEnabled;
    [NSUserDefaults.standardUserDefaults setBool:animationsEnabled forKey:kIMAppearanceAnimationsKey];
    [self notifyChange];
}

- (void)notifyChange {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) { continue; }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) { window.tintColor = self.accentColor; }
    }
    [NSNotificationCenter.defaultCenter postNotificationName:IMAppearanceDidChangeNotification object:self];
}

- (void)applyInterfaceStyle {
    UIUserInterfaceStyle style = UIUserInterfaceStyleUnspecified;
    if (self.mode == IMAppearanceModeLight) { style = UIUserInterfaceStyleLight; }
    if (self.mode == IMAppearanceModeDark) { style = UIUserInterfaceStyleDark; }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) { continue; }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            window.overrideUserInterfaceStyle = style;
        }
    }
}

- (UIColor *)accentColor {
    return [self accentColorForThemeID:self.themeID];
}

- (UIColor *)accentColorForThemeID:(NSString *)themeID {
    if ([themeID isEqualToString:@"ocean"]) { return UIColor.systemBlueColor; }
    if ([themeID isEqualToString:@"violet"]) { return UIColor.systemPurpleColor; }
    if ([themeID isEqualToString:@"midnight"]) { return [UIColor colorWithRed:0.24 green:0.62 blue:0.88 alpha:1]; }
    return UIColor.systemGreenColor;
}

- (UIColor *)bubbleMeColor {
    return [self bubbleMeColorForThemeID:self.themeID];
}

- (UIColor *)bubbleMeColorForThemeID:(NSString *)themeID {
    NSString *theme = [themeID copy];
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        BOOL dark = trait.userInterfaceStyle == UIUserInterfaceStyleDark;
        if ([theme isEqualToString:@"ocean"]) {
            return dark ? [UIColor colorWithRed:0.08 green:0.27 blue:0.43 alpha:1]
                        : [UIColor colorWithRed:0.78 green:0.92 blue:1 alpha:1];
        }
        if ([theme isEqualToString:@"violet"]) {
            return dark ? [UIColor colorWithRed:0.28 green:0.18 blue:0.42 alpha:1]
                        : [UIColor colorWithRed:0.91 green:0.84 blue:1 alpha:1];
        }
        if ([theme isEqualToString:@"midnight"]) {
            return dark ? [UIColor colorWithRed:0.10 green:0.24 blue:0.34 alpha:1]
                        : [UIColor colorWithRed:0.78 green:0.91 blue:0.95 alpha:1];
        }
        return dark ? [UIColor colorWithRed:0.12 green:0.30 blue:0.18 alpha:1]
                    : [UIColor colorWithRed:0.89 green:0.99 blue:0.82 alpha:1];
    }];
}

- (NSArray<UIColor *> *)wallpaperPairForThemeID:(NSString *)themeID dark:(BOOL)dark {
    if ([themeID isEqualToString:@"ocean"]) {
        return dark ? @[[UIColor colorWithRed:0.04 green:0.12 blue:0.20 alpha:1], [UIColor colorWithRed:0.07 green:0.24 blue:0.32 alpha:1]]
                    : @[[UIColor colorWithRed:0.72 green:0.91 blue:0.98 alpha:1], [UIColor colorWithRed:0.58 green:0.78 blue:0.94 alpha:1]];
    }
    if ([themeID isEqualToString:@"violet"]) {
        return dark ? @[[UIColor colorWithRed:0.12 green:0.07 blue:0.22 alpha:1], [UIColor colorWithRed:0.25 green:0.12 blue:0.32 alpha:1]]
                    : @[[UIColor colorWithRed:0.88 green:0.79 blue:0.98 alpha:1], [UIColor colorWithRed:0.72 green:0.86 blue:0.98 alpha:1]];
    }
    if ([themeID isEqualToString:@"midnight"]) {
        return dark ? @[[UIColor colorWithRed:0.02 green:0.05 blue:0.10 alpha:1], [UIColor colorWithRed:0.05 green:0.13 blue:0.20 alpha:1]]
                    : @[[UIColor colorWithRed:0.75 green:0.84 blue:0.89 alpha:1], [UIColor colorWithRed:0.56 green:0.72 blue:0.81 alpha:1]];
    }
    return dark ? @[[UIColor colorWithRed:0.05 green:0.10 blue:0.07 alpha:1], [UIColor colorWithRed:0.09 green:0.15 blue:0.10 alpha:1]]
                : @[[UIColor colorWithRed:0.84 green:0.91 blue:0.77 alpha:1], [UIColor colorWithRed:0.71 green:0.85 blue:0.61 alpha:1]];
}

- (UIColor *)wallpaperTopColor {
    return [self wallpaperColorsForThemeID:self.themeID].firstObject;
}

- (UIColor *)wallpaperBottomColor {
    return [self wallpaperColorsForThemeID:self.themeID].lastObject;
}

- (NSArray<UIColor *> *)wallpaperColorsForThemeID:(NSString *)themeID {
    NSString *resolvedTheme = IMContainsString(@[@"classic", @"ocean", @"violet", @"midnight"], themeID)
        ? [themeID copy] : @"classic";
    UIColor *top = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        return [self wallpaperPairForThemeID:resolvedTheme
                                        dark:trait.userInterfaceStyle == UIUserInterfaceStyleDark].firstObject;
    }];
    UIColor *bottom = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        return [self wallpaperPairForThemeID:resolvedTheme
                                        dark:trait.userInterfaceStyle == UIUserInterfaceStyleDark].lastObject;
    }];
    return @[top, bottom];
}

- (UIColor *)wallpaperDoodleColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        return [UIColor colorWithWhite:1 alpha:trait.userInterfaceStyle == UIUserInterfaceStyleDark ? 0.035 : 0.16];
    }];
}

- (void)resetToDefaults {
    self.mode = IMAppearanceModeSystem;
    self.themeID = @"classic";
    self.wallpaperID = @"doodle";
    self.chatFontSize = 17;
    self.bubbleRadius = 18;
    self.animationsEnabled = YES;
}

@end
