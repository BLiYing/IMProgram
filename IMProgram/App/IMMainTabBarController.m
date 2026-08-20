//  IMMainTabBarController.m

#import "IMMainTabBarController.h"
#import "IMConversationListViewController.h"
#import "IMContactsViewController.h"
#import "IMSettingsViewController.h"
#import "IMUserSearchViewController.h"
#import "IMProgram-Swift.h"
#import "IMChatDetailViewController.h"
#import "IMGlobalSearchViewController.h"
#import "IMChatViewController.h"
#import "IMDatabase.h"
#import <objc/runtime.h>

CGFloat const kIMLiquidBarHeight = 56;

/// 关联对象键：容器注入到某页的标题栏。**只认自己注入的那条**——不扫子视图找
/// `IMLiquidNavigationBar`，否则会把页面自持的栏（详情/「我」的写法）误当成自己的接管、
/// 每帧覆写它的标题与左右按钮。
static void * const kIMInjectedBarKey = (void *)&kIMInjectedBarKey;

/// 任何页面都可选实现，向注入的标题栏提供副标题（连接态 / 在线态 / 成员数等）。
/// 聊天页与会话列表页均实现之——连接态统一走副标题（同「在线」位置），标题保持纯净。
@protocol IMNavigationSubtitleProviding <NSObject>
- (NSString *)im_navigationSubtitle;
@end

/// 主界面统一导航容器：所有非根页面自动隐藏 TabBar，并恢复系统边缘侧滑返回。
/// 这样新增页面只需正常 push，不再依赖每个控制器手动设置 hidesBottomBarWhenPushed。
@interface IMMainNavigationController : UINavigationController <UIGestureRecognizerDelegate, UINavigationControllerDelegate, IMLiquidNavigationBarDelegate>
- (void)syncBarForController:(UIViewController *)vc;
- (void)setBackBadgeCount:(NSInteger)count forController:(UIViewController *)vc; // 任务2：返回按钮未读徽标
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
        || [vc isKindOfClass:IMSettingsViewController.class]
        || [vc isKindOfClass:IMGlobalSearchViewController.class]; // 自持 searchMode 液态栏（搜索框在标题行）
}

/// 取（首次调用则创建）某页**自己 view 内**的标题栏。放进页面自己的 view 是关键：这样侧滑返回时栏随整页
/// 一起移动、上一页露出即完整显示（对齐 Detail 页做法）；共用一条挂在导航容器上的固定栏做不到这点。
///
/// 用关联对象记住"我注入的那条"，而非扫子视图找 `IMLiquidNavigationBar`：后者分不清页面自持的栏，
/// 一旦某个自持栏页面漏进白名单就会被静默接管（标题/按钮每帧被覆写、页面自己的按钮失灵）。
- (IMLiquidNavigationBar *)barForController:(UIViewController *)vc {
    if (![vc isViewLoaded]) { return nil; }
    IMLiquidNavigationBar *existing = objc_getAssociatedObject(vc, kIMInjectedBarKey);
    if (existing) { return existing; }

    // 顺序要害：栏高由「本页安全区顶」反推，故必须**先**撑安全区再建约束，否则首帧栏塌成 0 高。
    // 把它放在创建栏之前而非交给调用方保证，调用顺序就不再是隐式契约。
    [self setExtraTopInset:kIMLiquidBarHeight forController:vc];

    IMLiquidNavigationBar *bar = [[IMLiquidNavigationBar alloc] initWithTitle:@"" subtitle:@"" actionTitle:nil];
    bar.delegate = self;
    // 告诉栏「宿主安全区被撑大了多少」：栏按 safeAreaInsets.top 摆按钮，不减掉这 56 按钮会下移到
    // bounds 之外——可见但 hitTest 点不到。存"撑大了多少"（常量）而非"状态栏多高"（随设备/旋转/
    // 是否入窗而变）：栏用减法从同一份 safeAreaInsets 还原，旋转与首次入窗都无需重新同步。
    bar.hostExtraTopInset = kIMLiquidBarHeight;
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:bar];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor],
        [bar.topAnchor constraintEqualToAnchor:vc.view.topAnchor],
        // 底边贴本页 safeArea 顶（其中已含上面撑进去的 56）；自持栏页面 inset 为 0，故它们要显式 +56。
        [bar.bottomAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor],
    ]];
    objc_setAssociatedObject(vc, kIMInjectedBarKey, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return bar;
}

- (void)setExtraTopInset:(CGFloat)extra forController:(UIViewController *)vc {
    UIEdgeInsets insets = vc.additionalSafeAreaInsets;
    if (fabs(insets.top - extra) > 0.5) { insets.top = extra; vc.additionalSafeAreaInsets = insets; }
}

/// 任务2：把返回按钮未读徽标数设到某页的注入栏（页面自持栏/未注入时安全空转）。
- (void)setBackBadgeCount:(NSInteger)count forController:(UIViewController *)vc {
    if (!vc || ![vc isViewLoaded] || [self controllerOwnsBar:vc]) { return; }
    IMLiquidNavigationBar *bar = [self barForController:vc];
    bar.backBadgeCount = count;
}

/// 同步某页的标题栏（内容取自该页自身，不读 topViewController——转场中 top 已提前指向别页会出错）。
- (void)syncBarForController:(UIViewController *)vc {
    if (!vc || ![vc isViewLoaded]) { return; }
    if ([self controllerOwnsBar:vc]) { [self setExtraTopInset:0 forController:vc]; return; }
    IMLiquidNavigationBar *bar = [self barForController:vc]; // 内部已先撑安全区
    if (!bar) { return; }
    // 页面可能在建栏之后又往 self.view 加了内容（聊天页 viewDidLoad 里先装导航按钮触发建栏、
    // 再 setupUI 加满屏 tableView + 壁纸），会把栏埋在底下看不见。仅当栏不在最上层时才提栏——
    // 静止态是 no-op，不会每帧打乱层级触发重排。
    if (vc.view.subviews.lastObject != bar) { [vc.view bringSubviewToFront:bar]; }
    [self applyTitleForController:vc toBar:bar];
    [self applyBarItemsForController:vc toBar:bar];
}

/// 标题/副标题/背景等"内容"部分。
- (void)applyTitleForController:(UIViewController *)vc toBar:(IMLiquidNavigationBar *)bar {
    BOOL isChat = [vc isKindOfClass:IMChatViewController.class];
    bar.titleText = vc.title ?: @"";
    bar.showsTitleGlass = isChat;
    // 副标题通用化：任何实现 im_navigationSubtitle 的页面都可提供（聊天页在线态/成员数、
    // 会话列表连接态…）。连接态不再拼进标题后缀，统一走副标题（同「在线」位置，无括号）。
    NSString *subtitle = @"";
    if ([vc respondsToSelector:@selector(im_navigationSubtitle)]) {
        subtitle = [(id<IMNavigationSubtitleProviding>)vc im_navigationSubtitle] ?: @"";
    }
    bar.subtitleText = subtitle;
    bar.compactContentProgress = 1;
    bar.immersiveAppearanceProgress = 0;
    bar.backgroundEffectProgress = 1;
}

/// 左右按钮：一律现取本页 `navigationItem`，不缓存到容器上——多条栏可同时在场（侧滑时前后两页的栏
/// 都可见可点），缓存一份就会出现"点 A 页的按钮却触发 B 页动作"。
- (void)applyBarItemsForController:(UIViewController *)vc toBar:(IMLiquidNavigationBar *)bar {
    UIBarButtonItem *left = vc.navigationItem.leftBarButtonItem;
    UIBarButtonItem *right = vc.navigationItem.rightBarButtonItem;
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

/// 被点的那条栏属于哪一页。侧滑期间前后两页的栏同时在场，必须按栏反查宿主页，
/// 不能想当然用 topViewController（转场中它已提前指向另一页）。
- (UIViewController *)controllerOwningBar:(IMLiquidNavigationBar *)bar {
    UIView *host = bar.superview;
    for (UIViewController *vc in self.viewControllers) {
        if (vc.isViewLoaded && vc.view == host) { return vc; }
    }
    return self.topViewController;
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
    // 只有当前顶层页的返回键才该 pop：侧滑露出的下层页的栏也可见，误触不应再弹一层。
    if ([self controllerOwningBar:bar] != self.topViewController) { return; }
    [self popViewControllerAnimated:YES];
}
- (void)liquidNavigationBarDidTapLeft:(IMLiquidNavigationBar *)bar {
    UIViewController *owner = [self controllerOwningBar:bar];
    [self invokeBarItem:owner.navigationItem.leftBarButtonItem onController:owner];
}
- (void)liquidNavigationBarDidTapAction:(IMLiquidNavigationBar *)bar {
    UIViewController *owner = [self controllerOwningBar:bar];
    [self invokeBarItem:owner.navigationItem.rightBarButtonItem onController:owner];
}
// 中间标题被点（仅聊天页 showsTitleGlass）：等同点右上角头像——打开会话详情。
- (void)liquidNavigationBarDidTapTitle:(IMLiquidNavigationBar *)bar {
    UIViewController *owner = [self controllerOwningBar:bar];
    [self invokeBarItem:owner.navigationItem.rightBarButtonItem onController:owner];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.interactivePopGestureRecognizer) {
        return self.viewControllers.count > 1 && self.transitionCoordinator == nil;
    }
    return YES;
}

@end

@implementation UIViewController (IMNavigationBar)

- (void)im_refreshNavigationBar {
    UINavigationController *nav = self.navigationController;
    if ([nav isKindOfClass:IMMainNavigationController.class]) {
        [(IMMainNavigationController *)nav syncBarForController:self];
    }
}

- (void)im_setBackBadgeCount:(NSInteger)count {
    UINavigationController *nav = self.navigationController;
    if ([nav isKindOfClass:IMMainNavigationController.class]) {
        [(IMMainNavigationController *)nav setBackBadgeCount:count forController:self];
    }
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
