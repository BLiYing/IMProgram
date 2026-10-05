//  IMSettingsSearchRegistry.h
//  首页全局搜索「设置」分组的显式登记表（SEARCH_DESIGN §3.1）。纯逻辑、无 UI 依赖，便于单测。
//
//  · 登记表是**显式**的，不从 UI 行反推：只列「能直接打开的页面」，纯展示行 / 开关内部子选项 / 破坏性行
//    （退出登录、清缓存、重置）/「开发中」占位行一律不进。
//  · 每条 = {id, title, path, systemImage, iconBg, route}。
//      path  ：从「我」页往下的**完整页面路径（含自身）**，如 [通知与提示音, 私聊通知, 提示音]；副标题显示「A › B › C」。
//      route ：与 path 逐级对应的页面 id（IMSettingsRouter 据此逐级建页）。不变式：route.count == path.count。
//  · 匹配：对 path 拼接串（含 title）做 trim + 大小写不敏感子串匹配，规则同 IMScopedSearchNormalize。
//  · 排序：title 命中在前、仅 path 命中在后；同档保持登记顺序。
//  · 文案一律取现有 IMLocalized key（登记表每次 +allEntries 现取，切语言后自然是新语言）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 登记表里一条可搜索的设置项。
@interface IMSettingsSearchEntry : NSObject
@property (nonatomic, copy) NSString *entryID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray<NSString *> *path;       ///< 完整页面路径（含自身），不含「我」
@property (nonatomic, copy, nullable) NSString *systemImage;
@property (nonatomic, strong, nullable) UIColor *iconBg;     ///< 与「我」页同款系统色底
@property (nonatomic, copy) NSArray<NSString *> *route;      ///< 逐级页面 id，与 path 等长
/// 仅供匹配的同义词（不显示）：文案叫「提示音」但用户会搜「声音」。命中算「标题命中」档。
@property (nonatomic, copy) NSArray<NSString *> *aliases;

+ (instancetype)entryWithID:(NSString *)entryID title:(NSString *)title path:(NSArray<NSString *> *)path
                systemImage:(nullable NSString *)image iconBg:(nullable UIColor *)bg route:(NSArray<NSString *> *)route;

/// 结果行副标题：「A › B」。一级页（path 仅自身）显示「我」页名，避免与标题重复。
- (NSString *)subtitle;
/// 匹配用拼接串：整条路径（已含自身标题）+ 标题，以 IMSettingsSearchPathSeparator 连接。
- (NSString *)searchHaystack;
@end

/// 路径分隔符（副标题与匹配拼接串共用）。
FOUNDATION_EXPORT NSString *const IMSettingsSearchPathSeparator;

@interface IMSettingsSearchRegistry : NSObject

/// 全部可搜索条目（按展示用的登记顺序，文案为当前界面语言）。
+ (NSArray<IMSettingsSearchEntry *> *)allEntries;

/// 在 entries 里按 keyword 过滤 + 排序。空 / 全空白关键词 → 空数组。
+ (NSArray<IMSettingsSearchEntry *> *)filterEntries:(NSArray<IMSettingsSearchEntry *> *)entries
                                            keyword:(nullable NSString *)keyword;

@end

NS_ASSUME_NONNULL_END
