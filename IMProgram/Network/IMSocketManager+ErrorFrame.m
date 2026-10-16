//  IMSocketManager+ErrorFrame.m
//  `error` 帧分派（PROTOCOL §8）。从 IMSocketManager.m 拆出：主文件已满行，本段又新增了注销踢下线分支。
//  声明见 IMSocketManager+Private.h。

#import "IMSocketManager+Private.h"
#import "IMLog.h"

NSString * const IMSocketDidReceiveAccountDeletedNotification = @"IMSocketDidReceiveAccountDeletedNotification";

@implementation IMSocketManager (ErrorFrame)

/// 仅在 _queue 调用。三类：① reason=account_deleted（连接级，本账号在别处被注销）；② 带 client_msg_id 的消息操作 / 发送拒绝；
/// ③ 其余连接级错误只记日志。
- (void)handleErrorFrame:(NSDictionary *)payload {
    if ([payload[@"reason"] isEqual:@"account_deleted"]) {
        // 服务端紧接着会断开连接：先置 _manualClose，避免退避重连去撞 401 再走一遍「续期 → 被踢」；
        // 上层收到通知后清聊天缓存（普通被踢保留缓存，注销踢不保留）并回登录页。
        IMLogSocket(@"account_deleted_frame_received");
        _manualClose = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:IMSocketDidReceiveAccountDeletedNotification object:self];
        });
        return;
    }
    NSString *cmid = [payload[@"client_msg_id"] isKindOfClass:[NSString class]] ? payload[@"client_msg_id"] : nil;
    // 消息操作被拒（如撤回超时 300008）：不动消息，主线程广播回滚提示。
    if (cmid.length > 0 && [_pendingOps containsObject:cmid]) {
        [_pendingOps removeObject:cmid];
        NSString *msg = [payload[@"message"] isKindOfClass:[NSString class]] ? payload[@"message"] : IMLocalized(@"common.action_failed");
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:IMSocketDidRejectMsgOpNotification
                                                              object:self userInfo:@{ @"message": msg }];
        });
    } else if (cmid.length > 0) {
        // 带 client_msg_id 的 error = 对某条 send_msg 的拒绝（如被拉黑、对方已注销 300003）→ 立刻判该条发送失败。
        [self handleSendRejected:cmid code:[payload[@"code"] integerValue] message:payload[@"message"]];
    } else {
        IMLogSocket(@"服务端 error: %@", payload);
    }
}

@end
