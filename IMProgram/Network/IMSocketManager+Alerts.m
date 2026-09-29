//  IMSocketManager+Alerts.m
//  通知与提示音（NOTIFICATIONS_DESIGN §3）：实时入站消息到达后判要不要响/振。
//  拆成独立分文件 category 的原因是体量门禁——IMSocketManager.m 已挂账 1600 行上限
//  （CODING_STYLE §7②：一组内聚方法 → 分文件 category），方法声明见 IMSocketManager+Private.h。
//
//  调用点在 IMSocketManager.m 的 processIncomingMessage: 内、dispatch_async(main) 块中，
//  且仅在 !fromSync（真正的实时 new_msg，不含 sync_resp / window_resp）时调用——
//  历史回填/离线积压/窗口加载一律不判，否则打开一个有几十条积压的会话会被当场弹一串提醒
//  （D4 桌面端早年踩过同一个坑，见 DESKTOP_DESIGN.md）。

#import "IMSocketManager+Private.h"
#import <UIKit/UIKit.h>      // UIApplication.applicationState（ctx.appActive）
#import "IMAlertDecision.h"
#import "IMAlertPlayer.h"
#import "IMNotificationSettings.h"
#import "IMChatPresence.h"   // ctx.viewingConv 的单一来源
#import "IMCallRecord.h"     // isCallRecord/missedCallForMe 判定
#import "IMRtcCall.h"        // ctx.inCall
#import "IMMessageModel.h"
#import "IMConversation.h"
#import "IMTimeUtil.h"

@implementation IMSocketManager (Alerts)

/// 拼出 IMAlertContext 交给纯函数 IMAlertDecide，中标就调 IMAlertPlayer。只在主线程调用。
- (void)maybeAlertForIncomingMessage:(IMMessageModel *)msg {
    NSString *selfUID = self.userID;
    if (msg.convID.length == 0 || selfUID.length == 0) { return; }

    // 会话是私聊/群聊、是否免打扰：查本地会话摘要缓存（权威来源，服务端已同步过来）；
    // 极端情况下（全新会话的第一条消息，摘要尚未落地）查不到，按 convID 前缀兜底判类型、muted 默认 NO
    // （查不到即从未设置过免打扰，默认值本来就是 NO，不算猜）。
    __block IMConversation *conv = nil;
    [self performDatabaseOperation:^(IMDatabase *database) {
        for (IMConversation *c in database.cachedConversations) {
            if ([c.convID isEqualToString:msg.convID]) { conv = c; break; }
        }
    }];
    BOOL isGroup = conv ? conv.isGroup : [msg.convID hasPrefix:@"g_"];

    BOOL isCallRecord = [msg.contentType isEqualToString:IMContentTypeCall];
    BOOL missedCallForMe = NO;
    if (isCallRecord) {
        // 按通话记录渲染规则的 tone 判（三端同口径：Web isMissedCall / Android isMissedPreview，
        // 向量在 IMServer docs/conformance/call_record.json）。**不用**「时长为 0」粗判：
        // 被叫侧 hangup d=0 渲染为「通话未接通」、tone=normal，不该响。本路径只见别人发的消息，故 viewerIsSender=NO。
        missedCallForMe = ![msg.from isEqualToString:selfUID]
            && IMCallRecordRender(msg.content, NO, isGroup, nil).tone == IMCallRecordToneMissed;
    }

    IMAlertContext *ctx = [IMAlertContext new];
    ctx.platform = IMAlertPlatformMobile;
    ctx.isLive = YES; // 本方法只在实时路径调用（见调用点的 !fromSync 守卫）
    ctx.isSelf = msg.from.length > 0 && [msg.from isEqualToString:selfUID];
    ctx.isSystem = [msg.contentType isEqualToString:@"system"];
    ctx.isRecalled = msg.recalledAt > 0;
    ctx.isCallRecord = isCallRecord;
    ctx.missedCallForMe = missedCallForMe;
    ctx.convType = isGroup ? IMAlertConvTypeGroup : IMAlertConvTypePrivate;
    ctx.muted = conv.muted;
    ctx.mentionsMe = msg.mentionAll || (msg.mentions.count > 0 && [msg.mentions containsObject:selfUID]);
    ctx.appActive = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    ctx.windowFocused = ctx.appActive; // 移动端无独立窗口焦点概念；判据仅在 platform=desktop 时读这个字段
    ctx.viewingConv = msg.convID.length > 0 && [msg.convID isEqualToString:IMChatPresence.currentViewingConvID];
    ctx.inCall = IMRtcCall.shared.isStarted;
    ctx.nowMs = IMNowMillis();
    ctx.lastSoundAtMs = IMAlertPlayer.shared.lastSoundAtMs;
    ctx.settings = IMNotificationSettings.shared.alertSnapshot;

    IMAlertResult *result = IMAlertDecide(ctx);
    if (result.sound && result.soundId.length > 0) { [IMAlertPlayer.shared playSoundNamed:result.soundId]; }
    if (result.vibrate) { [IMAlertPlayer.shared vibrate]; }
}

@end
