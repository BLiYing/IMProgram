//  IMChatViewController+Presence.m
//  聊天页「对端在线态」分文件实现（仅单聊）：30s 周期定时重算副标题（服务端不推下线帧，靠本地租约到期
//  体现离线，须自己叫醒）、订阅/退订对端 watch、拉取在线态快照。从 IMChatViewController.m 平移，未改行为。

#import "IMChatViewController+Private.h"  // 含 IMSocketManager / IMPresence
#import "IMHTTPService.h"
#import "IMUserCard.h"

@implementation IMChatViewController (Presence)

/// 在线态定时重算（仅单聊、仅页面可见期间）。
///
/// 必要性：服务端**不推下线帧**，对端离线是靠本地租约到期体现的——而"租约到期"是纯粹的时间流逝，
/// 不触发任何回调。若不自己叫醒，用户停在本页不动时副标题会永远停在「在线」（比有下线帧时更糟）。
/// 取 30s 周期而非"在 onlineUntil 时刻排一次性 timer"，是因为降档后的「N 分钟前在线」同样需要随时间推进，
/// 一次性 timer 只能修在线→离线那一跳，之后分钟数就冻住。
- (void)startPresenceTick {
    [self stopPresenceTick];
    if (self.isGroupChat) { return; } // 群聊副标题是成员数，不随时间变
    __weak typeof(self) weakSelf = self;
    __block NSInteger ticks = 0;
    self.presenceTickTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 repeats:YES block:^(NSTimer *timer) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { [timer invalidate]; return; }
        [self updateTitle];
        // 每 4 个 tick（2 分钟）在对端不在线时重拉一次快照：单聊 topic 随首条消息才建立，
        // 故「好友但从没聊过」的对端不在 broadcastOnline 的收件人集合里，他上线时我收不到 presence 帧。
        // 租约模型只会让状态降级，没有任何东西能把它升回「在线」——不轮询就永远显示离线。
        if (++ticks % 4 == 0 && !self.peerPresence.isOnline) {
            [self refreshPeerPresence];
        }
    }];
}

/// 停止定时重算（离开页面时必须调用：NSTimer 强引用 block，不停会连着 VC 一起活到 timer 失效）。
- (void)stopPresenceTick {
    [self.presenceTickTimer invalidate];
    self.presenceTickTimer = nil;
}

/// 订阅/退订对端在线态（仅单聊）。watch=YES 关注对端（服务端只推它、并回一帧快照）；NO 清空关注。
/// 全量替换语义，重复发送幂等；连上前发送会被 writeData 静默丢弃，故须在 didChangeState 连上时重发。
- (void)updatePeerWatch:(BOOL)watch {
    if (self.isGroupChat || self.peerID.length == 0) { return; }
    [IMSocketManager.sharedManager watchUsers:(watch ? @[self.peerID] : @[])];
}

/// 拉取对端在线态快照（单聊才有）。失败静默：在线态是锦上添花，不该弹错打扰聊天。
- (void)refreshPeerPresence {
    if (self.isGroupChat || self.peerID.length == 0) { return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService userProfileWithToken:token userID:self.peerID completion:^(IMUserCard *card, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !card) { return; }
        self.peerPresence = card.presence;
        [self updateTitle];
    }];
}

@end
