//  IMScopedSearch.h
//  底部「搜索」tab 按来源页分域的纯匹配规则（可单测；三端口径见汇报/设计）：
//   · 「我」页：只搜「我」页各设置项的**当前界面语言标题**，trim 后大小写不敏感子串匹配；不含「退出登录」。
//   · 「通讯录」页：本地联系人（备注/昵称/@账号）+ 群聊（群名），同一套 trim + 子串匹配。
//   · 「消息」页：保持原全局搜索，不经本文件。

#import <UIKit/UIKit.h>

@class IMGroupInfo;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMSearchScope) {
    IMSearchScopeMessages = 0,   ///< 消息页来的（默认）：会话/联系人/聊天记录 + 搜索用户
    IMSearchScopeContacts,       ///< 通讯录页来的：联系人 + 群聊
    IMSearchScopeMe,             ///< 我页来的：设置项
};

/// 「我」页一个可搜索条目（rowId 与 IMSettingsViewController 的行 id 一致，命中后据此跳转）。
@interface IMSettingsSearchEntry : NSObject
@property (nonatomic, copy) NSString *rowId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *systemImage;
@property (nonatomic, strong, nullable) UIColor *iconBgColor;   ///< 「我」页该行的图标底色（命中行与「我」页一致）
+ (instancetype)entryWithId:(NSString *)rowId title:(NSString *)title systemImage:(nullable NSString *)image;
@end

/// 关键词规范化：去首尾空白，空串 = 不搜。
NSString *IMScopedSearchNormalize(NSString *_Nullable keyword);

/// 子串命中（大小写不敏感）。keyword 为空恒 NO；任一候选字段命中即 YES。
BOOL IMScopedSearchMatches(NSString *_Nullable keyword, NSArray<NSString *> *fields);

/// 「我」页：按 entries 原顺序返回标题命中的条目。
NSArray<IMSettingsSearchEntry *> *IMSettingsSearchFilter(NSArray<IMSettingsSearchEntry *> *entries, NSString *_Nullable keyword);

/// 「通讯录」范围的群聊命中：在**完整的我的群列表**里按群名匹配（保持原顺序），与 Android `myGroups` 同口径。
/// 不能拿会话列表当范围——有群但没有会话行（没发过言/会话被删）的群会搜不到。
/// 群名为空时按 `fallbackName`（界面上显示的占位名「群聊」）参与匹配，与行上显示一致。
NSArray<IMGroupInfo *> *IMScopedGroupHits(NSArray<IMGroupInfo *> *_Nullable groups, NSString *_Nullable keyword,
                                          NSString *fallbackName);

NS_ASSUME_NONNULL_END
