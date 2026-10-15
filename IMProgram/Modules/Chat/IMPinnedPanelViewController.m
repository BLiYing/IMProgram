//  IMPinnedPanelViewController.m
//  布局（PINNED_PANEL_UX_SKETCH ②）：grabber → 自持液态标题栏（左 ✕、标题「置顶消息（N）」居中、副标题仅有权限者）
//  → 列表（聊天壁纸底、聊天真气泡）→ 底栏（**在流内**，高 64 + 安全区，顶 1px 分隔线，「取消所有置顶」胶囊居中，仅有权限者）。
//  点气泡 / 定位圆钮 = 先收起面板再走宿主 jumpToPinnedConvSeq:；长按气泡 = IMPopoverCard（过滤项）。

#import "IMPinnedPanelViewController.h"
#import "IMPinnedPanelLogic.h"
#import "IMMsgOpApply.h"           // IMChatPinnedItemsDroppingSeq
#import "IMPinnedPanelCellFactory.h"
#import "IMPinnedMessage.h"
#import "IMMessageModel.h"
#import "IMDatabase.h"
#import "IMHTTPService.h"
#import "IMChatBackgroundView.h"
#import "IMPopoverCard.h"
#import "IMTheme.h"
#import "IMGlass.h"
#import "IMLog.h"
#import "IMLocalization.h"
#import "UIViewController+IMToast.h"
#import "IMMainTabBarController.h" // kIMLiquidBarHeight
#import "IMProgram-Swift.h"        // IMLiquidNavigationBar

/// ✕ 距 sheet 顶留白（同 IMChatDateJumpViewController / IMFilePickerViewController）。
static const CGFloat kIMPinnedPanelTopPadding = 16;
/// 底栏：高 64（不含安全区），按钮高 44、距栏顶 10（稿 .ios .foot）、左右内边距 22。
static const CGFloat kIMPinnedFooterHeight = 64;
static const CGFloat kIMPinnedFooterButtonHeight = 44;
static const CGFloat kIMPinnedFooterButtonTop = 10;
static const CGFloat kIMPinnedFooterButtonPadding = 22;

@interface IMPinnedPanelViewController () <UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate,
                                           UISheetPresentationControllerDelegate, IMLiquidNavigationBarDelegate>
@property (nonatomic, weak, readwrite, nullable) id<IMPinnedPanelHost> host;
@property (nonatomic, copy, readwrite) NSArray<IMPinnedMessage *> *items;
@property (nonatomic, copy) NSArray<IMPinnedPanelRow *> *rows;
@property (nonatomic, assign) BOOL canUnpin;
@property (nonatomic, assign) BOOL clearing; ///< 「取消所有置顶」请求在途（防连点重复请求）
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) IMLiquidNavigationBar *navBar;
@property (nonatomic, assign) NSTimeInterval blockSheetDismissUntil; // 列表中途滑动 / 滑到顶的余势，不算「下滑关闭」
@property (nonatomic, assign) BOOL titleForcedVisible; // 见 viewDidLayoutSubviews
@property (nonatomic, strong) UIView *footer;
@property (nonatomic, strong) NSLayoutConstraint *tableBottomToFooter;
@property (nonatomic, strong) NSLayoutConstraint *tableBottomToView;
@end

@implementation IMPinnedPanelViewController

- (instancetype)initWithHost:(id<IMPinnedPanelHost>)host items:(NSArray<IMPinnedMessage *> *)items {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _host = host;
        _items = [items copy] ?: @[];
        _canUnpin = [host canPinMessages]; // 取消置顶与置顶同一权限（同一个 pin op，服务端同一份校验）
        _rows = [self buildRows];
        self.modalPresentationStyle = UIModalPresentationPageSheet;
        UISheetPresentationController *sheet = self.sheetPresentationController;
        // 只有「全高」一档：打开即到最高点，下滑到一定距离即关闭，没有中间态。
        sheet.detents = @[UISheetPresentationControllerDetent.largeDetent];
        sheet.prefersGrabberVisible = YES;
        sheet.delegate = self;
    }
    return self;
}

#pragma mark - 视图

- (void)viewDidLoad {
    [super viewDidLoad];
    if (@available(iOS 17.0, *)) { self.traitOverrides.userInterfaceLevel = UIUserInterfaceLevelBase; }
    self.view.backgroundColor = IMTheme.surface;
    [self installLiquidNavigationBar];
    [self installTableView];
    [self installFooter];
    [self applyChrome];
}

- (void)installLiquidNavigationBar {
    UIEdgeInsets insets = self.additionalSafeAreaInsets;
    insets.top = kIMPinnedPanelTopPadding + kIMLiquidBarHeight;
    self.additionalSafeAreaInsets = insets;

    IMLiquidNavigationBar *bar = [[IMLiquidNavigationBar alloc] initStandaloneWithTitle:[self titleText] subtitle:@"" actionTitle:nil];
    bar.delegate = self;
    bar.compactContentProgress = 1; // 自持栏：标题 / 副标题即刻可见（默认 0 = 全透明）
    bar.hostExtraTopInset = kIMLiquidBarHeight;
    bar.backgroundEffectProgress = 0;
    bar.leftImage = [UIImage systemImageNamed:@"xmark"
                            withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17
                                                                                             weight:UIImageSymbolWeightSemibold]];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar];
    self.navBar = bar;
    UIView *hairline = [self hairline];
    [self.view addSubview:hairline];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [hairline.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [hairline.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [hairline.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    ]];
}

- (UIView *)hairline {
    UIView *line = [UIView new];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.backgroundColor = IMTheme.separator;
    [line.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
    return line;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // 已知怪异（根因待查）：自持栏初始化后标题 / 副标题的 alpha 会被某处重置为 0，且 compactContentProgress 仍为 1，
    // 于是 didSet 的 guard 不再触发刷新。此处 0→1 强制过一遍 updateCompactContentVisibility，标题才可见。
    if (self.navBar.compactContentProgress != 1 || !self.titleForcedVisible) {
        self.navBar.compactContentProgress = 0;
        self.navBar.compactContentProgress = 1;
        self.titleForcedVisible = YES;
    }
}

- (void)installTableView {
    UITableView *tv = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.dataSource = self;
    tv.delegate = self;
    tv.separatorStyle = UITableViewCellSeparatorStyleNone;
    tv.allowsSelection = NO;
    tv.rowHeight = UITableViewAutomaticDimension;
    tv.estimatedRowHeight = 72;
    tv.contentInset = UIEdgeInsetsMake(6, 0, 12, 0); // 稿 .list padding 6 / 12
    tv.backgroundView = [IMChatBackgroundView new]; // 列表区 = 当前聊天壁纸（「像聊天页」的关键）
    [IMPinnedPanelCellFactory registerCellsInTableView:tv];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    tap.delegate = self;
    [tv addGestureRecognizer:tap];
    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    press.delegate = self;
    [tv addGestureRecognizer:press];
    [self.view addSubview:tv];
    self.tableView = tv;
    [NSLayoutConstraint activateConstraints:@[
        [tv.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tv.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tv.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    ]];
    self.tableBottomToView = [tv.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
}

/// 底栏占位在流内：列表是其上方的独立滚动区，任何一行都不会被它盖住。高 = 64 + 底部安全区（刘海机共 88）。
- (void)installFooter {
    UIView *footer = [UIView new];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    footer.backgroundColor = IMTheme.surface;
    [self.view addSubview:footer];
    self.footer = footer;
    UIView *line = [self hairline];
    [footer addSubview:line];
    UIButton *button = [self unpinAllButton];
    [footer addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
        [footer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [footer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [footer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [footer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-kIMPinnedFooterHeight],
        [line.topAnchor constraintEqualToAnchor:footer.topAnchor],
        [line.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor],
        [line.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor],
        [button.centerXAnchor constraintEqualToAnchor:footer.centerXAnchor],
        [button.topAnchor constraintEqualToAnchor:footer.topAnchor constant:kIMPinnedFooterButtonTop],
        [button.heightAnchor constraintEqualToConstant:kIMPinnedFooterButtonHeight],
    ]];
    self.tableBottomToFooter = [self.tableView.bottomAnchor constraintEqualToAnchor:footer.topAnchor];
}

/// 「取消所有置顶」胶囊：iOS 26 = Liquid Glass（UIButtonConfiguration glass）；更早 = systemThinMaterial 毛玻璃胶囊。
- (UIButton *)unpinAllButton {
    UIButtonConfiguration *cfg;
    if (@available(iOS 26.0, *)) {
        cfg = IMGlassButtonConfiguration();
    } else {
        cfg = [UIButtonConfiguration plainButtonConfiguration];
        UIVisualEffectView *material = [[UIVisualEffectView alloc] initWithEffect:
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
        cfg.background.customView = material;
        cfg.background.strokeColor = IMTheme.separator;
        cfg.background.strokeWidth = 1.0 / UIScreen.mainScreen.scale;
    }
    cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    cfg.baseForegroundColor = IMTheme.danger;
    cfg.contentInsets = NSDirectionalEdgeInsetsMake(0, kIMPinnedFooterButtonPadding, 0, kIMPinnedFooterButtonPadding);
    NSDictionary *attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold] };
    cfg.attributedTitle = [[NSAttributedString alloc] initWithString:IMLocalized(@"pinned.unpin_all") attributes:attrs];
    UIButton *button = [UIButton buttonWithConfiguration:cfg primaryAction:nil];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button addTarget:self action:@selector(unpinAllTapped) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

/// 标题 / 副标题 / 底栏随集合与权限刷新（权限决定副标题与底栏，见 IMPinnedPanelChromeForPermission）。
- (void)applyChrome {
    IMPinnedPanelChrome chrome = IMPinnedPanelChromeForPermission(self.canUnpin);
    self.navBar.titleText = [self titleText];
    self.navBar.subtitleText = IMLocalized(chrome.showsLongPressHint ? @"pinned.long_press_hint" : @"pinned.long_press_hint_readonly");
    self.footer.hidden = !chrome.showsUnpinAll;
    self.tableBottomToFooter.active = chrome.showsUnpinAll;
    self.tableBottomToView.active = !chrome.showsUnpinAll;
}

- (NSString *)titleText {
    return IMLocalizedFormat(@"pinned.title", (long)self.items.count);
}

#pragma mark - 数据

- (NSArray<IMPinnedPanelRow *> *)buildRows {
    id<IMPinnedPanelHost> host = self.host;
    NSString *convID = host.convID ?: @"";
    return IMPinnedPanelBuildRows(self.items, ^IMMessageModel *(IMPinnedMessage *item) {
        // 兜底顺序 ①本地库行 → ②接口完整对象 → ③类型词（IMPinnedResolveMessage）。
        __block IMMessageModel *local = nil;
        [host performDatabaseOperation:^(IMDatabase *database) {
            local = [database messageInConv:convID convSeq:item.convSeq];
        }];
        return IMPinnedResolveMessage(item, local, convID);
    }, host.userID, ^NSString *(int64_t millis) {
        return [IMTheme dayHeaderStringFromMillis:millis];
    }, ^BOOL(int64_t a, int64_t b) {
        return [IMTheme isMillis:a sameDayAsMillis:b];
    });
}

- (void)applyPinnedItems:(NSArray<IMPinnedMessage *> *)items {
    self.items = items ?: @[];
    self.rows = [self buildRows];
    if (self.isViewLoaded) {
        // 先让表格与 rows 对齐再谈收起：否则 dismiss 动画期间的布局仍按旧行数向数据源要 cell，
        // rows 已空 → objectAtIndex 越界崩溃（别的端「取消所有置顶」时面板开着必现）。
        if (self.rows.count > 0) { [self applyChrome]; }
        [self.tableView reloadData];
    }
    if (self.rows.count == 0) { // 集合为空（最后一条被取消 / 撤回）：自动收起
        if (self.presentingViewController && !self.isBeingDismissed) { [self dismissViewControllerAnimated:YES completion:nil]; }
    }
}

- (void)unpinConvSeq:(int64_t)convSeq {
    if (!self.canUnpin || convSeq <= 0) { return; }
    [self.host pinnedPanel:self unpinConvSeq:convSeq];
    // 只摘所长按那条（可逆、不确认），本地先淡出；msg_op 回来后宿主重拉对齐。
    NSArray<IMPinnedMessage *> *kept = IMChatPinnedItemsDroppingSeq(self.items, convSeq);
    [self applyPinnedItems:kept];
    [self.host pinnedPanel:self didChangeItems:kept];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ((NSUInteger)indexPath.row >= self.rows.count) { // 防御：rows 与表格瞬时不同步时给空白 cell，绝不越界
        return [IMPinnedPanelCellFactory dayPillCellWithText:@"" tableView:tableView indexPath:indexPath];
    }
    IMPinnedPanelRow *row = self.rows[(NSUInteger)indexPath.row];
    if (row.dayHeader.length > 0) {
        return [IMPinnedPanelCellFactory dayPillCellWithText:row.dayHeader tableView:tableView indexPath:indexPath];
    }
    __weak typeof(self) ws = self;
    int64_t seq = row.item.convSeq;
    return [IMPinnedPanelCellFactory messageCellForMessage:row.message mine:row.mine host:self.host
                                                 tableView:tableView indexPath:indexPath
                                                  onLocate:^{ [ws locateConvSeq:seq]; }
                                            onLayoutChange:^{ [ws refreshRowHeights]; }];
}

/// 异步内容（媒体尺寸 / 链接预览）回来：无动画刷行高；滚动中不打断（下次停下自然会量对）。
- (void)refreshRowHeights {
    if (self.tableView.isDragging || self.tableView.isDecelerating) { return; }
    [UIView performWithoutAnimation:^{
        [self.tableView beginUpdates];
        [self.tableView endUpdates];
    }];
}

#pragma mark - 手势：点气泡 = 定位，长按气泡 = 过滤菜单

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view isKindOfClass:UIControl.class]; // 定位圆钮自己处理点击
}

/// 命中的消息行 + cell（point 不在气泡上返回 nil：行内空白不算）。
- (nullable IMPinnedPanelRow *)rowForGesture:(UIGestureRecognizer *)g cell:(UITableViewCell **)outCell {
    CGPoint p = [g locationInView:self.tableView];
    NSIndexPath *ip = [self.tableView indexPathForRowAtPoint:p];
    if (!ip || ip.row >= (NSInteger)self.rows.count) { return nil; }
    IMPinnedPanelRow *row = self.rows[(NSUInteger)ip.row];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:ip];
    if (!row.item || !cell) { return nil; }
    if (![IMPinnedPanelCellFactory cell:cell bubbleContainsPoint:[g locationInView:cell]]) { return nil; }
    if (outCell) { *outCell = cell; }
    return row;
}

- (void)handleTap:(UITapGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateEnded) { return; }
    IMPinnedPanelRow *row = [self rowForGesture:g cell:NULL];
    if (row) { [self locateConvSeq:row.item.convSeq]; }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) { return; }
    UITableViewCell *cell = nil;
    IMPinnedPanelRow *row = [self rowForGesture:g cell:&cell];
    UIView *bubble = cell ? [IMPinnedPanelCellFactory bubbleViewInCell:cell] : nil;
    if (!row || !bubble || [IMPopoverCard isPresentingInHostView:self.view]) { return; }
    NSArray<IMPopoverCardItem *> *items = [self menuItemsForRow:row];
    CGRect anchor = [bubble convertRect:bubble.bounds toView:self.view];
    [IMPopoverCard presentFromRect:anchor inHostView:self.view items:items];
}

/// 复用聊天页长按菜单（IMPopoverCard），按「允许项」过滤：取消置顶（仅有权限）/ 复制（仅文本）/ 定位到消息。
- (NSArray<IMPopoverCardItem *> *)menuItemsForRow:(IMPinnedPanelRow *)row {
    __weak typeof(self) ws = self;
    int64_t seq = row.item.convSeq;
    NSString *text = row.message.content ?: @"";
    NSMutableArray<IMPopoverCardItem *> *out = [NSMutableArray array];
    for (NSString *aid in IMPinnedPanelMenuActionIDs(row.item.contentType, text, self.canUnpin)) {
        if ([aid isEqualToString:IMPinnedMenuActionUnpin]) {
            [out addObject:[IMPopoverCardItem itemWithTitle:IMLocalized(@"pinned.unpin") symbol:@"pin.slash"
                                                destructive:YES handler:^{ [ws unpinConvSeq:seq]; }]];
        } else if ([aid isEqualToString:IMPinnedMenuActionCopy]) {
            [out addObject:[IMPopoverCardItem itemWithTitle:IMLocalized(@"common.copy") symbol:@"doc.on.doc"
                                                destructive:NO handler:^{ [ws copyText:text]; }]];
        } else if ([aid isEqualToString:IMPinnedMenuActionLocate]) {
            [out addObject:[IMPopoverCardItem itemWithTitle:IMLocalized(@"chat.menu.locate") symbol:@"text.bubble"
                                                destructive:NO handler:^{ [ws locateConvSeq:seq]; }]];
        }
    }
    return out;
}

- (void)copyText:(NSString *)text {
    if (text.length == 0) { return; }
    UIPasteboard.generalPasteboard.string = text;
    [self im_showToast:IMLocalized(@"common.copied")];
}

/// 定位：先收起面板，再走宿主现有跳转（已含「目标已撤回 → toast + 重拉」，不重写）。
- (void)locateConvSeq:(int64_t)convSeq {
    if (convSeq <= 0 || self.isBeingDismissed) { return; }
    __weak id<IMPinnedPanelHost> host = self.host;
    [self dismissViewControllerAnimated:YES completion:^{ [host jumpToPinnedConvSeq:convSeq]; }];
}

#pragma mark - 取消所有置顶

- (void)unpinAllTapped {
    if (!self.canUnpin || self.clearing || self.items.count == 0) { return; }
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:IMLocalized(@"pinned.unpin_all_title")
                                                                message:IMLocalizedFormat(@"pinned.unpin_all_message", (long)self.items.count)
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"pinned.unpin_all_confirm") style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) { [ws performUnpinAll]; }]];
    [self presentViewController:ac animated:YES completion:nil];
}

/// 一次请求（POST …/pinned/clear），不在客户端循环发 pin。成功：横幅清空 + 面板收起；失败：toast + 重拉对齐。
- (void)performUnpinAll {
    NSString *token = IMHTTPService.sharedService.currentToken;
    NSString *convID = self.host.convID;
    if (token.length == 0 || convID.length == 0) { [self im_showToast:IMLocalized(@"common.action_failed")]; return; }
    self.clearing = YES;
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService clearPinnedMessagesWithToken:token convID:convID completion:^(NSInteger cleared, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        self.clearing = NO;
        if (error) {
            IMLogWarnWithTag(IMLogTagUI, @"pinned_clear_failed conv_id=%@ code=%ld", convID, (long)error.code);
            [self im_showToast:error.localizedDescription.length > 0 ? error.localizedDescription : IMLocalized(@"common.action_failed")];
            [self.host reloadPinnedBanner];
            return;
        }
        IMLogWithTag(IMLogTagUI, @"pinned_clear_ok conv_id=%@ cleared=%ld", convID, (long)cleared);
        [self.host pinnedPanel:self didChangeItems:@[]];
        [self applyPinnedItems:@[]]; // 空集合 → 收起
    }];
}

#pragma mark - 列表滑动 vs 下滑关闭

// 只在「手指落下时列表已在顶部」或「从标题栏 / 下拉条下拉」才允许关闭；
// 在列表里向上滑到顶、手指没抬又继续往下拖的那一下，不算关闭意图（否则快速回顶极易误关）。
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    BOOL atTop = scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 1;
    self.blockSheetDismissUntil = atTop ? 0 : DBL_MAX;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (self.blockSheetDismissUntil == DBL_MAX) {
        self.blockSheetDismissUntil = CACurrentMediaTime() + 0.8; // 覆盖手指抬起后的惯性回弹
    }
}

- (BOOL)presentationControllerShouldDismiss:(UIPresentationController *)presentationController {
    return CACurrentMediaTime() >= self.blockSheetDismissUntil;
}

#pragma mark - IMLiquidNavigationBarDelegate

- (void)liquidNavigationBarDidTapLeft:(IMLiquidNavigationBar *)bar { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)liquidNavigationBarDidTapBack:(IMLiquidNavigationBar *)bar { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)liquidNavigationBarDidTapAction:(IMLiquidNavigationBar *)bar { /* 右侧留空占位 */ }

@end
