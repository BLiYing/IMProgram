//  IMMediaServerTimeline.h
//  会话媒体时间线的「服务端续拉」持有者（OFFLINE_BACKLOG_DESIGN §4.9 第 5 项）：本地打底（可为空）+ 往更旧翻页。
//
//  本地有缺口且在线时，媒体库 / 查看器「前后没别的图了」是假的——缺口里的图本地没有。
//  这时时间线由本对象持有：先放本地打底（升序），到头了向服务端 `GET /conversations/{id}/media` 要更旧的一页并拼到前面。
//  拼接规则在纯函数 `IMMediaPagingPrependOlder`；本类只管游标 / 在途守卫 / 空页上限。
//  主线程使用（回调也回主线程）。

#import <Foundation/Foundation.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMMediaServerTimeline : NSObject

/// 当前时间线（升序，下标 0 = 最旧）。
@property (nonatomic, readonly) NSArray<IMMessageModel *> *messages;
/// 服务端是否还有更旧的页（已过滤清空位点）。
@property (nonatomic, readonly) BOOL hasMore;
/// 有一次续拉在途（防连点 / 连续滚动发多份同样的请求）。
@property (nonatomic, readonly) BOOL loading;

- (instancetype)initWithConvID:(NSString *)convID kind:(NSString *)kind clearedUpTo:(int64_t)clearedUpTo;

/// 放本地打底（升序）。`hasMore`=NO 表示本地已握着可见起点，不必问服务端。
/// 游标取打底里最旧一条（服务端严格更旧于它，不会重复给回来）；打底为空则从最新一页起。
- (void)seedWithMessages:(NSArray<IMMessageModel *> *)ascending hasMore:(BOOL)hasMore;

/// 取更旧的一页并拼到前面。`added` = 真正新增条数；失败时 `error` 非空且 `hasMore` 置 NO（离线降级，调用方给提示）。
/// 服务端回空页却仍 has_more（逐人隐藏过滤）时接着往前翻，最多 `IMMediaServerTimelineMaxEmptyPages` 页。
- (void)loadOlder:(void (^)(NSInteger added, NSError *_Nullable error))completion;

/// 某些消息被物理移除（为所有人删除 / 仅为我删除）后同步剔除，别让下次重派生把它们带回来。
- (void)removeMessagesWithConvSeqs:(NSSet<NSNumber *> *)seqs;

@end

extern const NSInteger IMMediaServerTimelineMaxEmptyPages;

NS_ASSUME_NONNULL_END
