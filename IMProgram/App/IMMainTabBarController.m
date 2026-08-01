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

/// 可选的自定义导航背景进度接口；声明后仍通过 respondsToSelector 兼容未实现页面。
@interface UIViewController (IMNavigationBackgroundProgress)
- (CGFloat)im_navigationBackgroundProgress;
@end

/// 主界面统一导航容器：所有非根页面自动隐藏 TabBar，并恢复系统边缘侧滑返回。
/// 这样新增页面只需正常 push，不再依赖每个控制器手动设置 hidesBottomBarWhenPushed。
@interface IMMainNavigationController : UINavigationController <UIGestureRecognizerDelegate, IMLiquidNavigationBarDelegate>
@property (nonatomic, strong) IMLiquidNavigationBar *imLiquidBar;
@property (nonatomic, weak) UIBarButtonItem *leftItem;
@property (nonatomic, weak) UIBarButtonItem *rightItem;
@end

@implementation IMMainNavigationController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.interactivePopGestureRecognizer.delegate = self;
    self.interactivePopGestureRecognizer.enabled = YES;
    self.navigationBar.prefersLargeTitles = NO;
    [self setNavigationBarHidden:YES animated:NO];
    self.imLiquidBar = [[IMLiquidNavigationBar alloc] initWithTitle:@"" subtitle:@"" actionTitle:nil];
    self.imLiquidBar.delegate = self;
    self.imLiquidBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.imLiquidBar];
    [NSLayoutConstraint activateConstraints:@[
        [self.imLiquidBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.imLiquidBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.imLiquidBar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.imLiquidBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:56],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self setNavigationBarHidden:YES animated:NO];
    [self syncLiquidBar];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self syncLiquidBar];
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
    [self syncLiquidBar];
}

- (void)syncLiquidBar {
    if (!self.isViewLoaded || !self.imLiquidBar) { return; }
    UIViewController *top = self.topViewController;
    BOOL ownsBar = [top isKindOfClass:IMChatDetailViewController.class];
    self.imLiquidBar.hidden = ownsBar;
    UIEdgeInsets insets = top.additionalSafeAreaInsets;
    BOOL isChat = [top isKindOfClass:IMChatViewController.class];
    // 聊天列表必须从自定义标题栏下方开始；只有详情页自持沉浸式导航并允许内容铺到顶端。
    CGFloat extraTop = ownsBar ? 0 : 56;
    if (fabs(insets.top - extraTop) > 0.5) {
        insets.top = extraTop;
        top.additionalSafeAreaInsets = insets;
    }
    if (ownsBar) { return; }
    self.imLiquidBar.titleText = top.title ?: @"";
    self.imLiquidBar.showsTitleGlass = isChat;
    NSString *subtitle = @"";
    if (isChat) {
        subtitle = [(IMChatViewController *)top im_navigationSubtitle] ?: @"";
    }
    self.imLiquidBar.subtitleText = subtitle;
    self.imLiquidBar.compactContentProgress = 1;
    self.imLiquidBar.immersiveAppearanceProgress = 0;
    CGFloat backgroundProgress = 1;
    if ([top respondsToSelector:@selector(im_navigationBackgroundProgress)]) {
        NSMethodSignature *signature = [top methodSignatureForSelector:@selector(im_navigationBackgroundProgress)];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.selector = @selector(im_navigationBackgroundProgress);
        invocation.target = top;
        [invocation invoke];
        [invocation getReturnValue:&backgroundProgress];
    }
    self.imLiquidBar.backgroundEffectProgress = backgroundProgress;

    UIBarButtonItem *left = top.navigationItem.leftBarButtonItem;
    UIBarButtonItem *right = top.navigationItem.rightBarButtonItem;
    self.leftItem = left;
    self.rightItem = right;
    BOOL root = self.viewControllers.count <= 1;
    self.imLiquidBar.showsBackButton = !root || left != nil;
    self.imLiquidBar.leftTitle = nil;
    self.imLiquidBar.leftImage = nil;
    if (left) {
        self.imLiquidBar.leftTitle = left.title;
        self.imLiquidBar.leftImage = left.image;
        if (!left.title.length && !left.image) {
            self.imLiquidBar.leftImage = [UIImage systemImageNamed:(left.style == UIBarButtonItemStyleDone ? @"xmark" : @"chevron.backward")];
        }
    }
    UIImage *actionImage = right.image;
    if (!actionImage && [right.customView isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)right.customView;
        actionImage = button.configuration.image ?: [button imageForState:UIControlStateNormal];
    }
    self.imLiquidBar.actionTitle = right.title;
    self.imLiquidBar.actionImage = actionImage;
    self.imLiquidBar.actionCircular = right != nil && right.title.length == 0 && actionImage != nil;
    self.imLiquidBar.actionEnabled = right ? right.enabled : YES;
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
