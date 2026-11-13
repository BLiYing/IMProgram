//  IMEmailUnbindViewController.m

#import "IMEmailUnbindViewController.h"
#import "IMEmailLoginViewController.h"
#import "IMEmailLogin.h"
#import "IMTwoStepViews.h"
#import "IMHTTPService+Email.h"
#import "IMLocalization.h"
#import "IMLog.h"
#import "IMIdentityProofSheet.h"

@interface IMEmailUnbindViewController ()
@property (nonatomic, strong, readwrite) IMProofSession *proofSession;
@end

@implementation IMEmailUnbindViewController

- (NSString *)pageTitle { return IMLocalized(@"email.action.unbind"); }
- (NSString *)primaryTitle { return IMLocalized(@"email.action.unbind"); }
- (UIColor *)primaryColor { return UIColor.systemRedColor; }

- (IMProofSession *)proofSession {
    if (!_proofSession) { _proofSession = [[IMProofSession alloc] initWithHost:self.host userID:self.userID]; }
    return _proofSession;
}

- (NSArray<IMTwoStepSection *> *)buildSections {
    return @[[IMTwoStepSection sectionWithRows:@[] footer:IMLocalized(@"email.unbind.body")]];
}

#pragma mark - 确认 + 提交

- (void)primaryTapped {
    if (self.presentedViewController) { return; } // 确认框已在弹出（连点）
    [self showError:nil];
    [self.view endEditing:YES];
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:IMLocalized(@"email.unbind.confirm_title")
                                                                message:IMLocalized(@"email.unbind.body")
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"email.action.unbind") style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) { [ws performUnbind]; }]];
    [self presentViewController:ac animated:YES completion:nil];
}

/// 确认身份弹层（密码或短信验证码）→ unbind {proof}。证明本身的错留在弹层里重输；其余回到本页红字。
- (void)performUnbind {
    __weak typeof(self) ws = self;
    [self.proofSession presentFrom:self request:^(NSString *token, IMIdentityProof *proof, void (^finish)(NSError *)) {
        [IMHTTPService.sharedService unbindEmailWithToken:token proof:proof completion:^(NSError *error) { finish(error); }];
    } completion:^(BOOL succeeded, NSError *pageError) {
        if (succeeded || pageError) { [ws handleUnbind:pageError]; }
    }];
}

- (void)handleUnbind:(nullable NSError *)error {
    if (!error) {
        IMLogUI(@"email_unbound");
        [IMEmailLoginViewController finishFlowFromPage:self state:nil toast:IMLocalized(@"email.toast.unbound")];
        return;
    }
    IMLogWarnWithTag(IMLogTagUI, @"email_unbind_failed code=%ld", (long)error.code);
    NSString *msg = IMEmailErrorMessage(error.code, -1, IMEmailRetryAfterFromError(error), error.localizedDescription);
    if (error.code == IMErrCodeEmailNotBound) { // 别的设备刚解绑：回根页（会重新取状态）
        [IMEmailLoginViewController finishFlowFromPage:self state:nil toast:msg];
        return;
    }
    [self showError:msg];
}

@end
