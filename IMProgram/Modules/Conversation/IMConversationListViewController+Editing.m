//  IMConversationListViewController+Editing.m
//  会话列表的「编辑模式」：左上角「编辑 / 完成」→ 行首勾选圈 + 底部选择栏（全选 / 已读 / 删除），批量设为已读与批量删除。
//  设计 IMServer/docs/design/CONV_LIST_EDIT_MODE_DESIGN.md + sketches/CONV_LIST_EDIT_MODE_UX_SKETCH.html。
//  状态在 `+Private.h` 的类扩展里：listEditing / editSelection（IMConversationSelection）/ editBar（IMConversationEditBar）。
//  行勾选走系统多选编辑态（tableView.setEditing + allowsMultipleSelectionDuringEditing），真相记在 editSelection，
//  reloadData 之后在 willDisplayCell 里按选择集补选行（同聊天多选）。

#import "IMConversationListViewController+Private.h"
#import "IMConversation.h"
#import "IMConversationSelection.h"
#import "IMConversationEditBar.h"
#import "IMBatchRunner.h"
#import "IMMainTabBarController.h" // im_refreshNavigationBar（注入式液态标题栏不监听 navigationItem）
#import "IMDatabase.h"
#import "IMHTTPService.h"
#import "IMSocketManager.h"
#import "IMTheme.h"
#import "IMLocalization.h"
#import "UIViewController+IMToast.h"

/// 批量请求同时在途的上限（设计 §4）。
static NSUInteger const kIMConvBatchConcurrency = 4;

@implementation IMConversationListViewController (Editing)

#pragma mark - 入口与标题

- (NSString *)currentListTitle {
    NSUInteger n = self.listEditing ? self.editSelection.count : 0;
    return n > 0 ? IMLocalizedFormat(@"conv.edit.selected_count", (long)n) : IMLocalized(@"ios.tab.messages");
}

- (void)refreshEditEntry {
    if (!self.isViewLoaded) { return; }
    SEL want = self.listEditing ? @selector(doneTapped) : (self.displayedConversations.count > 0 ? @selector(editTapped) : NULL);
    UIBarButtonItem *cur = self.navigationItem.leftBarButtonItem;
    if ((cur == nil && want == NULL) || (cur != nil && cur.action == want)) { return; }
    if (want == NULL) {
        self.navigationItem.leftBarButtonItem = nil;
    } else {
        // 必须用**带标题**的 item：统一 Liquid 标题栏按 leftTitle 渲染左位文字并把点击路由到本 item（同聊天多选「取消」）。
        NSString *title = IMLocalized(self.listEditing ? @"common.done" : @"common.edit");
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStylePlain
                                                                                target:self action:want];
    }
    [self im_refreshNavigationBar];
}

#pragma mark - 进入 / 退出

- (void)editTapped {
    if (self.listEditing) { return; }
    self.listEditing = YES;
    self.editSelection = [IMConversationSelection new];
    self.savedRightItem = self.navigationItem.rightBarButtonItem;
    self.navigationItem.rightBarButtonItem = nil; // 「＋」隐藏
    self.searchContainer.userInteractionEnabled = NO; // 搜索入口置灰
    self.searchContainer.alpha = 0.5;
    [self buildEditBarIfNeeded];
    [self updateEditBarInset];
    self.editBar.hidden = NO;
    self.editBar.alpha = 0;
    self.tableBottomConstraint.active = NO;
    self.tableBottomConstraint = [self.tableView.bottomAnchor constraintEqualToAnchor:self.editBar.topAnchor];
    self.tableBottomConstraint.active = YES;
    [self setTabBarHidden:YES animated:YES];
    self.tableView.allowsMultipleSelectionDuringEditing = YES;
    for (UITableViewCell *c in self.tableView.visibleCells) { [self applyEditSelectionBackgroundToCell:c]; }
    [self.tableView setEditing:YES animated:YES];
    [UIView animateWithDuration:0.25 animations:^{
        self.editBar.alpha = 1;
        [self.view layoutIfNeeded];
    }];
    [self refreshEditEntry];
    [self syncEditUI];
}

- (void)doneTapped { [self exitEditingAnimated:YES]; }

- (void)exitEditingIfNeeded { if (self.listEditing) { [self exitEditingAnimated:NO]; } }

- (void)exitEditingAnimated:(BOOL)animated {
    if (!self.listEditing) { return; }
    self.listEditing = NO;
    self.editSelection = nil;
    [self.tableView setEditing:NO animated:animated];
    self.searchContainer.userInteractionEnabled = YES;
    self.searchContainer.alpha = 1;
    self.navigationItem.rightBarButtonItem = self.savedRightItem;
    self.savedRightItem = nil;
    self.tableBottomConstraint.active = NO;
    self.tableBottomConstraint = [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    self.tableBottomConstraint.active = YES;
    [self setTabBarHidden:NO animated:animated];
    UIView *bar = self.editBar;
    __weak typeof(self) ws = self;
    // 动画被打断（0.25s 内又点了「编辑」）时 finished=NO：此时新一轮编辑已把栏显示出来，不能再藏。
    void (^finish)(BOOL) = ^(BOOL done) { if (ws.listEditing) { return; } bar.hidden = YES; };
    if (animated) {
        [UIView animateWithDuration:0.25 animations:^{ bar.alpha = 0; [self.view layoutIfNeeded]; } completion:finish];
    } else {
        finish(YES);
    }
    self.title = [self currentListTitle];
    [self refreshEditEntry];
    [self im_refreshNavigationBar];
}

/// 编辑中隐藏底部 TabBar（选择栏占它的位置）；iOS 18+ 用官方 API，旧系统直接藏 tabBar。
- (void)setTabBarHidden:(BOOL)hidden animated:(BOOL)animated {
    UITabBarController *tbc = self.tabBarController;
    if (!tbc) { return; }
    if (@available(iOS 18.0, *)) {
        [tbc setTabBarHidden:hidden animated:animated];
    } else {
        tbc.tabBar.hidden = hidden;
    }
}

/// 栏底留白 = 窗口底部安全区（只含 home 条）。不用页面安全区：TabBar 隐藏动画期间页面安全区还含 TabBar 高度，栏会悬空。
- (void)updateEditBarInset {
    UIWindow *w = self.view.window;
    self.editBar.bottomInset = w ? w.safeAreaInsets.bottom : self.view.safeAreaInsets.bottom;
}

- (void)buildEditBarIfNeeded {
    if (self.editBar) { return; }
    IMConversationEditBar *bar = [IMConversationEditBar new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [bar.selectAllButton addTarget:self action:@selector(selectAllTapped) forControlEvents:UIControlEventTouchUpInside];
    [bar.readButton addTarget:self action:@selector(markReadTapped) forControlEvents:UIControlEventTouchUpInside];
    [bar.deleteButton addTarget:self action:@selector(deleteTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:bar];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    self.editBar = bar;
}

#pragma mark - 选择集

/// 标题 + 底栏按钮态同步（每次选择变化 / 数据换新后调用）。
- (void)syncEditUI {
    if (!self.listEditing) { return; }
    NSArray<IMConversation *> *list = self.displayedConversations;
    IMConversationSelection *sel = self.editSelection;
    [self.editBar updateAllSelected:[sel isAllSelectedIn:list] canSelectAll:list.count > 0
                            canRead:[sel hasUnreadIn:list] canDelete:sel.count > 0];
    NSString *title = [self currentListTitle];
    if (![self.title isEqualToString:title]) {
        self.title = title;
        [self im_refreshNavigationBar];
    }
}

- (void)editingDataDidChange {
    if (!self.listEditing) { return; }
    [self.editSelection pruneToExistingIn:self.displayedConversations];
    [self syncEditUI];
}

- (void)editingScopeDidChange {
    if (!self.listEditing) { return; }
    [self.editSelection clear];
    [self syncEditUI];
}

- (void)editingDidToggleRowAtIndexPath:(NSIndexPath *)indexPath selected:(BOOL)selected {
    if (indexPath.row >= (NSInteger)self.displayedConversations.count) { return; }
    NSString *convID = self.displayedConversations[(NSUInteger)indexPath.row].convID;
    if (selected) { [self.editSelection select:convID]; } else { [self.editSelection deselect:convID]; }
    [self syncEditUI];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.listEditing) { [self editingDidToggleRowAtIndexPath:indexPath selected:NO]; }
}

/// 选中行底色 = 主色 16%（比置顶行深，两者才分得清）（覆盖系统默认灰）。进入编辑时已在屏的 cell 不会再走 willDisplayCell，editTapped 里补一遍。
- (void)applyEditSelectionBackgroundToCell:(UITableViewCell *)cell {
    if (cell.multipleSelectionBackgroundView) { return; }
    UIView *bg = [UIView new];
    bg.backgroundColor = [IMTheme.accent colorWithAlphaComponent:0.16];
    cell.multipleSelectionBackgroundView = bg;
}

/// reloadData 之后系统的选中态丢了：按选择集给在屏行补选；选中行底色 = 主色 16%（比置顶行深，两者才分得清）。
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.listEditing || indexPath.row >= (NSInteger)self.displayedConversations.count) { return; }
    [self applyEditSelectionBackgroundToCell:cell];
    BOOL want = [self.editSelection isSelected:self.displayedConversations[(NSUInteger)indexPath.row].convID];
    BOOL has = cell.isSelected; // 不用 indexPathsForSelectedRows：每个 cell 都新建数组 + 线性查找，全选千条会话时滚动是 O(可见×已选)
    if (want && !has) {
        [tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
    } else if (!want && has) {
        [tableView deselectRowAtIndexPath:indexPath animated:NO];
    }
}

- (void)selectAllTapped {
    NSArray<IMConversation *> *list = self.displayedConversations;
    if ([self.editSelection isAllSelectedIn:list]) {
        [self.editSelection clear];
    } else {
        [self.editSelection selectAllIn:list];
    }
    for (NSInteger i = 0; i < (NSInteger)list.count; i++) { // 在屏 + 屏外行一起同步系统选中态
        NSIndexPath *ip = [NSIndexPath indexPathForRow:i inSection:0];
        if ([self.editSelection isSelected:list[(NSUInteger)i].convID]) {
            [self.tableView selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
        } else {
            [self.tableView deselectRowAtIndexPath:ip animated:NO];
        }
    }
    [self syncEditUI];
}

#pragma mark - 批量已读

- (void)markReadTapped {
    NSMutableArray<IMConversation *> *items = [NSMutableArray array];
    for (IMConversation *c in [self.editSelection selectedConversationsIn:self.displayedConversations]) {
        if ([IMConversationSelection conversationHasUnread:c]) { [items addObject:c]; } // 无未读的选中项跳过
    }
    if (items.count == 0) { return; }
    self.editBar.userInteractionEnabled = NO; // 进行中防重入
    __weak typeof(self) ws = self;
    NSString *token = self.token;
    IMConversationSelection *session = self.editSelection; // 本次编辑会话：批量回来时若已退出 / 重新进入，就不动新会话
    [IMBatchRunner forEach:items concurrency:kIMConvBatchConcurrency
        work:^(IMConversation *c, void (^done)(NSError *)) {
            // 与单条「设为已读」同一路径：未读数 → 推进已读位点；手动标未读 → 设置接口清标记（muteUntil 传空，不碰免打扰）。
            if (c.unread > 0) { [IMSocketManager.sharedManager markReadConv:c.convID upToConvSeq:c.latestConvSeq]; }
            if (!c.markedUnread) { done(nil); return; }
            if (token.length == 0) { done([NSError errorWithDomain:@"IMConvEdit" code:-1 userInfo:nil]); return; } // 无登录态：算失败，不假装清掉
            [IMHTTPService.sharedService updateConversationSettingsWithToken:token convID:c.convID
                pinnedAt:c.pinnedAt muted:c.muted muteUntil:nil markedUnread:NO completion:done];
        }
        completion:^(NSArray *succeeded, NSArray *failed) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            [self finishMarkRead:succeeded failed:failed session:session];
        }];
}

- (void)finishMarkRead:(NSArray<IMConversation *> *)succeeded failed:(NSArray<IMConversation *> *)failed session:(IMConversationSelection *)session {
    self.editBar.userInteractionEnabled = YES;
    BOOL sameSession = self.listEditing && self.editSelection == session;
    for (IMConversation *c in succeeded) {
        c.unread = 0;
        c.markedUnread = NO;
    }
    for (IMConversation *c in failed) { c.unread = 0; } // 位点已推进；仅「标未读」没清掉
    NSArray<IMConversation *> *all = [succeeded arrayByAddingObjectsFromArray:failed];
    NSMutableSet<NSString *> *okIDs = [NSMutableSet setWithCapacity:succeeded.count];
    for (IMConversation *c in succeeded) { [okIDs addObject:c.convID]; }
    [self performDatabaseOperation:^(IMDatabase *database) {
        for (IMConversation *c in all) {
            [database markConversationFullyRead:c.convID upToConvSeq:c.latestConvSeq];
            if ([okIDs containsObject:c.convID]) {
                [database applyCachedSettingsForConversation:c.convID pinnedAt:c.pinnedAt muted:c.muted
                                                   muteUntil:c.muteUntil markedUnread:NO];
            }
        }
    }];
    [self refreshListIndicators];
    [self refreshVisibleRowsOrReload];
    [self reload]; // 批量结束后只重拉一次权威列表
    if (failed.count > 0) {
        [self im_showToast:IMLocalized(@"conv.error.mark_failed")];
        if (sameSession) { [self syncEditUI]; } // 失败项保留勾选、留在编辑模式
        return;
    }
    if (sameSession) { [self exitEditingAnimated:YES]; }
}

#pragma mark - 批量删除

/// 删除确认：标题「删除 N 个会话？」+ 正文（同 Android / Web 对话框，同一组文案键）；文件夹 Tab 内追加「同时从全部和所有文件夹消失」。
- (void)deleteTapped:(UIButton *)sender {
    NSUInteger n = self.editSelection.count;
    if (n == 0) { return; }
    NSString *body = IMLocalized(@"conv.edit.delete_body");
    if (self.selectedFolder) { body = [body stringByAppendingString:IMLocalized(@"conv.edit.delete_body_folder")]; }
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:IMLocalizedFormat(@"conv.edit.delete_title", (long)n)
                                                                message:body preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) ws = self;
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.delete") style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) { [ws performBatchDelete]; }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)performBatchDelete {
    NSArray<IMConversation *> *items = [self.editSelection selectedConversationsIn:self.displayedConversations];
    if (items.count == 0 || self.token.length == 0) { return; }
    self.editBar.userInteractionEnabled = NO;
    __weak typeof(self) ws = self;
    NSString *token = self.token;
    IMConversationSelection *session = self.editSelection;
    [IMBatchRunner forEach:items concurrency:kIMConvBatchConcurrency
        work:^(IMConversation *c, void (^done)(NSError *)) {
            [IMHTTPService.sharedService deleteConversationWithToken:token convID:c.convID completion:done];
        }
        completion:^(NSArray *succeeded, NSArray *failed) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            [self finishBatchDelete:succeeded failedCount:failed.count session:session];
        }];
}

- (void)finishBatchDelete:(NSArray<IMConversation *> *)succeeded failedCount:(NSUInteger)failedCount session:(IMConversationSelection *)session {
    self.editBar.userInteractionEnabled = YES;
    BOOL sameSession = self.listEditing && self.editSelection == session;
    NSMutableSet<NSString *> *gone = [NSMutableSet set];
    for (IMConversation *c in succeeded) { [gone addObject:c.convID]; if (sameSession) { [self.editSelection deselect:c.convID]; } }
    if (gone.count > 0) {
        // 取旧位置须在替换数据源之前；按 convID 对（reload 会换掉模型对象，不能按指针找）。
        NSMutableArray<NSIndexPath *> *rows = [NSMutableArray array];
        NSArray<IMConversation *> *old = self.displayedConversations;
        for (NSUInteger i = 0; i < old.count; i++) {
            if ([gone containsObject:old[i].convID]) { [rows addObject:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]]; }
        }
        NSMutableArray<IMConversation *> *remaining = [NSMutableArray array];
        for (IMConversation *c in self.conversations) { if (![gone containsObject:c.convID]) { [remaining addObject:c]; } }
        self.conversations = remaining;
        [self performDatabaseOperation:^(IMDatabase *database) {
            for (NSString *convID in gone) { [database deleteCachedConversation:convID]; }
        }];
        if ((NSInteger)self.displayedConversations.count == [self.tableView numberOfRowsInSection:0] - (NSInteger)rows.count) {
            [self.tableView deleteRowsAtIndexPaths:rows withRowAnimation:UITableViewRowAnimationAutomatic];
        } else {
            [self.tableView reloadData];
        }
        // 服务端仍是最终来源：等删除动画结束后静默拉一次收敛多端同时操作（与单条删除同口径）。
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil];
        [self performSelector:@selector(reload) withObject:nil afterDelay:0.42];
    }
    if (failedCount > 0) {
        [self im_showToast:IMLocalizedFormat(@"conv.edit.delete_failed", (long)failedCount)];
        if (sameSession) { [self syncEditUI]; } // 失败项保留勾选、留在编辑模式，便于重试
        return;
    }
    if (sameSession) { [self exitEditingAnimated:YES]; }
}

@end
