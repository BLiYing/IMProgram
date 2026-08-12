//  IMMediaPagerViewController.m

#import "IMMediaPagerViewController.h"
#import "IMPopoverCard.h" // 「更多」锚点菜单
#import "IMGlass.h"       // 标准 Liquid Glass 圆钮

@interface IMMediaPagerViewController () <UIPageViewControllerDataSource, UIPageViewControllerDelegate, IMMediaViewerContentDelegate>
@end

@implementation IMMediaPagerViewController {
    NSUInteger _count;
    NSUInteger _startIndex;
    IMMediaViewerViewController *_Nullable (^_provider)(NSUInteger);
    UIPageViewController *_pager;

    // 固定层 chrome（不随分页滑动；由 mediaIdentity 页切换时重绑到当前页）
    UILabel     *_counter;        // 顶部居中「i / N」
    UIButton    *_closeButton;    // 左上 ✕
    UIButton    *_downloadButton; // 右下 下载
    UIButton    *_galleryButton;  // 右下 媒体库（当前页有入口时显）
    UIButton    *_moreButton;     // 右下 更多（当前页有 moreActions 时显）
    UIStackView *_bottomStack;    // 右下一排（更多 / 媒体库 / 下载）

    // 沉浸态
    BOOL     _chromeVisible;
    NSTimer *_hideTimer;
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
    _chromeVisible = YES;
    [self updateChromeForCurrent];
    [self resetHideTimer]; // 进入即起 3s 计时（图片/播放中视频会自动隐；暂停/未开播视频常显）
}

/// 固定层：左上 ✕ + 顶部计数 + 右下（更多/媒体库/下载）。这些**不放进页**，故翻页时不动。
- (void)setupFixedChrome {
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    _closeButton = [self circleButtonWithSymbol:@"xmark" pointSize:16 diameter:40];
    [_closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_closeButton];
    [NSLayoutConstraint activateConstraints:@[
        [_closeButton.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:14],
        [_closeButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [_closeButton.widthAnchor constraintEqualToConstant:40],
        [_closeButton.heightAnchor constraintEqualToConstant:40],
    ]];

    _counter = [UILabel new];
    _counter.textColor = UIColor.whiteColor;
    _counter.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightMedium];
    _counter.textAlignment = NSTextAlignmentCenter;
    _counter.translatesAutoresizingMaskIntoConstraints = NO;
    _counter.hidden = _count <= 1; // 单张不显计数
    [self.view addSubview:_counter];
    [NSLayoutConstraint activateConstraints:@[
        [_counter.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_counter.topAnchor constraintEqualToAnchor:safe.topAnchor constant:14],
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

    [self updateCounterForIndex:_startIndex];

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

- (void)updateCounterForIndex:(NSUInteger)index {
    _counter.text = [NSString stringWithFormat:@"%lu / %lu", (unsigned long)(index + 1), (unsigned long)_count];
}

/// 翻页后把壳重绑到当前页：更新计数 + 媒体库/更多 是否显示（按当前页配置）。
- (void)updateChromeForCurrent {
    IMMediaViewerViewController *cur = self.currentViewer;
    if (!cur) { return; }
    [self updateCounterForIndex:cur.imMediaIndex];
    _galleryButton.hidden = !cur.hasGalleryEntry;      // stack 自动收起隐藏项
    _moreButton.hidden = cur.moreActions.count == 0;
}

#pragma mark - 固定层按钮动作（作用于当前页）

- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)downloadTapped { [self.currentViewer saveToAlbum]; [self resetHideTimer]; }

- (void)galleryTapped { [self.currentViewer invokeOpenGallery]; } // 内部先关查看器再回调，无需重置计时

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
    [self resetHideTimer];
}

#pragma mark - 沉浸态：3s 自动隐藏 / 单击切换 / 暂停常显

/// 当前是否应自动隐藏：图片 / 播放中视频 = 是；暂停或未开播视频 = 否（常显，用户确认）。
- (BOOL)shouldAutoHideChrome {
    IMMediaViewerViewController *cur = self.currentViewer;
    if (cur.isVideoContent && !cur.isVideoPlaying) { return NO; }
    return YES;
}

- (void)resetHideTimer {
    [_hideTimer invalidate];
    _hideTimer = nil;
    if (_chromeVisible && [self shouldAutoHideChrome]) {
        _hideTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(autoHide) userInfo:nil repeats:NO];
    }
}

- (void)autoHide { if ([self shouldAutoHideChrome]) { [self setChromeVisible:NO]; } }

- (void)setChromeVisible:(BOOL)visible {
    _chromeVisible = visible;
    [UIView animateWithDuration:0.22 animations:^{
        self->_closeButton.alpha = visible ? 1 : 0;
        self->_counter.alpha = visible ? 1 : 0;
        self->_bottomStack.alpha = visible ? 1 : 0;
    }];
    // 视频页联动：隐藏倍速 / 「查看原视频」（进度条+时间常驻保留）。
    [self.currentViewer setAuxControlsHidden:!visible];
    if (visible) { [self resetHideTimer]; } else { [_hideTimer invalidate]; _hideTimer = nil; }
}

#pragma mark - IMMediaViewerContentDelegate

- (void)mediaViewerContentDidSingleTap:(IMMediaViewerViewController *)vc {
    [self setChromeVisible:!_chromeVisible]; // 显示时点击→隐藏；隐藏时点击→显示（用户确认）
}

- (void)mediaViewerContent:(IMMediaViewerViewController *)vc playingChanged:(BOOL)playing {
    if (playing) {
        [self resetHideTimer];                 // 开播→起 3s 自动隐藏
    } else {
        [_hideTimer invalidate]; _hideTimer = nil;
        if (!_chromeVisible) { [self setChromeVisible:YES]; } // 暂停→唤回按钮并常显
    }
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
    [self updateChromeForCurrent];
    if (!_chromeVisible) { [self setChromeVisible:YES]; } // 翻页后恢复显示壳
    else { [self resetHideTimer]; }
}

// 关闭/退出即停计时：NSTimer 强持 self，不主动作废会把容器+子查看器+AVPlayer 多留 3s，
// 且 autoHide 会在已消失的 VC 上空跑。dealloc 也兜底（但那时已被 timer 拖住）。
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_hideTimer invalidate];
    _hideTimer = nil;
}

- (void)dealloc { [_hideTimer invalidate]; }

@end
