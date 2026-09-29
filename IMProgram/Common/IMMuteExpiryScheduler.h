//  IMMuteExpiryScheduler.h
//  定时免打扰到期刷新（NOTIFICATIONS_P1_DESIGN §4.4）：按本机会话缓存里「最近的一个未到期 mute_until」
//  挂一个一次性定时器，到点广播通知——会话列表铃铛/未读变灰、Tab 未读角标、例外列表据此重绘。
//  到期**不需要**发任何请求：服务端同一时刻自然也按"已过期"返回，本调度器只是让本地提前显示对。
//  对端 Android 已有在线态到期降档的同类定时器；Web 同理另写。

#import <Foundation/Foundation.h>

@class IMConversation;

NS_ASSUME_NONNULL_BEGIN

/// 到点广播（主线程）。监听方各自决定怎么刷：会话列表 reloadData + refreshListIndicators，
/// 例外列表 reloadExceptions + reloadData——数据本身没变（服务端 muted/mute_until 仍是旧值），
/// 变的只是"现在几点"，故不需要重新拉取，纯本地重算 IMIsMutedNow 即可。
FOUNDATION_EXPORT NSNotificationName const IMMuteExpiryDidChangeNotification;

@interface IMMuteExpiryScheduler : NSObject

+ (instancetype)shared;

/// 按当前账号的会话集合重新计算「最近一个未到期 mute_until」并重排定时器（幂等：排在同一时刻不重排）。
/// 调用时机：会话列表每次刷新（reload / refreshLocalConversations，收在 setConversations: 这一个咽喉）、
/// App 回到前台（后台期间 NSTimer 可能没跑，§4.4 明确要求）。
- (void)rescheduleWithConversations:(NSArray<IMConversation *> *)conversations;

/// 测试/账号切换用：清掉当前定时器。
- (void)cancelTimer;

@end

NS_ASSUME_NONNULL_END
