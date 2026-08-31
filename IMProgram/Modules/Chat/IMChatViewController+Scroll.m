//  IMChatViewController+Scroll.m
//  聊天页「↓N 跳转按钮 / 自动滚动 / 键盘跟随」分文件实现（CHAT_UX §7、§9）：滚动位点跟踪、
//  ↓N 未读计数与显隐、贴底/锚定滚动、键盘与附件面板互斥顶起输入栏。从 IMChatViewController.m 平移，未改行为。

#import "IMChatViewController+Private.h"
#import "IMMessageModel.h"
#import "IMTheme.h"
#import "IMLog.h"

@implementation IMChatViewController (Scroll)

#pragma mark - ↓N 跳转按钮 / 自动滚动（CHAT_UX §7、§9）

- (void)scrollToBottomAnimated:(BOOL)animated {
    if (self.windowState.messages.count == 0) { return; }
    NSIndexPath *last = [NSIndexPath indexPathForRow:self.windowState.messages.count - 1 inSection:0];
    [self.tableView scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

/// 精确贴底：自适应行高下 contentSize 初始基于估高（estimatedRowHeight=56），单次 layoutIfNeeded 只布局
/// 视口附近的行、离屏行仍是估算 → 一跳会停在真底部之上（进会话不贴底的根因）。
/// 改为「滚到末行(触发底部区域真实布局)→按最新 contentSize 精确对齐→再验证」迭代至收敛（≤6 轮防御死循环）。
- (void)scrollToAbsoluteBottom {
    if (self.windowState.messages.count == 0) { return; }
    NSIndexPath *last = [NSIndexPath indexPathForRow:(NSInteger)self.windowState.messages.count - 1 inSection:0];
    CGFloat y = 0;
    for (int pass = 0; pass < 6; pass++) {
        [self.tableView scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        [self.tableView layoutIfNeeded];
        CGFloat bottomInset = self.tableView.adjustedContentInset.bottom;
        CGFloat topInset = self.tableView.adjustedContentInset.top;
        y = self.tableView.contentSize.height - self.tableView.bounds.size.height + bottomInset;
        if (y < -topInset) { y = -topInset; }
        if (fabs(self.tableView.contentOffset.y - y) < 0.5) { return; } // 已精确贴底
        [self.tableView setContentOffset:CGPointMake(0, y) animated:NO];
    }
    // 6 轮仍未收敛=估高与真实行高差距过大（历史全是媒体/多行消息）。留痕定位"首进/发送后不贴底"。
    IMLogWarnWithTag(IMLogTagUI, @"chat_stick_bottom_not_converged conv_id=%@ rows=%lu offset_y=%.1f target_y=%.1f content_h=%.1f",
                     self.convID, (unsigned long)self.windowState.messages.count, self.tableView.contentOffset.y, y,
                     self.tableView.contentSize.height);
}

/// 是否贴近底部（距底 < 80pt，计入底部安全区 inset）。
- (BOOL)isNearBottom {
    UIScrollView *sv = self.tableView;
    CGFloat distance = sv.contentSize.height - sv.contentOffset.y - sv.bounds.size.height + sv.adjustedContentInset.bottom;
    return distance < 80;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (self.tableView.contentSize.height <= 0) { return; }
    [self markVisibleRowsRead];   // 可见即读：滚到哪、读到哪（先推进 pendingReadSeq）
    [self updateJumpButton];      // 再据新位点刷新 ↓N 计数
    [self maybeLoadOlderOnScroll]; // 快到顶了就往上翻一页（本地库优先，翻到头才问服务端）
    [self maybeLoadNewerOnScroll]; // 快到底了且窗口不含本地最新 → 从本地库接下一页（对称）
}

// 滚动中媒体尺寸落定被延迟的行高重排：拖拽/惯性结束后统一补一次（滚动期间做会肉眼可见地弹跳）。
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) { [self settleRowHeightsIfNeeded]; }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [self settleRowHeightsIfNeeded];
}

- (void)settleRowHeightsIfNeeded {
    if (!self.needsRowHeightSettle) { return; }
    self.needsRowHeightSettle = NO;
    [self refreshRowHeightsWithoutAnimation];
}

/// 据当前滚动位置显示/隐藏"↓N"：贴底则隐藏；离底则显示，徽标=视口下方未读数（随滚动递减）。
- (void)updateJumpButton {
    // 自己发消息触发的贴底动作在过渡窗口里 isNearBottom 会短暂 false（contentSize 已增而 offset 尚未收敛），
    // 此时不该弹出↓N。selfSendScrollGuardUntil 由 appendReloadAndScroll 设置（now+0.5s），命中则保持隐藏。
    if (self.selfSendScrollGuardUntil > [NSDate timeIntervalSinceReferenceDate]) {
        self.jumpButton.hidden = YES;
        self.jumpBadge.hidden = YES;
        return;
    }
    if ([self isNearBottom]) {
        self.jumpButton.hidden = YES;
        self.jumpBadge.hidden = YES;
        return;
    }
    self.jumpButton.hidden = NO;
    NSInteger below = [self unreadBelowReadFrontier];
    if (below > 0) {
        self.jumpBadge.hidden = NO;
        self.jumpBadge.text = below > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)below];
    } else {
        self.jumpBadge.hidden = YES;
    }
}

/// 视口下方仍未读的对端消息数 = conv_seq 超过已滚入位点(pendingReadSeq)的对端消息数。
/// 随着向下滚动 pendingReadSeq 推进 → 该数递减，滚到底为 0。
- (NSInteger)unreadBelowReadFrontier {
    // 分页后内存里只有当前一窗：看历史时数不出下方还有多少，改由 +Window.m 按本地库出（同一口径）。
    return [self windowUnreadBelowCount];
}

/// ↓ 按钮 = "我要看最新的"：正在看历史时先换回最新一窗，再贴底。
/// 只滚不换窗的话，按钮会把用户送到**历史窗口的底部**，看起来像是没反应。
- (void)jumpTapped {
    [self resetWindowToTailAnimated:YES];
    [self updateJumpButton];
}

- (void)observeKeyboard {
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWillChange:)
                                               name:UIKeyboardWillChangeFrameNotification object:nil];
}

- (void)keyboardWillChange:(NSNotification *)note {
    // 缩/放 tableView 前先判贴底：约束链让 inputBar 上移即压缩 tableView 高度，而 UITableView
    // frame 变化时 contentOffset 顶端锚定不动 → 贴底的最新消息会被抬起的输入栏/键盘盖住而非跟随。
    // 交互式收键盘（keyboardDismissMode=Interactive）由 tableView 拖拽驱动，此时 isTracking=YES，
    // 跳过强制滚动以免与用户手势打架；仅在点按聚焦/收起等非拖拽路径重锚（对齐 :2282 的拖拽守卫）。
    BOOL wasNearBottom = !self.tableView.isTracking && [self isNearBottom];
    CGRect endFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat overlap = CGRectGetHeight(self.view.bounds) - [self.view convertRect:endFrame fromView:nil].origin.y;
    self.kbInset = MAX(0, overlap - self.view.safeAreaInsets.bottom);
    if (self.kbInset > 0 && self.attachPanelVisible) { // 键盘弹起 → 收起附件面板（二者互斥）
        self.attachPanelVisible = NO;
        self.attachPanel.hidden = YES;
    }
    [self updateInputBottomAnimated:NO];
    // frame 落定后：原本贴底则重锚到底（弹起→上顶，收起→回落，与 inputBar 同帧移动）；
    // 非贴底（正在往前翻历史）维持现状，不打断阅读位置。
    if (wasNearBottom) { [self scrollToAbsoluteBottom]; }
}

/// 把一段操作推迟到键盘完全收起（inset 落定）后在主线程执行一次——用于引用跳转等依赖稳定布局的定位。
/// 一次性监听 UIKeyboardDidHideNotification，触发即摘除；调用方须在已 resignFirstResponder 且键盘确在弹起态时用。
- (void)runAfterKeyboardHidden:(void (^)(void))block {
    if (!block) { return; }
    __block id<NSObject> token = nil;
    __block BOOL done = NO;
    __weak typeof(self) weakSelf = self;
    void (^teardown)(void) = ^{
        if (token) { [NSNotificationCenter.defaultCenter removeObserver:token]; token = nil; }
    };
    token = [NSNotificationCenter.defaultCenter addObserverForName:UIKeyboardDidHideNotification
                                                           object:nil queue:NSOperationQueue.mainQueue
                                                       usingBlock:^(NSNotification *note) {
        if (done) { return; }
        done = YES;
        teardown();
        block(); // 键盘确已收起、布局已稳：执行跳转
    }];
    // 兜底：外接硬件键盘/焦点被别的响应者抢走等场景 UIKeyboardDidHide 可能永不到达，届时这个一次性观察者
    // 及其强引用的 block（内含 self）会永久驻留、泄漏整个聊天页。1s 后强制摘除；但仅当键盘确已收起
    // （kbInset==0）才补跑跳转——否则跳转会打在还没稳定的布局上、落点偏。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (done) { return; }
        done = YES;
        teardown();
        __strong typeof(weakSelf) self = weakSelf;
        if (self && self.kbInset <= 0) { block(); }
    });
}

/// 输入栏底部偏移 = 键盘遮挡 与 面板高度 取较大者（二者互斥，但统一处理避免竞态）。
- (void)updateInputBottomAnimated:(BOOL)animated {
    CGFloat h = MAX(self.kbInset, self.attachPanelVisible ? kIMAttachPanelHeight : 0);
    self.inputBottom.constant = -h;
    if (animated) {
        [UIView animateWithDuration:0.25 animations:^{ [self.view layoutIfNeeded]; }];
    } else {
        [self.view layoutIfNeeded];
    }
}
@end
