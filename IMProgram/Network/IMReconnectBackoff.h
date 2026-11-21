//  IMReconnectBackoff.h
//  WS 断线重连的等待时长：指数退避 + ±20% 随机抖动（横向扩容决策：客户端只改重连抖动）。
//  服务端重启时所有在线客户端同一刻断开，没有抖动就会在 1s / 2s / 4s… 同一刻一起涌回来。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// attempt 从 0 起；base / cap 秒；rand01 ∈ [0, 1]（单测注入，线上传随机数）。
/// 结果 = min(cap, base·2^attempt) × (0.8 + 0.4·rand01)，至少 0.1 秒。
FOUNDATION_EXPORT NSTimeInterval IMReconnectDelay(NSInteger attempt, NSTimeInterval base, NSTimeInterval cap, double rand01);

NS_ASSUME_NONNULL_END
