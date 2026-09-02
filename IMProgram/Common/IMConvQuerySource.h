//  IMConvQuerySource.h
//  「整会话问题」问谁：本地 / 服务端 / 本地但降级（IMServer/docs/design/OFFLINE_BACKLOG_DESIGN.md §4.9）。
//
//  与 im-web 的 `src/convQuerySource.ts` **同一份口径**。这是整套方案里唯一需要三端完全一致的
//  判断，所以抽成一个纯函数 + 单测钉死，而不是在每个功能点各写一遍 if：
//  写错的后果不是崩溃，是**答案悄悄不对**——大群里搜不到缺口里的消息、日历那些天全灰，
//  而界面一切正常、不报任何错。
//
//  判据只有两个输入：本地这个会话齐不齐（区间清单覆盖到 head 没有）、现在能不能上网。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMConvQuerySource) {
    IMConvQuerySourceLocal = 0,     ///< 本地齐全 → 本地（秒回、离线可用，与改造前完全一样）
    IMConvQuerySourceServer,        ///< 有缺口 + 在线 → 服务端（权威、完整）
    IMConvQuerySourceLocalDegraded, ///< 有缺口 + 离线 → 本地，但**必须告诉用户**只看了已下载的部分
};

/// @param complete 本地是否齐全（`[IMDatabase isConvComplete:]`）
/// @param online   当前是否在线
extern IMConvQuerySource IMPickConvQuerySource(BOOL complete, BOOL online);

/// 降级提示文案（三端同源；与 im-web 的 convQuerySource.ts 逐字一致，
/// 避免同一处境两副说辞——那会让用户以为是两个不同的问题）。
extern NSString * const IMDegradedSearchNotice;
extern NSString * const IMDegradedCalendarNotice;
extern NSString * const IMNeedNetworkNotice;

NS_ASSUME_NONNULL_END
