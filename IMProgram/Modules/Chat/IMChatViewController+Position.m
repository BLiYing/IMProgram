//  IMChatViewController+Position.m
//  聊天页「进会话定位 + 可见即读上报」分文件实现（CHAT_UX §3/§6）：首条未读定位、进场一次性锚定/贴底、
//  行锚到视口顶（抵消自适应估高偏差）、可见行已读扫描与节流上报。从 IMChatViewController.m 平移，未改行为。

#import "IMChatViewController+Private.h"  // 含 IMSocketManager（markReadConv）
#import "IMMessageModel.h"
#import "IMChatMessageLogic.h"            // IMContentTypeCountsAsUnread（未读口径，与服务端一致）
#import "IMDatabase.h"
#import "IMLog.h"

@implementation IMChatViewController (Position)

/// 首条未读所在行：conv_seq > entryReadSeq 的第一条「对端」消息；无未读返回 -1。
/// **必须与服务端未读口径一致**（M4-8）：服务端 unreadCount 排除 msg_op 事件行与 system 系统消息，
/// 这里若只按 `from != 我` 找，会把分割线/进会话锚点定位到不计未读的系统行——
/// 表现为「以下为 N 条新消息」下方实际多出几行（群改名/入群留痕都会触发）。
- (NSInteger)firstUnreadRow {
    if (self.entryUnread <= 0) { return -1; }
    for (NSInteger i = 0; i < (NSInteger)self.messages.count; i++) {
        IMMessageModel *m = self.messages[i];
        if (m.convSeq <= self.entryReadSeq) { continue; }
        if ([m.from isEqualToString:self.userID]) { continue; }
        if (IMContentTypeCountsAsUnread(m.contentType)) { return i; }
    }
    return -1;
}

/// 进会话定位（只做一次）：有未读则停在首条未读，否则到底（CHAT_UX §3）。
- (void)positionInitialIfNeeded {
    if (self.didInitialPosition || self.messages.count == 0) { return; }
    self.didInitialPosition = YES;
    NSInteger unreadRow = [self firstUnreadRow];
    if (unreadRow >= 0) {
        [self anchorRowToTop:unreadRow];
    } else {
        // 无未读：估高会让 scrollToRow…Bottom 欠滚（stop 在真正底部之上）→ 用强制布局后的精确贴底。
        [self scrollToAbsoluteBottom];
    }
    IMLogDebugWithTag(IMLogTagUI, @"chat_initial_position conv_id=%@ rows=%lu unread_row=%ld offset_y=%.1f content_h=%.1f viewport_h=%.1f",
                      self.convID, (unsigned long)self.messages.count, (long)unreadRow,
                      self.tableView.contentOffset.y, self.tableView.contentSize.height,
                      self.tableView.bounds.size.height);
    // 定位后下一轮 runloop（自适应高度落定）再兜一次：无未读精确贴底；有未读重锚首条未读
    //（估高偏差会让锚点漂移——未读只剩末尾几条时表现为"停在底部之上一截"，模拟器日志
    //  chat_initial_position 09:41:02 实锤：偏差 350pt）。之后推进已读/刷新 ↓N。
    dispatch_async(dispatch_get_main_queue(), ^{
        if (unreadRow < 0) { [self scrollToAbsoluteBottom]; }
        else { [self anchorRowToTop:unreadRow]; }
        [self markVisibleRowsRead];
    });
}

/// 把某行锚到视口顶（进会话停首条未读用）：scrollToRow 触发目标区域真实布局后再对齐一轮，
/// 抵消估高偏差；行靠近末尾时 scrollToRow 自带底部 clamp——未读不足一屏时锚定即等价于贴底。
- (void)anchorRowToTop:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.messages.count) { return; }
    NSIndexPath *ip = [NSIndexPath indexPathForRow:row inSection:0];
    for (int pass = 0; pass < 2; pass++) {
        [self.tableView scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionTop animated:NO];
        [self.tableView layoutIfNeeded];
    }
}

/// 可见即读（CHAT_UX §6 完整语义）：扫描当前在视口内的行，取其最大 conv_seq；
/// 若超过已滚入位点则记录并节流上报（read_seq 单调推进，对端据此显示已读双勾、列表未读递减）。
- (void)markVisibleRowsRead {
    int64_t maxSeq = 0;
    for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
        if (ip.row < (NSInteger)self.messages.count) {
            int64_t s = self.messages[ip.row].convSeq;
            if (s > maxSeq) { maxSeq = s; }
        }
    }
    if (maxSeq > self.pendingReadSeq) {
        self.pendingReadSeq = maxSeq;
        // 节流：滚动停 0.3s 后才真正发，避免每像素一条 receipt。
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flushReadPosition) object:nil];
        [self performSelector:@selector(flushReadPosition) withObject:nil afterDelay:0.3];
    }
    [self updateJumpButton]; // 位点推进/新消息后刷新 ↓N 计数
}

/// 把节流累积的已读位点上报（仅在超过上次上报值时发）。
- (void)flushReadPosition {
    if (self.pendingReadSeq > self.maxReadReported) {
        self.maxReadReported = self.pendingReadSeq;
        [self performDatabaseOperation:^(IMDatabase *database) {
            [database markConversation:self.convID readUpToConvSeq:self.maxReadReported];
        }];
        [IMSocketManager.sharedManager markReadConv:self.convID upToConvSeq:self.maxReadReported];
    }
}

@end
