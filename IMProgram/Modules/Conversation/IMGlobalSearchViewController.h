//  IMGlobalSearchViewController.h
//  首页全局搜索（搜索功能 P0，纯本地）：三分组结果——会话/群（标题）、联系人（好友）、聊天记录（本地 DB）。
//  从会话列表顶部搜索栏进入。点会话→打开；点联系人→单聊；点聊天记录→打开该会话并进「会话内搜索」预填同词。
//  设计见 docs/design/SEARCH_DESIGN.md §3。

#import <UIKit/UIKit.h>
#import "IMScopedSearch.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMGlobalSearchViewController : UIViewController
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;
/// 搜索范围：由底部 tab 容器按「从哪个 tab 点进搜索」设置（消息=全局；通讯录=联系人+群聊；我=设置项）。变更时清空关键词与结果。
@property (nonatomic, assign) IMSearchScope scope;
/// 「我」范围的数据源 / 命中后跳转（由 tab 容器接到「我」页；本页不持有它）。
@property (nonatomic, copy, nullable) NSArray<IMSettingsSearchEntry *> *(^settingsEntriesProvider)(void);
@property (nonatomic, copy, nullable) void (^settingsEntryOpener)(NSString *rowId);
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)n bundle:(nullable NSBundle *)b NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
