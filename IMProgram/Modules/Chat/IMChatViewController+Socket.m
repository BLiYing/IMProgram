//  IMChatViewController+Socket.m
//  聊天页「IMSocketManagerDelegate 主线程回调」分文件实现：连接态变化、收到消息/回执/在线态/typing 帧
//  → 更新内存模型、落库去重、驱动标题与列表。从 IMChatViewController.m 平移，未改行为。

#import "IMChatViewController+Private.h"
#import "IMMessageModel.h"
#import "IMDatabase.h"
#import "IMReadReceiptViewController.h"

@implementation IMChatViewController (Socket)

#pragma mark - IMSocketManagerDelegate（主线程回调）

- (void)socketManager:(IMSocketManager *)manager didChangeState:(IMSocketState)state {
    BOOL justConnected = (state == IMSocketStateConnected && self.connState != IMSocketStateConnected);
    self.connState = state;
    [self updateTitle];
    if (justConnected) {
        // 连上即补拉在线态快照，覆盖三种情况：①冷启动直接进本页时 currentToken 还是空的，
        // viewWillAppear 里那次拉取被静默跳过且无人重试；②断线期间对端状态已变，本地快照过期；
        // ③服务端重连竞态可能短暂把在线用户报成离线，重拉即纠正。
        [self refreshPeerPresence];
        [self updatePeerWatch:YES]; // watch 是连接级易失态：重连后必须重发，否则对端上线不再推达
    }
    if (state == IMSocketStateConnected) {
        [self markVisibleRowsRead]; // 重连后把当前可见的补报一次已读（可见即读）
    }
}

/// 标题：单聊=对方昵称（缺省回退 uid）；群聊=群名。连接态不再拼进标题后缀，统一走副标题（见 im_navigationSubtitle）。
/// 昵称随 caller 播种/复用重播种刷新（对齐会话列表/通讯录的 pull 口径，对齐 Web 显示昵称）；页内无 live 服务端刷新。
- (void)updateTitle {
    if (self.isGroupChat) {
        self.title = self.groupName.length > 0 ? self.groupName : @"群聊";
    } else {
        self.title = self.peerNickname.length ? self.peerNickname : self.peerID;
    }
    [self refreshUnifiedNavigationBar];
}

- (BOOL)im_isGroupChat { return self.isGroupChat; }

- (NSString *)im_navigationSubtitle {
    if (self.peerTyping) {
        return @"正在输入";
    }
    // 连接态优先：断开 / 连接中时副标题显示连接状态（同「在线」位置，无括号），
    // 覆盖单聊在线态与群聊成员数——此时本地在线快照无法再更新，显示连接态才是可验证的状态。
    NSString *conn = IMSocketStateSubtitle(self.connState);
    if (conn.length > 0) { return conn; }
    if (!self.isGroupChat) {
        // 单聊：在线态走副标题（原先的 🟢 已去掉）。
        return self.peerPresence.subtitleText ?: @"";
    }
    NSUInteger count = self.groupInfo.members.count;
    return count > 0 ? [NSString stringWithFormat:@"%lu 位成员", (unsigned long)count] : @"";
}

/// 消息排序（**唯一入口**，与 IMDatabase.messagesForConv 的 ORDER BY 及 im-web 的渲染排序三方一致）：
/// **时间戳主排**；同一毫秒时 conv_seq=0（待发/失败）视为最大值垫底，收到的（conv_seq>0）在前。
///
/// ⚠️ 曾出过的坑（2026-08-05）：这里原先与 DB 一样按 conv_seq 主排、且把 conv_seq=0 一律甩末尾。
/// 被拒收的消息**永远** conv_seq=0，于是永久钉在最底部，之后收到的消息全插到它上面 —— 用户滚到底
/// 只见旧的失败消息、以为新消息没收到。第一次进会话走 DB（当时已修）看着正常，Web 一发消息触发本
/// comparator 重排，时序又坏 —— **同一个 bug 在 DB 与内存两处各写了一遍**，故收敛到这一个方法。
- (void)sortMessagesInPlace {
    [self.messages sortUsingComparator:^NSComparisonResult(IMMessageModel *a, IMMessageModel *b) {
        if (a.timestamp != b.timestamp) {
            return a.timestamp < b.timestamp ? NSOrderedAscending : NSOrderedDescending;
        }
        // 同毫秒：conv_seq=0 视为 +∞ 垫底（等价 im-web 的 `convSeq || MAX_SAFE_INTEGER`）。
        int64_t sa = a.convSeq > 0 ? a.convSeq : INT64_MAX;
        int64_t sb = b.convSeq > 0 ? b.convSeq : INT64_MAX;
        if (sa == sb) { return NSOrderedSame; }
        return sa < sb ? NSOrderedAscending : NSOrderedDescending;
    }];
}

- (void)socketManager:(IMSocketManager *)manager didReceiveMessage:(IMMessageModel *)message {
    if (![self performDatabaseOperation:^(IMDatabase *database) {
        [database saveMessage:message]; // 任何会话的消息都落库（按 conv_seq 幂等）
    }]) { return; }
    if (![message.convID isEqualToString:self.convID]) { return; } // 非本会话不在此页显示
    // 同一条消息可能既被 new_msg 推送、又被 sync_resp 拉到，按 conv_seq 去重。
    if (message.convSeq > 0) {
        NSNumber *key = @(message.convSeq);
        if ([self.seenConvSeqs containsObject:key]) {
            // 完整历史校正会再次下发已经实时上屏的消息。不能重复插入，但要让权威元数据回填当前内存模型；
            // 否则 SQLite 已从 0 修复成真实 file_size，当前页面仍会一直显示 0 KB，直到重新进入会话。
            if ([message.contentType isEqualToString:@"file"] && message.fileSize > 0) {
                for (IMMessageModel *existing in self.messages) {
                    if (existing.convSeq != message.convSeq) { continue; }
                    existing.fileSize = message.fileSize;
                    if (message.fileName.length > 0) { existing.fileName = message.fileName; }
                    if (message.serverMsgID.length > 0) { existing.serverMsgID = message.serverMsgID; }
                    [self.tableView reloadData];
                    break;
                }
            }
            return;
        }
        [self.seenConvSeqs addObject:key];
    }
    // 收到新消息：贴底才自动贴底；在上方看历史则不打断，累加到"↓N"（CHAT_UX §9）。
    BOOL wasNearBottom = [self isNearBottom];
    // 绝大多数消息按序到达：直接尾插即保持有序，省掉每条都做的 O(n log n) 全量重排。
    // 仅当来的消息落在末条之前（乱序/补拉插队）才重排一次——判定口径与 sortMessagesInPlace 的
    // comparator 严格一致（timestamp 主序，同毫秒时 conv_seq=0 视为 +∞ 垫底）。
    IMMessageModel *lastMsg = self.messages.lastObject;
    BOOL needsSort = NO;
    if (lastMsg) {
        if (message.timestamp < lastMsg.timestamp) {
            needsSort = YES;
        } else if (message.timestamp == lastMsg.timestamp) {
            int64_t sNew = message.convSeq > 0 ? message.convSeq : INT64_MAX;
            int64_t sLast = lastMsg.convSeq > 0 ? lastMsg.convSeq : INT64_MAX;
            needsSort = sNew < sLast;
        }
    }
    [self.messages addObject:message];
    if (needsSort) { [self sortMessagesInPlace]; }
    [self.tableView reloadData];
    // 冷启动直进本页时 init 读库可能为空（账号数据库上下文未就绪），历史全靠 sync 事后补进——
    // 而 reloadData 不触发 VC 的 viewDidLayoutSubviews，进会话定位永远不会跑（模拟器日志实锤：
    // 该场景整个会话周期零 chat_initial_position）。首条消息落地时在此补一次定位。
    if (!self.didInitialPosition) {
        [self positionInitialIfNeeded];
        return; // positionInitialIfNeeded 内已含精确贴底/锚定 + markVisibleRowsRead
    }
    if (wasNearBottom) { [self scrollToBottomAnimated:YES]; }
    // 可见即读 + ↓N 刷新：贴底时新消息进视口即标已读；在上方看历史则不读、↓N 计数 +1（markVisibleRowsRead 内重算）。
    [self markVisibleRowsRead];
}

/// 对端已读到 upToConvSeq → 记录并刷新（已送达 → 已读）。
- (void)socketManager:(IMSocketManager *)manager didReadConv:(NSString *)convID by:(NSString *)from upToConvSeq:(int64_t)convSeq {
    if (![convID isEqualToString:self.convID] || [from isEqualToString:self.userID]) { return; }
    // 群聊：单个 peerReadSeq 无法表达「谁读到哪」，任一成员已读都推进会让所有人消息误显 ✓✓（已读）。
    // 群的已读语义走 IMReadReceiptViewController 的逐成员列表，气泡尾巴只保留 ✓（已送达）。
    if (self.isGroupChat) { return; }
    if (convSeq > self.peerReadSeq) {
        self.peerReadSeq = convSeq;
        [self.tableView reloadData];
    }
}

/// 对端正在输入 → 标题栏副标题暂显「正在输入」，3s 后恢复在线态/成员数。
- (void)socketManager:(IMSocketManager *)manager didTypingInConv:(NSString *)convID by:(NSString *)from {
    if (![convID isEqualToString:self.convID] || [from isEqualToString:self.userID]) { return; }
    self.peerTyping = YES;
    [self updateTitle];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideTyping) object:nil];
    [self performSelector:@selector(hideTyping) withObject:nil afterDelay:3.0];
}

- (void)hideTyping {
    self.peerTyping = NO;
    [self updateTitle];
}

/// 对端上线 → 更新副标题。（服务端不推下线：租约到期后 subtitleText 自动降级。）
- (void)socketManager:(IMSocketManager *)manager didChangePresenceForUser:(NSString *)user presence:(IMPresence *)presence {
    if (![user isEqualToString:self.peerID]) { return; }
    self.peerPresence = presence;
    [self updateTitle];
}

@end
