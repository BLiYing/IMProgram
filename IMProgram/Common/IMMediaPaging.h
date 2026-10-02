//  IMMediaPaging.h
//  会话媒体「服务端续拉」的纯判据（OFFLINE_BACKLOG_DESIGN §4.9 第 5 项）。对称 Android `MediaTimeline.prependOlder`
//  + `ConvQueryFloor.media`、Web `convQueriesApi.ts` 的 `fetchConvMedia`。
//
//  服务端按 conv_seq **倒序**给（cursor = 上页最后一条，之后只会更旧），时间线按**升序**用（下标 0 = 最旧）。
//  拼错的表现是翻页时跳到别的图上，或同一张出现两次，界面照常不报错——所以抽成纯函数单测。

#import <Foundation/Foundation.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

/**
 把更旧的一页并到升序时间线前面。
 @param currentAscending 当前时间线（升序）。
 @param page             服务端一页（顺序不限）。
 @param clearedUpTo      本机清空位点（§6.7）：`convSeq <= 它` 的丢掉；0 = 不设。
 @param outAdded         真正新增的条数——调用方据此把正在看的下标后移 `added`。
 @return 新时间线（升序）。只收比当前最旧一条**还旧**的、去重的、非撤回的项。
 */
extern NSArray<IMMessageModel *> *IMMediaPagingPrependOlder(NSArray<IMMessageModel *> *currentAscending,
                                                            NSArray<IMMessageModel *> *page,
                                                            int64_t clearedUpTo,
                                                            NSInteger *_Nullable outAdded);

/// 服务端还能不能翻出位点之上的东西：游标落到 `位点 + 1` 及以下时剩下的全在位点以内，别再翻（防清空过的大会话空翻一串页）。
extern BOOL IMMediaPagingHasMore(BOOL hasMore, int64_t nextCursor, int64_t clearedUpTo);

NS_ASSUME_NONNULL_END
