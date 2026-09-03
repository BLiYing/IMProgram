//  IMChatViewController+Window.m
//  聊天页的**消息窗口**：进会话只取一窗、向上翻页、按锚点开窗定位。
//  设计见 IMServer/docs/design/MESSAGE_WINDOW_DESIGN.md（协议 PROTOCOL §6.11）。
//
//  在此之前，进会话是 `messagesForConv:` **一次读全部**——本地有多少条读多少条全构造成对象。
//  小会话碰不到，聊了很久的会话（活跃大群一小时就能攒 7 万条）每次点进去都要重来一遍。
//  这跟群大小其实没关系、只跟消息条数有关，所以**分页不区分大小群**。
//
//  三层取数，逐层回落——前两层都不打网络，这是"跳转基本瞬时"的原因：
//    ① 目标已在当前窗口   → 直接滚动
//    ② 目标在本地库       → 按它开一窗（首次 sync 常已把历史灌进本地库）
//    ③ 都没有             → window_req 问服务端，落库后回到 ②
//
//  唯一的可变式：`messages` 是**当前这一窗**，不再是"全部消息"。凡是过去默认
//  "内存里有全部消息"的地方都必须看 `windowAtTail`（新消息上屏、↓N 计数、发送后贴底）。

#import "IMChatViewController+Private.h"
#import "IMDatabase+Ranges.h"
#import "IMMessageModel.h"
#import "IMDatabase.h"
#import "IMLog.h"
#import "UIViewController+IMToast.h"

/// 一窗条数（与 IMDatabase 的 kIMMessageWindowPageSize、服务端单侧上限、im-web 的 RENDER_WINDOW_STEP 同量级）。
static NSInteger IMWindowPage(void) { return kIMMessageWindowPageSize; }

/// 内存里最多留几窗：贴底连收消息时窗口会一直涨，到这个数就从**顶部**裁掉一窗。
/// 只在用户贴底时裁（见 trimWindowIfOverlongAtTail），否则会把正在看的那一段裁掉。
static const NSInteger kIMWindowMaxPages = 3;

/// 距顶多少 pt 触发向上翻页。给足提前量：翻页要读库/发请求，等滚到 0 才开始用户会看到明显的停顿。
static const CGFloat kIMWindowLoadOlderThreshold = 300;

/// 服务端开窗的兜底超时：断线/丢帧时不能让 windowLoading 永远挂着（那会把向上翻页永久卡死）。
static const NSTimeInterval kIMWindowRequestTimeout = 6.0;

@implementation IMChatViewController (Window)

#pragma mark - 装载

/// 进会话的第一窗。
///
/// 有未读时**以已读位点开窗**而不是恒取最新：未读超过一窗（离线一晚的群）时，取最新会让
/// "首条未读"根本不在窗口里，进会话定位与未读分割线双双失效——它们都要求那条消息在内存里。
/// 锚点传的是**位点**（entryReadSeq）而不是某条消息的 seq：那个位点未必对应任何一行
/// （它可能指向一条已被删除、或对我不可见的消息），IMDatabase 的 around 查询按位点切分，故成立。
- (void)loadInitialWindow {
    NSInteger page = IMWindowPage();
    __block NSArray<IMMessageModel *> *msgs = @[];
    __block int64_t localMax = 0;
    __block BOOL complete = YES;
    int64_t readSeq = self.entryReadSeq;
    BOOL hasUnread = self.entryUnread > 0 && readSeq > 0;
    NSString *convID = self.convID;
    [self performDatabaseOperation:^(IMDatabase *database) {
        msgs = hasUnread
            ? [database messagesForConv:convID aroundConvSeq:readSeq before:page / 4 after:page]
            : [database latestContiguousMessagesForConv:convID limit:page];
        localMax = [database maxConvSeqForConv:convID];
        complete = [database isConvComplete:convID];
    }];
    int64_t loadedMax = 0;
    for (IMMessageModel *m in msgs) { if (m.convSeq > loadedMax) { loadedMax = m.convSeq; } }
    [self applyWindowMessages:msgs atTail:(localMax == 0 || loadedMax >= localMax)];
    if (complete) { return; }   // 本地齐全：本地怎么开窗就是最终结果，不必问服务端

    // 本地不齐（离线积压留了缺口；超级群尤甚：max_gap=0，正文只在打开会话时取）。
    // **要哪一窗取决于有没有未读**，这一步分错方向的代价很实在：
    //   · 有未读 → 要**读位点附近**那一窗（OFFLINE_BACKLOG_DESIGN §4.0②），回来后停在首条未读；
    //   · 无未读 → 要最新一窗，回来后贴底。
    // 早先两种情况都去要最新一窗并贴底，于是有未读时不但把用户甩到最底，还顺手
    // markVisibleRowsRead 把读位点一路推到 head——十万条未读**打开即清零**（2026-09-03 实测）。
    if (!hasUnread) { [self requestServerTailWindowIfBehind]; return; }
    // 分割线已经能在本地摆出来 → 首屏就是对的，不必再问（往下滚由 loadNewer 续）。
    if ([self firstUnreadRow] >= 0) { return; }
    [self requestServerEntryWindowAroundReadSeq:readSeq];
}

/// 有未读、但读位点附近那一段没下载 → 按**读位点**开一窗（anchor=readSeq）。
///
/// 锚点传的是位点而非某条消息的 seq：它未必对应任何一行（可能指向已删或对我不可见的消息）。
/// 服务端的 window 查询按位点切分（LoadBefore(anchor) / LoadSince(anchor-1)），故成立；
/// 回包的 anchor_found 在这条路上**无意义**，不据它弹「原消息已被删除」。
- (void)requestServerEntryWindowAroundReadSeq:(int64_t)readSeq {
    if (readSeq <= 0 || IMSocketManager.sharedManager.state != IMSocketStateConnected) { return; }
    if (self.windowState.pendingEntryAnchor != 0) { return; }
    self.windowState.pendingEntryAnchor = readSeq;
    NSInteger page = IMWindowPage();
    IMLogDebugWithTag(IMLogTagUI, @"chat_window_entry_request conv_id=%@ read_seq=%lld unread=%ld",
                      self.convID, readSeq, (long)self.entryUnread);
    [IMSocketManager.sharedManager requestWindowForConv:self.convID anchor:readSeq
                                                 before:page / 4 after:page];
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kIMWindowRequestTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        // 只清自己那一次：值已变说明这帧早回来了、或又发了新的一次，别把别人的在途标志抹掉。
        if (ws.windowState.pendingEntryAnchor == readSeq) { ws.windowState.pendingEntryAnchor = 0; }
    });
}

/// 超级群 conv_bump：只有**本会话**才理会，其余一概不动。
/// 取的是「最新一窗」而不是 sync_req——超级群 max_gap 恒 0，sync 只会回一个 too_long。
- (void)onConvBump:(NSNotification *)note {
    NSArray *items = note.userInfo[@"items"];
    if (![items isKindOfClass:NSArray.class] || self.convID.length == 0) { return; }
    BOOL hit = NO;
    for (id it in items) {
        if (![it isKindOfClass:NSDictionary.class]) { continue; }
        NSString *cid = [it[@"conv_id"] isKindOfClass:NSString.class] ? it[@"conv_id"] : nil;
        if (cid.length > 0 && [cid isEqualToString:self.convID]) { hit = YES; break; }
    }
    if (!hit) { return; }
    // 用户正在看历史（窗口不在末尾）时**不要**把他拽到最新，只刷 ↓N——它按 head 算，
    // 不依赖本地有没有下载；用户想看时点 ↓，那条路会去取。
    if (!self.windowState.atTail) { [self updateJumpButton]; return; }
    [self requestServerTailWindowIfBehind];
}

/// 本地尾巴落后于服务端最新位点 → 要一窗最新的（anchor=0 即"取最新"，PROTOCOL §6.11）。
///
/// 刻意不复用 `requestServerWindowAnchor:isJump:`：那条路把 `pendingAnchor` 当在途标志，
/// 而 anchor=0 与"无在途"是同一个值，混用会让向上翻页的防重入判据失灵。
- (void)requestServerTailWindowIfBehind {
    if (IMSocketManager.sharedManager.state != IMSocketStateConnected) { return; }
    if (self.windowState.pendingTail) { return; }
    NSString *convID = self.convID;
    __block int64_t localMax = 0;
    [self performDatabaseOperation:^(IMDatabase *database) { localMax = [database maxConvSeqForConv:convID]; }];
    int64_t head = [IMSocketManager.sharedManager headConvSeqForConv:convID];
    if (head <= 0 || head <= localMax) { return; }   // 已经是最新的，或不知道最新在哪 → 不白跑
    self.windowState.pendingTail = YES;
    IMLogDebugWithTag(IMLogTagUI, @"chat_window_tail_request conv_id=%@ local_max=%lld head=%lld", convID, localMax, head);
    [IMSocketManager.sharedManager requestWindowForConv:convID anchor:0 before:IMWindowPage() after:0];
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kIMWindowRequestTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ ws.windowState.pendingTail = NO; });
}

/// **替换内存模型的唯一入口**：换窗 = 整段替换，不做多窗并存。
///
/// 多窗并存（内存里攒起互不相连的几段）会让"向下滚"的语义变复杂，且省不下什么内存。
/// Telegram 的窗口同样是单一连续区间，跳转即换锚点重开。
- (void)applyWindowMessages:(NSArray<IMMessageModel *> *)msgs atTail:(BOOL)atTail {
    self.windowState.messages = [msgs mutableCopy];
    // seenConvSeqs 跟着窗口重建：它是"这一窗里已有哪些 seq"的去重集，不是"本页见过的全部 seq"。
    // 不重建的话，换窗后旧窗里的 seq 仍在集合里 → 那些消息若随实时/补拉再来一次会被当重复丢掉，
    // 表现为窗口末尾莫名少几条。
    [self.windowState.seenConvSeqs removeAllObjects];
    int64_t earliest = 0;
    for (IMMessageModel *m in msgs) {
        if (m.convSeq <= 0) { continue; }
        [self.windowState.seenConvSeqs addObject:@(m.convSeq)];
        if (earliest == 0 || m.convSeq < earliest) { earliest = m.convSeq; }
    }
    self.windowState.atTail = atTail;
    // conv_seq 是会话内从 1 起的连续序号，故"最早一条就是 1"⇒ 上面确定没有了，免掉一次白跑的翻页请求。
    // （入群前历史不可见的新成员，其最早可见条 >1，会白跑一次，服务端回 has_before=false 后收敛。）
    self.windowState.hasMoreAbove = (earliest != 1);
    IMLogDebugWithTag(IMLogTagUI, @"chat_window_applied conv_id=%@ rows=%lu earliest=%lld at_tail=%d more_above=%d",
                      self.convID, (unsigned long)msgs.count, earliest, atTail, self.windowState.hasMoreAbove);
}

#pragma mark - 向上翻页

- (void)maybeLoadOlderOnScroll {
    // 初始定位（贴底/锚未读）没跑完之前 contentOffset 还停在 0 附近——那不是"用户滚到了顶"，
    // 是表刚建好。不拦的话每次进会话都会白翻一页（日志实锤：applied 200 后必跟一条 prepend 200）。
    if (!self.didInitialPosition) { return; }
    // pendingAnchor != 0 ⇒ 已有一次开窗在途（本地翻页是同步的，只有服务端那一步会在途）。
    if (!self.windowState.hasMoreAbove || self.windowState.pendingAnchor != 0 || self.windowState.messages.count == 0) { return; }
    if (self.tableView.contentOffset.y > kIMWindowLoadOlderThreshold) { return; }
    [self loadOlderPage];
}

/// 向上翻一页：先读本地库，本地翻到头才问服务端。
- (void)loadOlderPage {
    int64_t lo = [self earliestLoadedConvSeq];
    if (lo <= 0) { self.windowState.hasMoreAbove = NO; return; } // 窗口里全是待发消息，没有可作边界的位点
    NSInteger page = IMWindowPage();
    __block NSArray<IMMessageModel *> *older = @[];
    NSString *convID = self.convID;
    [self performDatabaseOperation:^(IMDatabase *database) {
        // **段内取**（OFFLINE_BACKLOG_DESIGN §4.7）：只要与 lo 同属一段的更早消息。
        // 光判"这一段里还有更早的"不够——段内剩余不足一页时，无下界的查询会径直翻过缺口，
        // 把旧岛接到窗口顶部。下界收在 contiguousMessagesForConv: 里，返回空即本段到头。
        older = [database contiguousMessagesForConv:convID beforeConvSeq:lo limit:page];
    }];
    if (older.count > 0) {
        [self prependMessages:older];
        return;
    }
    [self requestServerWindowAnchor:lo isJump:NO]; // 本段到头（或撞上缺口）→ 问服务端
}

/// 把更早的一段接到窗口顶部，并**保住用户当前看的那一行**。
///
/// 保位按「**同一条消息**补偿」，不是按「插入前后 contentSize 之差」。
///
/// 差值法在自适应行高下必错，且错得很大（2026-09-03 用户实测：上翻到 9820 触发拉取，
/// 回来后列表跳到 9891 才开始显示）。原因是 `reloadData` 会把**所有**行的高度打回
/// `estimatedRowHeight`(56)，contentSize 的增量里既含新插的那 200 行，也含"旧行由真实高度
/// 退回估高"的那部分差额；而真实气泡普遍比 56 矮，于是 delta 被高估几百上千 pt，
/// 补偿过头就把用户甩到了更靠后的消息上。
///
/// 换成锚点法之后与估高无关：记下当前最靠上那一行**距可视区顶的偏移**，重建后把同一条消息
/// 摆回同一个屏幕位置即可——不管它的 frame 在哪个坐标系里，差值是恒等的。
/// 迭代两轮的理由同 `scrollToAbsoluteBottom`：设完 offset 后锚点上方那几行才被真正布局出来，
/// 锚点的 rect 会再动一次，需要再修一遍才稳。
- (void)prependMessages:(NSArray<IMMessageModel *> *)older {
    if (older.count == 0) { return; }
    UITableView *table = self.tableView;
    NSIndexPath *anchor = table.indexPathsForVisibleRows.firstObject;
    CGFloat anchorScreenY = anchor ? [table rectForRowAtIndexPath:anchor].origin.y - table.contentOffset.y : 0;

    NSMutableArray<IMMessageModel *> *merged = [older mutableCopy];
    for (IMMessageModel *m in older) {
        if (m.convSeq > 0) { [self.windowState.seenConvSeqs addObject:@(m.convSeq)]; }
    }
    [merged addObjectsFromArray:self.windowState.messages];
    self.windowState.messages = merged;
    int64_t earliest = [self earliestLoadedConvSeq];
    self.windowState.hasMoreAbove = (earliest != 1);
    [table reloadData];

    // 行号与 windowState.messages 下标一一对应（numberOfRowsInSection 返回的就是它的 count，
    // 相册成员行只是高度为 0），故锚点的新行号 = 旧行号 + 本次插入条数，不必回数组里找。
    CGFloat y = table.contentOffset.y;
    NSInteger movedRow = anchor ? anchor.row + (NSInteger)older.count : NSNotFound;
    if (anchor && movedRow < (NSInteger)self.windowState.messages.count) {
        NSIndexPath *moved = [NSIndexPath indexPathForRow:movedRow inSection:0];
        for (int pass = 0; pass < 3; pass++) {
            [table layoutIfNeeded];
            CGFloat topInset = table.adjustedContentInset.top;
            CGFloat maxY = MAX(-topInset,
                               table.contentSize.height - table.bounds.size.height + table.adjustedContentInset.bottom);
            y = MIN(MAX([table rectForRowAtIndexPath:moved].origin.y - anchorScreenY, -topInset), maxY);
            if (fabs(table.contentOffset.y - y) < 0.5) { break; } // 已经在正确位置
            [table setContentOffset:CGPointMake(0, y) animated:NO];
        }
    } else {
        [table layoutIfNeeded];
    }
    IMLogDebugWithTag(IMLogTagUI, @"chat_window_prepend conv_id=%@ added=%lu rows=%lu earliest=%lld anchor_row=%ld offset_y=%.1f",
                      self.convID, (unsigned long)older.count, (unsigned long)self.windowState.messages.count,
                      earliest, (long)(anchor ? anchor.row : -1), y);
}

#pragma mark - 定位（三层回落的实现）

/// 目标已在当前窗口 → 滚过去并高亮一闪；不在则返回 NO 交给调用方回落。
- (BOOL)scrollToLoadedConvSeq:(int64_t)convSeq {
    if (convSeq <= 0) { return NO; }
    for (NSUInteger i = 0; i < self.windowState.messages.count; i++) {
        if (self.windowState.messages[i].convSeq != convSeq) { continue; }
        // 相册成员行本身零高（宫格整体画在 leader 行）：直接滚到成员下标会落在不可见行、高亮闪不出来。
        // 统一经 visibleRowForMessage 映射到该相册的 leader 行（普通消息即自身行）。
        NSUInteger visRow = [self visibleRowForMessage:self.windowState.messages[i]];
        NSInteger targetRow = (visRow == NSNotFound) ? (NSInteger)i : (NSInteger)visRow;
        NSIndexPath *ip = [NSIndexPath indexPathForRow:targetRow inSection:0];
        [self.tableView scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
        // 等滚动动画到位后再闪（已在视口时 scrollToRow 也可能微调，同样适用）。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self flashRowAtIndexPath:ip]; });
        return YES;
    }
    return NO;
}

/// 本地库里以目标为中心开一窗；目标本地没有则返回 NO（不动当前窗口）。
- (BOOL)openLocalWindowAroundConvSeq:(int64_t)convSeq {
    if (convSeq <= 0) { return NO; }
    NSInteger half = IMWindowPage() / 2;
    __block NSArray<IMMessageModel *> *msgs = @[];
    __block int64_t localMax = 0;
    NSString *convID = self.convID;
    [self performDatabaseOperation:^(IMDatabase *database) {
        msgs = [database messagesForConv:convID aroundConvSeq:convSeq before:half after:half];
        localMax = [database maxConvSeqForConv:convID];
    }];
    BOOL found = NO;
    int64_t loadedMax = 0;
    for (IMMessageModel *m in msgs) {
        if (m.convSeq == convSeq) { found = YES; }
        if (m.convSeq > loadedMax) { loadedMax = m.convSeq; }
    }
    if (!found) { return NO; }
    [self applyWindowMessages:msgs atTail:(localMax > 0 && loadedMax >= localMax)];
    [self.tableView reloadData];
    [self.tableView layoutIfNeeded];
    [self scrollToLoadedConvSeq:convSeq];
    [self updateJumpButton]; // 窗口离开末尾 → ↓N 要显示出来（计数改由 DB 出，见 windowUnreadBelowCount）
    return YES;
}

/// 向服务端开一窗。isJump=YES 是「跳到某条」（回来要滚过去），NO 是「向上翻一页」。
- (void)requestServerWindowAnchor:(int64_t)anchor isJump:(BOOL)isJump {
    if (IMSocketManager.sharedManager.state != IMSocketStateConnected) {
        // 不静默失败：离线时用户点了置顶横幅什么也不发生，会当成 bug 报上来。
        if (isJump) { [self im_showToast:@"网络未连接，无法加载这条消息"]; }
        self.windowState.hasMoreAbove = self.windowState.hasMoreAbove && !isJump; // 翻页失败不永久封死，重连后还能再试
        return;
    }
    NSInteger half = IMWindowPage() / 2;
    self.windowState.pendingAnchor = anchor;
    self.windowState.pendingIsJump = isJump;
    [IMSocketManager.sharedManager requestWindowForConv:self.convID anchor:anchor
                                                 before:(isJump ? half : IMWindowPage())
                                                  after:(isJump ? half : 0)];
    // 兜底超时：丢帧/断线时若不解锁 windowLoading，向上翻页会永久卡死（且没有任何提示）。
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kIMWindowRequestTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(ws) self = ws;
        if (!self || self.windowState.pendingAnchor != anchor) { return; }
        self.windowState.pendingAnchor = 0;
        IMLogWarnWithTag(IMLogTagUI, @"chat_window_request_timeout conv_id=%@ anchor=%lld is_jump=%d",
                         self.convID, anchor, isJump);
        if (isJump) { [self im_showToast:@"加载超时，请重试"]; }
    });
}

/// window_resp 到达（消息已由网络层落库）：按本地库把这一窗接上。
- (void)socketManager:(IMSocketManager *)manager
    didReceiveWindowForConv:(NSString *)convID
                     anchor:(int64_t)anchor
                anchorFound:(BOOL)anchorFound
                  hasBefore:(BOOL)hasBefore
                   hasAfter:(BOOL)hasAfter {
    if (![convID isEqualToString:self.convID]) { return; }
    // 锚点回显对不上 = 这帧是回更早那次开窗的（用户翻页途中又点了置顶横幅）。用了它会把窗口拉到错误的一段。
    // 进会话「按读位点开窗」那一路：消息已落库，这里换成围绕读位点的一窗并**停在首条未读**。
    // 与下面 anchor=0 那一路的关键差别：**不贴底、不强制标已读**——把用户按到最底再标已读，
    // 等于替他把整段未读读完了。
    if (anchor != 0 && anchor == self.windowState.pendingEntryAnchor) {
        self.windowState.pendingEntryAnchor = 0;
        NSString *cid = self.convID;
        NSInteger page = IMWindowPage();
        __block NSArray<IMMessageModel *> *msgs = @[];
        __block int64_t localMax = 0;
        [self performDatabaseOperation:^(IMDatabase *database) {
            msgs = [database messagesForConv:cid aroundConvSeq:anchor before:page / 4 after:page];
            localMax = [database maxConvSeqForConv:cid];
        }];
        if (msgs.count == 0) { return; }   // 服务端也没有可见内容 → 保持首屏，别把界面清空
        int64_t loadedMax = 0;
        for (IMMessageModel *m in msgs) { if (m.convSeq > loadedMax) { loadedMax = m.convSeq; } }
        [self applyWindowMessages:msgs atTail:(localMax == 0 || loadedMax >= localMax)];
        [self.tableView reloadData];
        // 首屏那次若因窗口为空而早退，didInitialPosition 还是 NO；这里补上，免得随后的兜底
        // positionInitialIfNeeded 再定位一次，把用户刚落好的位置又挪走。
        self.didInitialPosition = YES;
        [self applyInitialPosition];       // 停首条未读；分割线仍摆不出来时它自己回落到贴底
        return;
    }
    // anchor=0 是「要最新一窗」那一路（无未读时进会话 / 点 ↓）：消息已落库，这里把窗口拉到尾段。
    if (anchor == 0 && self.windowState.pendingTail) {
        self.windowState.pendingTail = NO;
        NSString *cid = self.convID;
        NSInteger page = IMWindowPage();
        __block NSArray<IMMessageModel *> *msgs = @[];
        [self performDatabaseOperation:^(IMDatabase *database) {
            msgs = [database latestContiguousMessagesForConv:cid limit:page];
        }];
        if (msgs.count > 0) {
            [self applyWindowMessages:msgs atTail:YES];
            [self.tableView reloadData];
            [self scrollToAbsoluteBottom];
            [self markVisibleRowsRead];
            [self updateJumpButton];
        }
        return;
    }
    if (anchor != self.windowState.pendingAnchor) { return; }
    BOOL wasJump = self.windowState.pendingIsJump;
    self.windowState.pendingAnchor = 0;
    if (wasJump) {
        if (!anchorFound) {
            // 这次是**真的**：服务端明确说这条不存在/对我不可见。
            // 改造前只能靠"往前翻满 N 页还没见到"来猜，猜错就报出假的「原消息已被删除」。
            [self im_showToast:@"原消息已被删除"];
            return;
        }
        if (![self openLocalWindowAroundConvSeq:anchor]) {
            [self im_showToast:@"原消息已被删除"]; // 服务端说在，落库后却查不到 ⇒ 本端「仅为我删除」过
        }
        return;
    }
    // 向上翻页：落库后从本地库取那一段接到顶部。
    int64_t lo = [self earliestLoadedConvSeq];
    __block NSArray<IMMessageModel *> *older = @[];
    NSString *cid = self.convID;
    NSInteger page = IMWindowPage();
    [self performDatabaseOperation:^(IMDatabase *database) {
        // 同样走段内取：服务端这一页若未填满（撞上可见下界等），无下界的查询会把旧岛捞上来。
        // 本窗已在 handleWindowResp 登记过区间，故此刻 lo 所在段已包含刚拿回的这一段。
        older = [database contiguousMessagesForConv:cid beforeConvSeq:lo limit:page];
    }];
    if (older.count > 0) { [self prependMessages:older]; }
    // **服务端的 has_before 是权威，且必须写在 prepend 之后**：prepend 里那句
    // `hasMoreAbove = (earliest != 1)` 只是本地启发式，对"入群前历史不可见"的新成员是错的
    // （他能看到的最早一条是 500 而不是 1）。顺序反了的话，启发式会把标志重新打开，
    // 于是每次滚到顶都再问一次服务端、每次都得到"没有了"——永远不收敛的空转。
    self.windowState.hasMoreAbove = hasBefore;
}

#pragma mark - 向下翻页

/// 快滚到窗口底部且窗口不含本地最新 → 从本地库接下一页（对称于向上翻页）。
///
/// 没有它，跳到历史后往下滚会在窗口底"撞墙"——下面明明还有（至少在本地库里），却只能点 ↓ 回到最新。
/// 只走本地库、不走服务端：向下的空洞只会出现在「跳到比同步游标更深的历史」这一种情形，
/// 缺的那段由后台 sync 持续补（补上后这里自然能翻到）；为它单开一条服务端向下取数不划算。
/// 代价：本地不连续时（跳深处 + 同步没追上）翻下去会直接接到下一段，中间无视觉提示——
/// 与"首次同步期间尾窗横跨两段"同一个已知限制。
- (void)maybeLoadNewerOnScroll {
    if (!self.didInitialPosition) { return; } // 同 maybeLoadOlderOnScroll：建表期的 offset 不是用户手势
    if (self.windowState.atTail || self.windowState.pendingAnchor != 0 || self.windowState.messages.count == 0) { return; }
    UIScrollView *sv = self.tableView;
    CGFloat distance = sv.contentSize.height - sv.contentOffset.y - sv.bounds.size.height;
    if (distance > kIMWindowLoadOlderThreshold) { return; }
    int64_t hi = 0;
    for (IMMessageModel *m in self.windowState.messages) {
        if (m.convSeq > hi) { hi = m.convSeq; }
    }
    if (hi <= 0) { return; }
    NSInteger page = IMWindowPage();
    __block NSArray<IMMessageModel *> *newer = @[];
    __block int64_t localMax = 0;
    NSString *convID = self.convID;
    [self performDatabaseOperation:^(IMDatabase *database) {
        newer = [database messagesForConv:convID aroundConvSeq:hi before:0 after:page];
        localMax = [database maxConvSeqForConv:convID];
    }];
    if (newer.count == 0) {
        if (localMax <= hi) { self.windowState.atTail = YES; [self updateJumpButton]; } // 其实已在本地末尾
        return;
    }
    int64_t newHi = hi;
    for (IMMessageModel *m in newer) {
        if (m.convSeq > 0) { [self.windowState.seenConvSeqs addObject:@(m.convSeq)]; }
        if (m.convSeq > newHi) { newHi = m.convSeq; }
    }
    [self.windowState.messages addObjectsFromArray:newer];
    self.windowState.atTail = (localMax > 0 && newHi >= localMax);
    [self.tableView reloadData]; // 追加在视口下方，contentOffset 不动
    [self updateJumpButton];
    IMLogDebugWithTag(IMLogTagUI, @"chat_window_append conv_id=%@ added=%lu rows=%lu at_tail=%d",
                      self.convID, (unsigned long)newer.count, (unsigned long)self.windowState.messages.count,
                      self.windowState.atTail);
}

#pragma mark - 回到末尾

/// 回到"最新一窗"。发送消息、点 ↓ 按钮都走这里——它们的语义都是"我要看最新的"。
- (void)resetWindowToTailAnimated:(BOOL)animated {
    BOOL replaced = !self.windowState.atTail;
    if (replaced) {
        __block NSArray<IMMessageModel *> *msgs = @[];
        NSString *convID = self.convID;
        NSInteger page = IMWindowPage();
        [self performDatabaseOperation:^(IMDatabase *database) {
            msgs = [database latestContiguousMessagesForConv:convID limit:page];
        }];
        [self applyWindowMessages:msgs atTail:YES];
        [self.tableView reloadData];
    }
    // 点 ↓ 的语义是"我要看最新的"。有缺口时本地尾巴未必就是最新，只回本地等于到不了真正的底
    // （红点也清不掉）。与 Web 的 jumpToBottom 走 openConversation(latest, latest) 同口径。
    [self requestServerTailWindowIfBehind];
    // 刚整窗替换过：全表只有估高（56），单发的 scrollToBottomAnimated 会大幅欠滚——
    // 3 万条群里实测停在真底部上方约 170 行，看起来像 ↓ 没起作用。必须走迭代收敛的精确贴底；
    // 反正内容全换了，滚动动画也没有"从哪滚到哪"的连续性可言。动画只留给"窗口没换、只是滚上去了"的情形。
    if (animated && !replaced) { [self scrollToBottomAnimated:YES]; } else { [self scrollToAbsoluteBottom]; }
    [self markVisibleRowsRead];
    [self updateJumpButton];
}

/// 连收消息时窗口只涨不缩（活跃大群一小时 7 万条），到 kIMWindowMaxPages 窗就裁。**从哪头裁看用户在哪**：
/// - 贴底（在跟最新）：从**顶部**裁——那一段在屏幕上方老远，看不到任何跳动；
/// - 不贴底（停在窗口上方看着，尾部还在涨——首次同步追赶、大群刷屏都会这样）：从**底部**裁，
///   裁掉的行在视口下方、不可见，不动用户正看的位置；裁完窗口不再含本地最新 ⇒ atTail=NO，
///   之后的新消息经 didReceiveMessage 的守卫只落库不上屏——"每条消息一次 reloadData"的追赶风暴就此打住。
///   （3 万条首次同步实测：不这么做，窗口一路涨到几万条、主线程被 reload 打满，点置顶横幅都排不上队。）
- (void)trimWindowIfOverlongAtTail {
    NSInteger page = IMWindowPage();
    if (!self.windowState.atTail || (NSInteger)self.windowState.messages.count <= kIMWindowMaxPages * page) { return; }
    if ([self isNearBottom]) {
        NSRange drop = NSMakeRange(0, (NSUInteger)page);
        for (NSUInteger i = 0; i < drop.length; i++) {
            int64_t s = self.windowState.messages[i].convSeq;
            if (s > 0) { [self.windowState.seenConvSeqs removeObject:@(s)]; }
        }
        [self.windowState.messages removeObjectsInRange:drop];
        self.windowState.hasMoreAbove = YES; // 裁掉的那一段仍在本地库里，往上翻能拿回来
        [self.tableView reloadData];
        [self scrollToAbsoluteBottom];
        IMLogDebugWithTag(IMLogTagUI, @"chat_window_trim conv_id=%@ dropped=%ld rows=%lu",
                          self.convID, (long)page, (unsigned long)self.windowState.messages.count);
        return;
    }
    // 从底部裁：只裁已上号的行（conv_seq==0 的待发/失败消息属于"最新一段"的一部分，
    // 且用户此刻若有待发消息，appendReloadAndScroll 早已把窗口拉回末尾——碰到就停）。
    NSInteger overflow = (NSInteger)self.windowState.messages.count - kIMWindowMaxPages * page;
    NSInteger dropped = 0;
    while (dropped < overflow) {
        IMMessageModel *last = self.windowState.messages.lastObject;
        if (!last || last.convSeq <= 0) { break; }
        [self.windowState.seenConvSeqs removeObject:@(last.convSeq)];
        [self.windowState.messages removeLastObject];
        dropped++;
    }
    if (dropped == 0) { return; }
    self.windowState.atTail = NO; // 裁掉的是最新一段：窗口不再贴着本地末尾
    [self.tableView reloadData];  // 裁的行全在视口下方，contentOffset 不动、画面无跳变
    [self updateJumpButton];
    IMLogDebugWithTag(IMLogTagUI, @"chat_window_trim_bottom conv_id=%@ dropped=%ld rows=%lu",
                      self.convID, (long)dropped, (unsigned long)self.windowState.messages.count);
}

#pragma mark - ↓N 计数

/// 视口下方仍未读的对端消息数。
///
/// 窗口在末尾时按内存数（快，且与屏幕上看到的一致）；不在末尾时内存里只有历史那一段、
/// 根本数不出下方还有多少，改由本地库出——口径与内存版严格一致（发件人非我 且 conv_seq > 已滚入位点）。
- (NSInteger)windowUnreadBelowCount {
    NSString *convID = self.convID;
    int64_t frontier = self.pendingReadSeq;
    // head = 服务端最新位点的内存快照（O(1)，不碰库）。下面两条分支都要拿它当上界。
    int64_t head = [IMSocketManager.sharedManager headConvSeqForConv:convID];
    if (self.windowState.atTail) {
        int64_t windowMax = 0;
        NSInteger n = 0;
        for (IMMessageModel *m in self.windowState.messages) {
            if (m.convSeq > windowMax) { windowMax = m.convSeq; }
            if (![m.from isEqualToString:self.userID] && m.convSeq > frontier) { n++; }
        }
        // **`atTail` 只说明「窗口含本地最新一条」，不等于「含会话最新一条」**。
        // 有缺口时本地尾巴可能落后服务端上万条，此时数内存必然偏小——1 万条未读实测显示成
        // 185（= 窗口里读位点之后的条数），看着像个正常数字，其实是窗口大小（2026-09-03）。
        // 判据用 head 与**窗口最大 seq** 比，不用 isConvComplete:：后者要查库，而这里
        // 每帧滚动都会走一遍；head 本就在内存里，够用且更直接。
        if (head > windowMax && head > frontier) { return (NSInteger)(head - frontier); }
        return n;
    }
    // **本地有缺口时不能数本地**（IMServer/docs/design/OFFLINE_BACKLOG_DESIGN.md §4.9 第 8 项）：
    // 离线积压被留成缺口后，缺口里的消息根本没下载，数出来必然偏小——而 ↓N 少显示几百条
    // 不会报错、界面照常，只是数字悄悄不对。改用服务端最新位点减去已滚入位点（O(1)、不碰消息表）。
    // 代价是把本人消息与系统消息也算进去，在"缺口"这个场景下（积压成千上万）这点偏差无意义。
    __block BOOL complete = YES;
    __block NSInteger n = 0;
    [self performDatabaseOperation:^(IMDatabase *database) {
        complete = [database isConvComplete:convID];
        n = [database countIncomingInConv:convID afterConvSeq:frontier]; // 两条分支都可能用到（见下）
    }];
    if (complete) { return n; }
    // head 未知（老服务端 / 尚未收到过带 head 的响应）→ **退回数本地**，宁可偏小也不编造。
    // 早先这里直接返回 0，等于「有缺口且不知道 head 时把 ↓N 藏起来」——那是另一种错，
    // 且与 Web 的判据不一致（im-web/src/unreadBelow.ts 是两端共同口径，CHAT_UX §7）。
    if (head <= 0) { return n; }
    return head > frontier ? (NSInteger)(head - frontier) : 0;
}

#pragma mark - 辅助

/// 窗口里最早的已上号 conv_seq（待发消息 conv_seq==0 不算）；窗口里没有已上号消息时返回 0。
- (int64_t)earliestLoadedConvSeq {
    int64_t earliest = 0;
    for (IMMessageModel *m in self.windowState.messages) {
        if (m.convSeq > 0 && (earliest == 0 || m.convSeq < earliest)) { earliest = m.convSeq; }
    }
    return earliest;
}

@end
