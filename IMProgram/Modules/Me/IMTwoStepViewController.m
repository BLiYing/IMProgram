//  IMTwoStepViewController.m

#import "IMTwoStepViewController.h"
#import "IMTwoStepPasswordViewController.h"
#import "IMTwoStepVerifyViewController.h"
#import "IMTwoStepViews.h"
#import "IMTwoStep.h"
#import "IMHTTPService+TwoStep.h"
#import "IMLocalization.h"
#import "IMLog.h"

@interface IMTwoStepViewController ()
@property (nonatomic, strong, nullable) IMTwoStepState *state; ///< nil = 还没取到
@property (nonatomic, assign) BOOL loadFailed;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, strong) UIActivityIndicatorView *loadingSpinner;
@end

@implementation IMTwoStepViewController

- (NSString *)pageTitle { return IMLocalized(@"twostep.title"); }
- (BOOL)isFlowRoot { return YES; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.tableView.backgroundView = self.loadingSpinner;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadState]; // 子页返回 / 多端之间进页重新取值
}

#pragma mark - 加载

- (void)loadState {
    if (self.loading) { return; }
    self.loading = YES;
    self.loadFailed = NO;
    if (!self.state) { [self.loadingSpinner startAnimating]; }
    __weak typeof(self) ws = self;
    [self withToken:^(NSString *token) {
        [IMHTTPService.sharedService fetchTwoStepStateWithToken:token completion:^(IMTwoStepState *state, NSError *error) {
            [ws finishLoadWithState:state error:error];
        }];
    } failure:^(NSError *error) {
        [ws finishLoadWithState:nil error:error];
    }];
}

- (void)finishLoadWithState:(nullable IMTwoStepState *)state error:(nullable NSError *)error {
    self.loading = NO;
    [self.loadingSpinner stopAnimating];
    if (state) {
        self.state = state;
        self.loadFailed = NO;
        [self showError:nil];
    } else {
        IMLogWarnWithTag(IMLogTagUI, @"twostep_state_load_failed code=%ld", (long)error.code);
        self.loadFailed = (self.state == nil);
        if (self.loadFailed) { [self showError:error.localizedDescription]; }
    }
    [self reloadSections];
    [self refreshPrimary];
}

#pragma mark - 渲染

- (BOOL)isOn { return self.state.enabled; }

- (UIView *)headerContentView {
    if (!self.state) { return nil; }
    if ([self isOn]) { return IMTwoStepHeroView(IMLocalized(@"twostep.on.title"), [self.state enabledSinceText]); }
    return IMTwoStepHeroView(IMLocalized(@"twostep.title"), IMLocalized(@"twostep.intro.body"));
}

- (NSString *)primaryTitle {
    if (self.loadFailed) { return IMLocalized(@"common.retry"); }
    return (self.state && ![self isOn]) ? IMLocalized(@"twostep.intro.start") : nil;
}

- (BOOL)primaryEnabled { return !self.loading; }

- (void)primaryTapped {
    if (self.loadFailed) { [self loadState]; return; }
    [self.navigationController pushViewController:[[IMTwoStepPasswordViewController alloc] initWithHost:self.host userID:self.userID] animated:YES];
}

- (NSArray<IMTwoStepSection *> *)buildSections {
    if (!self.state || ![self isOn]) { return @[]; }
    __weak typeof(self) ws = self;
    NSInteger remaining = self.state.recoveryRemaining;
    UIColor *valueColor = IMTwoStepRecoveryIsLow(remaining) ? UIColor.systemOrangeColor : UIColor.secondaryLabelColor;
    NSString *value = remaining >= 0 ? IMTwoStepRecoveryRemainingText(remaining) : nil;
    IMTwoStepRow *recovery = [IMTwoStepRow rowWithView:IMTwoStepValueRow(IMLocalized(@"twostep.recovery.row"), value, valueColor, YES)
                                                 onTap:^{ [ws openVerify:IMTwoStepVerifyModeRegenerate]; }];
    recovery.showsChevron = YES;
    recovery.view.accessibilityIdentifier = @"twostep.row.recovery";
    IMTwoStepRow *disable = [IMTwoStepRow rowWithView:IMTwoStepCenteredTextRow(IMLocalized(@"twostep.disable.row"), UIColor.systemRedColor)
                                                onTap:^{ [ws openVerify:IMTwoStepVerifyModeDisable]; }];
    disable.view.accessibilityIdentifier = @"twostep.row.disable";
    return @[
        [IMTwoStepSection sectionWithRows:@[recovery] footer:IMTwoStepRecoveryFooter(remaining)],
        [IMTwoStepSection sectionWithRows:@[disable] footer:nil],
    ];
}

- (void)openVerify:(IMTwoStepVerifyMode)mode {
    [self.navigationController pushViewController:[[IMTwoStepVerifyViewController alloc] initWithHost:self.host userID:self.userID mode:mode]
                                         animated:YES];
}

@end
