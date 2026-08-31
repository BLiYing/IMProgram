//  IMChatViewController+Search.m
//  会话内搜索（搜索功能）：顶部搜索栏**在标题栏那一行**（自持 IMLiquidNavigationBar 的 searchMode，复用 titleGlass
//  得 24 圆角 + 玻璃，搜索框/取消背景透明）；底部命中导航**无背景**（📅/来自/▲▼ 各自玻璃钮浮在聊天上，「第 N/M 条」
//  是独立玻璃胶囊）；📅 底部卡片按日期跳转；👤 群内「来自」发件人过滤（点即插高亮 token + 字段 ✕，选人复用真实头像）。
//  设计见 docs/design/SEARCH_DESIGN.md §0.1/§4/§4.1/§5；命中口径同后端 G4（content(text)+caption 子串，大小写不敏感）。

#import "IMChatViewController+Private.h"
#import "IMChatSearchState.h"
#import "IMChatDateJumpViewController.h"
#import "IMMessageModel.h"
#import "IMDatabase.h"      // 搜索命中/日历打点/发件人候选一律查库（分页后内存只剩一窗）
#import "IMTheme.h"
#import "IMGlass.h"
#import "IMMainTabBarController.h"   // kIMLiquidBarHeight
#import "IMProgram-Swift.h"          // IMLiquidNavigationBar（searchMode）
#import "UILabel+IMAvatar.h"         // im_setAvatarURL:（复用真实头像逻辑）
#import "UIViewController+IMToast.h"
#import "IMAccountIdentity.h"

static const CGFloat kIMSearchNavBarH = 48;
static const CGFloat kIMSearchFromRowH = 52;

@implementation IMChatViewController (Search)

#pragma mark - 进入 / 退出

- (void)beginInChatSearch { [self beginInChatSearchWithKeyword:nil]; }

- (void)beginInChatSearchWithKeyword:(nullable NSString *)keyword {
    if (self.searchState.searching) {
        if (keyword.length > 0) { self.searchState.searchField.text = keyword; [self recomputeSearchHitsAndJump:YES]; }
        [self.searchState.searchField becomeFirstResponder];
        return;
    }
    self.searchState = [IMChatSearchState new];   // 状态袋：进入创建、退出整体置 nil（CODING_STYLE §7）
    self.searchState.searching = YES;
    self.searchState.searchFromUID = nil;
    [self extendTableToScreenBottom]; // 表底改贴屏幕底：壁纸随表铺到底，隐藏输入栏后不露白
    [self buildSearchTopBar];
    [self hideInjectedBar];         // 隐藏注入的聊天标题栏，让磨砂搜索栏后面干净（不透出会话名/按钮）
    [self buildSearchNavBar];
    self.inputBar.hidden = YES;
    if (self.jumpButton) { self.jumpButton.hidden = YES; }
    // 先多选再搜索：选择栏此刻已在场（原贴安全区底），须重锚到新建的搜索栏**上方**（否则两排重叠——用户反馈的 bug）。
    if (self.selecting) { [self updateSelectionBarBottomAnchor]; }
    [self updateJumpButtonBottomAnchor]; // 向下钮改贴选择栏/搜索栏顶（出现时不重叠；b）
    // c：搜索态键盘**不因点空白/上下滑而收起**——只有点「取消」才收（endInChatSearch）。
    // 故不再设 keyboardDismissMode=OnDrag、也不再挂点空白 resignFirstResponder 的手势。
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeNone;
    [self observeSearchKeyboard];
    if (keyword.length > 0) { self.searchState.searchField.text = keyword; }
    [self.searchState.searchField becomeFirstResponder];
    [self recomputeSearchHitsAndJump:YES];
}

- (void)endInChatSearch {
    if (!self.searchState.searching) { return; }
    self.searchState.searching = NO;
    [self dismissSearchFromPanel];
    [self.searchState.searchField resignFirstResponder];
    if (self.searchState.searchKbObserver) { [[NSNotificationCenter defaultCenter] removeObserver:self.searchState.searchKbObserver]; self.searchState.searchKbObserver = nil; }
    [self.searchState.searchTopBar removeFromSuperview]; self.searchState.searchTopBar = nil; self.searchState.searchField = nil;
    [self.searchState.searchNavBar removeFromSuperview]; self.searchState.searchNavBar = nil;
    self.searchState.searchCountPill = nil; self.searchState.searchCountLabel = nil;
    self.searchState.searchPrevButton = nil; self.searchState.searchNextButton = nil;
    self.searchState.searchCalButton = nil; self.searchState.searchFromButton = nil; self.searchState.searchNavBottom = nil;
    self.searchState.searchHits = nil; self.searchState.searchHitIndex = 0; self.searchState.searchKeyword = nil; self.searchState.searchFromUID = nil;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeNone;
    // 多选态下退出搜索：输入栏保持隐藏（选择栏独占底部），否则才恢复——修复"取消搜索后输入框与选择钮重叠"。
    if (!self.selecting) { self.inputBar.hidden = NO; }
    self.searchState.hiddenInjectedBar.hidden = NO; self.searchState.hiddenInjectedBar = nil;   // 恢复注入标题栏
    if (self.searchState.tapToDismiss) { [self.tableView removeGestureRecognizer:self.searchState.tapToDismiss]; }
    [self restoreTableBottom];
    if (self.selecting) {
        [self extendTableBottomForSelection];   // 选择态仍需壁纸铺到底（接管搜索让出的表底）
        [self updateSelectionBarBottomAnchor];  // 搜索栏已移除 → 选择栏落回安全区底（不再堆叠）
    }
    [self updateJumpButtonBottomAnchor];        // 向下钮落回 选择栏/replyBar 顶（搜索栏已移除）
    self.searchState = nil;   // 整袋释放
    [self.tableView reloadData];   // 清掉气泡内命中词高亮
}

/// 搜索期间把消息表底边从「replyBar 顶」换成「屏幕底」：表的 backgroundView（聊天壁纸）随表铺到底，
/// 隐藏输入栏后其原区域不再露出 self.view 的白底（systemBackground）——底部玻璃钮真正浮在壁纸上。
/// 退出时 restoreTableBottom 恢复原约束。（此前用「另插一层全屏壁纸」遮，未能覆盖该区域，改为收敛到单机制。）
- (void)extendTableToScreenBottom {
    NSLayoutConstraint *orig = nil;
    for (NSLayoutConstraint *c in self.view.constraints) {
        if (c.firstItem == self.tableView && c.firstAttribute == NSLayoutAttributeBottom) { orig = c; break; }
    }
    if (!orig) { return; }
    self.searchState.searchSavedTableBottom = orig;
    orig.active = NO;
    self.searchState.searchTableBottom = [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    self.searchState.searchTableBottom.active = YES;
    UIEdgeInsets ci = self.tableView.contentInset;
    self.searchState.savedBottomInset = ci.bottom;   // 记原始底，键盘观察者在此基础上叠导航条+键盘让位
    ci.bottom = self.searchState.savedBottomInset + kIMSearchNavBarH + 8;
    self.tableView.contentInset = ci;
}

- (void)restoreTableBottom {
    if (!self.searchState.searchTableBottom) { return; }
    self.searchState.searchTableBottom.active = NO; self.searchState.searchTableBottom = nil;
    // 无脑重激活「搜索前活着的那根 table.bottom」——它在两条路径下都自动对：
    //   ① 未多选：就是原「表底=replyBar 顶」，激活它=还原默认；
    //   ② 已多选：就是 selectionState.tableBottom（=表底→屏幕底），激活它=接管到多选自己的表底约束。
    // 上一版曾在 selecting 时跳过激活以为要交给 extendTableBottomForSelection 接管，但那函数开头
    // `if (selectionState.tableBottom) return;` 早退，导致表底"全无激活约束→列表被挤没高度不见了"(regression)。
    self.searchState.searchSavedTableBottom.active = YES;
    self.searchState.searchSavedTableBottom = nil;
    UIEdgeInsets ci = self.tableView.contentInset;
    ci.bottom = self.searchState.savedBottomInset;   // 恢复进搜索前的原始底（键盘让位一并清除）
    self.tableView.contentInset = ci;
    UIEdgeInsets si = self.tableView.verticalScrollIndicatorInsets;
    si.bottom = self.searchState.savedBottomInset;
    self.tableView.verticalScrollIndicatorInsets = si;
}

/// 隐藏注入的聊天标题栏（IMLiquidNavigationBar，非本搜索栏）：磨砂搜索栏后面才不会透出会话名/返回/信息钮。
- (void)hideInjectedBar {
    for (UIView *v in self.view.subviews) {
        if (v != self.searchState.searchTopBar && [v isKindOfClass:[IMLiquidNavigationBar class]]) {
            self.searchState.hiddenInjectedBar = v; v.hidden = YES; return;
        }
    }
}

#pragma mark - 顶部搜索栏（自持 IMLiquidNavigationBar · searchMode）

- (void)buildSearchTopBar {
    IMLiquidNavigationBar *bar = [[IMLiquidNavigationBar alloc] initWithTitle:@"" subtitle:@"" actionTitle:@"取消"];
    bar.delegate = (id<IMLiquidNavigationBarDelegate>)self;
    bar.hostExtraTopInset = kIMLiquidBarHeight;   // 内容落在与注入栏同款的标题行
    // 不设 opaqueProgress：保持与标题栏同款**磨砂**背景（注入栏已单独隐藏，无需靠不透光遮挡）。
    bar.tintColor = IMTheme.accent;                // 「取消」用主题色
    bar.searchPlaceholder = @"搜索聊天记录";
    bar.searchModeActive = YES;
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar];
    self.searchState.searchTopBar = bar;

    UISearchTextField *tf = bar.searchTextField;
    tf.tintColor = IMTheme.accent;
    [tf addTarget:self action:@selector(searchTextChanged) forControlEvents:UIControlEventEditingChanged];
    self.searchState.searchField = tf;

    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    ]];
}

// IMLiquidNavigationBarDelegate：右侧「取消」→ 退出搜索；左/返回态在搜索模式已隐藏，兜底同样退出。
- (void)liquidNavigationBarDidTapAction:(IMLiquidNavigationBar *)bar { [self endInChatSearch]; }
- (void)liquidNavigationBarDidTapLeft:(IMLiquidNavigationBar *)bar { [self endInChatSearch]; }
- (void)liquidNavigationBarDidTapBack:(IMLiquidNavigationBar *)bar { [self endInChatSearch]; }

#pragma mark - 底部命中导航条（无背景 · 玻璃钮浮起 · 计数独立玻璃胶囊）

- (UIButton *)searchGlassButtonSymbol:(NSString *)symbol action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    UIButtonConfiguration *cfg = IMGlassButtonConfiguration();
    cfg.image = [UIImage systemImageNamed:symbol];
    cfg.baseForegroundColor = IMTheme.textPrimary;
    cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    b.configuration = cfg;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [b.widthAnchor constraintEqualToConstant:36],
        [b.heightAnchor constraintEqualToConstant:36],
    ]];
    return b;
}

- (UIView *)buildCountPill {
    UIVisualEffectView *pill = IMGlassEffectView(NO);
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.layer.cornerRadius = 16;
    pill.layer.cornerCurve = kCACornerCurveContinuous;
    pill.clipsToBounds = YES;
    UILabel *lbl = [UILabel new];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    lbl.textColor = IMTheme.textPrimary;
    [pill.contentView addSubview:lbl];
    [NSLayoutConstraint activateConstraints:@[
        [lbl.leadingAnchor constraintEqualToAnchor:pill.contentView.leadingAnchor constant:12],
        [lbl.trailingAnchor constraintEqualToAnchor:pill.contentView.trailingAnchor constant:-12],
        [lbl.topAnchor constraintEqualToAnchor:pill.contentView.topAnchor constant:6],
        [lbl.bottomAnchor constraintEqualToAnchor:pill.contentView.bottomAnchor constant:-6],
    ]];
    self.searchState.searchCountLabel = lbl;
    return pill;
}

- (void)buildSearchNavBar {
    UIView *nav = [UIView new];   // 无背景：玻璃钮/胶囊各自浮在聊天上
    nav.translatesAutoresizingMaskIntoConstraints = NO;
    nav.backgroundColor = UIColor.clearColor;

    UIButton *cal = [self searchGlassButtonSymbol:@"calendar" action:@selector(searchCalTapped)];
    self.searchState.searchCalButton = cal;
    [nav addSubview:cal];

    UIButton *from = [self searchGlassButtonSymbol:@"person" action:@selector(searchFromTapped)];
    self.searchState.searchFromButton = from;
    from.hidden = !self.isGroupChat; // 「来自」仅群聊
    [nav addSubview:from];

    UIView *pill = [self buildCountPill];
    self.searchState.searchCountPill = pill;
    [nav addSubview:pill];

    UIButton *prev = [self searchGlassButtonSymbol:@"chevron.up" action:@selector(searchPrevTapped)];
    UIButton *next = [self searchGlassButtonSymbol:@"chevron.down" action:@selector(searchNextTapped)];
    self.searchState.searchPrevButton = prev; self.searchState.searchNextButton = next;
    [nav addSubview:prev]; [nav addSubview:next];

    [self.view addSubview:nav];
    self.searchState.searchNavBar = nav;
    self.searchState.searchNavBottom = [nav.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [nav.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [nav.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.searchState.searchNavBottom,
        [nav.heightAnchor constraintEqualToConstant:kIMSearchNavBarH],
        [cal.leadingAnchor constraintEqualToAnchor:nav.leadingAnchor constant:16],
        [cal.centerYAnchor constraintEqualToAnchor:nav.centerYAnchor],
        [from.leadingAnchor constraintEqualToAnchor:cal.trailingAnchor constant:10],
        [from.centerYAnchor constraintEqualToAnchor:nav.centerYAnchor],
        [next.trailingAnchor constraintEqualToAnchor:nav.trailingAnchor constant:-16],
        [next.centerYAnchor constraintEqualToAnchor:nav.centerYAnchor],
        [prev.trailingAnchor constraintEqualToAnchor:next.leadingAnchor constant:-10],
        [prev.centerYAnchor constraintEqualToAnchor:nav.centerYAnchor],
        [pill.trailingAnchor constraintEqualToAnchor:prev.leadingAnchor constant:-10],
        [pill.centerYAnchor constraintEqualToAnchor:nav.centerYAnchor],
    ]];
}

#pragma mark - 键盘跟随（底部导航条上移）

- (void)observeSearchKeyboard {
    __weak typeof(self) ws = self;
    self.searchState.searchKbObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardWillChangeFrameNotification
                                                          object:nil queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
        __strong typeof(ws) self = ws;
        if (!self || !self.searchState.searching) { return; }
        CGRect end = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
        CGFloat kbTop = [self.view convertRect:end fromView:nil].origin.y;
        CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - kbTop);
        CGFloat safeBottom = self.view.safeAreaInsets.bottom;
        self.searchState.searchNavBottom.constant = overlap > safeBottom ? -(overlap - safeBottom) : 0;
        // 键盘让位：表格底部 contentInset = 原始底 + 导航条 + 键盘遮挡量——内容整体在键盘之上，
        // 命中/最新消息不被键盘挡（scrollToRow Middle 会按 inset 后的可视区取中）。
        UIEdgeInsets ci = self.tableView.contentInset;
        ci.bottom = self.searchState.savedBottomInset + kIMSearchNavBarH + 8 + overlap;
        self.tableView.contentInset = ci;
        UIEdgeInsets si = self.tableView.verticalScrollIndicatorInsets;
        si.bottom = ci.bottom;
        self.tableView.verticalScrollIndicatorInsets = si;
        NSTimeInterval dur = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
        [UIView animateWithDuration:dur animations:^{ [self.view layoutIfNeeded]; }];
        // 让位后校正可见性（有命中→命中居中不闪；无关键词→贴底浮在键盘上）——**必须等键盘动画结束后**：
        // scrollToAbsoluteBottom 是多轮 layoutIfNeeded+setContentOffset 的重同步滚动，在 willChangeFrame
        // 里同步执行会打断键盘呈现（OnDrag 把它当拖拽收起），实测键盘直接不弹出（2026-08-21 修）。
        __weak typeof(self) wself = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((dur + 0.05) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(wself) self = wself;
            if (!self || !self.searchState.searching) { return; }
            if (self.searchState.searchHits.count > 0) { [self scrollCurrentSearchHitVisible]; }
            else if (self.searchState.searchKeyword.length == 0) { [self scrollToAbsoluteBottom]; }
        });
    }];
}

#pragma mark - 文本输入

- (void)searchTextChanged {
    // 拼音等输入法**组合中**（markedText 未上屏）不重算：否则每敲一个字母列表就跳一次（2026-08-21 修）。
    if (self.searchState.searchField.markedTextRange) { return; }
    // token 被删（字段 ✕ / 退格）→ 取消「来自」过滤、👤 重现。
    if (self.isGroupChat && self.searchState.searchFromButton.hidden && self.searchState.searchField.tokens.count == 0) {
        [self clearFromFilterUI];
    }
    [self recomputeSearchHitsAndJump:YES];
}

#pragma mark - 命中计算 / 导航

- (NSString *)currentSearchKeyword {
    NSString *t = self.searchState.searchField.text ?: @"";
    return [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)recomputeSearchHitsAndJump:(BOOL)jumpToNewest {
    NSString *kw = [self currentSearchKeyword];
    self.searchState.searchKeyword = kw;
    NSString *fromUID = self.searchState.searchFromUID;
    // **查本地库、不扫内存窗口**：分页后 `windowState.messages` 只有当前一窗，扫它等于把
    // 「会话内搜索」悄悄改成「只搜看得见的这 200 条」——功能还在、结果是错的，最难发现的那种。
    __block NSArray<NSNumber *> *hits = @[];
    NSString *convID = self.convID;
    [self performDatabaseOperation:^(IMDatabase *database) {
        hits = [database searchConvSeqsInConv:convID keyword:kw fromUID:fromUID limit:0];
    }];
    self.searchState.searchHits = hits;                 // 升序（DB 查询已保证）
    self.searchState.searchHitIndex = (NSInteger)hits.count - 1; // 默认最新命中
    [self updateSearchNavState];
    [self.tableView reloadData];   // 刷新气泡内命中词高亮（cell 经 searchHighlightKeyword 染色）
    if (jumpToNewest && hits.count > 0) {
        [self jumpToConvSeq:hits.lastObject.longLongValue];
    }
}

/// 把当前命中滚到可视区居中（**不闪烁**）：键盘让位后校正可见性用；显式 ▲▼/默认跳仍走 jumpToConvSeq:（带闪烁）。
- (void)scrollCurrentSearchHitVisible {
    if (self.searchState.searchHits.count == 0) { return; }
    int64_t seq = self.searchState.searchHits[(NSUInteger)MAX(0, self.searchState.searchHitIndex)].longLongValue;
    for (IMMessageModel *m in self.windowState.messages) {
        if (m.convSeq == seq) {
            NSUInteger row = [self visibleRowForMessage:m];
            if (row == NSNotFound) { return; }
            [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]
                                  atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
            return;
        }
    }
}

- (void)updateSearchNavState {
    NSInteger n = (NSInteger)self.searchState.searchHits.count;
    BOOL hasQuery = (self.searchState.searchKeyword.length > 0 || self.searchState.searchFromUID.length > 0);
    if (n == 0) {
        self.searchState.searchCountLabel.text = hasQuery ? @"无匹配" : @"";
        self.searchState.searchCountPill.hidden = !hasQuery;
    } else {
        self.searchState.searchCountPill.hidden = NO;
        self.searchState.searchCountLabel.text = [NSString stringWithFormat:@"第 %ld / %ld 条", (long)(self.searchState.searchHitIndex + 1), (long)n];
    }
    BOOL canPrev = (n > 0 && self.searchState.searchHitIndex > 0);
    BOOL canNext = (n > 0 && self.searchState.searchHitIndex < n - 1);
    self.searchState.searchPrevButton.enabled = canPrev;
    self.searchState.searchNextButton.enabled = canNext;
    self.searchState.searchPrevButton.alpha = canPrev ? 1.0 : 0.4;
    self.searchState.searchNextButton.alpha = canNext ? 1.0 : 0.4;
}

- (void)searchPrevTapped {  // 更旧
    if (self.searchState.searchHitIndex <= 0) { return; }
    self.searchState.searchHitIndex -= 1;
    [self updateSearchNavState];
    [self jumpToConvSeq:self.searchState.searchHits[self.searchState.searchHitIndex].longLongValue];
}

- (void)searchNextTapped {  // 更新
    if (self.searchState.searchHitIndex >= (NSInteger)self.searchState.searchHits.count - 1) { return; }
    self.searchState.searchHitIndex += 1;
    [self updateSearchNavState];
    [self jumpToConvSeq:self.searchState.searchHits[self.searchState.searchHitIndex].longLongValue];
}

#pragma mark - 📅 按日期跳转

/// 日历上「这天有消息」的打点集合。查库——只看当前窗口的话，日历会几乎全灰。
- (NSSet<NSDate *> *)activeDaysFromMessages {
    NSCalendar *cal = [NSCalendar currentCalendar];
    __block NSArray<NSNumber *> *dayStarts = @[];
    NSString *convID = self.convID;
    int64_t offsetMs = (int64_t)NSTimeZone.systemTimeZone.secondsFromGMT * 1000;
    [self performDatabaseOperation:^(IMDatabase *database) {
        dayStarts = [database activeLocalDayStartsInConv:convID utcOffsetMs:offsetMs];
    }];
    NSMutableSet<NSDate *> *days = [NSMutableSet set];
    for (NSNumber *ms in dayStarts) {
        // 再过一次 startOfDayForDate:：SQL 那边是按固定偏移整除分的桶，夏令时下可能差一小时。
        [days addObject:[cal startOfDayForDate:[NSDate dateWithTimeIntervalSince1970:ms.longLongValue / 1000.0]]];
    }
    return days;
}

- (void)searchCalTapped {
    [self.searchState.searchField resignFirstResponder];
    __weak typeof(self) ws = self;
    IMChatDateJumpViewController *vc =
        [[IMChatDateJumpViewController alloc] initWithActiveDays:[self activeDaysFromMessages]
                                                          onPick:^(IMDateJumpKind kind, NSDate *day) {
        [ws handleDateJumpKind:kind day:day];
    }];
    [self presentViewController:vc animated:YES completion:nil];
}

/// 本会话中 timestamp ≥ epochMs 的第一条的 conv_seq（查库，理由同 recomputeSearchHitsAndJump:）。
- (int64_t)firstConvSeqAtOrAfter:(NSTimeInterval)epochMs {
    __block int64_t seq = 0;
    NSString *convID = self.convID;
    [self performDatabaseOperation:^(IMDatabase *database) {
        seq = [database firstConvSeqInConv:convID atOrAfterTimestamp:(int64_t)epochMs];
    }];
    return seq;
}

- (void)handleDateJumpKind:(IMDateJumpKind)kind day:(nullable NSDate *)day {
    NSCalendar *cal = [NSCalendar currentCalendar];
    if (kind == IMDateJumpKindEarliest) {
        // 「跳到最早」= timestamp ≥ 0 的第一条。分页前这里扫内存正好等价（内存就是全部），
        // 分页后会变成"跳到当前窗口最早那条"，也就是原地不动。
        int64_t earliest = [self firstConvSeqAtOrAfter:0];
        if (earliest > 0) { [self jumpToConvSeq:earliest]; }
        return;
    }
    if (kind == IMDateJumpKindToday) {
        NSTimeInterval todayMs = [cal startOfDayForDate:[NSDate date]].timeIntervalSince1970 * 1000.0;
        int64_t seq = [self firstConvSeqAtOrAfter:todayMs];
        if (seq > 0) { [self jumpToConvSeq:seq]; }
        else {
            __block int64_t lastSeq = 0;
            NSString *cid = self.convID;
            [self performDatabaseOperation:^(IMDatabase *database) { lastSeq = [database maxConvSeqForConv:cid]; }];
            if (lastSeq > 0) { [self jumpToConvSeq:lastSeq]; [self im_showToast:@"今天暂无消息，已跳到最近一条"]; }
        }
        return;
    }
    if (!day) { return; }
    NSTimeInterval dayMs = day.timeIntervalSince1970 * 1000.0;
    int64_t seq = [self firstConvSeqAtOrAfter:dayMs];
    if (seq <= 0) { [self im_showToast:@"该日期及之后暂无消息"]; return; }
    [self jumpToConvSeq:seq];
    // 落点是不是用户选的那天：查库拿那一条（跳转可能要等服务端开窗，此刻它未必在内存里）。
    __block IMMessageModel *hit = nil;
    NSString *cid2 = self.convID;
    [self performDatabaseOperation:^(IMDatabase *database) { hit = [database messageInConv:cid2 convSeq:seq]; }];
    if (!hit) { return; }
    NSDate *hitDay = [cal startOfDayForDate:[NSDate dateWithTimeIntervalSince1970:hit.timestamp / 1000.0]];
    if (![cal isDate:hitDay inSameDayAsDate:day]) {
        NSDateFormatter *fmt = [NSDateFormatter new];
        fmt.dateFormat = @"M月d日";
        [self im_showToast:[NSString stringWithFormat:@"该日期无消息，已跳到 %@", [fmt stringFromDate:hitDay]]];
    }
}

#pragma mark - 👤 来自（群内发件人过滤，图标钮开关 + 字段 token）

- (void)searchFromTapped {
    if (self.searchState.searchFromPanel) { [self dismissSearchFromPanel]; return; }
    // 点即插高亮「来自:」token + 显字段 ✕ + 隐藏底部 👤（选人前占位，选中再补名）。
    [self insertFromTokenWithName:nil];
    [self presentSearchFromPanel];
    [self.searchState.searchField becomeFirstResponder];
}

- (void)insertFromTokenWithName:(nullable NSString *)name {
    NSString *text = name.length > 0 ? [NSString stringWithFormat:@"来自:%@", name] : @"来自:";
    UISearchToken *tok = [UISearchToken tokenWithIcon:[UIImage systemImageNamed:@"person.fill"] text:text];
    tok.representedObject = self.searchState.searchFromUID ?: @"";
    self.searchState.searchField.tokens = @[tok];
    // token 与光标间距没有公开 API：给**字段文本**前置一个空格拉开视觉间隔（token 内加空格无效——
    // 空格落在胶囊内部）。currentSearchKeyword 会 trim，不影响命中；清除时在 clearFromFilterUI 剥掉。
    NSString *cur = self.searchState.searchField.text ?: @"";
    if (![cur hasPrefix:@" "]) { self.searchState.searchField.text = [@" " stringByAppendingString:cur]; }
    self.searchState.searchField.clearButtonMode = UITextFieldViewModeAlways; // 字段 ✕ 常显以清 token
    self.searchState.searchFromButton.hidden = YES;
}

- (void)clearFromFilterUI {
    self.searchState.searchFromUID = nil;
    [self dismissSearchFromPanel];
    self.searchState.searchField.tokens = @[];
    NSString *cur = self.searchState.searchField.text ?: @"";
    if ([cur hasPrefix:@" "]) { self.searchState.searchField.text = [cur substringFromIndex:1]; } // 剥掉 token 期间前置的空格
    self.searchState.searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.searchState.searchFromButton.hidden = !self.isGroupChat;
}

/// 「来自」候选 = 本会话**已发过消息**的去重发件人（刻意如此：没发过言的成员过滤后必 0 命中，列出无意义；
/// 2026-08-20 确认维持此逻辑，勿改成全量群成员）。
/// 候选打包 {uid, name, avatar}（名字=备注→昵称→uid，头像走消息表里的发送者头像 URL）。
/// 查库取每人的**最新一条**作代表：只看当前窗口的话，候选会缩成"最近发过言的那几个人"。
- (NSArray<NSDictionary *> *)searchFromCandidates {
    __block NSArray<IMMessageModel *> *samples = @[];
    NSString *convID = self.convID;
    [self performDatabaseOperation:^(IMDatabase *database) {
        samples = [database distinctSenderSamplesInConv:convID limit:0];
    }];
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (IMMessageModel *m in samples) {
        if (m.from.length == 0) { continue; }
        [out addObject:@{ @"uid": m.from,
                          @"name": IMDisplayName([self senderNameForMessage:m], nil),
                          @"avatar": [self senderAvatarURLForMessage:m] ?: @"" }];
    }
    return out;
}

- (void)presentSearchFromPanel {
    NSArray<NSDictionary *> *candidates = [self searchFromCandidates];
    if (candidates.count == 0) { [self im_showToast:@"暂无可筛选的发件人"]; return; }

    // 磨砂透明圆角卡（材质与搜索标题栏协调）：玻璃容器 + 14pt continuous 圆角裁切 + 左右留边浮在聊天上。
    UIVisualEffectView *panel = IMGlassEffectView(NO);
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.layer.cornerRadius = 14;
    panel.layer.cornerCurve = kCACornerCurveContinuous;
    panel.clipsToBounds = YES;

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.showsVerticalScrollIndicator = YES;
    [panel.contentView addSubview:scroll];

    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    for (NSDictionary *cand in candidates) {
        [stack addArrangedSubview:[self searchFromRowForUID:cand[@"uid"] name:cand[@"name"] avatarURL:cand[@"avatar"]]];
    }

    [self.view addSubview:panel];
    self.searchState.searchFromPanel = panel;

    CGFloat rowsH = kIMSearchFromRowH * (CGFloat)MIN((NSInteger)candidates.count, 5);
    [NSLayoutConstraint activateConstraints:@[
        [panel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [panel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [panel.topAnchor constraintEqualToAnchor:self.searchState.searchTopBar.bottomAnchor constant:6],
        [panel.heightAnchor constraintEqualToConstant:rowsH],
        [scroll.topAnchor constraintEqualToAnchor:panel.contentView.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:panel.contentView.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:panel.contentView.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:panel.contentView.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor],
    ]];
}

- (void)dismissSearchFromPanel {
    [self.searchState.searchFromPanel removeFromSuperview];
    self.searchState.searchFromPanel = nil;
}

- (UIControl *)searchFromRowForUID:(NSString *)uid name:(NSString *)name avatarURL:(nullable NSString *)avatarURL {
    UIControl *row = [UIControl new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.accessibilityValue = uid;
    row.accessibilityLabel = name;
    [row addTarget:self action:@selector(searchFromRowTapped:) forControlEvents:UIControlEventTouchUpInside];

    // 头像**复用真实头像逻辑**（UILabel+IMAvatar：先首字母取色底、再异步加载真实头像图，@面板同款）。
    // 首字母居中/字体是宿主 label 的职责（category 只管字符与取色底）——@面板同款配置，漏设会左对齐跑偏。
    UILabel *av = [UILabel new];
    av.translatesAutoresizingMaskIntoConstraints = NO;
    av.textAlignment = NSTextAlignmentCenter;
    av.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    av.textColor = UIColor.whiteColor;
    av.layer.cornerRadius = 18; av.clipsToBounds = YES;
    [av im_setAvatarURL:(avatarURL.length > 0 ? avatarURL : nil) seed:uid displayName:name];

    UILabel *nm = [UILabel new];
    nm.translatesAutoresizingMaskIntoConstraints = NO;
    nm.font = [UIFont systemFontOfSize:15];
    nm.textColor = IMTheme.textPrimary;
    nm.text = name;

    UIView *hair = [UIView new];
    hair.translatesAutoresizingMaskIntoConstraints = NO;
    hair.backgroundColor = IMTheme.separator;

    [row addSubview:av]; [row addSubview:nm]; [row addSubview:hair];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:kIMSearchFromRowH],
        [av.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14],
        [av.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [av.widthAnchor constraintEqualToConstant:36],
        [av.heightAnchor constraintEqualToConstant:36],
        [nm.leadingAnchor constraintEqualToAnchor:av.trailingAnchor constant:11],
        [nm.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14],
        [nm.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [hair.leadingAnchor constraintEqualToAnchor:nm.leadingAnchor],
        [hair.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [hair.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [hair.heightAnchor constraintEqualToConstant:0.5],
    ]];
    return row;
}

- (void)searchFromRowTapped:(UIControl *)row {
    NSString *uid = row.accessibilityValue;
    NSString *name = row.accessibilityLabel;
    if (uid.length == 0) { return; }
    self.searchState.searchFromUID = uid;
    [self insertFromTokenWithName:(name ?: uid)]; // token 补上具体人名
    [self dismissSearchFromPanel];
    [self recomputeSearchHitsAndJump:YES];
}

@end
