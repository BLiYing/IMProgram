//  IMSocketManager+ConvClear.h
//  「删除会话」＝ 清空聊天记录 + 隐藏会话（OFFLINE_BACKLOG_DESIGN §6.7.1）的统一「清除到位点」例程。
//  三个触发点共用同一个入口：本机删除成功 / 别的设备 conv_update(delete) / 会话列表快照 cleared_at 追平。

#import "IMSocketManager.h"
#import "IMConversation.h"

@class IMDatabase;

NS_ASSUME_NONNULL_BEGIN

@interface IMSocketManager (ConvClear)

/// 清该会话消息 + 区间清单 + 写位点（= max(本机既有位点, serverClearedAt)；serverClearedAt<=0 取本机所知最新）+ 推游标，
/// 并丢网络层缓存的服务端下界（`IMBacklogTracker._historyFloor`）。返回写入后的位点。
/// 在 `performDatabaseOperation:` 块内调用（传块里的 database）。**须先于 `deleteCachedConversation:`**（要读会话行里的 head）。
- (int64_t)clearConvToFloor:(NSString *)convID serverClearedAt:(int64_t)serverClearedAt database:(IMDatabase *)database;

/// 收到 `conv_update(action=delete)`（别的设备删的）：帧里 `cleared_at` 走同一例程，再删会话行。返回账号上下文是否仍有效。
- (BOOL)applyConvDeleteFrame:(NSDictionary *)data convID:(NSString *)convID;

/// 会话列表快照对齐：某项 `clearedAt` > 本机位点时跑同一例程（离线设备 / 旧版本残留 / 重装）。返回触发的会话数。
- (NSUInteger)alignClearFloorsFromConversations:(NSArray<IMConversation *> *)conversations database:(IMDatabase *)database;

@end

NS_ASSUME_NONNULL_END
