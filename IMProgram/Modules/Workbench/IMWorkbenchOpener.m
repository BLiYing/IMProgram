//  IMWorkbenchOpener.m

#import "IMWorkbenchOpener.h"
#import "IMCustomerServiceViewController.h"
#import "IMHTTPService.h"
#import "IMHTTPService+Workbench.h"
#import "IMLocalization.h"
#import "IMLog.h"
#import "IMWorkbench.h"
#import "UIViewController+IMToast.h"


@implementation IMWorkbenchOpener

+ (void)pushURL:(NSURL *)url title:(NSString *)title from:(UIViewController *)host {
    // 等待期间用户已离开（返回 / 切 Tab / 又开了别的）：不把旧结果压上来
    if (!host.view.window || (host.navigationController && host.navigationController.topViewController != host)) { return; }
    IMCustomerServiceViewController *web = [[IMCustomerServiceViewController alloc] initWorkbenchWithURL:url title:title];
    if (host.navigationController) {
        [host.navigationController pushViewController:web animated:YES];
    } else {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:web];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [host presentViewController:nav animated:YES completion:nil];
    }
}

+ (void)openAppID:(NSString *)appID name:(NSString *)name unitID:(NSString *)unitID
             from:(UIViewController *)host onUnavailable:(void (^)(void))onUnavailable {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0 || appID.length == 0) { [host im_showToast:IMLocalized(@"workbench.open_failed")]; return; }
    __weak UIViewController *weakHost = host;
    [IMHTTPService.sharedService workbenchOpenAppWithToken:token unitID:unitID appID:appID completion:^(NSDictionary *data, NSError *error) {
        UIViewController *h = weakHost;
        if (!h) { return; }
        if (error) {
            IMLogWarnWithTag(IMLogTagHTTP, @"workbench_open_failed code=%ld", (long)error.code);
            [h im_showToast:(error.code == IMWorkbenchErrorAppUnavailable ? error.localizedDescription : IMLocalized(@"workbench.open_failed"))];
            if (error.code == IMWorkbenchErrorAppUnavailable && onUnavailable) { onUnavailable(); }
            return;
        }
        NSString *raw = [data[@"url"] isKindOfClass:NSString.class] ? data[@"url"] : @"";
        NSURL *url = [NSURL URLWithString:raw];
        if (![IMWorkbench isAllowedWebURL:url]) { // 服务端已校验；这里再挡一次（WORKBENCH_DESIGN §6）
            IMLogWarnWithTag(IMLogTagUI, @"workbench_open_blocked scheme=%@", url.scheme ?: @"(nil)");
            [h im_showToast:IMLocalized(@"workbench.open_failed")];
            return;
        }
        [self pushURL:url title:name from:h];
    }];
}

+ (void)openLink:(NSString *)link from:(UIViewController *)host {
    NSURL *url = [NSURL URLWithString:link ?: @""];
    if (![IMWorkbench isAllowedWebURL:url]) {
        IMLogWarnWithTag(IMLogTagUI, @"workbench_link_blocked scheme=%@", url.scheme ?: @"(nil)");
        return;
    }
    [self pushURL:url title:@"" from:host];
}

@end
