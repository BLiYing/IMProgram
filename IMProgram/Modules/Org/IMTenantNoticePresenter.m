//  IMTenantNoticePresenter.m

#import "IMTenantNoticePresenter.h"
#import "IMHTTPService.h"
#import "IMHTTPService+Directory.h"
#import "IMLocalization.h"
#import "IMLog.h"
#import "IMTenantStore.h"

@implementation IMTenantNoticePresenter {
    __weak UIViewController *_host;
    __weak UIAlertController *_alert; // 正在显示的告知；被别的路径收掉（换号 / 换根控制器）后自动变 nil
    BOOL _showing;
    BOOL _acking;   // 已点「我知道了」、ack 在途（此时弹窗已收起，但不能复位重弹）
}

+ (instancetype)shared {
    static IMTenantNoticePresenter *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IMTenantNoticePresenter new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(presentIfNeeded)
                                                   name:IMTenantStoreDidChangeNotification object:nil];
    }
    return self;
}

- (void)attachToHost:(UIViewController *)host {
    _host = host;
    [self presentIfNeeded];
}

- (void)presentIfNeeded {
    UIViewController *host = _host;
    IMTenantStore *store = IMTenantStore.shared;
    // 弹窗没经「我知道了」就被收掉（退出登录换根控制器等）：不复位就再也不弹了。
    if (_showing && !_alert.presentingViewController && !_acking) { _showing = NO; }
    if (_showing || !host || !host.view.window || !store.hasTenant || !store.noticePending) { return; }
    // 盖在最上层已呈现的页面上（如正在看的大图）；正在转场时下一次快照再说。
    UIViewController *top = host;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) { top = top.presentedViewController; }
    if (top.isBeingPresented || top.isBeingDismissed) { return; }
    _showing = YES;
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:IMLocalizedFormat(@"org.audit_notice_title", store.tenantName)
                                            message:IMLocalized(@"org.audit_notice")
                                     preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) ws = self;
    UIAlertAction *ok = [UIAlertAction actionWithTitle:IMLocalized(@"common.got_it") style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *a) { [ws acknowledge]; }];
    [alert addAction:ok];
    alert.preferredAction = ok;
    _alert = alert;
    [top presentViewController:alert animated:YES completion:nil];
}

- (void)acknowledge {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { _showing = NO; return; }
    _acking = YES;
    [IMTenantStore.shared markNoticeAcked]; // 本次进程不再弹；ack 失败下次快照仍 pending 时再弹
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService directoryNoticeAckWithToken:token completion:^(NSDictionary *data, NSError *error) {
        __strong typeof(ws) self = ws;
        if (self) { self->_showing = NO; self->_acking = NO; }
        if (error) { IMLogWarnWithTag(IMLogTagHTTP, @"notice_ack_failed code=%ld", (long)error.code); }
    }];
}

@end
