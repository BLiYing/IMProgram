//  IMChatViewController+SendService.m
//  聊天页「常驻发送服务通知」分文件实现：与 IMMediaSendService 常驻发件箱对账（进度/元数据/派发/失败/
//  ACK/取消）、msg_op 应用（撤回·编辑·置顶）与消息移除、外观实时切换、返回按钮全局未读徽标节流刷新。
//  由主实现 viewDidLoad 用 @selector 接线（观察者身份仍是 VC）。从 IMChatViewController.m 平移，未改行为。

#import "IMChatViewController+Private.h"  // 含 IMSocketManager.h（kIMConvIDKey / kIMMsgOp* 键）
#import "IMMediaSendService.h"            // kIMMediaSend* 通知键
#import "IMMessageModel.h"
#import "IMPinnedMessage.h"
#import "IMChatBackgroundView.h"
#import "IMDatabase.h"
#import "IMMainTabBarController.h"        // im_setBackBadgeCount
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import "IMAppearance.h"

@implementation IMChatViewController (SendService)

#pragma mark - 常驻发送服务通知

/// 用户取消发送：服务已删库行与本地副本，本页移除这行气泡。
- (void)onMediaSendCancelled:(NSNotification *)note {
    if (![self mediaSendNoteIsMine:note]) { return; }
    NSString *key = note.userInfo[kIMMediaSendClientMsgIDKey];
    IMMessageModel *mine = [self messageForClientMsgID:key];
    if (!mine) { return; }
    [self.windowState.messages removeObjectIdenticalTo:mine];
    [self.tableView reloadData];
}

/// userInfo 里的 convID 是否本会话。
- (BOOL)mediaSendNoteIsMine:(NSNotification *)note {
    return [note.userInfo[kIMMediaSendConvIDKey] isEqualToString:self.convID];
}

/// 按 clientMsgID 找本页消息模型（服务实例与本页实例可能不是同一个对象——重进会话后本页持有的是
/// 从库里读出的副本）。
- (IMMessageModel *)messageForClientMsgID:(NSString *)clientMsgID {
    if (clientMsgID.length == 0) { return nil; }
    for (IMMessageModel *m in self.windowState.messages) {
        if ([m.clientMsgID isEqualToString:clientMsgID]) { return m; }
    }
    return nil;
}

- (void)onMediaSendProgress:(NSNotification *)note {
    if (![self mediaSendNoteIsMine:note]) { return; }
    IMMessageModel *m = [self messageForClientMsgID:note.userInfo[kIMMediaSendClientMsgIDKey]];
    if (!m) { return; }
    if ([m.contentType isEqualToString:@"file"]) {
        // 文件气泡：圆环/状态行/文案随 configure 一次性布好，整行重渲染。
        // reload 若引起行高微变（如状态行出现/消失）会把底部顶走——原本贴底则重新贴底
        //（与 MetaChanged/Ack 回调对称；已精确贴底时 scrollToAbsoluteBottom 首轮即返回，无额外开销）。
        BOOL wasNearBottom = [self isNearBottom];
        [self refreshVisibleCellForMessage:m];
        if (wasNearBottom) { [self scrollToAbsoluteBottom]; }
    } else {
        [self updateUploadProgressForMessage:m]; // 只改覆盖层/环 strokeEnd，不 reload（无闪烁）
    }
}

/// 元数据/缩略图就绪：气泡从方形占位切到真实比例，行高变化后若原本贴底则重新贴底
/// （否则内容会被顶出屏幕，看起来像"列表突然滚动了一下"）。
- (void)onMediaSendMetaChanged:(NSNotification *)note {
    if (![self mediaSendNoteIsMine:note]) { return; }
    IMMessageModel *m = [self messageForClientMsgID:note.userInfo[kIMMediaSendClientMsgIDKey]];
    if (!m) { return; }
    BOOL wasNearBottom = [self isNearBottom];
    [self refreshVisibleCellForMessage:m];
    [self refreshRowHeightsWithoutAnimation];
    if (wasNearBottom) { [self scrollToAbsoluteBottom]; }
}

/// 上传完成、消息已发出、库里已换真实 ID：把本页模型同步过去（若持有的是旧副本）。
- (void)onMediaSendDispatched:(NSNotification *)note {
    if (![self mediaSendNoteIsMine:note]) { return; }
    IMMessageModel *serviceModel = note.userInfo[kIMMediaSendMessageKey];
    NSString *oldKey = note.userInfo[kIMMediaSendOldClientMsgIDKey];
    IMMessageModel *mine = [self messageForClientMsgID:oldKey] ?: [self messageForClientMsgID:serviceModel.clientMsgID];
    if (!mine) { return; }
    if (mine != serviceModel) {
        // 本页持有库副本：用服务实例整体替换（后续 ack/刷新都以它为准），避免两份模型漂移。
        NSUInteger idx = [self.windowState.messages indexOfObjectIdenticalTo:mine];
        if (idx != NSNotFound) { [self.windowState.messages replaceObjectAtIndex:idx withObject:serviceModel]; }
    }
    // 上传完成瞬间气泡内容切换（文件行状态区收敛、媒体角标变化）可能微调行高：原本贴底则重新贴底。
    BOOL wasNearBottom = [self isNearBottom];
    [self refreshVisibleCellForMessage:serviceModel];
    if (wasNearBottom) { [self scrollToAbsoluteBottom]; }
}

- (void)onMediaSendFailed:(NSNotification *)note {
    if (![self mediaSendNoteIsMine:note]) { return; }
    IMMessageModel *m = [self messageForClientMsgID:note.userInfo[kIMMediaSendClientMsgIDKey]];
    if (!m) { return; }
    m.status = IMMessageStatusFailed; // 服务实例已置位；本页若持有库副本在此对齐
    [self updateUploadProgressForMessage:m];
    [self refreshVisibleCellForMessage:m];
    [self im_showToast:@"发送失败，点击可重试"];
}

/// 服务端 ack（状态/conv_seq/note 已由服务落库）：只更新内存模型与界面。
- (void)onMediaSendAck:(NSNotification *)note {
    if (![self mediaSendNoteIsMine:note]) { return; }
    IMMessageModel *serviceModel = note.userInfo[kIMMediaSendMessageKey];
    IMMessageModel *mine = [self messageForClientMsgID:serviceModel.clientMsgID];
    if (!mine) { return; }
    BOOL wasNearBottom = [self isNearBottom];
    if (mine != serviceModel) {
        mine.status = serviceModel.status;
        mine.convSeq = serviceModel.convSeq;
        mine.note = serviceModel.note;
        mine.noteCode = serviceModel.noteCode; // 随 note 一起拷：决定系统行给不给恢复入口（200103 → 发好友申请）
    }
    if (mine.convSeq > 0) { [self.windowState.seenConvSeqs addObject:@(mine.convSeq)]; } // 防 sync 重复回显自己发的
    // 相册成员的 ACK 只定点刷宫格角标/状态胶囊；但**被拒收挂了系统行时行高会变**，
    // 定点刷新不重算高度（系统行会被裁掉），必须整表 reload 走下面的分支。
    if (mine.groupID.length > 0 && mine.note.length == 0) {
        [self refreshVisibleCellForMessage:mine];
        return;
    }
    [self.tableView reloadData];
    if (wasNearBottom) { [self scrollToBottomAnimated:YES]; } // 被拒收挂系统行后仍贴底可见
}

/// 会话历史被清空（资料页操作）：本会话则清空内存消息 + 刷新表。
- (void)onConversationCleared:(NSNotification *)note {
    if (![note.userInfo[kIMConvIDKey] isEqualToString:self.convID]) { return; }
    [self.windowState.messages removeAllObjects];
    [self.windowState.seenConvSeqs removeAllObjects];
    // 清空后窗口回到"空的最新一窗"：不复位的话，若清空前正停在历史，windowAtTail 会一直是 NO，
    // 之后新收的消息会被当作"用户在看历史"而不上屏。
    self.windowState.atTail = YES;
    self.windowState.hasMoreAbove = NO;
    [self.tableView reloadData];
}

/// 外观设置实时生效：刷新壁纸、消息 Cell、输入框与当前主题色，不需要重新进入聊天。
- (void)appearanceChanged {
    self.view.tintColor = IMTheme.accent;
    self.inputBar.backgroundColor = IMTheme.surface;
    self.inputField.backgroundColor = IMTheme.pageBackground;
    self.inputField.font = [UIFont systemFontOfSize:MAX(15, IMTheme.chatFontSize - 1)];
    self.inputField.layer.cornerRadius = IMAppearance.shared.bubbleRadius;
    self.inputField.layer.borderColor =
        [IMTheme.separator resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    if ([self.tableView.backgroundView isKindOfClass:IMChatBackgroundView.class]) {
        [(IMChatBackgroundView *)self.tableView.backgroundView refreshAppearance];
    }
    [self.tableView reloadData];
}

/// 消息操作应用到某条消息：本会话则就地更新内存模型 + 刷新（撤回→墓碑，编辑→改文本）。
- (void)onMsgOpApplied:(NSNotification *)note {
    NSString *convID = note.userInfo[kIMConvIDKey];
    if (![convID isEqualToString:self.convID]) { return; }
    int64_t target = [note.userInfo[kIMMsgOpTargetSeqKey] longLongValue];
    // 契约（IMSocketManager.h）：socket 层已解析并落库，这里逐字段采用**与库一致的终值**——
    // 不再解读 op/pinned 协议细节（曾两处解析各带相反默认），也不再自造时间戳（曾与库值偏差，
    // 重进会话后撤回/置顶时刻跳变）。
    NSNumber *recalledAt = note.userInfo[kIMMsgOpRecalledAtKey];
    NSNumber *editedAt   = note.userInfo[kIMMsgOpEditedAtKey];
    NSNumber *pinnedAt   = note.userInfo[kIMMsgOpPinnedAtKey];
    // 撤回会把气泡替换为墓碑行（高度骤减，最后一条为图片/视频时缩水几百 pt）——需在 reload 前
    // 记住是否贴底，reload 后强制精确贴底，否则 contentOffset 会被 UIKit clamp 向上跳一段
    // （露出白底 + 一次视觉抖动）。仅撤回路径需要，编辑/置顶行高变化可忽略。
    BOOL wasNearBottomForRecall = (recalledAt != nil) && [self isNearBottom];
    for (IMMessageModel *m in self.windowState.messages) {
        if (m.convSeq != target) { continue; }
        if (recalledAt) {
            m.recalledAt = recalledAt.longLongValue;
            m.recalledBy = note.userInfo[kIMMsgOpRecalledByKey];
        }
        if (editedAt) {
            m.editedAt = editedAt.longLongValue;
            NSString *newContent = note.userInfo[kIMMsgOpContentKey];
            if (newContent) { m.content = newContent; }
        }
        if (pinnedAt) { m.pinnedAt = pinnedAt.longLongValue; } // 0=取消置顶
        break;
    }
    [self.tableView reloadData];
    if (wasNearBottomForRecall) { [self scrollToAbsoluteBottom]; } // animated:NO，无闪
    // 横幅刷新：pin/unpin 必刷；撤回/编辑若命中横幅里的置顶项也要刷——服务端置顶列表已剔除
    // 撤回消息、编辑改文案，不刷会留一条指向墓碑/旧文案的横幅（delete 路径同理已无条件刷）。
    BOOL touchesPinnedBanner = NO;
    if (recalledAt || editedAt) {
        for (IMPinnedMessage *p in self.bannerStack.pinnedItems) {
            if (p.convSeq == target) { touchesPinnedBanner = YES; break; }
        }
    }
    // 撤回命中横幅：**先本地剔除再重拉**。reloadPinnedBanner 是 best-effort（拉失败保留旧集合），
    // 只靠它收敛的话弱网下横幅会继续挂着一条已撤回消息的预览文案——显示态本身就该在这里收敛，
    // 网络重拉退回成"与服务端对齐"的补充。（jumpToPinnedConvSeq: 的提示是兜底，不是主路径。）
    if (recalledAt && touchesPinnedBanner) {
        NSMutableArray<IMPinnedMessage *> *kept = [NSMutableArray arrayWithCapacity:self.bannerStack.pinnedItems.count];
        for (IMPinnedMessage *p in self.bannerStack.pinnedItems) {
            if (p.convSeq != target) { [kept addObject:p]; }
        }
        self.bannerStack.pinnedItems = kept; // setter 内部夹紧轮转索引 + 重新应用横幅
    }
    if (pinnedAt || touchesPinnedBanner) { [self reloadPinnedBanner]; }
}

/// 我方发起的操作被拒（如撤回超时）：吐司提示（不改消息）。
- (void)onMsgOpRejected:(NSNotification *)note {
    NSString *msg = note.userInfo[@"message"];
    [self im_showToast:msg.length > 0 ? msg : @"操作失败"];
}

/// 任务2：某条消息被物理移除（为所有人删除 / 仅为我删除）→ 本会话则从消息列表删掉并刷新。
- (void)onMessageRemoved:(NSNotification *)note {
    NSString *convID = note.userInfo[kIMConvIDKey];
    if (![convID isEqualToString:self.convID]) { return; }
    int64_t target = [note.userInfo[kIMMsgOpTargetSeqKey] longLongValue];
    if (target <= 0) { return; }
    NSUInteger idx = NSNotFound;
    for (NSUInteger i = 0; i < self.windowState.messages.count; i++) {
        if (self.windowState.messages[i].convSeq == target) { idx = i; break; }
    }
    if (idx == NSNotFound) { return; }
    [self.windowState.messages removeObjectAtIndex:idx];
    [self.tableView reloadData];
    [self reloadPinnedBanner]; // 删掉的可能正是一条置顶消息，别让横幅指向已消失的消息
}

/// 合并刷新入口：消息/已读通知成批到达时，每 0.12s 至多刷一次徽标（避免每条一次全表 SUM）。
/// 刻意用「在途标记 + dispatch_after + weak」而非 cancel+performSelector 重排——后者有三个坑：
/// ① trailing-edge 重排在持续消息流（同步补拉逐条发通知、间隔 <0.12s）下整段饿死不刷新；
/// ② performSelector:afterDelay: 只挂 NSDefaultRunLoopMode，滚动期间不触发；
/// ③ 它 retain target，pending 期间 dealloc 根本不会执行，"dealloc cancel 兜底"是伪命题。
/// 本实现 pending 期间新通知直接返回（leading-window，burst 中仍按节拍刷新）；weak 捕获下
/// 页面 pop 后定时器触发即 no-op，不续命 VC。
- (void)scheduleBackUnreadBadgeRefresh {
    if (self.backBadgeRefreshPending) { return; }
    self.backBadgeRefreshPending = YES;
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        self.backBadgeRefreshPending = NO;
        [self refreshBackUnreadBadge];
    });
}

/// 任务2：刷新返回按钮的全局未读总数徽标（各会话 unread 之和，排除当前会话，微信式）。
- (void)refreshBackUnreadBadge {
    __block NSInteger total = 0;
    [self performDatabaseOperation:^(IMDatabase *database) {
        total = [database totalUnreadExcludingConv:self.convID];
    }];
    [self im_setBackBadgeCount:total];
}

@end
