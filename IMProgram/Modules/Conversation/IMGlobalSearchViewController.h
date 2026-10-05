//  IMGlobalSearchViewController.h
//  首页全局搜索（纯本地）：会话/群（标题）→ 联系人（好友）→ 聊天记录（本地 DB）→ 设置 → 搜索用户。
//  从会话列表顶部搜索栏进入（scope=Messages）；通讯录页顶搜索框也 push 本页（scope=Contacts，只出联系人+群聊）。
//  点会话→打开；点联系人→单聊；点聊天记录→定位到命中；点设置项→切到「我」tab 逐级打开（IMSettingsSearchRegistry）。
//  设计见 docs/design/SEARCH_DESIGN.md §3。

#import <UIKit/UIKit.h>
#import "IMScopedSearch.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMGlobalSearchViewController : UIViewController
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;
/// 搜索范围：消息页进来=全局（默认，含「设置」分组）；通讯录页进来=联系人+群聊。须在页面出现前设置。
@property (nonatomic, assign) IMSearchScope scope;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)n bundle:(nullable NSBundle *)b NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
