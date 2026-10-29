//  IMHTTPService+ClearAll.h
//  清除所有对话 REST（PROTOCOL §6.8；设计 CLEAR_ALL_CONVERSATIONS_DESIGN §3）。completion 回主线程。

#import "IMHTTPService.h"
#import "IMClearAll.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMHTTPService (ClearAll)

/// POST /api/v1/users/me/conversations/clear（无 body，Bearer）。成功回 {cleared, items}；
/// 限流 100002 / 网络 / 回包不是对象 → error（调用方不得动本机）。
- (void)clearAllConversationsWithToken:(NSString *)token
                            completion:(void (^)(IMClearAllResult *_Nullable result, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
