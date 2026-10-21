//  IMConversationListViewController+Folders.m
//  会话列表的「聊天文件夹」部分：Tab 条（表格首个 section header，吸顶）、横滑切换与行滑动的冲突判定、
//  长按菜单「添加到文件夹 / 移出」、Tab 长按菜单。设计 IMServer/docs/design/CHAT_FOLDERS_DESIGN.md §4。
//  状态在 `+Private.h` 的类扩展里（selectedFolderID / displayedConversations / folderTabs …）。

#import "IMPopoverCard.h"
#import "IMConversationListViewController+Private.h"
#import "IMChatFolderStore.h"
#import "IMChatFolderLogic.h"
#import "IMChatFolderTabsView.h"
#import "IMChatFolderEditViewController.h"
#import "IMConversation.h"
#import "IMMenuAction.h"
#import "IMLocalization.h"
#import "UIViewController+IMToast.h"

/// 记录触摸起点的横滑识别器（聊天文件夹 Tab 切换）。起点必须在**触摸按下时**就拿到：
/// UITableView 的行滑动在 pan 开始移动时才向代理要按钮配置，那时 gesture 的 location 已不是起点。
@interface IMFolderSwipePanRecognizer : UIPanGestureRecognizer
@property (nonatomic, assign) CGPoint startPoint;
@end

@implementation IMFolderSwipePanRecognizer
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    UITouch *t = touches.anyObject;
    if (t && self.view) { self.startPoint = [t locationInView:self.view]; }
}
@end

@implementation IMConversationListViewController (Folders)


/// 行滑动按钮组展开宽度的估计（最多 4 个，每个约 74pt）：只用于算尾部区域，实际取 min(它, 列表宽 40%)。
static CGFloat const kIMRowActionsWidthEstimate = 4 * 74;
/// 横滑超过这个位移才切 Tab（≈ Android 72dp 阈值）。
static CGFloat const kIMFolderSwipeThreshold = 64;

- (void)setUpFolderTabs {
    __weak typeof(self) ws = self;
    self.folderHeaderShown = IMChatFolderStore.shared.folders.count > 0;
    self.folderTabs = [[IMChatFolderTabsView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, kIMChatFolderTabsHeight)];
    self.folderTabs.onSelect = ^(NSInteger index) { [ws selectTabIndex:index]; };
    self.folderTabs.onLongPressFolder = ^(NSInteger folderIndex, CGRect rect) {
        if (ws.listEditing) { return; } // 编辑模式：Tab 只用来切换范围，长按菜单关闭
        [ws presentTabMenuForFolderIndex:folderIndex sourceRect:rect];
    };

    self.folderPan = [[IMFolderSwipePanRecognizer alloc] initWithTarget:self action:@selector(folderPanChanged:)];
    self.folderPan.delegate = self;
    self.folderPan.maximumNumberOfTouches = 1;
    self.folderPan.cancelsTouchesInView = NO;
    [self.tableView addGestureRecognizer:self.folderPan];
}

/// 数据变化后重绘 Tab 条（角标 / 名称 / 选中项）。
- (void)refreshFolderTabs {
    if (!self.folderTabs) { return; }
    NSArray<IMChatFolder *> *folders = IMChatFolderStore.shared.folders;
    NSInteger idx = [IMChatFolderLogic indexOfFolderID:self.selectedFolderID inFolders:folders] + 1; // -1 → 0 = 全部
    [self.folderTabs configureWithFolders:folders conversations:self.conversations selectedIndex:idx];
}

/// 文件夹整表变化：过滤结果 + Tab 条跟着变；Tab 条出现 / 消失要重载表格（section header 高度变了）；
/// 只是少了几行（从当前文件夹移出）时做行删除动画。
- (void)onFoldersChanged {
    if (!self.isViewLoaded) { return; }
    NSArray<IMConversation *> *old = self.displayedConversations;
    NSString *oldFolder = self.selectedFolderID;
    [self rebuildDisplayedConversations];
    [self refreshListIndicators]; // 空态 + Tab 条
    BOOL shouldShow = IMChatFolderStore.shared.folders.count > 0;
    BOOL sameScope = (oldFolder.length == 0 && self.selectedFolderID.length == 0) || [oldFolder isEqualToString:self.selectedFolderID];
    if (!sameScope) { [self editingScopeDidChange]; } // 当前 Tab 被删 / 回落「全部」：选择集清空（保持编辑）
    else { [self editingDataDidChange]; } // 同范围内成员变化（他端把会话移出当前文件夹）：剔除已看不见的已选项
    if (shouldShow != self.folderHeaderShown || !sameScope || !self.view.window) {
        self.folderHeaderShown = shouldShow;
        [self.tableView reloadData];
        return;
    }
    NSArray<IMConversation *> *now = self.displayedConversations;
    if (now.count < old.count) { // 是否是 old 的保序子序列 → 动画删行
        NSMutableArray<NSIndexPath *> *gone = [NSMutableArray array];
        NSUInteger j = 0;
        for (NSUInteger i = 0; i < old.count; i++) {
            if (j < now.count && now[j] == old[i]) { j++; }
            else { [gone addObject:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]]; }
        }
        if (j == now.count && (NSInteger)gone.count == (NSInteger)(old.count - now.count)) {
            [self.tableView performBatchUpdates:^{
                [self.tableView deleteRowsAtIndexPaths:gone withRowAnimation:UITableViewRowAnimationAutomatic];
            } completion:nil];
            return;
        }
    }
    [self refreshVisibleRowsOrReload];
}

#pragma mark Tab 切换

- (NSInteger)currentTabIndex {
    return [IMChatFolderLogic indexOfFolderID:self.selectedFolderID inFolders:IMChatFolderStore.shared.folders] + 1;
}

- (void)selectTabIndex:(NSInteger)index {
    NSArray<IMChatFolder *> *folders = IMChatFolderStore.shared.folders;
    index = MAX(0, MIN(index, (NSInteger)folders.count));
    NSString *newID = index == 0 ? nil : folders[(NSUInteger)index - 1].folderID;
    if ((newID == nil && self.selectedFolderID.length == 0) || [newID isEqualToString:self.selectedFolderID]) {
        [self.folderTabs setSelectedIndex:index animated:YES];
        return;
    }
    // 每个 Tab 记住自己的滚动位置（设计 §4.3）。
    self.folderScrollOffsets[self.selectedFolderID ?: @""] = [NSValue valueWithCGPoint:self.tableView.contentOffset];
    self.selectedFolderID = newID;
    [self rebuildDisplayedConversations];
    [self refreshListIndicators];
    [self editingScopeDidChange]; // 编辑中切 Tab：清空选择、保持编辑
    [self.folderTabs setSelectedIndex:index animated:YES];
    // 切换动画：只淡入表格内容（吸顶的 Tab 条是 section header，随表格走，不宜整体横移）。
    CATransition *fade = [CATransition animation];
    fade.type = kCATransitionFade;
    fade.duration = 0.16;
    [self.tableView.layer addAnimation:fade forKey:@"folderSwitch"];
    [self.tableView reloadData];
    NSValue *saved = self.folderScrollOffsets[newID ?: @""];
    CGFloat minY = -self.tableView.adjustedContentInset.top;
    CGFloat maxY = MAX(minY, self.tableView.contentSize.height - CGRectGetHeight(self.tableView.bounds) + self.tableView.adjustedContentInset.bottom);
    CGFloat y = saved ? MIN(MAX(saved.CGPointValue.y, minY), maxY) : minY;
    [self.tableView setContentOffset:CGPointMake(0, y) animated:NO];
}

#pragma mark 横滑手势（与行滑动按钮的冲突判定，设计 §4.3）

/// 向左滑、起手在尾部区域之外、且还有下一个 Tab → 这一滑属于 Tab 切换，行按钮不应出现。
- (BOOL)leftSwipeBelongsToTabsAtStartX:(CGFloat)startX {
    if (self.rowSwipeOpen || IMChatFolderStore.shared.folders.count == 0) { return NO; }
    NSInteger idx = [self currentTabIndex];
    BOOL hasNext = idx < (NSInteger)IMChatFolderStore.shared.folders.count;
    return [IMChatFolderLogic swipeOutcomeForTranslationX:-kIMFolderSwipeThreshold startX:startX
                                                listWidth:CGRectGetWidth(self.tableView.bounds)
                                             actionsWidth:kIMRowActionsWidthEstimate
                                                  hasNext:hasNext hasPrev:idx > 0 rowOpen:NO]
        == IMChatFolderSwipeOutcomeNextTab;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gr {
    if (gr != self.folderPan) { return YES; }
    if (self.listEditing || IMChatFolderStore.shared.folders.count == 0 || self.rowSwipeOpen) { return NO; } // 编辑模式：左右滑切 Tab 关闭
    CGPoint v = [self.folderPan velocityInView:self.tableView];
    if (fabs(v.x) < fabs(v.y) * 1.5) { return NO; } // 竖向为主：交给列表滚动
    NSInteger idx = [self currentTabIndex];
    IMChatFolderSwipeOutcome o = [IMChatFolderLogic swipeOutcomeForTranslationX:(v.x < 0 ? -kIMFolderSwipeThreshold : kIMFolderSwipeThreshold)
                                                                         startX:[self folderSwipeStartX]
                                                                      listWidth:CGRectGetWidth(self.tableView.bounds)
                                                                   actionsWidth:kIMRowActionsWidthEstimate
                                                                        hasNext:idx < (NSInteger)IMChatFolderStore.shared.folders.count
                                                                        hasPrev:idx > 0 rowOpen:NO];
    return o == IMChatFolderSwipeOutcomeNextTab || o == IMChatFolderSwipeOutcomePrevTab;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return gr == self.folderPan; // 不挡表格自己的滚动 / 行滑动识别
}

- (void)folderPanChanged:(UIPanGestureRecognizer *)pan {
    if (pan.state != UIGestureRecognizerStateEnded) { return; }
    CGFloat tx = [pan translationInView:self.tableView].x;
    CGFloat vx = [pan velocityInView:self.tableView].x;
    if (fabs(tx) < kIMFolderSwipeThreshold && fabs(vx) > 600) { tx = vx < 0 ? -kIMFolderSwipeThreshold : kIMFolderSwipeThreshold; }
    NSInteger idx = [self currentTabIndex];
    IMChatFolderSwipeOutcome o = [IMChatFolderLogic swipeOutcomeForTranslationX:(fabs(tx) < kIMFolderSwipeThreshold ? 0 : tx)
                                                                         startX:[self folderSwipeStartX]
                                                                      listWidth:CGRectGetWidth(self.tableView.bounds)
                                                                   actionsWidth:kIMRowActionsWidthEstimate
                                                                        hasNext:idx < (NSInteger)IMChatFolderStore.shared.folders.count
                                                                        hasPrev:idx > 0 rowOpen:self.rowSwipeOpen];
    if (o == IMChatFolderSwipeOutcomeNextTab) { [self selectTabIndex:idx + 1]; }
    else if (o == IMChatFolderSwipeOutcomePrevTab) { [self selectTabIndex:idx - 1]; }
}

- (void)tableView:(UITableView *)tableView willBeginEditingRowAtIndexPath:(NSIndexPath *)indexPath { self.rowSwipeOpen = YES; }
- (void)tableView:(UITableView *)tableView didEndEditingRowAtIndexPath:(nullable NSIndexPath *)indexPath { self.rowSwipeOpen = NO; }

#pragma mark Section header = Tab 条（plain 样式自带吸顶）

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return IMChatFolderStore.shared.folders.count > 0 ? self.folderTabs : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return IMChatFolderStore.shared.folders.count > 0 ? kIMChatFolderTabsHeight : CGFLOAT_MIN;
}

#pragma mark 长按菜单：添加到文件夹 / 移出（设计 §4.4）

/// 文件夹相关项，**放在菜单第一位**：未入夹 =「添加到文件夹」；已入夹 =「从「X」移出」排第一（多夹时「从文件夹移出 ›」），
/// 其后仍保留「添加到文件夹」以便再放进别的夹。
- (NSArray<IMMenuAction *> *)folderMenuActionsFor:(IMConversation *)c {
    IMChatFolderStore *store = IMChatFolderStore.shared;
    if (c.convID.length == 0) { return @[]; }
    __weak typeof(self) ws = self;
    NSMutableArray<IMMenuAction *> *out = [NSMutableArray array];
    NSArray<IMChatFolder *> *containing = [store foldersContainingConv:c.convID];

    IMChatFolder *current = [self selectedFolder];
    if (current && [current containsConv:c.convID]) {
        NSString *title = IMLocalizedFormat(@"folder.menu.remove_from", current.name);
        [out addObject:[IMMenuAction actionWithId:@"folderRemove" title:title image:@"folder.badge.minus" handler:^{
            [ws setConversation:c inFolder:current member:NO];
        }]];
    } else if (containing.count == 1) {
        IMChatFolder *only = containing.firstObject;
        [out addObject:[IMMenuAction actionWithId:@"folderRemove" title:IMLocalizedFormat(@"folder.menu.remove_from", only.name)
                                            image:@"folder.badge.minus" handler:^{
            [ws setConversation:c inFolder:only member:NO];
        }]];
    } else if (containing.count > 1) {
        NSMutableArray<IMMenuAction *> *kids = [NSMutableArray array];
        for (IMChatFolder *f in containing) {
            [kids addObject:[IMMenuAction actionWithId:[@"folderRemove." stringByAppendingString:f.folderID] title:f.name
                                                 image:nil handler:^{ [ws setConversation:c inFolder:f member:NO]; }]];
        }
        [out addObject:[IMMenuAction submenuWithId:@"folderRemove" title:IMLocalized(@"folder.menu.remove_from_multi")
                                             image:@"folder.badge.minus" children:kids]];
    }

    if (store.folders.count == 0) { // 还没有任何文件夹：不展开二级，直接弹新建输入框
        [out addObject:[IMMenuAction actionWithId:@"folderAdd" title:IMLocalized(@"folder.menu.add") image:@"folder.badge.plus" handler:^{
            [ws presentCreateFolderAlertForConversation:c];
        }]];
        return out;
    }
    NSMutableArray<IMMenuAction *> *kids = [NSMutableArray array];
    for (IMChatFolder *f in store.folders) {
        BOOL has = [f containsConv:c.convID];
        BOOL full = !has && (NSInteger)f.convIDs.count >= store.maxConvs;
        NSString *title = full ? [NSString stringWithFormat:@"%@ · %@", f.name,
                                  IMLocalizedFormat(@"folder.menu.full", (long)store.maxConvs)] : f.name;
        [kids addObject:[IMMenuAction actionWithId:[@"folderToggle." stringByAppendingString:f.folderID] title:title
                                             image:(has ? @"checkmark" : nil) handler:^{
            [ws setConversation:c inFolder:f member:!has];
        }]];
    }
    BOOL maxed = (NSInteger)store.folders.count >= store.maxFolders;
    NSString *newTitle = maxed ? [NSString stringWithFormat:@"%@ · %@", IMLocalized(@"folder.menu.new"),
                                  IMLocalizedFormat(@"folder.menu.max_reached", (long)store.maxFolders)]
                               : IMLocalized(@"folder.menu.new");
    [kids addObject:[IMMenuAction actionWithId:@"folderNew" title:newTitle image:@"plus" handler:^{
        if (maxed) { [ws im_showToast:IMLocalized(@"err.300301")]; return; }
        [ws presentCreateFolderAlertForConversation:c];
    }]];
    [out addObject:[IMMenuAction submenuWithId:@"folderAdd" title:IMLocalized(@"folder.menu.add")
                                         image:@"folder" children:kids]];
    return out;
}

/// 把会话放进 / 移出某文件夹（服务端权威：成功后整表替换，列表随通知刷新）。
- (void)setConversation:(IMConversation *)c inFolder:(IMChatFolder *)folder member:(BOOL)member {
    if (member && (NSInteger)folder.convIDs.count >= IMChatFolderStore.shared.maxConvs && ![folder containsConv:c.convID]) {
        [self im_showToast:IMLocalized(@"err.300302")];
        return;
    }
    __weak typeof(self) ws = self;
    NSString *name = folder.name;
    [IMChatFolderStore.shared changeConvsInFolder:folder.folderID
                                              add:member ? @[c.convID] : @[]
                                           remove:member ? @[] : @[c.convID]
                                       completion:^(NSError *error) {
        if (error) { [ws im_showToast:[IMChatFolderStore userMessageForError:error]]; return; }
        [ws im_showToast:IMLocalizedFormat(member ? @"folder.toast.added" : @"folder.toast.removed", name)];
    }];
}

/// 「新建文件夹…」：输入名称，创建后直接把该会话放进去。
- (void)presentCreateFolderAlertForConversation:(IMConversation *)c {
    IMChatFolderStore *store = IMChatFolderStore.shared;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:IMLocalized(@"folder.edit.title_create")
        message:IMLocalizedFormat(@"folder.new.message", c.displayName) preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = IMLocalized(@"folder.edit.name_placeholder");
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    __weak typeof(self) ws = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.create") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *name = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        // 服务端按字符（rune）计长；NSString.length 是 UTF-16 单元，emoji 占 2，会把合法名称误拒。
        NSInteger runes = (NSInteger)([name lengthOfBytesUsingEncoding:NSUTF32StringEncoding] / 4);
        if (name.length == 0 || runes > store.maxNameLength) {
            [ws im_showToast:IMLocalized(@"err.300303")];
            return;
        }
        [store createFolderNamed:name convIDs:@[c.convID] completion:^(IMChatFolder *folder, NSError *error) {
            if (error) { [ws im_showToast:[IMChatFolderStore userMessageForError:error]]; return; }
            [ws im_showToast:IMLocalizedFormat(@"folder.toast.created", name)];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark Tab 长按菜单：编辑 / 删除

- (void)presentTabMenuForFolderIndex:(NSInteger)folderIndex sourceRect:(CGRect)rect {
    NSArray<IMChatFolder *> *folders = IMChatFolderStore.shared.folders;
    if (folderIndex < 0 || folderIndex >= (NSInteger)folders.count) { return; }
    IMChatFolder *folder = folders[(NSUInteger)folderIndex];
    __weak typeof(self) ws = self;
    NSArray<IMPopoverCardItem *> *items = @[
        [IMPopoverCardItem itemWithTitle:IMLocalized(@"folder.tab.menu_edit") symbol:@"pencil" destructive:NO handler:^{
            IMChatFolderEditViewController *vc = [[IMChatFolderEditViewController alloc] initWithFolderID:folder.folderID
                                                                                                     host:ws.host token:ws.token userID:ws.userID];
            [ws.navigationController pushViewController:vc animated:YES];
        }],
        [IMPopoverCardItem itemWithTitle:IMLocalized(@"folder.tab.menu_delete") symbol:@"trash" destructive:YES handler:^{
            [ws confirmDeleteFolder:folder];
        }],
    ];
    // 锚点：该 Tab 在本页 view 坐标系内的矩形，菜单贴在其正下方（与 Android / Web 一致，不再是底部 ActionSheet）。
    CGRect anchor = [self.folderTabs convertRect:rect toView:self.view];
    [IMPopoverCard presentFromRect:anchor inHostView:self.view items:items];
}

- (void)confirmDeleteFolder:(IMChatFolder *)folder {
    __weak typeof(self) ws = self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
        message:IMLocalizedFormat(@"folder.edit.delete_confirm", folder.name) preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [IMChatFolderStore.shared deleteFolder:folder.folderID completion:^(NSError *error) {
            if (error) { [ws im_showToast:[IMChatFolderStore userMessageForError:error]]; }
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}


- (CGFloat)folderSwipeStartX {
    return [(IMFolderSwipePanRecognizer *)self.folderPan startPoint].x;
}

@end
