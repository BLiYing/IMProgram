//  IMQRLoginConfirmViewController.m

#import "IMQRLoginConfirmViewController.h"
#import "IMHTTPService.h"
#import "IMKeyValueCardView.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"

@interface IMQRLoginConfirmViewController ()
@property (nonatomic, copy) NSString *ticket;
@property (nonatomic, copy, nullable) NSString *device;
@property (nonatomic, copy, nullable) NSString *ip;
@property (nonatomic, copy, nullable) NSString *location;
@property (nonatomic, strong) UIButton *confirmButton;
@property (nonatomic, strong) UIButton *rejectButton;
@property (nonatomic, assign) BOOL submitting;
@end

@implementation IMQRLoginConfirmViewController

+ (void)pushFrom:(UIViewController *)from
          ticket:(NSString *)ticket
          device:(NSString *)device
              ip:(NSString *)ip
        location:(NSString *)location {
    IMQRLoginConfirmViewController *vc = [IMQRLoginConfirmViewController new];
    vc.ticket = ticket;
    vc.device = device;
    vc.ip = ip;
    vc.location = location;
    vc.title = @"网页版登录确认"; // 容器注入的液态标题栏据此显示标题 + 返回键
    [from.navigationController pushViewController:vc animated:YES];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = IMTheme.groupedBackground;

    UIImageView *icon = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"desktopcomputer"]];
    icon.tintColor = IMTheme.accent;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:icon];

    UILabel *title = [UILabel new];
    title.text = @"确认登录网页版";
    title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    title.textColor = IMTheme.textPrimary;
    title.textAlignment = NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];

    UILabel *sub = [UILabel new];
    sub.text = @"有设备正在用你的账号登录网页版，请核对下方信息";
    sub.font = [UIFont systemFontOfSize:13];
    sub.textColor = IMTheme.textSecondary;
    sub.textAlignment = NSTextAlignmentCenter;
    sub.numberOfLines = 0;
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:sub];

    // 信息卡：设备 / IP / 大致位置 / 时间（这四条是用户识破"被骗扫码"的唯一依据）。
    UIView *card = [self buildInfoCard];
    [self.view addSubview:card];

    // 安全提示条（红底）。
    UILabel *warn = [UILabel new];
    warn.text = @"不是你本人操作？请点「不是我，拒绝登录」，并尽快修改密码。";
    warn.font = [UIFont systemFontOfSize:12.5];
    warn.textColor = IMTheme.danger;
    warn.numberOfLines = 0;
    warn.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *warnBox = [UIView new];
    warnBox.backgroundColor = [IMTheme.danger colorWithAlphaComponent:0.10];
    warnBox.layer.cornerRadius = 10;
    warnBox.translatesAutoresizingMaskIntoConstraints = NO;
    [warnBox addSubview:warn];
    [self.view addSubview:warnBox];

    self.confirmButton = [self buttonWithTitle:@"确认登录" titleColor:UIColor.whiteColor
                                    background:IMTheme.accent border:nil action:@selector(confirmTapped)];
    [self.view addSubview:self.confirmButton];

    self.rejectButton = [self buttonWithTitle:@"不是我，拒绝登录" titleColor:IMTheme.danger
                                   background:IMTheme.cardBackground border:IMTheme.danger action:@selector(rejectTapped)];
    [self.view addSubview:self.rejectButton];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [icon.topAnchor constraintEqualToAnchor:g.topAnchor constant:28],
        [icon.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [icon.widthAnchor constraintEqualToConstant:52],
        [icon.heightAnchor constraintEqualToConstant:46],

        [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:14],
        [title.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [title.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],

        [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
        [sub.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [sub.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],

        [card.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:22],
        [card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [warnBox.topAnchor constraintEqualToAnchor:card.bottomAnchor constant:14],
        [warnBox.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [warnBox.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [warn.topAnchor constraintEqualToAnchor:warnBox.topAnchor constant:9],
        [warn.bottomAnchor constraintEqualToAnchor:warnBox.bottomAnchor constant:-9],
        [warn.leadingAnchor constraintEqualToAnchor:warnBox.leadingAnchor constant:11],
        [warn.trailingAnchor constraintEqualToAnchor:warnBox.trailingAnchor constant:-11],

        [self.rejectButton.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-20],
        [self.rejectButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.rejectButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.rejectButton.heightAnchor constraintEqualToConstant:50],

        [self.confirmButton.bottomAnchor constraintEqualToAnchor:self.rejectButton.topAnchor constant:-10],
        [self.confirmButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.confirmButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.confirmButton.heightAnchor constraintEqualToConstant:50],
    ]];
}

/// 键值信息卡（复用 IMKeyValueCardView）。
/// 「扫码时间」= 用户此刻扫码/确认的时刻（scan 接口未回服务端时间）——按实义命名，不谎称是网页发起时间。
- (UIView *)buildInfoCard {
    return [IMKeyValueCardView cardWithRows:@[
        @[@"设备", self.device.length ? self.device : @"未知设备"],
        @[@"IP 地址", self.ip.length ? self.ip : @"未知"],
        @[@"大致位置", self.location.length ? self.location : @"未知"],
        @[@"扫码时间", [self nowTimeString]],
    ]];
}

- (UIButton *)buttonWithTitle:(NSString *)title titleColor:(UIColor *)titleColor
                   background:(UIColor *)bg border:(nullable UIColor *)border action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:titleColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    b.backgroundColor = bg;
    b.layer.cornerRadius = 12;
    if (border) {
        b.layer.borderWidth = 1;
        b.layer.borderColor = border.CGColor;
    }
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    return b;
}

- (NSString *)nowTimeString {
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"HH:mm";
    return [@"今天 " stringByAppendingString:[f stringFromDate:NSDate.date]];
}

#pragma mark - 动作

- (void)confirmTapped {
    if (self.submitting) { return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:@"登录已失效，请重新登录"]; return; }
    [self setSubmitting:YES];
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService qrLoginConfirmWithToken:token ticket:self.ticket completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) {
            [self setSubmitting:NO];
            [self im_showToast:(error.localizedDescription.length ? error.localizedDescription : @"确认登录失败")];
            return;
        }
        [self.navigationController popViewControllerAnimated:YES];
        [UIViewController im_showGlobalToast:@"已确认，网页版即将登录"];
    }];
}

- (void)rejectTapped {
    if (self.submitting) { return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:@"登录已失效，请重新登录"]; return; }
    [self setSubmitting:YES];
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService qrLoginRejectWithToken:token ticket:self.ticket completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) {
            [self setSubmitting:NO];
            [self im_showToast:(error.localizedDescription.length ? error.localizedDescription : @"拒绝登录失败")];
            return;
        }
        [self.navigationController popViewControllerAnimated:YES];
        [UIViewController im_showGlobalToast:@"已拒绝该次登录"];
    }];
}

- (void)setSubmitting:(BOOL)submitting {
    _submitting = submitting;
    self.confirmButton.enabled = !submitting;
    self.rejectButton.enabled = !submitting;
    self.confirmButton.alpha = submitting ? 0.6 : 1.0;
    self.rejectButton.alpha = submitting ? 0.6 : 1.0;
}

@end
