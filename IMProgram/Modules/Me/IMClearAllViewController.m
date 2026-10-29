//  IMClearAllViewController.m

#import "IMClearAllViewController.h"
#import "IMClearAll.h"
#import "IMDatabase.h"
#import "IMHTTPService+ClearAll.h"
#import "IMMainTabBarController.h"
#import "UIViewController+IMToast.h"
#import "IMLocalization.h"
#import "IMLog.h"

@interface IMClearAllViewController ()
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, assign) NSInteger visibleCount; ///< 页面打开时本机会话列表的可见会话数（仅用于弹窗文案）；-1 = 还没读到
@end

@implementation IMClearAllViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) { _host = [host copy]; _userID = [userID copy]; _visibleCount = -1; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"privacy.clear_all.title");
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ // 大号的会话缓存读取别卡进页动画
        NSInteger n = (NSInteger)IMDatabase.sharedDatabase.cachedConversations.count;
        dispatch_async(dispatch_get_main_queue(), ^{ ws.visibleCount = n; });
    });
}

#pragma mark - 版式覆写（共用版式见 IMDangerPageViewController）

- (NSString *)dangerHeaderText { return IMLocalized(@"privacy.clear_all.warn_title"); }
- (NSString *)dangerSubmitTitle { return IMLocalized(@"privacy.clear_all.button"); }
- (NSString *)dangerSubmitIdentifier { return @"clear_all.submit"; }

- (NSArray<NSString *> *)dangerConsequenceTexts {
    return @[IMLocalized(@"privacy.clear_all.b1"), IMLocalized(@"privacy.clear_all.b2"),
             IMLocalized(@"privacy.clear_all.b3"), IMLocalized(@"privacy.clear_all.b4")];
}

/// 蓝色信息条「想留一份备份？」：纯提示，不可点。
- (NSArray<UIView *> *)dangerViewsBelowConsequences {
    return @[[self dangerInfoTipWithText:IMLocalized(@"privacy.clear_all.tip")]];
}

#pragma mark - 确认 → 请求

- (void)dangerSubmitTapped {
    if (self.busy) { return; }
    NSInteger n = self.visibleCount >= 0 ? self.visibleCount : (NSInteger)IMDatabase.sharedDatabase.cachedConversations.count;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:IMLocalized(@"privacy.clear_all.confirm_title")
                                                                message:IMClearAllConfirmBody(n)
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"privacy.clear_all.confirm_ok") style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) { [ws performClear]; }]];
    [self presentViewController:ac animated:YES completion:nil];
}

/// 取新鲜 token → POST。**本机变更只在 HTTP 明确成功后发生**（失败不半清）。
/// 回调里强持有 self：请求在途时用户可能侧滑返回，请求仍要走完并清本机（设计 §1「返回键可用但请求继续」）。
- (void)performClear {
    [self setBusy:YES];
    [self showError:@""];
    IMHTTPService.sharedService.host = self.host;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *loginErr) {
        if (token.length == 0) { [self failWithError:loginErr]; return; }
        [IMHTTPService.sharedService clearAllConversationsWithToken:token completion:^(IMClearAllResult *result, NSError *err) {
            if (!result) { [self failWithError:err]; return; }
            IMLogWithTag(IMLogTagHTTP, @"clear_all_conversations cleared=%ld", (long)result.cleared);
            [IMClearAll applyResult:result completion:^(BOOL dbApplied) { [self finishWithCleared:result.cleared]; }];
        }];
    }];
}

- (void)failWithError:(NSError *)err {
    [self setBusy:NO];
    NSString *msg = err.localizedDescription;
    [self showError:msg.length > 0 ? msg : IMLocalized(@"common.action_failed")];
}

/// 成功：Tab 红点清零，返回隐私页并弹 toast（N 以服务端 cleared 为准）。页面已不在栈顶（用户中途返回了）则用全局 toast。
- (void)finishWithCleared:(NSInteger)cleared {
    [self setBusy:NO];
    NSString *text = IMClearAllToastText(cleared);
    UITabBarController *tab = self.tabBarController;
    if ([tab isKindOfClass:IMMainTabBarController.class]) { [(IMMainTabBarController *)tab setConversationsTabDotVisible:NO]; }
    UINavigationController *nav = self.navigationController;
    NSUInteger idx = nav ? [nav.viewControllers indexOfObject:self] : NSNotFound;
    if (nav && nav.topViewController == self && idx != NSNotFound && idx > 0) {
        UIViewController *privacy = nav.viewControllers[idx - 1];
        [nav popViewControllerAnimated:YES];
        [privacy im_showToast:text];
    } else {
        [UIViewController im_showGlobalToast:text];
    }
}

@end
