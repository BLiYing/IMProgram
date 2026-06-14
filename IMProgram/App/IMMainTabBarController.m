//  IMMainTabBarController.m

#import "IMMainTabBarController.h"
#import "IMConversationListViewController.h"
#import "IMSettingsViewController.h"

@implementation IMMainTabBarController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        IMConversationListViewController *convList =
            [[IMConversationListViewController alloc] initWithHost:host userID:userID];
        UINavigationController *convNav = [[UINavigationController alloc] initWithRootViewController:convList];
        convNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"会话"
                                                           image:[UIImage systemImageNamed:@"bubble.left.and.bubble.right"]
                                                             tag:0];

        IMSettingsViewController *settings = [[IMSettingsViewController alloc] initWithUserID:userID];
        UINavigationController *settingsNav = [[UINavigationController alloc] initWithRootViewController:settings];
        settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"我"
                                                               image:[UIImage systemImageNamed:@"person.crop.circle"]
                                                                 tag:1];

        self.viewControllers = @[convNav, settingsNav];
    }
    return self;
}

@end
