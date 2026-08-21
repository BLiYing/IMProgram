//  IMFavoritesCategories.h
//  收藏页「分类」的类型推导（纯逻辑，可单测）。
//  仿会话详情页 IMChatDetailTabs：分类**按收藏里实际存在的内容类型动态生成**，只展示存在的类别；
//  但收藏页**恒有「全部」置首并作默认**（详情页无「全部」，因它逐类浏览；收藏是浏览主界面，需总览）。
//  归类口径与 IMChatDetailTabs 对齐（链接=独立 link 或形如 URL 的文本），两处规则不漂移。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 一个收藏分类。除「全部」外均由 content_type 派生。
typedef NS_ENUM(NSInteger, IMFavoriteCategory) {
    IMFavoriteCategoryAll = 0, ///< 全部（恒在、置首、默认；非内容类型）
    IMFavoriteCategoryMedia,   ///< 媒体（image / video）
    IMFavoriteCategoryFiles,   ///< 文件（file）
    IMFavoriteCategoryLinks,   ///< 链接（link 类型，或 text 且形如 URL）
    IMFavoriteCategoryVoice,   ///< 语音（audio / voice）
    IMFavoriteCategoryText,    ///< 文本（text 且非链接、非聊天记录）
    IMFavoriteCategoryRecord,  ///< 聊天记录（合并转发 chat_record）
};

/// 分类描述：类别 + 展示标题。
@interface IMFavoriteCategoryTab : NSObject
@property (nonatomic, assign) IMFavoriteCategory kind;
@property (nonatomic, copy) NSString *title;
@end

@interface IMFavoritesCategories : NSObject

/// 由收藏列表（原始字典数组，含 content_type / content 键）推导有序分类：
/// 「全部」恒第一；其余按 媒体→文件→链接→语音→文本 顺序，仅当该类别存在收藏时才出现。
+ (NSArray<IMFavoriteCategoryTab *> *)categoriesForFavorites:(nullable NSArray<NSDictionary *> *)favorites;

/// 同上，但可选是否含「全部」。B 方案（复用详情页逐签浏览）不含「全部」：
/// 页签 = 按 媒体→文件→链接→语音→文本→聊天记录 顺序仅存在者；全无可归类收藏时返回空数组。
+ (NSArray<IMFavoriteCategoryTab *> *)categoriesForFavorites:(nullable NSArray<NSDictionary *> *)favorites
                                                  includeAll:(BOOL)includeAll;

/// 某条收藏是否属于某分类。`All` 对任意非空收藏恒 YES。用于分类/范围搜索过滤，避免与推导逻辑重复。
+ (BOOL)favorite:(nullable NSDictionary *)favorite matchesCategory:(IMFavoriteCategory)kind;

/// 分类的中文标题。
+ (NSString *)titleForCategory:(IMFavoriteCategory)kind;

@end

NS_ASSUME_NONNULL_END
