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

static UIColor *IMColorFromHex(uint32_t hex) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0 alpha:1];
}

// 把 color 按比例 f 混向 target（f=0 原色、f=1 目标色）；用于从主题色派生气泡/壁纸配色。
static UIColor *IMBlendColor(UIColor *color, UIColor *target, CGFloat f) {
    CGFloat r1 = 0, g1 = 0, b1 = 0, a1 = 1, r2 = 0, g2 = 0, b2 = 0, a2 = 1;
    [color getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
    [target getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
    return [UIColor colorWithRed:r1 + (r2 - r1) * f
                           green:g1 + (g2 - g1) * f
                            blue:b1 + (b2 - b1) * f alpha:1];
}

// 内置主题合法 ID 的唯一来源：init / setThemeID / wallpaperColorsForThemeID 校验共用，避免多处漂移。
static NSArray<NSString *> *IMValidThemeIDs(void) {
    return @[@"classic", @"ocean", @"violet", @"midnight",
             @"lime", @"titian", @"mars-green", @"klein-blue", @"burgundy",
             @"schonbrunn", @"tiffany", @"china-red", @"hermes-orange", @"prussian-blue"];
}

// 新增色系主题：只给「主题色（accent）」，气泡与壁纸由 accent 按可读性派生
// （浅色 → 淡彩底配深字；深色 → 暗彩底配白字，与 IMTheme.bubbleMeText=labelColor 契约一致）。
// 经典/海洋/紫晶/深海 4 个老主题仍走各自手调分支，不进此表。
static NSDictionary<NSString *, UIColor *> *IMCustomThemeAccents(void) {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"lime": IMColorFromHex(0x6ECC54),          // 莱姆绿
            @"titian": IMColorFromHex(0xD34947),        // 提香红
            @"mars-green": IMColorFromHex(0x018B8D),    // 马尔斯绿
            @"klein-blue": IMColorFromHex(0x002FA7),    // 克莱因蓝
            @"burgundy": IMColorFromHex(0x470125),      // 勃垦第红
            @"schonbrunn": IMColorFromHex(0xF9D46C),    // 申布伦黄
            @"tiffany": IMColorFromHex(0x71E2D1),       // 蒂芙尼蓝
            @"china-red": IMColorFromHex(0xC8161D),     // 中国红
            @"hermes-orange": IMColorFromHex(0xEB5C20), // 爱马仕橙
            @"prussian-blue": IMColorFromHex(0x0D3A69), // 普鲁士蓝
        };
    });
    return map;
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
        _themeID = IMContainsString(IMValidThemeIDs(), storedTheme) ? storedTheme : @"classic";
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
    _themeID = IMContainsString(IMValidThemeIDs(), themeID) ? [themeID copy] : @"classic";
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
    UIColor *custom = IMCustomThemeAccents()[themeID];
    if (custom) { return custom; }
    return UIColor.systemGreenColor;
}

- (UIColor *)bubbleMeColor {
    return [self bubbleMeColorForThemeID:self.themeID];
}

- (UIColor *)bubbleMeColorForThemeID:(NSString *)themeID {
    NSString *theme = [themeID copy];
    UIColor *custom = IMCustomThemeAccents()[theme];
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        BOOL dark = trait.userInterfaceStyle == UIUserInterfaceStyleDark;
        if (custom) {
            // 气泡保留较多本色（浅色 42%、深色 50%），与下方极淡壁纸拉开对比；文字用 labelColor 仍达标。
            return dark ? IMBlendColor(custom, UIColor.blackColor, 0.50)
                        : IMBlendColor(custom, UIColor.whiteColor, 0.58);
        }
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
    UIColor *custom = IMCustomThemeAccents()[themeID];
    if (custom) {
        // 壁纸压到极淡（浅色近白微染、深色近黑微染），只作背景，与更饱和的气泡拉开区分度。
        return dark ? @[IMBlendColor(custom, UIColor.blackColor, 0.92), IMBlendColor(custom, UIColor.blackColor, 0.84)]
                    : @[IMBlendColor(custom, UIColor.whiteColor, 0.91), IMBlendColor(custom, UIColor.whiteColor, 0.84)];
    }
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
    NSString *resolvedTheme = IMContainsString(IMValidThemeIDs(), themeID)
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
