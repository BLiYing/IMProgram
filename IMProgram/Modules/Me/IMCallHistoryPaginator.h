//  IMCallHistoryPaginator.h
//  「最近通话」页的翻页 + 筛选状态机，与网络/UI 解耦（注入 fetcher block，可用假数据单测，不用起模拟器）。
//  设计：IMServer docs/design/CALL_HISTORY_DESIGN.md §3/§3.5。
//
//  两个视图（全部 / 未接）共用同一份已加载数据（`allRecords`），筛选只是换一个纯函数谓词，不是两套请求状态机。
//  「未接」视图的翻页是**自动连续**的：过滤后新增数量不够 `minVisible` 就接着请求下一页，直到凑够或到底。
//  `reload`（首次进页 / callEnd 刷新）用一个自增 generation 标记作废在途的旧翻页请求，参考 IMRtcCall 已有的
//  同一套防护思路（`_generation` / `gen != self->_generation` 即丢弃）。

#import <Foundation/Foundation.h>
#import "IMCallHistoryRecord.h"

NS_ASSUME_NONNULL_BEGIN

/// 拉一页数据：`cursor` 为 nil 表示首页；返回本页记录 + 下一页游标（nil = 到底）。
/// `cursor`/`nextCursor` 刻意用不透明的 `id`（SDK 实际游标是 `Int64`/`NSNumber`，不是字符串）——
/// 本类只透传，从不解析它的内容，换成任何可判空等值的类型都不用改这层。
typedef void (^IMCallHistoryFetchCompletion)(NSArray<IMCallHistoryRecord *> *_Nullable records,
                                              id _Nullable nextCursor, NSError *_Nullable error);
typedef void (^IMCallHistoryFetchBlock)(id _Nullable cursor, NSInteger limit,
                                        IMCallHistoryFetchCompletion completion);

@interface IMCallHistoryPaginator : NSObject

- (instancetype)initWithSelfUID:(NSString *)selfUID pageSize:(NSInteger)pageSize fetcher:(IMCallHistoryFetchBlock)fetcher;

/// 迄今已加载的全部记录（未筛选，倒序）。
@property (nonatomic, readonly, copy) NSArray<IMCallHistoryRecord *> *allRecords;
/// 服务端已到底（`nextCursor == nil`）。
@property (nonatomic, readonly, assign) BOOL reachedEnd;
/// 是否有翻页/刷新请求在途。
@property (nonatomic, readonly, assign) BOOL loading;
/// 当前筛选（切换本身是纯状态变更，不发请求；若切到「未接」后已加载数据不够，调用方自行接着调 loadMore）。
@property (nonatomic, assign) IMCallHistoryFilter filter;

/// 当前筛选下的可见记录（对 `allRecords` 应用 `filter`）。
- (NSArray<IMCallHistoryRecord *> *)filteredRecords;

/// 首次进页 / `callEnd` 刷新：作废在途旧请求（generation++），清空已加载数据，重新拉首页。
/// `minVisible`：筛选后至少要凑够这么多条才停（仅在 `filter==Missed` 时生效；`All` 视图只拉一页）。
- (void)reloadWithMinVisible:(NSInteger)minVisible completion:(nullable void (^)(NSError *_Nullable error))completion;

/// 上拉加载下一页；语义同 `reloadWithMinVisible:completion:`，但在已有数据后追加而非清空。
/// `nextCursor == nil`（已到底）或已有翻页在途时是空操作，直接回调 nil error。
- (void)loadMoreWithMinVisible:(NSInteger)minVisible completion:(nullable void (^)(NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
