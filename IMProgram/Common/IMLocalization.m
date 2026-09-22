//  IMLocalization.m

#import "IMLocalization.h"

NSString *const IMLanguagePrefSystem = @"system";
NSString *const IMLanguagePrefZhHans = @"zh-Hans";
NSString *const IMLanguagePrefEnglish = @"en";
NSNotificationName const IMLanguageDidChangeNotification = @"IMLanguageDidChangeNotification";

static NSString *const kIMLanguageDefaultsKey = @"im.language";

@implementation IMLocalization {
    NSUserDefaults *_defaults;
    NSBundle *_resources;            // 含 zh-Hans.lproj / en.lproj 的 Bundle（默认 mainBundle）
    NSArray<NSString *> * (^_systemLanguages)(void);
    NSString *_preference;
    NSBundle *_langBundle;           // 当前语言的 .lproj Bundle；缺失时回落 _resources
}

+ (instancetype)shared {
    static IMLocalization *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[IMLocalization alloc] initWithDefaults:NSUserDefaults.standardUserDefaults
                                              bundle:NSBundle.mainBundle
                                     systemLanguages:^NSArray<NSString *> * { return NSLocale.preferredLanguages; }];
    });
    return s;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults bundle:(NSBundle *)bundle
                 systemLanguages:(NSArray<NSString *> * (^)(void))systemLanguages {
    if ((self = [super init])) {
        _defaults = defaults;
        _resources = bundle;
        _systemLanguages = [systemLanguages copy];
        NSString *saved = [defaults stringForKey:kIMLanguageDefaultsKey];
        _preference = [IMLocalization isValidPreference:saved] ? saved : IMLanguagePrefSystem;
        [self reloadBundle];
    }
    return self;
}

+ (BOOL)isValidPreference:(nullable NSString *)p {
    return [p isEqualToString:IMLanguagePrefSystem] || [p isEqualToString:IMLanguagePrefZhHans]
        || [p isEqualToString:IMLanguagePrefEnglish];
}

+ (NSString *)resolveLanguageForPreference:(NSString *)preference systemLanguages:(NSArray<NSString *> *)systemLanguages {
    if (![preference isEqualToString:IMLanguagePrefSystem]) {
        return [preference isEqualToString:IMLanguagePrefZhHans] ? IMLanguagePrefZhHans : IMLanguagePrefEnglish;
    }
    for (NSString *raw in systemLanguages) {
        NSString *l = raw.lowercaseString;
        if ([l hasPrefix:@"zh"]) { return IMLanguagePrefZhHans; } // 繁体暂归简体（无繁体资源）
        if ([l hasPrefix:@"en"]) { return IMLanguagePrefEnglish; }
    }
    return IMLanguagePrefEnglish; // 都不支持回落英文，不是中文
}

- (NSString *)preference { return _preference; }

- (NSString *)language {
    return [IMLocalization resolveLanguageForPreference:_preference systemLanguages:_systemLanguages()];
}

- (NSLocale *)locale {
    return [NSLocale localeWithLocaleIdentifier:[self.language isEqualToString:IMLanguagePrefZhHans] ? @"zh_Hans_CN" : @"en_US"];
}

- (void)reloadBundle {
    NSString *path = [_resources pathForResource:self.language ofType:@"lproj"];
    _langBundle = path ? [NSBundle bundleWithPath:path] : nil;
}

- (void)setPreference:(NSString *)preference {
    if (![IMLocalization isValidPreference:preference] || [preference isEqualToString:_preference]) { return; }
    _preference = [preference copy];
    if ([preference isEqualToString:IMLanguagePrefSystem]) { [_defaults removeObjectForKey:kIMLanguageDefaultsKey]; }
    else { [_defaults setObject:preference forKey:kIMLanguageDefaultsKey]; }
    [self reloadBundle];
    void (^post)(void) = ^{
        [NSNotificationCenter.defaultCenter postNotificationName:IMLanguageDidChangeNotification object:self];
    };
    if (NSThread.isMainThread) { post(); } else { dispatch_async(dispatch_get_main_queue(), post); }
}

/// 缺键回落：当前语言 → 中文源 → 键本身（不返回空串，界面上看到键名比空白好排查）。
- (NSString *)stringForKey:(NSString *)key {
    static NSString *const kMissing = @"__im_i18n_missing__";
    NSString *s = [_langBundle localizedStringForKey:key value:kMissing table:nil];
    if (s && ![s isEqualToString:kMissing]) { return s; }
    NSString *zhPath = [_resources pathForResource:IMLanguagePrefZhHans ofType:@"lproj"];
    NSBundle *zh = zhPath ? [NSBundle bundleWithPath:zhPath] : nil;
    s = [zh localizedStringForKey:key value:kMissing table:nil];
    return (s && ![s isEqualToString:kMissing]) ? s : key;
}

- (NSString *)formattedStringForKey:(NSString *)key, ... {
    NSString *fmt = [self stringForKey:key];
    va_list args;
    va_start(args, key);
    NSString *out = [[NSString alloc] initWithFormat:fmt locale:self.locale arguments:args];
    va_end(args);
    return out;
}

+ (NSString *)nativeNameForLanguage:(NSString *)language {
    return [language isEqualToString:IMLanguagePrefZhHans] ? @"简体中文" : @"English";
}

- (NSString *)systemLanguageNativeName {
    return [IMLocalization nativeNameForLanguage:
            [IMLocalization resolveLanguageForPreference:IMLanguagePrefSystem systemLanguages:_systemLanguages()]];
}

- (NSString *)currentPreferenceLabel {
    if ([_preference isEqualToString:IMLanguagePrefSystem]) {
        return [self formattedStringForKey:@"settings.language.current_system", [self systemLanguageNativeName]];
    }
    return [IMLocalization nativeNameForLanguage:_preference];
}

@end
