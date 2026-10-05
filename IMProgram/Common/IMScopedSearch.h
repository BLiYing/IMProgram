//  IMScopedSearch.h
//  全局搜索页按来源分域的纯匹配规则（可单测）：
//   · 「通讯录」页进来：本地联系人（备注/昵称/@账号）+ 群聊（群名），trim + 大小写不敏感子串匹配。
//   · 「消息」页进来：原全局搜索（另有「设置」分组，见 IMSettingsSearchRegistry）。
//  底部「搜索」tab 与「我」范围已于 2026-10-05 删除（SEARCH_DESIGN §3.1）。

#import <UIKit/UIKit.h>

@class IMGroupInfo;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMSearchScope) {
    IMSearchScopeMessages = 0,   ///< 消息页来的（默认）：会话/联系人/聊天记录/设置 + 搜索用户
    IMSearchScopeContacts,       ///< 通讯录页来的：联系人 + 群聊
};

/// 关键词规范化：去首尾空白，空串 = 不搜。
NSString *IMScopedSearchNormalize(NSString *_Nullable keyword);

/// 子串命中（大小写不敏感）。keyword 为空恒 NO；任一候选字段命中即 YES。
BOOL IMScopedSearchMatches(NSString *_Nullable keyword, NSArray<NSString *> *fields);

/// 「通讯录」范围的群聊命中：在**完整的我的群列表**里按群名匹配（保持原顺序），与 Android `myGroups` 同口径。
/// 不能拿会话列表当范围——有群但没有会话行（没发过言/会话被删）的群会搜不到。
/// 群名为空时按 `fallbackName`（界面上显示的占位名「群聊」）参与匹配，与行上显示一致。
NSArray<IMGroupInfo *> *IMScopedGroupHits(NSArray<IMGroupInfo *> *_Nullable groups, NSString *_Nullable keyword,
                                          NSString *fallbackName);

NS_ASSUME_NONNULL_END
