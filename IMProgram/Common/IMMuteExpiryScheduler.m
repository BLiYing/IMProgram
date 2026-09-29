//  IMMuteExpiryScheduler.m

#import "IMMuteExpiryScheduler.h"
#import "IMConversation.h"
#import "IMTimeUtil.h"

NSNotificationName const IMMuteExpiryDidChangeNotification = @"IMMuteExpiryDidChangeNotification";

@implementation IMMuteExpiryScheduler {
    NSTimer *_timer;
    int64_t _scheduledForMs; // 0 = 当前没有排期
}

+ (instancetype)shared {
    static IMMuteExpiryScheduler *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [IMMuteExpiryScheduler new]; });
    return instance;
}

- (void)rescheduleWithConversations:(NSArray<IMConversation *> *)conversations {
    int64_t now = IMNowMillis();
    int64_t nearest = 0;
    for (IMConversation *c in conversations) {
        if (!c.muted || c.muteUntil <= 0) { continue; } // 永久（0）与未免打扰都不需要定时器
        if (c.muteUntil <= now) { continue; } // 已过期：下次任意一次刷新会自然收敛，不必单独排期
        if (nearest == 0 || c.muteUntil < nearest) { nearest = c.muteUntil; }
    }
    if (nearest == 0) { [self cancelTimer]; return; }
    if (_timer.isValid && _scheduledForMs == nearest) { return; } // 已排在同一时刻，避免抖动重排
    [self cancelTimer];
    _scheduledForMs = nearest;
    NSTimeInterval delay = MAX(0.05, (NSTimeInterval)(nearest - now) / 1000.0);
    __weak typeof(self) ws = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:delay repeats:NO block:^(NSTimer *t) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        self->_scheduledForMs = 0;
        [NSNotificationCenter.defaultCenter postNotificationName:IMMuteExpiryDidChangeNotification object:nil];
    }];
}

- (void)cancelTimer {
    [_timer invalidate];
    _timer = nil;
    _scheduledForMs = 0;
}

@end
