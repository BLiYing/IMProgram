//  IMHTTPService+ConvQueries.h
//  「关于整个会话」的服务端查询（IMServer/docs/design/OFFLINE_BACKLOG_DESIGN.md §4.9）。
//
//  它们回答的都是**整会话**问题：这个词一共出现在哪些消息里、哪几天有消息。
//  离线积压被留成缺口后，本地库只有其中几段，继续用本地算会得到一个"看起来正常、其实残缺"的
//  答案——大群里搜不到缺口里的消息、日历那些天全灰，而且**不报错**。那是最难发现的一类错。
//
//  **不是**要取代本地：本地齐全时仍走本地（秒回、离线可用），只有有缺口且在线时才问服务端。
//  分流判据收在 IMConvQuerySource.h 的 `IMPickConvQuerySource`（与 im-web 同一份口径）。
//
//  对端实现：IMServer/cmd/imserver/handlers_backlog.go、handlers_conversation.go；
//  Web 侧对应 im-web/src/sdk/convQueriesApi.ts。

#import "IMHTTPService.h"

NS_ASSUME_NONNULL_BEGIN

/// 日历里的一天。
@interface IMConvCalendarDay : NSObject
@property (nonatomic, assign) int64_t dayStartMs;   ///< 当天 00:00 的毫秒时间戳（按客户端传的时区切）
@property (nonatomic, assign) NSInteger count;      ///< 当天消息条数
@property (nonatomic, assign) int64_t firstConvSeq; ///< 当天第一条：点这一天就拿它当锚点开窗
@end

@interface IMHTTPService (ConvQueries)

/// 会话内检索（服务端权威）。
///
/// `fromUID` 非空时叠加「来自某人」过滤——本地有缺口时这一筛也必须由服务端给，
/// 否则缺口里那些人的消息会静默漏掉。cursor=0 表示从最新开始，按 conv_seq 倒序。
/// 回调给的是**命中的 conv_seq（升序）**：调用方只需要位点，正文本地有或按需开窗取。
- (void)searchConvMessagesWithToken:(NSString *)token
                             convID:(NSString *)convID
                            keyword:(NSString *)keyword
                            fromUID:(nullable NSString *)fromUID
                              limit:(NSInteger)limit
                         completion:(void (^)(NSArray<NSNumber *> *convSeqsAscending,
                                              BOOL hasMore,
                                              NSError *_Nullable error))completion;

/// 日历按天聚合。
///
/// **必须给 from/to**（服务端有跨度上限）：客户端按可见月份问，不设区间等于一次请求扫完整个会话，
/// 正是本设计通篇在避免的。utcOffsetMs 用本机时区——切天必须按用户所在时区，否则整张日历错位一格。
- (void)convCalendarWithToken:(NSString *)token
                       convID:(NSString *)convID
                       fromMs:(int64_t)fromMs
                         toMs:(int64_t)toMs
                  utcOffsetMs:(int64_t)utcOffsetMs
                   completion:(void (^)(NSArray<IMConvCalendarDay *> *days,
                                        NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
