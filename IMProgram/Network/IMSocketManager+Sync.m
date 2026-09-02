#import "IMSocketManager+Private.h"
#import "IMDatabase+Ranges.h"   // saveIncomingPage:advanceTo:rangeLo:rangeHi:（整页原子落库 + 区间登记）
#import "IMMessageModel.h"
#import "IMProtocol.h"
#import "IMLog.h"

// 离线补拉（sync_resp 的处理）。从 IMSocketManager.m 拆出，理由见 IMSocketManager+Private.h 头注释：
// 与实时投递互为补充但机制完全不同，且在超级群下正文全靠这条链（IMServer 侧同样把 sync.go
// 从 hub.go 拆了出来，两端沿同一条缝切，改动时容易对照）。

@implementation IMSocketManager (Sync)

/// 处理 sync_resp：按会话投递增量消息，并据服务端权威 covered_conv_seq 推进游标；has_more 时以新位点继续拉。
/// 仅在 _queue 调用。
///
/// 死循环修复（2026-08-13）：服务端为做**按用户可见性过滤**（G2 history_visible 抬入群下界、「仅为我删除」
/// 隐藏项）会在 conv_seq 序列里留下客户端永远拿不到的空洞。老逻辑只按「连续」推进，游标会永久卡在空洞前一位，
/// 每 10s 空转重拉同一页（真机曾连刷一天多）。中间态：本页消息全部落库成功后，把游标直接推进到服务端断言
/// 的 covered_conv_seq——它保证 (since, covered] 内每个序号要么已下发、要么对本人不可见。
///
/// 丢消息事务原子性修复（2026-08-25）：老逻辑「消息事务」与「游标事务」分成**两次**提交——中间进程被杀
/// （sync burst 期间用户杀 App、系统 OOM、切账号），会出现「消息 A 事务已 commit 但 WAL 未 checkpoint
/// 就丢，而游标事务后写入并保住」→ 游标越过 A，A 永久漏（真机 seq=416 案例复现）。改为**逐条**原子提交
/// 游标：`saveIncomingMessage:advancingSyncedConvSeq:` 把消息行与游标推进合到同一 `inTransaction:` 里，
/// 一条消息事务失败 → 游标绝不越过它。页尾若 `covered > 最后一条 seq`（服务端可见性空洞），再补一次
/// `advanceSyncedConvSeqForConv:covered` 单事务，把空洞跨过——首条失败后 syncAdvanceSeq 传 0，
/// 后续消息事务照落但不再动游标，游标停在最后成功一条上，靠 backoff 重拉。事务数不变（仍是每条一事务），
/// 只是每事务多一次 im_conversation_local 主键 UPDATE，纳秒级。
- (void)handleSyncResp:(NSDictionary *)data {
    NSArray *convs = [data[@"conversations"] isKindOfClass:[NSArray class]] ? data[@"conversations"] : @[];
    for (NSDictionary *conv in convs) {
        if (![conv isKindOfClass:[NSDictionary class]]) { continue; }
        NSString *convID = conv[@"conv_id"];
        if (convID.length == 0) { continue; }
        [_syncingConvs removeObject:convID];
        // head：服务端会话真实最新位点（仅在游标带了 max_gap 时下发）。落内存 + 落库，
        // ↓N 计数与「本地齐不齐」都用它，不数本地（OFFLINE_BACKLOG_DESIGN §4.4）。
        int64_t head = [conv[@"head_conv_seq"] longLongValue];
        if (head > 0) {
            [_backlog noteHead:head forConv:convID];
            [self performDatabaseOperation:^(IMDatabase *database) {
                [database updateHeadConvSeq:head forConv:convID];
            }];
        }
        // 积压超过 max_gap：服务端一条正文都没给，只告诉我们"最新到哪了"。
        // **绝不推游标、绝不登记区间**——没下载就不许宣称拿到。那一段记成缺口，
        // 之后由 window_req 按需开窗补（§4.4 / §4.7）。
        if ([conv[@"too_long"] boolValue]) {
            [_backlog markGapForConv:convID];
            IMLogSocket(@"sync_backlog_too_long conv=%@ since=%lld head=%lld",
                        convID, [self syncedSeqForConv:convID], head);
            continue;
        }
        int64_t pageStart = [self syncedSeqForConv:convID];
        NSArray *messages = [conv[@"messages"] isKindOfClass:[NSArray class]] ? conv[@"messages"] : @[];
        int64_t firstFailureSeq = 0; // 首个落库失败的下发序号（0=全部成功）
        // 整页收集 → 一次事务提交（§4.8）。此前是**每条一个事务**：那是 seq=416 事故
        // 「消息丢了游标却越过」的根治手段，约束本身不变，只是把粒度从"每条"降到"每页"——
        // 页内任一条失败即整页回滚、整页重拉，「消息未落库则位点绝不越过」照旧成立，
        // 而补拉 10 万条时事务数从 10 万降到 500。
        NSMutableArray<IMMessageModel *> *pageMsgs = [NSMutableArray arrayWithCapacity:messages.count];
        for (NSDictionary *md in messages) {
            if (![md isKindOfClass:[NSDictionary class]]) { continue; }
            IMMessageModel *m = [IMMessageModel receivedMessageWithNewMsgData:md];
            // 非普通消息（msg_op 事件行 / 已被"为所有人删除"的墓碑）仍走逐条路径：
            // 它们不是"入库一条消息"，而是"应用一次效果"，语义与整页写入不同。
            if ([m.contentType isEqualToString:kIMTypeMsgOp] || m.deletedAt > 0) {
                if (![self processIncomingMessage:m fromSync:YES syncAdvanceSeq:0] && firstFailureSeq == 0 && m.convSeq > 0) {
                    firstFailureSeq = m.convSeq;
                }
                continue;
            }
            if (m.convSeq > 0) { [pageMsgs addObject:m]; }
        }
        int64_t pageAdvance = pageMsgs.lastObject.convSeq;
        if (pageMsgs.count > 0) {
            __block BOOL pageOK = NO;
            [self performDatabaseOperation:^(IMDatabase *database) {
                pageOK = [database saveIncomingPage:pageMsgs
                                          advanceTo:pageAdvance
                                            rangeLo:pageStart + 1
                                            rangeHi:pageAdvance];
            }];
            if (pageOK) {
                [self updateSyncedSeqForConv:convID seq:pageAdvance];
                [self sendReceiptForConv:convID upTo:pageAdvance]; // 整页一个 delivered（合批，§4.8）
                // 落库成功后才投递 UI：与逐条路径同序（先持久化、再上屏），
                // 且**整页一次**通知，而不是每条一个 dispatch_async + NSNotification。
                [self deliverSyncedPage:pageMsgs];
            } else if (firstFailureSeq == 0) {
                firstFailureSeq = pageMsgs.firstObject.convSeq; // 整页回滚 → 游标停在 pageStart
            }
        }
        // 权威覆盖位点：全部成功 → 若 covered > 已推进位点（存在可见性空洞未被消息事务带到位），补一次单事务
        // 把游标推到 covered；有失败 → 不补，靠 backoff 重拉，游标停在最后成功一条上。
        int64_t covered = [conv[@"covered_conv_seq"] longLongValue];
        BOOL fullyDurable = (firstFailureSeq == 0);
        int64_t currentSynced = [self syncedSeqForConv:convID];
        if (fullyDurable && covered > currentSynced) {
            [self updateSyncedSeqForConv:convID seq:covered];
            [self performDatabaseOperation:^(IMDatabase *database) {
                [database advanceSyncedConvSeqForConv:convID toConvSeq:covered]; // 跨过服务端可见性空洞
            }];
            currentSynced = covered;
        }
        if (fullyDurable) {
            // 本页全部落库成功 → 登记区间「(pageStart, currentSynced] 我已齐全」（§4.2 不变量 I1）。
            // 只在 fullyDurable 分支登记：有任何一条没落住就不许宣称这段齐全，
            // 与游标"消息未落则绝不越过"是同一条约束，只是从位点推广到区间。
            if (currentSynced > pageStart) {
                int64_t rangeLo = pageStart + 1, rangeHi = currentSynced;
                [self performDatabaseOperation:^(IMDatabase *database) {
                    [database registerRangeInConv:convID from:rangeLo to:rangeHi];
                }];
            }
            // 追平了就不再算"有缺口"（缺口只会收窄，不会扩大）。
            BOOL caughtUp = ![conv[@"has_more"] boolValue] && (head == 0 || currentSynced >= head);
            if (caughtUp) { [_backlog clearGapForConv:convID]; }
            [_syncStalledUntil removeObjectForKey:convID];
            // 只有真推进了才继续翻页；否则是空页/已追平，停手（避免 has_more 误设时空转）。
            if (currentSynced > pageStart && [conv[@"has_more"] boolValue]) {
                [self sendSyncReqForConvs:@[convID]];
            }
            continue;
        }
        // 落库有失败（典型：磁盘/上下文异常）：退避 10s 后从（可能已部分推进的）游标重拉，防热循环。
        _syncStalledUntil[convID] = @(CFAbsoluteTimeGetCurrent() + 10);
        IMLogSocket(@"sync stalled (durable save failed); backing off 10s conv=%@ synced=%lld first_fail=%lld",
                    convID, [self syncedSeqForConv:convID], firstFailureSeq);
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), _queue, ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            [self sendSyncReqForConvs:@[convID]]; // 到点重试；仍失败会再次退避，节奏 6 次/分钟
        });
    }
}

/// 整页补拉消息的 UI 投递：一次主线程派发、一次列表通知（仅在 queue 调用）。
///
/// 逐条派发在补拉 10 万条时就是 10 万个主线程 block + 10 万条通知。会话列表侧本就有节流
/// （0.12s/0.4s 合并），但 block 本身还是要过主线程——这一条与"每条一个事务""每条一个回执"
/// 并列，是补拉卡顿的三个固定成本之一（§2.3）。
- (void)deliverSyncedPage:(NSArray<IMMessageModel *> *)msgs {
    if (msgs.count == 0) { return; }
    NSString *convID = msgs.firstObject.convID ?: @"";
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        id<IMSocketManagerDelegate> d = self.delegate;
        if ([d respondsToSelector:@selector(socketManager:didReceiveMessage:)]) {
            for (IMMessageModel *m in msgs) { [d socketManager:self didReceiveMessage:m]; }
        }
        [NSNotificationCenter.defaultCenter postNotificationName:IMSocketDidReceiveMessageNotification
                                                          object:self
                                                        userInfo:@{ kIMConvIDKey: convID }];
    });
}

@end
