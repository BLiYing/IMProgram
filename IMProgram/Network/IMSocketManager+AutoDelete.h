//  IMSocketManager+AutoDelete.h
//  conv_update{action:settings} 里的 auto_delete_sec 落库 + 触发清理（AUTO_DELETE_DESIGN §3.2/§3.4）。
//  独立 category：IMSocketManager.m 已挂账 1600 行上限（只准降不准升）。

#import "IMSocketManager.h"
#import "IMDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMSocketManager (AutoDelete)

/// 在 performDatabaseOperation 块内调用：data 带 auto_delete_sec + auto_delete_from（完整状态，成对覆盖）才处理；
/// sec 或 from 变了且 sec>0 才请求清理该会话（重复帧幂等；不追溯，from 之前的消息不会被清）。
- (void)applyAutoDeleteFromConvUpdate:(NSDictionary *)data convID:(NSString *)convID database:(IMDatabase *)database;

@end

NS_ASSUME_NONNULL_END
