//  IMSettingsViewController.m

#import "IMSettingsViewController.h"
#import "IMLoginViewController.h"
#import "IMSocketManager.h"
#import "IMTheme.h"

@interface IMSettingsViewController ()
@property (nonatomic, copy) NSString *userID;
@end

@implementation IMSettingsViewController

- (instancetype)initWithUserID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) { _userID = [userID copy]; }
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

    UIButton *logoutButton = [UIButton buttonWithType:UIButtonTypeSystem];
    logoutButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIButtonConfiguration *cfg = [UIButtonConfiguration filledButtonConfiguration];
    cfg.baseBackgroundColor = UIColor.systemRedColor;
    logoutButton.configuration = cfg;
    [logoutButton setTitle:@"退出登录" forState:UIControlStateNormal];
    [logoutButton addTarget:self action:@selector(logoutTapped) forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:uidLabel];
    [self.view addSubview:logoutButton];
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [uidLabel.topAnchor constraintEqualToAnchor:guide.topAnchor constant:IMTheme.space4 * 2],
        [uidLabel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:IMTheme.space4],
        [logoutButton.topAnchor constraintEqualToAnchor:uidLabel.bottomAnchor constant:IMTheme.space4 * 2],
        [logoutButton.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:IMTheme.space4],
        [logoutButton.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-IMTheme.space4],
    ]];
}

- (void)logoutTapped {
    [IMSocketManager.sharedManager disconnect];
    UIWindow *window = self.view.window;
    IMLoginViewController *login = [IMLoginViewController new];
    window.rootViewController = [[UINavigationController alloc] initWithRootViewController:login];
}

@end
