//  IMLocalization.h
//  App 内界面语言（每设备偏好，跟随系统 / 简体中文 / English）。契约见 ../IMServer/docs/design/I18N_DESIGN.md。
//
//  为什么不直接 NSLocalizedString：它只跟**系统**语言，不支持 App 内切换。这里按偏好选 `xx.lproj` 的 NSBundle 取词。
//  文案来自 ../IMServer/docs/i18n/strings.json，经 scripts/i18n/gen-i18n.mjs 生成到 Resources/Localization/，勿手改生成物。
//  ⚠️ **禁止在 +load / 静态初始化 / 全局常量里取文案**——那时求值一次，切语言后不会变；常量里放 key，用的时候再取。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 偏好值（存 NSUserDefaults `im.language`）。
extern NSString *const IMLanguagePrefSystem;   // @"system"
extern NSString *const IMLanguagePrefZhHans;   // @"zh-Hans"
extern NSString *const IMLanguagePrefEnglish;  // @"en"

/// 偏好变了（含解析出的语言没变但偏好变了，如 system→zh）。主线程发。SceneDelegate 据此重建根控制器。
extern NSNotificationName const IMLanguageDidChangeNotification;

@interface IMLocalization : NSObject

+ (instancetype)shared;
/// 测试 / 注入用：指定偏好存储、资源 Bundle 与系统语言来源。
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
                          bundle:(NSBundle *)bundle
                 systemLanguages:(NSArray<NSString *> * (^)(void))systemLanguages NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// 「跟随系统」解析（纯函数）：首个被支持的系统语言；繁体归简体；都不支持回落 en（设计稿 §2）。
+ (NSString *)resolveLanguageForPreference:(NSString *)preference systemLanguages:(NSArray<NSString *> *)systemLanguages;

@property (nonatomic, copy, readonly) NSString *preference; ///< system | zh-Hans | en
@property (nonatomic, copy, readonly) NSString *language;   ///< 解析后：zh-Hans | en
@property (nonatomic, strong, readonly) NSLocale *locale;   ///< 解析后语言对应的 locale（日期/数字格式化用它，不是系统 locale）

/// 设偏好；非法值忽略；真的变了才落盘并发通知。
- (void)setPreference:(NSString *)preference;

- (NSString *)stringForKey:(NSString *)key;
/// 带占位符（`%1$@` / `%1$ld`，由生成器产出）；按 App 语言的 locale 格式化，复数走 stringsdict。
- (NSString *)formattedStringForKey:(NSString *)key, ...;

/// 语言的**自称**（不随界面语言翻译，用户切错了还认得出来）。
+ (NSString *)nativeNameForLanguage:(NSString *)language;
/// 设置页「语言」行右侧的当前值：跟随系统时写成「跟随系统（简体中文）」。
- (NSString *)currentPreferenceLabel;
/// 「跟随系统」当前解析成的语言自称。
- (NSString *)systemLanguageNativeName;

@end

#define IMLocalized(key) ([IMLocalization.shared stringForKey:(key)])
#define IMLocalizedFormat(key, ...) ([IMLocalization.shared formattedStringForKey:(key), ##__VA_ARGS__])

/// 按 `args` 个数安全分派到 `IMLocalizedFormat`（ObjC 变参方法不能用一个动态长度的数组直接转发调用，
/// 只能按元数分档手写）。P3 结构化模板批量复用（IMSysEventFormatter 的 sys_event/系统通知、
/// IMMediaUtil 的 reply_snapshot_kind），避免各处各写一份相同的按元数分派 switch。
/// `args.count` 超出已实现档位时返回未替换的原串（防御性兜底，理论上不会触发——上限由调用方模板决定）。
FOUNDATION_EXPORT NSString *IMLocalizedFormatArgs(NSString *key, NSArray<NSString *> *args);

NS_ASSUME_NONNULL_END
