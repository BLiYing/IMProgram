//
//  IMChatViewController+Resend.m
//  发送失败重发（微信式：气泡左侧红❗，点一下就重发；不进长按菜单，避免两个入口）。
//
//  两类失败**不能同一条路**，判据单一来源是 `IMResendPolicyForMessage`（IMChatMessageLogic）：
//   - 上传失败：服务器上根本没有这条（content 仍是 im-pending:// 本地引用）→ 从本地副本重传，
//     换新 client_msg_id 不会重复；
//   - send_msg 失败（ack 超时 / 连接中断）：内容已就绪 → **按原 client_msg_id 重发**，
//     靠服务端 (conv_id, client_msg_id) 幂等去重。换新 ID 会在"上次其实已存下、只是 ack 丢了"时
//     让对端收到两条——这是本功能最容易写错的一处。
//
//  被服务端明确拒收的（拉黑/禁言/非好友/内容过大）不给重发入口：原样再发必然再次被拒，
//  它们的恢复入口是气泡下方那行系统行（如 200103 → 发好友申请）。
//

#import "IMChatViewController+Private.h"
#import "IMChatViewController+Voice.h"   // im_resendVoiceMessage:（语音不走 IMMediaSendService，见下）
#import "IMChatMessageLogic.h"
#import "IMMessageModel.h"
#import "IMDatabase.h"
#import "IMSocketManager.h"
#import "UIViewController+IMToast.h"

@implementation IMChatViewController (Resend)

- (void)im_resendMessage:(IMMessageModel *)message {
    if (!message) { return; }
    // 相册宫格整组共用一个红❗（哪一格失败由格内 "!" 表达）→ 点一次重发组里所有失败成员，
    // 否则用户得逐格去点、而宫格外侧压根没有逐格入口。
    if (message.groupID.length > 0) {
        // 快照一份再遍历：重发路径会就地改 self.messages（语音那条会删旧行重建），边遍历边改要崩。
        for (IMMessageModel *m in [[self albumMembersForGroupID:message.groupID] copy]) {
            [self im_resendSingleMessage:m];
        }
        return;
    }
    [self im_resendSingleMessage:message];
}

- (void)im_resendSingleMessage:(IMMessageModel *)m {
    switch (IMResendPolicyForMessage(m, [m.from isEqualToString:self.userID])) {
        case IMResendPolicyNone:
            return;   // 红❗此时本就不可点，走到这里只可能是并发改了状态
        case IMResendPolicyRetryUpload:
            // 语音上传不走 IMMediaSendService 常驻队列（VC 内手工链，见 +Voice.m 注释），单列一条路。
            if ([m.contentType isEqualToString:@"voice"]) { [self im_resendVoiceMessage:m]; return; }
            [self retryPendingMessage:m];
            return;
        case IMResendPolicySameID:
            [self im_resendWithOriginalClientMsgID:m];
            return;
    }
}

/// send_msg 失败那类：内容已就绪（正文或已上传的服务器 URL），按**原 client_msg_id** 再发一次。
- (void)im_resendWithOriginalClientMsgID:(IMMessageModel *)m {
    NSString *clientMsgID = m.clientMsgID;
    __weak typeof(self) ws = self;
    BOOL queued = [IMSocketManager.sharedManager resendMessage:m
                                                        toUser:(self.isGroupChat ? @"" : self.peerID)
                                                    completion:^(BOOL success, NSError *error, int64_t convSeq) {
        // 与首发同一个收口：状态/conv_seq/被拒文案/落库/贴底全在里面，别在这里再写一份。
        [ws handleSendResult:success convSeq:convSeq error:error forClientMsgID:clientMsgID];
    }];
    if (!queued) { [self im_showToast:@"这条消息内容已丢失，无法重发"]; return; }

    // 入队成功才转「发送中…」：红❗随之消失，给出点击反馈（不然 5s ack 超时窗内像点了没反应）。
    // completion 不可能在此之前跑完（socket 内部 dispatch_async 到自己的串行队列、再回主线程），故顺序安全。
    // note/noteCode 必须一并清掉，否则上一轮失败的系统行会挂在这一轮的重试上。
    m.status = IMMessageStatusSending;
    m.note = nil;
    m.noteCode = 0;
    [self performDatabaseOperation:^(IMDatabase *database) {
        [database saveMessage:m]; // 按 clientMsgID upsert：failed → sending
    }];
    [self refreshVisibleCellForMessage:m];
}

@end
