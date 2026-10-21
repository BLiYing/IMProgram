//  IMSocketManager+AutoDelete.h
//  conv_update{action:settings} 里的 auto_delete_sec 落库 + 触发清理（AUTO_DELETE_DESIGN §3.2/§3.4）。
//  独立 category：IMSocketManager.m 已挂账 1600 行上限（只准降不准升）。

#import "IMSocketManager.h"
#import "IMDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMSocketManager (AutoDelete)

/// 在 performDatabaseOperation 块内调用：data 带 auto_delete_sec（完整状态，直接覆盖）才处理；
/// 档位 > 0 就请求清理该会话（变短 / 由关变开 / 重复帧都幂等）。
- (void)applyAutoDeleteFromConvUpdate:(NSDictionary *)data convID:(NSString *)convID database:(IMDatabase *)database;

@end

NS_ASSUME_NONNULL_END
