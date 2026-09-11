//  IMChatSearchPaging.h
//  会话内搜索「服务端命中翻页」的判据（IMServer/docs/design/OFFLINE_BACKLOG_DESIGN.md §4.9 第 1 项的后半）。
//
//  与 im-web 的 `src/searchPaging.ts` **同一份口径**（IMServer/docs/SYMMETRY.md 有登记）。
//  抽成纯函数的理由同 IMChatWindowPlan：**判错了不会报错**——
//  服务端按 conv_seq **倒序**一页页给（cursor 往回走），命中集却按**升序**用（下标 0 = 最早，▲ = 更旧），
//  「再要一页」拿回来的是更旧的一批，要拼到**前面**，当前下标随之整体后移。算错了界面照常，
//  只是 ▲ 一下跳到了别的命中上，或者计数虚涨。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 一次 ▲ 里连续遇到「空页但仍 has_more」时最多再往前翻几页。
/// 服务端先取 limit+1 条再按「仅为我删除」等逐人隐藏过滤，隐藏项多时一页可能一条不剩
/// （IMServer `internal/conversation/search.go` 的 searchPage 注释）。不设上限的话，
/// 满屏隐藏项的会话会把一次点击变成无界请求。与 im-web `MAX_EMPTY_PAGES` 同值。
extern const NSInteger IMChatSearchMaxEmptyPages;

/**
 把更旧的一页并到升序命中集前面。

 @param currentAscending 当前命中集（升序）。
 @param page             服务端这一页的命中 conv_seq，顺序不限。
 @param outAdded         真正新增的条数（去重后）。调用方把下标落到 `added - 1`——
                         也就是紧挨着原来最旧命中的上一条。
 @return 新命中集（升序）。只收比当前最旧命中**还旧**的项：防重复页 / 游标回退把已有命中再塞一遍。
 */
extern NSArray<NSNumber *> *IMChatSearchPrependOlderHits(NSArray<NSNumber *> *currentAscending,
                                                         NSArray<NSNumber *> *page,
                                                         NSInteger *outAdded);

/// ▲（更旧）此刻能不能点：不在最旧命中上；或在最旧命中上、但服务端还有更早的页且没有一次在途。
/// 在途时灰掉，防连点发出多份同样的请求。
extern BOOL IMChatSearchCanGoOlder(NSInteger hitIndex, NSInteger hitCount, BOOL hasMorePages, BOOL loadingOlder);

NS_ASSUME_NONNULL_END
