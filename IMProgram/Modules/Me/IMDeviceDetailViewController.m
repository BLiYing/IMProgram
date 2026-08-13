//  IMDeviceDetailViewController.m

#import "IMDeviceDetailViewController.h"
#import "IMDeviceModels.h"
#import "IMHTTPService.h"
#import "IMKeyValueCardView.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"

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
    self.title = @"设备详情";
    self.view.backgroundColor = IMTheme.groupedBackground;

    UILabel *icon = [UILabel new];
    icon.text = self.device.platformEmoji;
    icon.font = [UIFont systemFontOfSize:34];
    icon.textAlignment = NSTextAlignmentCenter;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:icon];

    UILabel *name = [UILabel new];
    name.text = self.device.deviceName.length ? self.device.deviceName : @"未知设备";
    name.font = [UIFont systemFontOfSize:19 weight:UIFontWeightSemibold];
    name.textColor = IMTheme.textPrimary;
    name.textAlignment = NSTextAlignmentCenter;
    name.numberOfLines = 2;
    name.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:name];

    UIView *card = [self buildInfoCard];
    [self.view addSubview:card];

    UILabel *note = [UILabel new];
    note.text = @"位置由 IP 粗略反查，仅供识别，不参与鉴权。";
    note.font = [UIFont systemFontOfSize:12];
    note.textColor = IMTheme.textSecondary;
    note.numberOfLines = 0;
    note.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:note];

    self.revokeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.revokeButton setTitle:@"退出登录该设备" forState:UIControlStateNormal];
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
    NSString *statusText = d.online ? @"在线" : d.lastActiveText;
    UIColor *statusColor = d.online ? IMTheme.onlineDot : IMTheme.textSecondary;
    NSString *typeText = d.appVersion.length ? [NSString stringWithFormat:@"%@ · v%@", d.platformLabel, d.appVersion]
                                             : d.platformLabel;
    return [IMKeyValueCardView cardWithRows:@[
        @[@"状态", statusText, statusColor],
        @[@"类型", typeText],
        @[@"登录时间", d.loginTimeText],
        @[@"最近活跃", (d.online ? @"当前在线" : d.lastActiveText)],
        @[@"IP 地址", (d.loginIP.length ? d.loginIP : @"未知")],
        @[@"大致位置", (d.loginLoc.length ? d.loginLoc : @"未知")],
    ]];
}

#pragma mark - 退出该设备

- (void)confirmRevoke {
    if (self.submitting) { return; }
    NSString *name = self.device.deviceName.length ? self.device.deviceName : @"该设备";
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"退出该设备登录？"
        message:[NSString stringWithFormat:@"「%@」将立即下线并需重新登录。若这不是你的设备，退出后建议顺手改密码。", name]
        preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"退出登录" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [ws revoke];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)revoke {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:@"登录已失效，请重新登录"]; return; }
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
            [self im_showToast:(error.localizedDescription.length ? error.localizedDescription : @"退出设备失败")];
            return;
        }
        // 列表页 viewWillAppear 会自动重刷，这里只需回退 + 全局提示。
        [self.navigationController popViewControllerAnimated:YES];
        [UIViewController im_showGlobalToast:@"已退出该设备"];
    }];
}

@end
