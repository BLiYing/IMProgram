//  IMDeviceDetailViewController.m

#import "IMDeviceDetailViewController.h"
#import "IMDeviceModels.h"
#import "IMHTTPService.h"
#import "IMKeyValueCardView.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"
#import "IMLocalization.h"

@interface IMDeviceDetailViewController ()
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, strong) IMDeviceSession *device;
@property (nonatomic, strong) UIButton *revokeButton;
@property (nonatomic, assign) BOOL submitting;
@end

@implementation IMDeviceDetailViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID device:(IMDeviceSession *)device {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        _device = device;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"device.detail.title");
    self.view.backgroundColor = IMTheme.groupedBackground;

    UILabel *icon = [UILabel new];
    icon.text = self.device.platformEmoji;
    icon.font = [UIFont systemFontOfSize:34];
    icon.textAlignment = NSTextAlignmentCenter;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:icon];

    UILabel *name = [UILabel new];
    name.text = self.device.deviceName.length ? self.device.deviceName : IMLocalized(@"device.platform.unknown");
    name.font = [UIFont systemFontOfSize:19 weight:UIFontWeightSemibold];
    name.textColor = IMTheme.textPrimary;
    name.textAlignment = NSTextAlignmentCenter;
    name.numberOfLines = 2;
    name.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:name];

    UIView *card = [self buildInfoCard];
    [self.view addSubview:card];

    UILabel *note = [UILabel new];
    note.text = IMLocalized(@"device.detail.location_note");
    note.font = [UIFont systemFontOfSize:12];
    note.textColor = IMTheme.textSecondary;
    note.numberOfLines = 0;
    note.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:note];

    self.revokeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.revokeButton setTitle:IMLocalized(@"device.detail.revoke_button") forState:UIControlStateNormal];
    [self.revokeButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.revokeButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.revokeButton.backgroundColor = IMTheme.danger;
    self.revokeButton.layer.cornerRadius = 12;
    [self.revokeButton addTarget:self action:@selector(confirmRevoke) forControlEvents:UIControlEventTouchUpInside];
    self.revokeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.revokeButton];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [icon.topAnchor constraintEqualToAnchor:g.topAnchor constant:24],
        [icon.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [name.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:8],
        [name.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [name.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],

        [card.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:22],
        [card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [note.topAnchor constraintEqualToAnchor:card.bottomAnchor constant:10],
        [note.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:18],
        [note.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-18],

        [self.revokeButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.revokeButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.revokeButton.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-20],
        [self.revokeButton.heightAnchor constraintEqualToConstant:50],
    ]];
}

- (UIView *)buildInfoCard {
    IMDeviceSession *d = self.device;
    NSString *statusText = d.online ? IMLocalized(@"common.online") : d.lastActiveText;
    UIColor *statusColor = d.online ? IMTheme.onlineDot : IMTheme.textSecondary;
    NSString *typeText = d.appVersion.length ? [NSString stringWithFormat:@"%@ · v%@", d.platformLabel, d.appVersion]
                                             : d.platformLabel;
    return [IMKeyValueCardView cardWithRows:@[
        @[IMLocalized(@"common.status"), statusText, statusColor],
        @[IMLocalized(@"common.type"), typeText],
        @[IMLocalized(@"device.detail.login_time"), d.loginTimeText],
        @[IMLocalized(@"device.detail.last_active"), (d.online ? IMLocalized(@"device.detail.currently_online") : d.lastActiveText)],
        @[IMLocalized(@"qr.login_confirm.row_ip"), (d.loginIP.length ? d.loginIP : IMLocalized(@"common.unknown"))],
        @[IMLocalized(@"qr.login_confirm.row_location"), (d.loginLoc.length ? d.loginLoc : IMLocalized(@"common.unknown"))],
    ]];
}

#pragma mark - 退出该设备

- (void)confirmRevoke {
    if (self.submitting) { return; }
    NSString *name = self.device.deviceName.length ? self.device.deviceName : IMLocalized(@"device.detail.fallback_name");
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:IMLocalized(@"device.detail.revoke_confirm_title")
        message:IMLocalizedFormat(@"device.detail.revoke_confirm_message", name)
        preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"settings.logout") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [ws revoke];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)revoke {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:IMLocalized(@"common.login_expired")]; return; }
    self.submitting = YES;
    self.revokeButton.enabled = NO;
    self.revokeButton.alpha = 0.6;
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService revokeDeviceWithToken:token sessionID:self.device.sessionID completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) {
            self.submitting = NO;
            self.revokeButton.enabled = YES;
            self.revokeButton.alpha = 1.0;
            [self im_showToast:(error.localizedDescription.length ? error.localizedDescription : IMLocalized(@"device.detail.revoke_failed"))];
            return;
        }
        // 列表页 viewWillAppear 会自动重刷，这里只需回退 + 全局提示。
        [self.navigationController popViewControllerAnimated:YES];
        [UIViewController im_showGlobalToast:IMLocalized(@"device.detail.revoked_toast")];
    }];
}

@end
