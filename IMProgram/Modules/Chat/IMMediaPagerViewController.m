//  IMMediaPagerViewController.m

#import "IMMediaPagerViewController.h"
#import "IMPopoverCard.h" // 「更多」锚点菜单
#import "IMGlass.h"       // 标准 Liquid Glass 圆钮
#import "IMMainTabBarController.h" // kIMLiquidBarHeight
#import "IMProgram-Swift.h"         // IMLiquidNavigationBar（复用聊天页标题栏）

@interface IMMediaPagerViewController () <UIPageViewControllerDataSource, UIPageViewControllerDelegate, IMMediaViewerContentDelegate, IMLiquidNavigationBarDelegate>
@end

@implementation IMMediaPagerViewController {
    NSUInteger _count;
    NSUInteger _startIndex;
    IMMediaViewerViewController *_Nullable (^_provider)(NSUInteger);
    UIPageViewController *_pager;

    // 固定层 chrome（不随分页滑动；由 mediaIdentity 页切换时重绑到当前页）
    IMLiquidNavigationBar *_navBar;  // 顶部标题栏：复用聊天页同款液态玻璃栏（返回键 + 会话名 + i/N 计数）
    UIButton    *_downloadButton; // 右下 下载
    UIButton    *_galleryButton;  // 右下 媒体库（当前页有入口时显）
    UIButton    *_moreButton;     // 右下 更多（当前页有 moreActions 时显）
    UIStackView *_bottomStack;    // 右下一排（更多 / 媒体库 / 下载）

    // 沉浸态：默认显示，点按切换显隐（无自动隐藏倒计时）。
    BOOL _chromeVisible;
}

+ (instancetype)pagerWithCount:(NSUInteger)count
                    startIndex:(NSUInteger)startIndex
                  pageProvider:(IMMediaViewerViewController *_Nullable (^)(NSUInteger))pageProvider {
    IMMediaPagerViewController *vc = [IMMediaPagerViewController new];
    vc->_count = count;
    vc->_startIndex = MIN(startIndex, count > 0 ? count - 1 : 0);
    vc->_provider = [pageProvider copy];
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    return vc;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    // 横向滚动翻页，页间留 20pt 黑边（避免相邻图片贴边）。
    _pager = [[UIPageViewController alloc] initWithTransitionStyle:UIPageViewControllerTransitionStyleScroll
                                            navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal
                                                          options:@{UIPageViewControllerOptionInterPageSpacingKey: @20}];
    _pager.dataSource = self;
    _pager.delegate = self;
    IMMediaViewerViewController *first = [self viewerAtIndex:_startIndex];
    if (first) {
        [_pager setViewControllers:@[first] direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
    }
    [self addChildViewController:_pager];
    _pager.view.frame = self.view.bounds;
    _pager.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_pager.view];
    [_pager didMoveToParentViewController:self];

    [self setupFixedChrome];
    _chromeVisible = YES;   // 默认显示；点按画面才切换显隐（无自动隐藏倒计时）
    [self updateChromeForCurrent];
}

/// 固定层：顶部液态标题栏（复用聊天页 IMLiquidNavigationBar：返回键 + 会话名 + i/N）+ 右下（更多/媒体库/下载）。
/// 这些**不放进页**，故翻页时不动。
- (void)setupFixedChrome {
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    // 顶部标题栏：直接复用聊天页那套液态玻璃栏，风格一致。左侧默认返回键（关闭本页），中间会话名 + i/N 计数。
    _navBar = [[IMLiquidNavigationBar alloc] initWithTitle:(self.conversationTitle ?: @"") subtitle:@"" actionTitle:nil];
    _navBar.delegate = self;
    _navBar.showsBackButton = YES;                 // 默认返回键（取代原 ✕）
    // ⚠️ 标题/副标题的透明度由 compactContentProgress 驱动（默认 0 = 全透明）；主导航容器注入时会设 1，
    // 自持必须自己设，否则整条栏只剩返回键（曾因此标题完全不显示）。showsTitleGlass=聊天页同款标题玻璃胶囊。
    _navBar.compactContentProgress = 1;
    _navBar.showsTitleGlass = YES;
    _navBar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark; // 全屏黑底 → 暗色玻璃 + 白前景
    _navBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_navBar];
    [NSLayoutConstraint activateConstraints:@[
        [_navBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_navBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_navBar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_navBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:kIMLiquidBarHeight],
    ]];

    _downloadButton = [self circleButtonWithSymbol:@"arrow.down.to.line" pointSize:16 diameter:44];
    [_downloadButton addTarget:self action:@selector(downloadTapped) forControlEvents:UIControlEventTouchUpInside];
    _galleryButton = [self circleButtonWithSymbol:@"square.grid.2x2" pointSize:16 diameter:44];
    [_galleryButton addTarget:self action:@selector(galleryTapped) forControlEvents:UIControlEventTouchUpInside];
    _moreButton = [self circleButtonWithSymbol:@"ellipsis" pointSize:16 diameter:44];
    [_moreButton addTarget:self action:@selector(moreTapped) forControlEvents:UIControlEventTouchUpInside];

    // 右下一排（左→右：更多、媒体库、下载）；隐藏的成员在 stack 里会自动收起、不留空位。
    _bottomStack = [[UIStackView alloc] initWithArrangedSubviews:@[_moreButton, _galleryButton, _downloadButton]];
    _bottomStack.axis = UILayoutConstraintAxisHorizontal;
    _bottomStack.alignment = UIStackViewAlignmentCenter;
    _bottomStack.spacing = 14;
    _bottomStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_bottomStack];
    [NSLayoutConstraint activateConstraints:@[
        [_bottomStack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [_bottomStack.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16],
    ]];

    [self updateSubtitleForIndex:_startIndex];

    // 下滑关闭（沉浸看图的退出手势；缩放态下由内层 scrollView 消化竖向 pan，不误触）。
    UISwipeGestureRecognizer *down = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(closeTapped)];
    down.direction = UISwipeGestureRecognizerDirectionDown;
    [self.view addGestureRecognizer:down];
}

- (UIButton *)circleButtonWithSymbol:(NSString *)name pointSize:(CGFloat)pt diameter:(CGFloat)d {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *img = [UIImage systemImageNamed:name
                          withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:pt weight:UIImageSymbolWeightSemibold]];
    UIButtonConfiguration *cfg = IMGlassButtonConfiguration();
    cfg.image = img;
    cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    cfg.contentInsets = NSDirectionalEdgeInsetsZero;
    cfg.baseForegroundColor = UIColor.whiteColor;
    b.configuration = cfg;
    b.overrideUserInterfaceStyle = UIUserInterfaceStyleDark; // 全屏黑底：玻璃/灰底偏深、白图标有对比
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b.widthAnchor constraintEqualToConstant:d].active = YES;
    [b.heightAnchor constraintEqualToConstant:d].active = YES;
    return b;
}

/// 按下标现建一页；越界返回 nil（供 dataSource 表示到头）。设 chromeless + delegate + imMediaIndex。
- (IMMediaViewerViewController *)viewerAtIndex:(NSUInteger)index {
    if (index >= _count || !_provider) { return nil; }
    IMMediaViewerViewController *vc = _provider(index);
    vc.imMediaIndex = index;        // vc 可能为 nil（provider 弱引用兜底），发消息给 nil 安全
    vc.chromeless = YES;            // 内容页不画壳；壳在本容器固定层
    vc.contentDelegate = self;
    return vc;
}

- (IMMediaViewerViewController *)currentViewer {
    return (IMMediaViewerViewController *)_pager.viewControllers.firstObject;
}

- (void)updateSubtitleForIndex:(NSUInteger)index {
    // 单张不显计数；多张显纯数字 i/N（挂到液态标题栏副标题）。
    _navBar.subtitleText = _count > 1 ? [NSString stringWithFormat:@"%lu / %lu", (unsigned long)(index + 1), (unsigned long)_count] : @"";
}

/// 翻页后把壳重绑到当前页：更新数目 + 媒体库/更多 是否显示（按当前页配置）。
- (void)updateChromeForCurrent {
    IMMediaViewerViewController *cur = self.currentViewer;
    if (!cur) { return; }
    [self updateSubtitleForIndex:cur.imMediaIndex];
    _galleryButton.hidden = !cur.hasGalleryEntry;      // stack 自动收起隐藏项
    _moreButton.hidden = cur.moreActions.count == 0;
}

#pragma mark - 固定层按钮动作（作用于当前页）

- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)downloadTapped { [self.currentViewer saveToAlbum]; }

- (void)galleryTapped { [self.currentViewer invokeOpenGallery]; } // 内部先关查看器再回调

- (void)moreTapped {
    IMMediaViewerViewController *cur = self.currentViewer;
    if (!cur) { return; }
    __weak typeof(self) ws = self;
    NSMutableArray<IMPopoverCardItem *> *items = [NSMutableArray array];
    // 内置「下载」（不关查看器）+ 外部动作（先关查看器再执行，回到聊天页上下文）。
    [items addObject:[IMPopoverCardItem itemWithTitle:@"下载" symbol:@"arrow.down.to.line" destructive:NO handler:^{
        [ws.currentViewer saveToAlbum];
    }]];
    for (IMPopoverCardItem *ext in cur.moreActions) {
        void (^inner)(void) = ext.handler;
        [items addObject:[IMPopoverCardItem itemWithTitle:ext.title symbol:ext.symbol destructive:ext.destructive handler:^{
            [ws dismissViewControllerAnimated:YES completion:^{ if (inner) { inner(); } }];
        }]];
    }
    [IMPopoverCard presentFromAnchor:_moreButton inHostView:self.view items:items];
}

#pragma mark - 沉浸态：默认显示 / 单击切换显隐（无自动隐藏倒计时）

- (void)setChromeVisible:(BOOL)visible {
    _chromeVisible = visible;
    // 隐藏时同时停用交互：否则 alpha=0 的全宽标题栏仍会拦住顶部点击 → 误触返回（而非唤回壳）。
    _navBar.userInteractionEnabled = visible;
    _bottomStack.userInteractionEnabled = visible;
    [UIView animateWithDuration:0.22 animations:^{
        self->_navBar.alpha = visible ? 1 : 0;
        self->_bottomStack.alpha = visible ? 1 : 0;
    }];
    // 视频页联动：隐藏倍速 / 「查看原视频」（进度条+时间常驻保留）。
    [self.currentViewer setAuxControlsHidden:!visible];
}

#pragma mark - IMLiquidNavigationBarDelegate（复用聊天页标题栏：返回键关闭本页）

- (void)liquidNavigationBarDidTapBack:(IMLiquidNavigationBar *)bar { [self closeTapped]; }
- (void)liquidNavigationBarDidTapAction:(IMLiquidNavigationBar *)bar { /* 无右侧动作 */ }
- (void)liquidNavigationBarDidTapLeft:(IMLiquidNavigationBar *)bar { /* 无自定义左项 */ }

#pragma mark - IMMediaViewerContentDelegate

- (void)mediaViewerContentDidSingleTap:(IMMediaViewerViewController *)vc {
    [self setChromeVisible:!_chromeVisible]; // 显示时点击→隐藏；隐藏时点击→显示
}

- (void)mediaViewerContent:(IMMediaViewerViewController *)vc playingChanged:(BOOL)playing {
    // 无自动隐藏：播放/暂停不再驱动壳的显隐（壳只由点按切换）。留空以满足协议。
}

#pragma mark - UIPageViewControllerDataSource（翻到头即停：越界返回 nil）

- (UIViewController *)pageViewController:(UIPageViewController *)pvc
      viewControllerBeforeViewController:(UIViewController *)vc {
    NSUInteger idx = ((IMMediaViewerViewController *)vc).imMediaIndex;
    if (idx == 0) { return nil; }
    return [self viewerAtIndex:idx - 1];
}

- (UIViewController *)pageViewController:(UIPageViewController *)pvc
       viewControllerAfterViewController:(UIViewController *)vc {
    NSUInteger idx = ((IMMediaViewerViewController *)vc).imMediaIndex;
    return [self viewerAtIndex:idx + 1];   // idx+1 >= _count 时 viewerAtIndex 自返 nil
}

#pragma mark - UIPageViewControllerDelegate

- (void)pageViewController:(UIPageViewController *)pvc
        didFinishAnimating:(BOOL)finished
   previousViewControllers:(NSArray<UIViewController *> *)previousViewControllers
       transitionCompleted:(BOOL)completed {
    if (!completed) { return; }   // 未翻过去（回弹）→ 保持原状
    // 翻页后把壳重绑到当前页（数目/媒体库/更多）；壳的显隐沿用当前态（隐藏则保持隐藏，由点按切换）。
    [self updateChromeForCurrent];
    [self.currentViewer setAuxControlsHidden:!_chromeVisible];
}

@end
