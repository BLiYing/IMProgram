//  IMDeviceDetailViewController.m

#import "IMDeviceDetailViewController.h"
#import "IMDeviceModels.h"
#import "IMHTTPService.h"
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
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.backgroundColor = IMTheme.cardBackground;
    stack.layer.cornerRadius = 12;
    stack.layoutMargins = UIEdgeInsetsMake(2, 14, 2, 14);
    stack.layoutMarginsRelativeArrangement = YES;

    IMDeviceSession *d = self.device;
    NSString *statusText = d.online ? @"在线" : d.lastActiveText;
    UIColor *statusColor = d.online ? IMTheme.onlineDot : IMTheme.textSecondary;
    NSString *typeText = d.appVersion.length ? [NSString stringWithFormat:@"%@ · v%@", d.platformLabel, d.appVersion]
                                             : d.platformLabel;

    NSArray *rows = @[
        @[@"状态", statusText, statusColor],
        @[@"类型", typeText, IMTheme.textSecondary],
        @[@"登录时间", d.loginTimeText, IMTheme.textSecondary],
        @[@"最近活跃", (d.online ? @"当前在线" : d.lastActiveText), IMTheme.textSecondary],
        @[@"IP 地址", (d.loginIP.length ? d.loginIP : @"未知"), IMTheme.textSecondary],
        @[@"大致位置", (d.loginLoc.length ? d.loginLoc : @"未知"), IMTheme.textSecondary],
    ];
    for (NSUInteger i = 0; i < rows.count; i++) {
        NSArray *r = rows[i];
        [stack addArrangedSubview:[self kvRowKey:r[0] value:r[1] valueColor:r[2] showSeparator:(i > 0)]];
    }
    return stack;
}

- (UIView *)kvRowKey:(NSString *)key value:(NSString *)value valueColor:(UIColor *)valueColor showSeparator:(BOOL)sep {
    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *k = [UILabel new];
    k.text = key;
    k.font = [UIFont systemFontOfSize:14];
    k.textColor = IMTheme.textPrimary;
    k.translatesAutoresizingMaskIntoConstraints = NO;
    [k setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [row addSubview:k];

    UILabel *v = [UILabel new];
    v.text = value;
    v.font = [UIFont systemFontOfSize:13];
    v.textColor = valueColor ?: IMTheme.textSecondary;
    v.textAlignment = NSTextAlignmentRight;
    v.numberOfLines = 0;
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:v];

    NSMutableArray<NSLayoutConstraint *> *cons = [NSMutableArray arrayWithArray:@[
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [k.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [k.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [v.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [v.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [v.leadingAnchor constraintGreaterThanOrEqualToAnchor:k.trailingAnchor constant:12],
        [v.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor constant:9],
        [v.bottomAnchor constraintLessThanOrEqualToAnchor:row.bottomAnchor constant:-9],
    ]];
    if (sep) {
        UIView *line = [UIView new];
        line.backgroundColor = IMTheme.separator;
        line.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:line];
        [cons addObjectsFromArray:@[
            [line.topAnchor constraintEqualToAnchor:row.topAnchor],
            [line.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [line.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [line.heightAnchor constraintEqualToConstant:0.5],
        ]];
    }
    [NSLayoutConstraint activateConstraints:cons];
    return row;
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
