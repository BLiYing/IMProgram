//  IMMainTabBarController.m

#import "IMMainTabBarController.h"
#import "IMConversationListViewController.h"
#import "IMContactsViewController.h"
#import "IMSettingsViewController.h"
#import "IMUserSearchViewController.h"
#import "IMProgram-Swift.h"
#import "IMChatDetailViewController.h"
#import "IMChatViewController.h"
#import "IMDatabase.h"

/// 液态标题栏在状态栏之下占用的高度。容器据此撑大被注入页面的顶部安全区（内容从栏下方开始），
/// 并把同一个值传给栏（`hostExtraTopInset`）好让它还原真实状态栏高度。两处必须是同一个数，故抽为常量。
static CGFloat const kIMLiquidBarExtraTopInset = 56;

/// 可选的自定义导航背景进度接口；声明后仍通过 respondsToSelector 兼容未实现页面。
@interface UIViewController (IMNavigationBackgroundProgress)
- (CGFloat)im_navigationBackgroundProgress;
@end

/// 主界面统一导航容器：所有非根页面自动隐藏 TabBar，并恢复系统边缘侧滑返回。
/// 这样新增页面只需正常 push，不再依赖每个控制器手动设置 hidesBottomBarWhenPushed。
@interface IMMainNavigationController : UINavigationController <UIGestureRecognizerDelegate, UINavigationControllerDelegate, IMLiquidNavigationBarDelegate>
@property (nonatomic, weak) UIBarButtonItem *leftItem;
@property (nonatomic, weak) UIBarButtonItem *rightItem;
@end

@implementation IMMainNavigationController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.delegate = self; // 转场落定（含交互式返回完成/取消）后统一同步标题栏，见 navigationController:didShowViewController:
    self.interactivePopGestureRecognizer.delegate = self;
    self.interactivePopGestureRecognizer.enabled = YES;
    self.navigationBar.prefersLargeTitles = NO;
    [self setNavigationBarHidden:YES animated:NO];
    // 标题栏不再共用一条挂在导航容器上的固定栏——改为每页在自己的 view 里持有一条（见 barForController:），
    // 使其随页面一起侧滑、上一页露出即完整显示（对齐 Detail/Settings 的自持栏做法）。
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self setNavigationBarHidden:YES animated:NO];
    [self syncBarForController:self.topViewController];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // 转场进行中各页的栏已随各自 view 就位、无需再动；且此时 topViewController 已提前指向别页，按它同步会出错。
    // 故有转场就跳过；转场由 willShow/didShow 负责，静态期间这里持续刷新顶层页（如聊天在线副标题变化）。
    if (self.transitionCoordinator) { return; }
    [self syncBarForController:self.topViewController];
}

// 转场开始：先把**即将出现**的页的栏配好，使其在推入/侧滑露出的整个过程中就完整显示（而非等落定才出现）。
- (void)navigationController:(UINavigationController *)navigationController
     willShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    [self syncBarForController:viewController];
}

// 转场落定（push/pop/交互式返回的完成或取消都回调，viewController 即最终页）后再确认一次。
- (void)navigationController:(UINavigationController *)navigationController
      didShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    [self syncBarForController:viewController];
}

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if (self.viewControllers.count > 0) {
        viewController.hidesBottomBarWhenPushed = YES;
        // 当前页面的返回项使用图标式系统返回键；iOS 26 会自动呈现独立 Liquid Glass 圆钮。
        // Minimal 也避免把上一级标题塞进返回按钮，保持截图中的分离式标题栏。
        viewController.navigationItem.backButtonDisplayMode = UINavigationItemBackButtonDisplayModeMinimal;
    }
    [super pushViewController:viewController animated:animated];
    self.interactivePopGestureRecognizer.enabled = YES;
    [self syncBarForController:self.topViewController];
}

/// Detail / Settings 自绘沉浸式标题栏（栏已挂在它们自己的 view 里）；导航容器不再替它们管栏。
- (BOOL)controllerOwnsBar:(UIViewController *)vc {
    return [vc isKindOfClass:IMChatDetailViewController.class]
        || [vc isKindOfClass:IMSettingsViewController.class];
}

/// 取（首次调用则创建）某页**自己 view 内**的标题栏。放进页面自己的 view 是关键：这样侧滑返回时栏随整页
/// 一起移动、上一页露出即完整显示（对齐 Detail 页做法）；共用一条挂在导航容器上的固定栏做不到这点。
- (IMLiquidNavigationBar *)barForController:(UIViewController *)vc {
    if (![vc isViewLoaded]) { return nil; }
    for (UIView *sub in vc.view.subviews) {
        if ([sub isKindOfClass:IMLiquidNavigationBar.class]) { return (IMLiquidNavigationBar *)sub; }
    }
    IMLiquidNavigationBar *bar = [[IMLiquidNavigationBar alloc] initWithTitle:@"" subtitle:@"" actionTitle:nil];
    bar.delegate = self;
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:bar];
    // 底边贴本页 safeArea 顶 + 0（而非 Detail 自持栏的 +56）：本页的 additionalSafeAreaInsets.top 已被
    // 设为 56（见 syncBarForController:），页面自身的 safeAreaLayoutGuide 顶部 = 状态栏 + 56，56 已计入；
    // 再 +56 会叠加成「状态栏 + 112」，标题栏整体下坠一截（Detail 页 inset 为 0，故它要显式 +56）。
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor],
        [bar.topAnchor constraintEqualToAnchor:vc.view.topAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor],
    ]];
    return bar;
}

- (void)setExtraTopInset:(CGFloat)extra forController:(UIViewController *)vc {
    UIEdgeInsets insets = vc.additionalSafeAreaInsets;
    if (fabs(insets.top - extra) > 0.5) { insets.top = extra; vc.additionalSafeAreaInsets = insets; }
}

/// 同步某页的标题栏（内容取自该页自身，不读 topViewController——转场中 top 已提前指向别页会出错）。
- (void)syncBarForController:(UIViewController *)vc {
    if (!vc || ![vc isViewLoaded]) { return; }
    if ([self controllerOwnsBar:vc]) { [self setExtraTopInset:0 forController:vc]; return; }
    [self setExtraTopInset:kIMLiquidBarExtraTopInset forController:vc]; // 列表内容从标题栏下方开始
    IMLiquidNavigationBar *bar = [self barForController:vc];
    if (!bar) { return; }
    [vc.view bringSubviewToFront:bar]; // 页面若在其后又加了子视图，保持栏在最上层不被盖住
    // 告诉栏「本页安全区被我撑大了多少」：栏按 safeAreaInsets.top 摆按钮，而上面 setExtraTopInset: 已把
    // 本页安全区撑到「状态栏+56」，不减掉这 56 按钮会下移到 bounds 之外——可见但点不到。
    // 传常量而非"当前状态栏高度"：后者随设备/旋转/是否已入窗而变，而本容器在旋转时不会重新同步（见
    // viewDidLayoutSubviews 的转场早退）。栏用减法从同一份 safeAreaInsets 还原，任何时刻自洽。
    bar.hostExtraTopInset = kIMLiquidBarExtraTopInset;

    BOOL isChat = [vc isKindOfClass:IMChatViewController.class];
    bar.titleText = vc.title ?: @"";
    bar.showsTitleGlass = isChat;
    bar.subtitleText = isChat ? ([(IMChatViewController *)vc im_navigationSubtitle] ?: @"") : @"";
    bar.compactContentProgress = 1;
    bar.immersiveAppearanceProgress = 0;
    CGFloat backgroundProgress = 1;
    if ([vc respondsToSelector:@selector(im_navigationBackgroundProgress)]) {
        NSMethodSignature *signature = [vc methodSignatureForSelector:@selector(im_navigationBackgroundProgress)];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.selector = @selector(im_navigationBackgroundProgress);
        invocation.target = vc;
        [invocation invoke];
        [invocation getReturnValue:&backgroundProgress];
    }
    bar.backgroundEffectProgress = backgroundProgress;

    UIBarButtonItem *left = vc.navigationItem.leftBarButtonItem;
    UIBarButtonItem *right = vc.navigationItem.rightBarButtonItem;
    self.leftItem = left;   // 仅顶层栏可点，故按钮回调统一路由到 topViewController（见 didTap* 方法）
    self.rightItem = right;
    BOOL root = self.viewControllers.firstObject == vc;
    bar.showsBackButton = !root || left != nil;
    bar.leftTitle = nil;
    bar.leftImage = nil;
    if (left) {
        bar.leftTitle = left.title;
        bar.leftImage = left.image;
        if (!left.title.length && !left.image) {
            bar.leftImage = [UIImage systemImageNamed:(left.style == UIBarButtonItemStyleDone ? @"xmark" : @"chevron.backward")];
        }
    }
    UIImage *actionImage = right.image;
    if (!actionImage && [right.customView isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)right.customView;
        actionImage = button.configuration.image ?: [button imageForState:UIControlStateNormal];
    }
    bar.actionTitle = right.title;
    bar.actionImage = actionImage;
    bar.actionCircular = right != nil && right.title.length == 0 && actionImage != nil;
    bar.actionEnabled = right ? right.enabled : YES;
}

- (void)invokeBarItem:(UIBarButtonItem *)item onController:(UIViewController *)controller {
    if (!item) { return; }
    if ([item.customView isKindOfClass:UIButton.class]) {
        [(UIButton *)item.customView sendActionsForControlEvents:UIControlEventTouchUpInside];
        return;
    }
    id target = item.target ?: controller;
    if (item.action && [target respondsToSelector:item.action]) {
        UIApplication *app = UIApplication.sharedApplication;
        [app sendAction:item.action to:target from:item forEvent:nil];
    }
}

- (void)liquidNavigationBarDidTapBack:(IMLiquidNavigationBar *)bar {
    [self popViewControllerAnimated:YES];
}
- (void)liquidNavigationBarDidTapLeft:(IMLiquidNavigationBar *)bar {
    [self invokeBarItem:self.leftItem onController:self.topViewController];
}
- (void)liquidNavigationBarDidTapAction:(IMLiquidNavigationBar *)bar {
    [self invokeBarItem:self.rightItem onController:self.topViewController];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.interactivePopGestureRecognizer) {
        return self.viewControllers.count > 1 && self.transitionCoordinator == nil;
    }
    return YES;
}

@end

@implementation IMMainTabBarController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        // 必须先切换账号命名空间，再创建任何会读取本地消息/会话的子页面。
        [IMDatabase.sharedDatabase useOwnerUserID:userID];
        IMConversationListViewController *convList =
            [[IMConversationListViewController alloc] initWithHost:host userID:userID];
        UINavigationController *convNav = [[IMMainNavigationController alloc] initWithRootViewController:convList];
        convNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"会话"
                                                           image:[UIImage systemImageNamed:@"bubble.left.and.bubble.right"]
                                                             tag:0];

        IMContactsViewController *contacts =
            [[IMContactsViewController alloc] initWithHost:host userID:userID];
        UINavigationController *contactsNav = [[IMMainNavigationController alloc] initWithRootViewController:contacts];
        contactsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"通讯录"
                                                               image:[UIImage systemImageNamed:@"person.2"]
                                                                 tag:1];

        IMSettingsViewController *settings = [[IMSettingsViewController alloc] initWithHost:host userID:userID];
        UINavigationController *settingsNav = [[IMMainNavigationController alloc] initWithRootViewController:settings];
        settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"我"
                                                               image:[UIImage systemImageNamed:@"person.crop.circle"]
                                                                 tag:2];

        IMUserSearchViewController *search = [[IMUserSearchViewController alloc] initWithHost:host userID:userID];
        UINavigationController *searchNav = [[IMMainNavigationController alloc] initWithRootViewController:search];
        searchNav.tabBarItem = [[UITabBarItem alloc] initWithTabBarSystemItem:UITabBarSystemItemSearch tag:3];

        if (@available(iOS 18.0, *)) {
            self.mode = UITabBarControllerModeTabBar;
            UITab *convTab = [[UITab alloc] initWithTitle:@"会话" image:[UIImage systemImageNamed:@"bubble.left.and.bubble.right"]
                                               identifier:@"im.tab.conversations"
                                   viewControllerProvider:^UIViewController *(UITab *tab) { return convNav; }];
            UITab *contactsTab = [[UITab alloc] initWithTitle:@"通讯录" image:[UIImage systemImageNamed:@"person.2"]
                                                   identifier:@"im.tab.contacts"
                                       viewControllerProvider:^UIViewController *(UITab *tab) { return contactsNav; }];
            UITab *settingsTab = [[UITab alloc] initWithTitle:@"我" image:[UIImage systemImageNamed:@"person.crop.circle"]
                                                   identifier:@"im.tab.settings"
                                       viewControllerProvider:^UIViewController *(UITab *tab) { return settingsNav; }];
            UITab *searchTab = [[UITab alloc] initWithTitle:@"搜索" image:[UIImage systemImageNamed:@"magnifyingglass"]
                                                 identifier:@"im.tab.search"
                                     viewControllerProvider:^UIViewController *(UITab *tab) { return searchNav; }];
            searchTab.preferredPlacement = UITabPlacementPinned; // iOS 26：右侧独立 Glass 搜索圆钮
            self.tabs = @[convTab, contactsTab, settingsTab, searchTab];
            if (@available(iOS 26.0, *)) {
                self.tabBarMinimizeBehavior = UITabBarMinimizeBehaviorNever;
            }
        } else {
            self.viewControllers = @[convNav, contactsNav, settingsNav, searchNav];
        }
    }
    return self;
}

@end
