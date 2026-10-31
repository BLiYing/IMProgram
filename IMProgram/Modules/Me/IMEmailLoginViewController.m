//  IMEmailLoginViewController.m

#import "IMEmailLoginViewController.h"
#import "IMEmailFormViewController.h"
#import "IMEmailUnbindViewController.h"
#import "IMEmailViews.h"
#import "IMTwoStepViews.h"
#import "IMHTTPService+Email.h"
#import "IMLocalization.h"
#import "IMLog.h"

@interface IMEmailLoginViewController ()
@property (nonatomic, strong, readwrite, nullable) IMEmailState *state;
@property (nonatomic, assign) BOOL loadFailed;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, strong) UIActivityIndicatorView *loadingSpinner;
@end

@implementation IMEmailLoginViewController

- (NSString *)pageTitle { return IMLocalized(@"email.title"); }
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
        [IMHTTPService.sharedService fetchEmailStateWithToken:token completion:^(IMEmailState *state, NSError *error) {
            [ws finishLoadWithState:state error:error];
        }];
    } failure:^(NSError *error) {
        [ws finishLoadWithState:nil error:error];
    }];
}

- (void)finishLoadWithState:(nullable IMEmailState *)state error:(nullable NSError *)error {
    self.loading = NO;
    [self.loadingSpinner stopAnimating];
    if (state) {
        self.state = state;
        self.loadFailed = NO;
        [self showError:nil];
    } else {
        IMLogWarnWithTag(IMLogTagUI, @"email_state_load_failed code=%ld", (long)error.code);
        self.loadFailed = (self.state == nil);
        if (self.loadFailed) { [self showError:error.localizedDescription]; }
    }
    [self reloadSections];
    [self refreshPrimary];
}

- (void)applyState:(IMEmailState *)state {
    self.state = state;
    self.loadFailed = NO;
    if (self.isViewLoaded) { [self showError:nil]; [self reloadSections]; [self refreshPrimary]; }
}

+ (void)finishFlowFromPage:(IMTwoStepFormViewController *)page state:(IMEmailState *)state toast:(NSString *)toast {
    for (UIViewController *vc in page.navigationController.viewControllers) {
        if (![vc isKindOfClass:IMEmailLoginViewController.class]) { continue; }
        IMEmailLoginViewController *root = (IMEmailLoginViewController *)vc;
        if (!state) {
            state = [IMEmailState new];
            state.available = root.state ? root.state.available : YES;
        }
        [root applyState:state];
        break;
    }
    [page popToFlowRootWithToast:toast];
}

#pragma mark - 渲染

- (BOOL)isBound { return self.state.bound; }

- (UIView *)headerContentView {
    if (!self.state) { return nil; }
    if ([self isBound]) { return IMEmailHeroView(self.state.email, YES, [self.state boundSinceText], nil); }
    return IMEmailHeroView(IMLocalized(@"email.title"), NO, IMLocalized(@"email.intro"),
                           self.state.available ? nil : IMLocalized(@"email.unavailable"));
}

- (NSString *)primaryTitle {
    if (self.loadFailed) { return IMLocalized(@"common.retry"); }
    return (self.state && ![self isBound]) ? IMLocalized(@"email.action.bind") : nil;
}

- (BOOL)primaryEnabled {
    if (self.loadFailed) { return !self.loading; }
    return !self.loading && self.state.available; // available:false → 主按钮置灰
}

- (void)primaryTapped {
    if (self.loadFailed) { [self loadState]; return; }
    [self openFormChange:NO];
}

- (NSArray<IMTwoStepSection *> *)buildSections {
    if (!self.state || ![self isBound]) { return @[]; }
    __weak typeof(self) ws = self;
    IMTwoStepRow *change = [IMTwoStepRow rowWithView:IMTwoStepValueRow(IMLocalized(@"email.action.change"), nil, UIColor.secondaryLabelColor, YES)
                                               onTap:^{ [ws openFormChange:YES]; }];
    change.showsChevron = YES;
    change.view.accessibilityIdentifier = @"email.row.change";
    IMTwoStepRow *unbind = [IMTwoStepRow rowWithView:IMTwoStepCenteredTextRow(IMLocalized(@"email.action.unbind"), UIColor.systemRedColor)
                                               onTap:^{ [ws openUnbind]; }];
    unbind.view.accessibilityIdentifier = @"email.row.unbind";
    return @[
        [IMTwoStepSection sectionWithRows:@[change] footer:nil],
        [IMTwoStepSection sectionWithRows:@[unbind] footer:IMLocalized(@"email.bound.footer")],
    ];
}

- (void)openFormChange:(BOOL)change {
    IMEmailFormViewController *vc = [[IMEmailFormViewController alloc] initWithHost:self.host userID:self.userID
                                                                              change:change currentEmail:self.state.email];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openUnbind {
    [self.navigationController pushViewController:[[IMEmailUnbindViewController alloc] initWithHost:self.host userID:self.userID] animated:YES];
}

@end
