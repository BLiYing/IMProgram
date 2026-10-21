//  IMAutoDeleteScheduler.h
//  自动删除消息的清理调度（AUTO_DELETE_DESIGN §3.2）：
//  设置变更 / 入库后 / 启动·回前台 / 前台每 30 秒 → 合并去抖（NSObject+IMCoalescedPerform）→ 后台串行队列清理本地库
//  → 主线程发 IMSocketDidRemoveMessageNotification（聊天页气泡、会话列表预览/未读、置顶横幅、媒体库、详情页签都已订阅它）。
//  后台不扫（无后台任务），回前台补扫。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 前台常驻扫描间隔（秒）。
FOUNDATION_EXPORT const NSTimeInterval IMAutoDeleteSweepInterval;

@interface IMAutoDeleteScheduler : NSObject

+ (instancetype)shared;

/// 幂等：挂 30 秒计时器与回前台监听，并立即请求一次全量扫描（启动补扫）。
- (void)start;

/// 请求清理一个会话；nil = 所有有档位的会话。0.25s 内多次请求合并为一次。主线程调用。
- (void)requestSweepForConv:(nullable NSString *)convID;

/// 同步执行一次（单测 / 调用方已在后台）：返回按会话分组被删掉的 conv_seq；不发通知。
- (NSDictionary<NSString *, NSArray<NSNumber *> *> *)sweepConvs:(nullable NSArray<NSString *> *)convIDs nowMs:(int64_t)nowMs;

@end

NS_ASSUME_NONNULL_END
