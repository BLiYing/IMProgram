//  IMSettingsViewController.m

#import "IMSettingsViewController.h"
#import "IMProfileEditViewController.h"
#import "IMBlockedListViewController.h"
#import "IMLoginViewController.h"
#import "IMSocketManager.h"
#import "IMTheme.h"

@interface IMSettingsViewController ()
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@end

@implementation IMSettingsViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"我";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UILabel *uidLabel = [UILabel new];
    uidLabel.translatesAutoresizingMaskIntoConstraints = NO;
    uidLabel.text = [NSString stringWithFormat:@"当前账号：%@", self.userID];
    uidLabel.textColor = IMTheme.textPrimary;

    UIButton *editButton = [UIButton buttonWithType:UIButtonTypeSystem];
    editButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIButtonConfiguration *editCfg = [UIButtonConfiguration filledButtonConfiguration];
    editCfg.baseBackgroundColor = IMTheme.accent;
    editButton.configuration = editCfg;
    [editButton setTitle:@"编辑资料" forState:UIControlStateNormal];
    [editButton addTarget:self action:@selector(editProfileTapped) forControlEvents:UIControlEventTouchUpInside];

    UIButton *blockedButton = [UIButton buttonWithType:UIButtonTypeSystem];
    blockedButton.translatesAutoresizingMaskIntoConstraints = NO;
    blockedButton.configuration = [UIButtonConfiguration grayButtonConfiguration];
    [blockedButton setTitle:@"黑名单" forState:UIControlStateNormal];
    [blockedButton addTarget:self action:@selector(blockedTapped) forControlEvents:UIControlEventTouchUpInside];

    UIButton *logoutButton = [UIButton buttonWithType:UIButtonTypeSystem];
    logoutButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIButtonConfiguration *cfg = [UIButtonConfiguration filledButtonConfiguration];
    cfg.baseBackgroundColor = UIColor.systemRedColor;
    logoutButton.configuration = cfg;
    [logoutButton setTitle:@"退出登录" forState:UIControlStateNormal];
    [logoutButton addTarget:self action:@selector(logoutTapped) forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:uidLabel];
    [self.view addSubview:editButton];
    [self.view addSubview:blockedButton];
    [self.view addSubview:logoutButton];
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [uidLabel.topAnchor constraintEqualToAnchor:guide.topAnchor constant:IMTheme.space4 * 2],
        [uidLabel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:IMTheme.space4],
        [editButton.topAnchor constraintEqualToAnchor:uidLabel.bottomAnchor constant:IMTheme.space4 * 2],
        [editButton.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:IMTheme.space4],
        [editButton.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-IMTheme.space4],
        [blockedButton.topAnchor constraintEqualToAnchor:editButton.bottomAnchor constant:IMTheme.space3],
        [blockedButton.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:IMTheme.space4],
        [blockedButton.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-IMTheme.space4],
        [logoutButton.topAnchor constraintEqualToAnchor:blockedButton.bottomAnchor constant:IMTheme.space3],
        [logoutButton.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:IMTheme.space4],
        [logoutButton.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-IMTheme.space4],
    ]];
}

- (void)editProfileTapped {
    IMProfileEditViewController *edit = [[IMProfileEditViewController alloc] initWithHost:self.host userID:self.userID];
    [self.navigationController pushViewController:edit animated:YES];
}

- (void)blockedTapped {
    IMBlockedListViewController *blocked = [[IMBlockedListViewController alloc] initWithHost:self.host userID:self.userID];
    [self.navigationController pushViewController:blocked animated:YES];
}

- (void)logoutTapped {
    [IMSocketManager.sharedManager disconnect];
    UIWindow *window = self.view.window;
    IMLoginViewController *login = [IMLoginViewController new];
    window.rootViewController = [[UINavigationController alloc] initWithRootViewController:login];
}

@end
