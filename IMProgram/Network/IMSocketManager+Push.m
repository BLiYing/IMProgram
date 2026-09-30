//  IMSocketManager+Push.m

#import "IMSocketManager+Push.h"
#import "IMSocketManager+Private.h"
#import "IMProtocol.h"
#import "IMLog.h"

NSNotificationName const IMSocketDidReceiveNotifySettingsUpdateNotification = @"IMSocketDidReceiveNotifySettingsUpdateNotification";

@implementation IMSocketManager (Push)

- (void)noteAppDidEnterBackground {
    dispatch_async(_queue, ^{
        self->_appActive = NO;
        if (self.state == IMSocketStateConnected) {
            [self sendEnvelopeType:kIMTypeAppState data:@{ @"state": @"background" } completion:nil];
        }
    });
}

- (void)noteAppDidBecomeActive {
    dispatch_async(_queue, ^{
        self->_appActive = YES;
        [self sendAppStateAfterHandshake];
    });
}

#pragma mark - 主实现调用（仅在 _queue 调用）

/// 握手成功后按 App 当前真实前后台补报一次（PROTOCOL §6.12）。**后台里重连也要报 background**：
/// 服务端新连接默认 foreground，切后台后网络抖一下、在后台自动重连成功，不报的话服务端就一直当它在前台、
/// 不给这台设备推送，而 App 其实已被挂起——那段时间来的消息谁也不提醒（M5 批 1 /code-review）。
- (void)sendAppStateAfterHandshake {
    if (self.state != IMSocketStateConnected) { return; }
    NSString *state = self->_appActive ? @"foreground" : @"background";
    [self sendEnvelopeType:kIMTypeAppState data:@{ @"state": state } completion:nil];
}

- (void)handleAdditionalFrameType:(NSString *)type payload:(NSDictionary *)payload {
    if ([type isEqualToString:kIMTypeNotifySettingsUpdate]) {
        // 账号级通知设置版本变更（M5）：只广播，IMAccountNotifySettingsSync 据此按版本判断是否重拉。
        int64_t version = [payload[@"version"] longLongValue];
        IMLogSocket(@"notify_settings_update_received version=%lld", version);
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:IMSocketDidReceiveNotifySettingsUpdateNotification
                                                              object:self userInfo:@{ @"version": @(version) }];
        });
    } else {
        IMLogSocket(@"未处理类型: %@", type);
    }
}

@end
