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
    int64_t readSeq = self.entryReadSeq;
    BOOL hasUnread = self.entryUnread > 0 && readSeq > 0;
    NSString *convID = self.convID;
    [self performDatabaseOperation:^(IMDatabase *database) {
        msgs = hasUnread
            ? [database messagesForConv:convID aroundConvSeq:readSeq before:page / 4 after:page]
            : [database latestMessagesForConv:convID limit:page];
        localMax = [database maxConvSeqForConv:convID];
    }];
    int64_t loadedMax = 0;
    for (IMMessageModel *m in msgs) { if (m.convSeq > loadedMax) { loadedMax = m.convSeq; } }
    [self applyWindowMessages:msgs atTail:(localMax == 0 || loadedMax >= localMax)];
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
        older = [database messagesForConv:convID beforeConvSeq:lo limit:page];
    }];
    if (older.count > 0) {
        [self prependMessages:older];
        return;
    }
    [self requestServerWindowAnchor:lo isJump:NO]; // 本地到头 → 服务端可能还有
}

/// 把更早的一段接到窗口顶部，并**保住用户当前看的那一行**。
///
/// 做法是按 contentSize 的增量补偿 contentOffset。自适应行高下离屏行仍是估高（56），
/// 故这个增量是近似值、可能有几十 pt 的偏差；胜在无论行高多离谱都不会把用户甩到别处。
- (void)prependMessages:(NSArray<IMMessageModel *> *)older {
    CGFloat oldHeight = self.tableView.contentSize.height;
    CGFloat oldOffsetY = self.tableView.contentOffset.y;
    NSMutableArray<IMMessageModel *> *merged = [older mutableCopy];
    for (IMMessageModel *m in older) {
        if (m.convSeq > 0) { [self.windowState.seenConvSeqs addObject:@(m.convSeq)]; }
    }
    [merged addObjectsFromArray:self.windowState.messages];
    self.windowState.messages = merged;
    int64_t earliest = [self earliestLoadedConvSeq];
    self.windowState.hasMoreAbove = (earliest != 1);
    [self.tableView reloadData];
    [self.tableView layoutIfNeeded];
    CGFloat delta = self.tableView.contentSize.height - oldHeight;
    [self.tableView setContentOffset:CGPointMake(0, oldOffsetY + delta) animated:NO];
    IMLogDebugWithTag(IMLogTagUI, @"chat_window_prepend conv_id=%@ added=%lu rows=%lu earliest=%lld delta_y=%.1f",
                      self.convID, (unsigned long)older.count, (unsigned long)self.windowState.messages.count, earliest, delta);
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
        older = [database messagesForConv:cid beforeConvSeq:lo limit:page];
    }];
    if (older.count > 0) { [self prependMessages:older]; }
    // **服务端的 has_before 是权威，且必须写在 prepend 之后**：prepend 里那句
    // `hasMoreAbove = (earliest != 1)` 只是本地启发式，对"入群前历史不可见"的新成员是错的
    // （他能看到的最早一条是 500 而不是 1）。顺序反了的话，启发式会把标志重新打开，
    // 于是每次滚到顶都再问一次服务端、每次都得到"没有了"——永远不收敛的空转。
    self.windowState.hasMoreAbove = hasBefore;
}

#pragma mark - 回到末尾

/// 回到"最新一窗"。发送消息、点 ↓ 按钮都走这里——它们的语义都是"我要看最新的"。
- (void)resetWindowToTailAnimated:(BOOL)animated {
    if (!self.windowState.atTail) {
        __block NSArray<IMMessageModel *> *msgs = @[];
        NSString *convID = self.convID;
        NSInteger page = IMWindowPage();
        [self performDatabaseOperation:^(IMDatabase *database) {
            msgs = [database latestMessagesForConv:convID limit:page];
        }];
        [self applyWindowMessages:msgs atTail:YES];
        [self.tableView reloadData];
    }
    if (animated) { [self scrollToBottomAnimated:YES]; } else { [self scrollToAbsoluteBottom]; }
    [self markVisibleRowsRead];
}

/// 贴底连收消息时窗口只涨不缩（活跃大群一小时 7 万条），到 kIMWindowMaxPages 窗就从顶部裁掉一窗。
/// **只在用户贴底时裁**：裁的是顶部、贴底时那一段在屏幕外，用户看不到任何跳动；
/// 正在往上翻历史时裁会把他正看的内容抽走。
- (void)trimWindowIfOverlongAtTail {
    NSInteger page = IMWindowPage();
    if (!self.windowState.atTail || (NSInteger)self.windowState.messages.count <= kIMWindowMaxPages * page) { return; }
    if (![self isNearBottom]) { return; }
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
}

#pragma mark - ↓N 计数

/// 视口下方仍未读的对端消息数。
///
/// 窗口在末尾时按内存数（快，且与屏幕上看到的一致）；不在末尾时内存里只有历史那一段、
/// 根本数不出下方还有多少，改由本地库出——口径与内存版严格一致（发件人非我 且 conv_seq > 已滚入位点）。
- (NSInteger)windowUnreadBelowCount {
    if (self.windowState.atTail) {
        NSInteger n = 0;
        for (IMMessageModel *m in self.windowState.messages) {
            if (![m.from isEqualToString:self.userID] && m.convSeq > self.pendingReadSeq) { n++; }
        }
        return n;
    }
    __block NSInteger n = 0;
    NSString *convID = self.convID;
    int64_t frontier = self.pendingReadSeq;
    [self performDatabaseOperation:^(IMDatabase *database) {
        n = [database countIncomingInConv:convID afterConvSeq:frontier];
    }];
    return n;
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
