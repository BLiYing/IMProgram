//  UIViewController+IMDeleteSheet.m

#import "UIViewController+IMDeleteSheet.h"

@implementation UIViewController (IMDeleteSheet)

- (void)im_presentDeleteChoiceSheetWithSelfOnly:(void (^)(void))selfOnly
                                       everyone:(void (^)(void))everyone {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"仅删除自己" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *a) { if (selfOnly) { selfOnly(); } }]];
    // 破坏性重的「为所有人删除」放最后（destructive-last，与本仓菜单约定一致，降低误触不可逆项）。
    [sheet addAction:[UIAlertAction actionWithTitle:@"为所有人删除" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *a) { if (everyone) { everyone(); } }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view; // iPad 锚点兜底（居中）
    sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2,
                                                                self.view.bounds.size.height / 2, 0, 0);
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
