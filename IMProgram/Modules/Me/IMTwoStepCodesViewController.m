//  IMTwoStepCodesViewController.m

#import "IMTwoStepCodesViewController.h"
#import "IMTwoStepViews.h"
#import "IMTwoStep.h"
#import "IMLocalization.h"
#import "IMLog.h"
#import "UIViewController+IMToast.h"

static NSString * const kIMRecoveryFileName = @"im-recovery-codes.txt";

@interface IMTwoStepCodesViewController ()
@property (nonatomic, copy) NSArray<NSString *> *codes;
@property (nonatomic, assign) BOOL regenerated;
@property (nonatomic, assign) BOOL completed;
@property (nonatomic, strong) IMTwoStepCheckRow *checkRow;
@end

@implementation IMTwoStepCodesViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID
               recoveryCodes:(NSArray<NSString *> *)codes regenerated:(BOOL)regenerated {
    self = [super initWithHost:host userID:userID];
    if (self) {
        _codes = [codes copy];
        _regenerated = regenerated;
    }
    return self;
}

- (NSString *)pageTitle { return IMLocalized(@"twostep.codes.title"); }
- (NSString *)primaryTitle { return IMLocalized(@"twostep.codes.done"); }
- (BOOL)primaryEnabled { return IMTwoStepCanFinish(self.checkRow.checked); }
- (BOOL)locksBackNavigation { return IMTwoStepShouldInterceptLeave(YES, self.completed); }

- (void)viewDidLoad {
    self.checkRow = [[IMTwoStepCheckRow alloc] initWithText:IMLocalized(@"twostep.codes.saved_check")];
    [super viewDidLoad];
}

- (NSArray<IMTwoStepSection *> *)buildSections {
    __weak typeof(self) ws = self;
    IMTwoStepSection *grid = [IMTwoStepSection sectionWithRows:@[[IMTwoStepRow rowWithView:IMTwoStepRecoveryGrid(self.codes) onTap:nil]]
                                                        footer:nil];
    UIView *copy = IMTwoStepCenteredTextRow(IMLocalized(@"twostep.codes.copy_all"), UIColor.systemBlueColor);
    copy.accessibilityIdentifier = @"twostep.codes.copy_all";
    UIView *save = IMTwoStepCenteredTextRow(IMLocalized(@"twostep.codes.save_file"), UIColor.systemBlueColor);
    save.accessibilityIdentifier = @"twostep.codes.save_file";
    IMTwoStepSection *actions = [IMTwoStepSection sectionWithRows:@[
        [IMTwoStepRow rowWithView:copy onTap:^{ [ws copyAll]; }],
        [IMTwoStepRow rowWithView:save onTap:^{ [ws saveFile]; }],
    ] footer:IMLocalized(@"twostep.codes.footer")];
    IMTwoStepSection *check = [IMTwoStepSection sectionWithRows:@[
        [IMTwoStepRow rowWithView:self.checkRow onTap:^{ [ws toggleSaved]; }],
    ] footer:nil];
    return @[grid, actions, check];
}

#pragma mark - 动作

- (void)toggleSaved {
    self.checkRow.checked = !self.checkRow.checked;
    [self refreshPrimary];
}

- (void)copyAll {
    // 恢复码等同凭据：只放本机剪贴板，2 分钟后自动过期。
    [UIPasteboard.generalPasteboard setItems:@[@{ @"public.utf8-plain-text": IMTwoStepRecoveryClipboardText(self.codes) }]
                                     options:@{ UIPasteboardOptionLocalOnly: @YES,
                                                UIPasteboardOptionExpirationDate: [NSDate dateWithTimeIntervalSinceNow:120] }];
    [self im_showToast:IMLocalized(@"twostep.bind.copied")];
}

/// 写临时文件 → 系统分享面板（存到「文件」/ AirDrop…）；面板收起后删临时文件。
- (void)saveFile {
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:kIMRecoveryFileName]];
    NSError *error = nil;
    // 恢复码等同凭据：落盘加完整文件保护；系统分享面板没回调就被杀进程时，临时文件也不会以可读形态长留。
    NSData *payload = [IMTwoStepRecoveryFileText(self.codes) dataUsingEncoding:NSUTF8StringEncoding];
    if (![payload writeToURL:url options:NSDataWritingAtomic | NSDataWritingFileProtectionComplete error:&error]) {
        IMLogWarnWithTag(IMLogTagUI, @"twostep_codes_file_write_failed code=%ld", (long)error.code);
        [self im_showToast:IMLocalized(@"common.action_failed")];
        return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    share.completionWithItemsHandler = ^(UIActivityType type, BOOL done, NSArray *items, NSError *err) {
        NSError *rmErr = nil;
        if (![NSFileManager.defaultManager removeItemAtURL:url error:&rmErr]) {
            IMLogWarnWithTag(IMLogTagUI, @"twostep_codes_file_cleanup_failed code=%ld", (long)rmErr.code);
        }
    };
    share.popoverPresentationController.sourceView = self.view;
    share.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:share animated:YES completion:nil];
}

- (void)primaryTapped {
    self.completed = YES;
    [self popToFlowRootWithToast:IMLocalized(self.regenerated ? @"twostep.toast.regenerated" : @"twostep.toast.enabled")];
}

@end
