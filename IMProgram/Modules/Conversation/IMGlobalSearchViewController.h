//  IMGlobalSearchViewController.h
//  首页全局搜索（搜索功能 P0，纯本地）：三分组结果——会话/群（标题）、联系人（好友）、聊天记录（本地 DB）。
//  从会话列表顶部搜索栏进入。点会话→打开；点联系人→单聊；点聊天记录→打开该会话并进「会话内搜索」预填同词。
//  设计见 docs/SEARCH_DESIGN.md §3。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMGlobalSearchViewController : UIViewController
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)n bundle:(nullable NSBundle *)b NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
