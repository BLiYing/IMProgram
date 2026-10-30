//  IMTwoStepBindViewController.m

#import "IMTwoStepBindViewController.h"
#import "IMTwoStepCodesViewController.h"
#import "IMTwoStepViews.h"
#import "IMTwoStep.h"
#import "IMHTTPService+TwoStep.h"
#import "IMLocalization.h"
#import "IMLog.h"
#import "UIViewController+IMToast.h"

@interface IMTwoStepBindViewController () <UITextFieldDelegate>
@property (nonatomic, strong) IMTwoStepSetup *setup;
@property (nonatomic, strong) UITextField *codeField;
@property (nonatomic, strong) UIView *codeRow;
@property (nonatomic, assign) BOOL manualExpanded;
@end

@implementation IMTwoStepBindViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID setup:(IMTwoStepSetup *)setup {
    self = [super initWithHost:host userID:userID];
    if (self) { _setup = setup; }
    return self;
}

- (NSString *)pageTitle { return IMLocalized(@"twostep.bind.title"); }
- (NSString *)primaryTitle { return IMLocalized(@"twostep.bind.submit"); }
- (BOOL)primaryEnabled { return IMTwoStepCodeIsComplete(self.codeField.text); }

- (void)viewDidLoad {
    self.codeField = IMTwoStepMakeCodeField(IMLocalized(@"twostep.field.code"));
    self.codeField.delegate = self;
    [self.codeField addTarget:self action:@selector(codeChanged) forControlEvents:UIControlEventEditingChanged];
    self.codeRow = IMTwoStepFieldRow(self.codeField, 56);
    [super viewDidLoad];
}

#pragma mark - 渲染

- (NSArray<IMTwoStepSection *> *)buildSections {
    IMTwoStepSection *qr = [IMTwoStepSection sectionWithRows:@[[IMTwoStepRow rowWithView:IMTwoStepQRCard(self.setup.otpauthURI) onTap:nil]]
                                                      footer:nil];
    qr.header = IMLocalized(@"twostep.bind.hint");
    __weak typeof(self) ws = self;
    NSMutableArray<IMTwoStepRow *> *manualRows = [NSMutableArray arrayWithObject:
        [IMTwoStepRow rowWithView:[self manualToggleRow] onTap:^{ [ws toggleManual]; }]];
    if (self.manualExpanded) { [manualRows addObject:[IMTwoStepRow rowWithView:[self manualKeyRow] onTap:nil]]; }
    return @[qr,
             [IMTwoStepSection sectionWithRows:manualRows footer:nil],
             [IMTwoStepSection sectionWithRows:@[[IMTwoStepRow rowWithView:self.codeRow onTap:nil]] footer:nil]];
}

/// 「无法扫码？手动输入密钥 ⌄」折叠行。
- (UIView *)manualToggleRow {
    UILabel *l = [UILabel new];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    l.text = IMLocalized(@"twostep.bind.manual");
    l.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    l.textColor = UIColor.systemBlueColor;
    l.numberOfLines = 0;
    UIImageView *chev = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:self.manualExpanded ? @"chevron.up" : @"chevron.down"]];
    chev.translatesAutoresizingMaskIntoConstraints = NO;
    chev.tintColor = UIColor.tertiaryLabelColor;
    chev.contentMode = UIViewContentModeScaleAspectFit;
    [chev.widthAnchor constraintEqualToConstant:16].active = YES;
    [chev.heightAnchor constraintEqualToConstant:16].active = YES;
    UIView *row = [UIView new];
    row.accessibilityIdentifier = @"twostep.manual_toggle";
    [row addSubview:l];
    [row addSubview:chev];
    [NSLayoutConstraint activateConstraints:@[
        [l.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
        [l.trailingAnchor constraintEqualToAnchor:chev.leadingAnchor constant:-8],
        [l.topAnchor constraintEqualToAnchor:row.topAnchor constant:11],
        [l.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-11],
        [chev.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16],
        [chev.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:44],
    ]];
    return row;
}

/// 展开后的密钥行：4 位一组等宽居中（每行 4 组），右侧「复制」。
- (UIView *)manualKeyRow {
    UILabel *key = [UILabel new];
    key.translatesAutoresizingMaskIntoConstraints = NO;
    key.text = IMTwoStepGroupSecret(self.setup.secret, 4, 4);
    key.font = [UIFont monospacedSystemFontOfSize:17 weight:UIFontWeightMedium];
    key.textColor = UIColor.labelColor;
    key.numberOfLines = 0;
    key.textAlignment = NSTextAlignmentCenter;
    key.accessibilityIdentifier = @"twostep.secret";
    UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
    copy.translatesAutoresizingMaskIntoConstraints = NO;
    [copy setTitle:IMLocalized(@"twostep.bind.copy") forState:UIControlStateNormal];
    copy.titleLabel.font = [UIFont systemFontOfSize:13];
    [copy setTitleColor:UIColor.systemBlueColor forState:UIControlStateNormal];
    [copy addTarget:self action:@selector(copySecret) forControlEvents:UIControlEventTouchUpInside];
    [copy setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [copy setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    copy.accessibilityIdentifier = @"twostep.secret_copy";
    UIView *row = [UIView new];
    [row addSubview:key];
    [row addSubview:copy];
    [NSLayoutConstraint activateConstraints:@[
        [key.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
        [key.topAnchor constraintEqualToAnchor:row.topAnchor constant:12],
        [key.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-12],
        [copy.leadingAnchor constraintEqualToAnchor:key.trailingAnchor constant:8],
        [copy.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16],
        [copy.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    return row;
}

- (void)toggleManual {
    self.manualExpanded = !self.manualExpanded;
    [self reloadSections];
}

- (void)copySecret {
    // 密钥等同凭据：只放本机剪贴板（不走通用剪贴板同步），2 分钟后自动过期。
    [UIPasteboard.generalPasteboard setItems:@[@{ @"public.utf8-plain-text": self.setup.secret ?: @"" }]
                                     options:@{ UIPasteboardOptionLocalOnly: @YES,
                                                UIPasteboardOptionExpirationDate: [NSDate dateWithTimeIntervalSinceNow:120] }];
    [self im_showToast:IMLocalized(@"twostep.bind.copied")];
}

#pragma mark - 输入

- (void)codeChanged {
    if (!self.codeField.markedTextRange) { // 组词期间不改写文本
        NSString *clean = IMTwoStepSanitizeCode(self.codeField.text);
        if (![clean isEqualToString:self.codeField.text]) { self.codeField.text = clean; }
    }
    if (!self.errorLabel.hidden) { [self showError:nil]; } // 错码红字随输入消失；输入本身不清空
    [self refreshPrimary];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (self.primaryButton.enabled) { [self primaryButtonTapped]; }
    return NO;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    dispatch_async(dispatch_get_main_queue(), ^{ [self scrollPrimaryButtonIntoView]; });
}

#pragma mark - 提交

- (void)primaryTapped {
    NSString *code = IMTwoStepSanitizeCode(self.codeField.text);
    [self showError:nil];
    self.busy = YES;
    __weak typeof(self) ws = self;
    [self withToken:^(NSString *token) {
        [IMHTTPService.sharedService enableTwoStepWithToken:token code:code completion:^(NSArray<NSString *> *codes, NSError *error) {
            [ws handleEnable:codes error:error];
        }];
    }];
}

- (void)handleEnable:(nullable NSArray<NSString *> *)codes error:(nullable NSError *)error {
    self.busy = NO;
    if (codes.count > 0) {
        IMTwoStepMarkEnabledNow();
        IMLog(@"twostep_enabled recovery_count=%lu", (unsigned long)codes.count);
        IMTwoStepCodesViewController *vc = [[IMTwoStepCodesViewController alloc] initWithHost:self.host userID:self.userID
                                                                                recoveryCodes:codes regenerated:NO];
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }
    IMLogWarnWithTag(IMLogTagUI, @"twostep_enable_failed code=%ld", (long)error.code);
    NSString *msg = IMTwoStepErrorMessage(error.code, IMTwoStepErrorContextBind, -1, NO, error.localizedDescription);
    if (IMTwoStepErrorEndsFlow(error.code, IMTwoStepErrorContextBind)) { // 待确认密钥 30 分钟过期：回 ② 重新开始
        UINavigationController *nav = self.navigationController;
        [nav popViewControllerAnimated:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [nav.topViewController im_showToast:msg];
        });
        return;
    }
    if (error.code == IMErrCodeTwoStepAlreadyEnabled) { [self popToFlowRootWithToast:msg]; return; }
    [self showError:msg];
    if (error.code == IMErrCodeTwoStepCodeInvalid) { [self markErrorView:self.codeRow]; } // 输入不清空
}

@end
