//  IMConversationListViewController.h
//  会话列表：登录后首页。拉 GET /api/v1/conversations，点进入聊天页。

#import <UIKit/UIKit.h>

@class IMConversation, IMDatabaseAccountContext;

NS_ASSUME_NONNULL_BEGIN

/// 会话列表的本地种子：context 这一代账号的本地会话快照（离线首屏）；context 为 nil / 已失效返回空数组。
/// 会话列表页 init 与通讯录首页「最近联系」的兜底（会话列表还没广播过时）共用这一份读取。
FOUNDATION_EXPORT NSArray<IMConversation *> *IMCachedConversationListSeed(IMDatabaseAccountContext *_Nullable context);

@interface IMConversationListViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
