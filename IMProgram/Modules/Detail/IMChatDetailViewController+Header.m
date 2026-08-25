//  IMChatDetailViewController+Header.m
//  详情页「头部」分文件实现：构建 UI（表格/头像/液态标题栏/页签）与头部形变（滚动驱动 morph）。
//  从 IMChatDetailViewController.m 平移，未改行为；私有属性/常量经 IMChatDetailViewController+Private.h 共享。

#import "IMChatDetailViewController+Private.h"
#import "IMDetailMemberCell.h"
#import "IMDetailFileCell.h"
#import "IMDetailLinkCell.h"
#import "IMDetailMediaContainerCell.h"
#import "IMMediaUtil.h"
#import "IMMainTabBarController.h"    // im_refreshNavigationBar / kIMLiquidBarHeight
#import "IMChatDetailTabs.h"
#import "IMLiquidSegmentedControl.h"
#import "IMDetailHeaderViews.h"
#import "IMDropletHeaderMorph.h"
#import "IMGroupInfo.h"
#import "IMTheme.h"
#import "IMGlass.h"
#import "UILabel+IMAvatar.h"
#import "IMLog.h"

@implementation IMChatDetailViewController (Header)

#pragma mark - 构建 UI

- (void)buildTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self; self.tableView.delegate = self;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.sectionHeaderTopPadding = 0;
    // 关闭高度估算：所有行/页眉走精确 heightFor…，reloadData 后 contentSize / rectForHeaderInSection 立即准确，
    // 切 tab 时 pinOffset 才不会因估算落偏（#4 维持贴顶的前提）。
    self.tableView.estimatedRowHeight = 0;
    self.tableView.estimatedSectionHeaderHeight = 0;
    self.tableView.estimatedSectionFooterHeight = 0;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"plain"];
    [self.tableView registerClass:IMDetailMemberCell.class forCellReuseIdentifier:@"member"];
    [self.tableView registerClass:IMDetailMediaContainerCell.class forCellReuseIdentifier:@"mediagrid"];
    [self.tableView registerClass:IMDetailFileCell.class forCellReuseIdentifier:@"detailfile"];
    [self.tableView registerClass:IMDetailLinkCell.class forCellReuseIdentifier:@"detaillink"];
    UIView *spacer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 300)];
    spacer.backgroundColor = UIColor.clearColor;
    self.pillsView = [self buildPillsView];
    [spacer addSubview:self.pillsView];
    self.tableView.tableHeaderView = spacer;
    [self.view addSubview:self.tableView];

    // 横滑切换页签（左/右）；成员行区域让位给行滑动删除（见 shouldReceiveTouch）。
    UISwipeGestureRecognizer *sl = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeToNextTab:)];
    sl.direction = UISwipeGestureRecognizerDirectionLeft; sl.delegate = self;
    UISwipeGestureRecognizer *sr = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeToPrevTab:)];
    sr.direction = UISwipeGestureRecognizerDirectionRight; sr.delegate = self;
    [self.tableView addGestureRecognizer:sl];
    [self.tableView addGestureRecognizer:sr];
}

/// 操作排按钮规格（header 悬浮 pills 与 actions cell 共用，保证一致）。
/// 微信式好友准入（任务一 P0）：单聊非好友只显「加好友 + 更多」，不显「消息/呼叫/视频」——
/// 非好友发消息会被服务端 200103 拒收，故不给发消息入口，主入口是加好友。
- (NSArray<NSDictionary *> *)actionPillSpecs {
    NSMutableArray *specs = [NSMutableArray array];
    // 系统通知会话：只留「更多」（免打扰/清空聊天）——加好友/消息/呼叫/视频/搜索都不适用。
    // 见 docs/SYSTEM_NOTICE_SESSION_DESIGN.md §5.3 / §7 权限矩阵。
    if (!self.isGroup && [self.peerID isEqualToString:@"system"]) {
        [specs addObject:@{@"t": @"更多", @"s": @"ellipsis", @"a": @"more"}];
        return specs;
    }
    if (!self.isGroup) {
        if (!self.peerIsFriend) {
            [specs addObject:@{@"t": @"加好友", @"s": @"person.badge.plus", @"a": @"addfriend"}];
        } else {
            if (self.showsMessagePill) {
                [specs addObject:@{@"t": @"消息", @"s": @"bubble.right.fill", @"a": @"message"}];
            }
            [specs addObject:@{@"t": @"呼叫", @"s": @"phone.fill", @"a": @"call"}];
            [specs addObject:@{@"t": @"视频", @"s": @"video.fill", @"a": @"video"}];
        }
    }
    // 搜索：群聊与**单聊好友**都显示（对齐 im-web；功能待开发，点击走占位 toast）。
    // 非好友不显示——尚无聊天记录可搜，与隐藏备注名/设置/页签三张卡同一判据。
    if (self.isGroup || self.peerIsFriend) {
        [specs addObject:@{@"t": @"搜索", @"s": @"magnifyingglass", @"a": @"search"}];
    }
    [specs addObject:@{@"t": @"更多", @"s": @"ellipsis", @"a": @"more"}];
    return specs;
}

/// 操作排单个按钮（header 悬浮 pills 与 actions cell 共用，保证外观一致）。
/// iOS 26 的 glassButtonConfiguration 前景走单色化（≈label 色，浅色下即黑），会吞掉 baseForegroundColor 的 accent，
/// 于是「搜索/更多/呼叫/视频」恒为黑（iOS 18 的 grayButtonConfiguration 尊重 baseForegroundColor，故无此问题）。
/// 解决：把 accent 直接烘进图标（AlwaysOriginal）与标题（显式前景色），绕开玻璃单色化——两系统都稳定显 accent。
- (UIButton *)actionPillButtonForSpec:(NSDictionary *)spec {
    UIColor *tint = IMTheme.accent;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *cfg = IMGlassButtonConfiguration();
    cfg.image = [[UIImage systemImageNamed:spec[@"s"]] imageWithTintColor:tint renderingMode:UIImageRenderingModeAlwaysOriginal];
    cfg.title = spec[@"t"];
    cfg.imagePlacement = NSDirectionalRectEdgeTop;
    cfg.imagePadding = 4;
    cfg.baseForegroundColor = tint;   // iOS 18 生效；iOS 26 由下面的显式前景色兜底
    cfg.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *old) {
        NSMutableDictionary *attrs = [old mutableCopy];
        attrs[NSFontAttributeName] = [UIFont systemFontOfSize:11];
        attrs[NSForegroundColorAttributeName] = tint;
        return attrs;
    };
    cfg.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    button.configuration = cfg;
    button.tintColor = tint;
    button.accessibilityLabel = spec[@"a"];
    [button addTarget:self action:([spec[@"a"] isEqualToString:@"more"] ? @selector(moreTapped:) : @selector(pillTapped:))
     forControlEvents:UIControlEventTouchUpInside];
    return button;
}

/// 好友态变化后原地重建 header 悬浮操作排（frame 由 viewDidLayoutSubviews 复位）。
- (void)rebuildPillsView {
    UIView *spacer = self.pillsView.superview;
    if (!spacer) { return; }
    [self.pillsView removeFromSuperview];
    self.pillsView = [self buildPillsView];
    [spacer addSubview:self.pillsView];
    [self.view setNeedsLayout];
}

- (UIView *)buildPillsView {
    UIView *host = [UIView new];
    host.backgroundColor = UIColor.clearColor;
    NSArray<NSDictionary *> *specs = [self actionPillSpecs];

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.spacing = 9;
    [host addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:host.topAnchor constant:6],
        [stack.bottomAnchor constraintEqualToAnchor:host.bottomAnchor constant:-6],
    ]];
    for (NSDictionary *spec in specs) {
        [stack addArrangedSubview:[self actionPillButtonForSpec:spec]];
    }
    return host;
}

/// 给分段控件挂"点击即贴顶"的 tap（与其自身选择手势并存），支持单 tab / 重复点当前 tab 也贴顶。
- (void)addTabPinTapTo:(IMLiquidSegmentedControl *)seg {
    UITapGestureRecognizer *tp = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tabBarTapped)];
    tp.cancelsTouchesInView = NO; tp.delaysTouchesBegan = NO; tp.delegate = self;
    [seg addGestureRecognizer:tp];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }

/// 成员行上的横滑留给「移除」滑动动作，不触发页签切换；其余区域（媒体/文件/链接/空白）横滑切页签。
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldReceiveTouch:(UITouch *)touch {
    if (![gr isKindOfClass:UISwipeGestureRecognizer.class]) { return YES; }
    if (self.tabs.count == 0) { return NO; }
    // 右滑（=上一签）与系统「左边缘向右划返回」方向相同：起手落在左边缘时让位给返回手势，
    // 否则会先切到上一签（如「文件」→「媒体」）再退出，观感是"先滑到媒体 tab 再返回"（Bug a）。
    if (((UISwipeGestureRecognizer *)gr).direction == UISwipeGestureRecognizerDirectionRight &&
        [touch locationInView:self.view].x <= 24) {
        return NO;
    }
    CGPoint p = [touch locationInView:self.tableView];
    NSIndexPath *ip = [self.tableView indexPathForRowAtPoint:p];
    if (ip && [self sectionKindAt:ip.section] == IMDetailSectionTabs) {
        IMChatDetailTab *t = self.tabs[self.selectedTab];
        if (t.kind == IMDetailTabKindMembers && ip.row > 0) { return NO; } // 成员行 → 行滑动删除
    }
    return YES;
}

- (void)buildHeaderOverlay {
    NSString *seed = self.isGroup ? self.convID : (self.peerID ?: @"");
    NSString *name = self.displayTitle;
    NSString *url = [self headerAvatarURL];

    // 静态头部容器：完整覆盖遮罩带（灵动岛下 171pt）+ 头像 rest 位置。
    // 头像/黑底/effects/mask 全部挂在这里，mask 作用于容器本身而非小尺寸头像，
    // 避免 171pt 遮罩被 50pt 头像 bounds 裁成矩形。
    self.headerContainer = [[IMDetailHeaderContainer alloc] initWithFrame:CGRectZero];
    self.headerContainer.backgroundColor = UIColor.clearColor;
    self.headerContainer.userInteractionEnabled = YES;
    self.headerContainer.clipsToBounds = NO;
    [self.view addSubview:self.headerContainer];

    // 灵动岛遮罩底层黑底：对应 Telegram `bottomCoverNode`，alpha 随 maskValue 线性增长。
    self.dropletBottomCover = [[UIView alloc] initWithFrame:CGRectZero];
    self.dropletBottomCover.userInteractionEnabled = NO;
    self.dropletBottomCover.hidden = YES;
    self.dropletBottomCover.backgroundColor = [UIColor colorWithWhite:0 alpha:0];
    [self.headerContainer addSubview:self.dropletBottomCover];

    self.avatarView = [[IMDetailAvatarView alloc] initWithFrame:CGRectZero];
    [self.avatarView setAvatarURL:url seed:seed name:name];
    self.avatarView.userInteractionEnabled = YES;
    [self.avatarView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(avatarTapped)]];
    [self.headerContainer addSubview:self.avatarView];
    self.headerContainer.interactiveChild = self.avatarView;

    // 顶部 blur+径向渐变+黑色淡入：对应 Telegram `topCoverNode` (DynamicIslandBlurNode)。
    self.dropletTopCover = [[IMTelegramAvatarEffectsView alloc] initWithFrame:CGRectZero];
    self.dropletTopCover.userInteractionEnabled = NO;
    self.dropletTopCover.hidden = YES;
    [self.headerContainer addSubview:self.dropletTopCover];

    // Lottie 遮罩本体：只在 progress>0.03 时挂到 headerContainer.maskView。
    self.dropletMask = [[IMTelegramAvatarMaskView alloc] initWithFrame:CGRectZero];
    self.dropletMask.userInteractionEnabled = NO;

    self.nameOnImage = [self makeNameLabel:22 color:UIColor.whiteColor shadow:YES];
    self.nameOnImage.textAlignment = NSTextAlignmentLeft;
    self.subOnImage = [self makeNameLabel:13 color:[UIColor.whiteColor colorWithAlphaComponent:0.85] shadow:YES];
    self.subOnImage.textAlignment = NSTextAlignmentLeft;
    // 起点比导航栏 title (17pt) 略大，滑动过程会 CGAffineTransformScale 到 ≈17pt，视觉即"移动+缩小到标题栏"。
    // 对齐 Telegram PeerInfoHeaderNode.titleFont ≈ 28pt / titleMinScale=0.6 → 端点 16.8pt。
    self.nameBelow = [self makeNameLabel:26 color:IMTheme.textPrimary shadow:NO];
    self.subBelow = [self makeNameLabel:15 color:IMTheme.textSecondary shadow:NO];
    for (UILabel *l in @[self.nameOnImage, self.subOnImage, self.nameBelow, self.subBelow]) { [self.view addSubview:l]; }
    self.nameOnImage.text = name; self.nameBelow.text = name;
    self.subOnImage.text = self.displaySubtitle; self.subBelow.text = self.displaySubtitle;

    self.liquidNavigationBar = [[IMLiquidNavigationBar alloc] initWithTitle:name
                                                                     subtitle:self.displaySubtitle
                                                                  actionTitle:(self.isGroup ? @"编辑" : nil)];
    self.liquidNavigationBar.delegate = self;
    self.liquidNavigationBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.liquidNavigationBar];
    [NSLayoutConstraint activateConstraints:@[
        [self.liquidNavigationBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.liquidNavigationBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.liquidNavigationBar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.liquidNavigationBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:kIMLiquidBarHeight],
    ]];
    // 吸顶条：页签滚到折叠顶栏下方时出现，只托镜像分段控件——**本身保持透明**。
    // ⚠️ 它的 z 序在导航栏【之上】（否则分段药丸顶部会被栏盖掉），所以绝不能给它不透明底：
    // 那会把返回按钮下缘 2pt 一起涂掉（按钮 topInset+6…+50，本条从 topInset+48 起），
    // 表现为"返回按钮被切、左侧出现分割感"（踩过一次）。
    // 内容透出问题改由标题栏自身随头部收拢变实解决，见 applyHeaderMorph。
    self.stickyBar = [[UIView alloc] initWithFrame:CGRectZero];
    self.stickyBar.backgroundColor = UIColor.clearColor;
    self.stickyBar.hidden = YES;
    [self.view addSubview:self.stickyBar];
    self.stickySeg = [[IMLiquidSegmentedControl alloc] initWithFrame:CGRectZero];
    [self.stickySeg addTarget:self action:@selector(stickySegChanged:) forControlEvents:UIControlEventValueChanged];
    [self addTabPinTapTo:self.stickySeg];
    [self.stickyBar addSubview:self.stickySeg];

    // 名字/副标题上移锁定后要充当导航栏 title，必须渲染在液态导航栏与吸顶条【之上】
    //（否则被磨砂背景盖住变虚）。居中文字标签 userInteractionEnabled 默认 NO，不挡两侧按钮点击。
    [self.view bringSubviewToFront:self.nameBelow];
    [self.view bringSubviewToFront:self.subBelow];

    // 共享 Zone① 头部形变驱动：与「我」页 IMSettingsViewController 同一套；改一处两页同步。
    self.headerMorph = [IMDropletHeaderMorph new];
    self.headerMorph.container = self.headerContainer;
    self.headerMorph.avatar = self.avatarView;
    self.headerMorph.bottomCover = self.dropletBottomCover;
    self.headerMorph.topCover = self.dropletTopCover;
    self.headerMorph.mask = self.dropletMask;
    self.headerMorph.name = self.nameBelow;
    self.headerMorph.meta = self.subBelow;
    self.headerMorph.bar = self.liquidNavigationBar;
    self.headerMorph.nameRestFont = 26;
    self.headerMorph.metaRestFont = 15;
    self.headerMorph.collapseOffset = [self headerCollapseOffset];
}

- (UILabel *)makeNameLabel:(CGFloat)size color:(UIColor *)color shadow:(BOOL)shadow {
    UILabel *l = [UILabel new];
    l.font = [UIFont systemFontOfSize:size weight:(size >= 20 ? UIFontWeightSemibold : UIFontWeightRegular)];
    l.textColor = color; l.textAlignment = NSTextAlignmentCenter;
    if (shadow) { l.layer.shadowColor = UIColor.blackColor.CGColor; l.layer.shadowOpacity = 0.35;
                  l.layer.shadowRadius = 6; l.layer.shadowOffset = CGSizeMake(0, 1); }
    return l;
}

- (NSString *)headerAvatarURL {
    // 群：优先已加载的群资料头像，否则用聊天页透传的（_peerAvatarURL 承载）；单聊：对方头像。
    NSString *raw = self.isGroup ? (self.group.avatarURL.length ? self.group.avatarURL : self.peerAvatarURL)
                                 : self.peerAvatarURL;
    return raw.length ? IMMediaFullURL(raw, self.host) : @"";
}
- (NSString *)displayTitle {
    if (self.isGroup) {
        NSString *remark = [self currentConvRemark]; // 群备注（仅本人可见，G1）优先
        if (remark.length) { return remark; }
        return self.group.name.length ? self.group.name : (self.groupName.length ? self.groupName : @"群聊");
    }
    return self.peerNickname.length ? self.peerNickname : (self.peerID ?: @"");
}
- (NSString *)displaySubtitle {
    if (self.isGroup) {
        NSUInteger n = self.group.members.count;
        return n > 0 ? [NSString stringWithFormat:@"%lu 位成员", (unsigned long)n] : @"群聊";
    }
    return self.peerID ?: @"";
}

#pragma mark - 头部形变（滚动驱动）

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self applyHeaderMorph];
    [self updatePillsVisibility];
    [self updateStickyTabs];
}

/// tab 贴顶时顶边。贴到标题栏底(topInset+56)之上一点，让分段控件紧贴标题栏、上方内容被磨砂栏遮住不外露。
/// stickyBar / pinOffset / updateStickyTabs 统一取此值。
- (CGFloat)tabPinTop { return self.topInset + 48; }
/// 运行时实时的页签栏高度（tab 高度改了这里自动跟随），用于 Zone② detent 的半-tab 临界。
- (CGFloat)tabBarHeight {
    NSInteger sec = [self indexOfSection:IMDetailSectionTabs];
    if (sec == NSNotFound) { return kIMDetailTabBarH; }
    CGFloat h = [self.tableView rectForHeaderInSection:sec].size.height;
    return h > 0 ? h : kIMDetailTabBarH;
}

/// 松手临界吸附：Zone①(头部收拢) + Zone②(tab 贴顶后列表起步 detent)。
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity
                    targetContentOffset:(inout CGPoint *)targetContentOffset {
    CGFloat off = scrollView.contentOffset.y;
    CGFloat H = [self headerCollapseOffset];
    // Zone①：仅当【惯性落点】也落在 (0,H) 收拢带内才吸附（否则快速甩动的动量应穿过 H 直达列表，不被卡住）。
    if (off < H && targetContentOffset->y < H) {
        CGFloat snap = [IMDropletHeaderMorph snapTargetForOffset:off velocity:velocity.y collapseOffset:H];
        if (snap >= 0) { targetContentOffset->y = snap; return; }
    }
    // Zone②：tab 贴顶后，列表在 tab 正下方(off=pin)起步上滑。落点在 (pin, pin+半tab) 内 → 回弹到 pin
    //（撤销这段滑动，tab 仍贴顶）；≥ 半tab → 放行自然滚动。
    CGFloat pin = [self pinOffset];
    if (pin <= 0) { return; }
    CGFloat half = [self tabBarHeight] / 2;
    CGFloat t = targetContentOffset->y;
    if (t > pin && t < pin + half) { targetContentOffset->y = pin; }
}

/// 头部完全收拢（态H）所需上滑距离：此时 name/成员进标题栏、pills 恰好停到标题栏下方。
/// 由 pills 几何推导：pills rest 顶 = topInset+208，停靠目标顶 = topInset+64 → H = 144（保持两者同步）。
- (CGFloat)headerCollapseOffset { return 144; }

- (void)applyHeaderMorph {
    CGFloat W = self.view.bounds.size.width;
    if (W <= 0) { return; }
    CGFloat off = MAX(0, self.tableView.contentOffset.y); // 下拉橡皮筋不参与形变
    // Zone① 全部形变（头像吸附 + 遮罩/覆盖 + name/成员迁移进标题栏）交给共享驱动，与「我」页同一套。
    self.headerMorph.topInset = self.topInset;
    self.headerMorph.collapseOffset = [self headerCollapseOffset];
    [self.headerMorph applyForOffset:off width:W];
    // 标题栏随头部收拢同步「变实」：收拢到位＝群名/成员数已迁入标题栏，此时其下正开始穿过
    // 「消息免打扰」等卡片内容；通透磨砂挡不住会透出，故此刻让底色推到不透明。
    // 与 name/成员的迁移用**同一个进度**，观感天然同步；且只作用于本页这条自持栏，不影响其他页面。
    CGFloat collapse = IMClamp(off / MAX(1, [self headerCollapseOffset]), 0, 1);
    self.liquidNavigationBar.opaqueProgress = collapse * kIMDetailNavOpaqueOnCollapse;
    // 图上名（photo 模式）本页不用，恒隐。
    self.nameOnImage.alpha = 0;
    self.subOnImage.alpha = 0;
    CGFloat q = IMClamp(off / 120.0, 0, 1);
    [self fireHapticsForPhase:q hasPhoto:NO phaseP:1];
}

/// 操作排（搜索/更多）：不再淡出。随内容上滑停靠到标题栏正下方并【始终可见】(态H)；
/// 继续上滑(Zone②)时它自然滚到磨砂标题栏之后被遮挡（= 滚走），无需 alpha 淡出。
- (void)updatePillsVisibility {
    if (!self.pillsView.superview) { return; }
    CGRect frameInView = [self.pillsView.superview convertRect:self.pillsView.frame toView:self.view];
    CGFloat topInView = CGRectGetMinY(frameInView);
    self.pillsView.alpha = 1;
    // 进入标题栏区(被磨砂栏遮挡)后停用点击，避免隔着导航栏误触搜索/更多。
    self.pillsView.userInteractionEnabled = topInView > self.topInset + kIMLiquidBarHeight;
}

/// 锚点触感：正圆成形（photo p≈1、未进吸附）与吸附完成（q≈1）各一次；反向复位后可再触发。
- (void)fireHapticsForPhase:(CGFloat)q hasPhoto:(BOOL)hasPhoto phaseP:(CGFloat)p {
    if (q >= 0.98 && !self.didHapticAbsorb) {
        self.didHapticAbsorb = YES;
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleSoft] impactOccurred];
    }
    if (q < 0.5) { self.didHapticAbsorb = NO; }
    if (hasPhoto && q <= 0 && p >= 0.98 && !self.didHapticCircle) {
        self.didHapticCircle = YES;
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleSoft] impactOccurred];
    }
    if (p < 0.5) { self.didHapticCircle = NO; }
}

@end
