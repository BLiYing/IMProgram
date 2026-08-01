//  IMBottomSheet.m
//  统一使用 UIKit 的系统 action sheet；iOS 26 由系统提供 Liquid Glass 外观。

#import "IMBottomSheet.h"

@implementation IMBottomSheetItem
+ (instancetype)itemWithTitle:(NSString *)title symbol:(NSString *)symbol handler:(dispatch_block_t)handler {
    IMBottomSheetItem *it = [IMBottomSheetItem new];
    it.title = title; it.symbol = symbol; it.handler = handler;
    return it;
}
@end

static UIViewController *IMBottomSheetViewControllerForView(UIView *view) {
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:UIViewController.class]) { return (UIViewController *)responder; }
        responder = responder.nextResponder;
    }
    return nil;
}

@implementation IMBottomSheet

+ (void)showInView:(UIView *)host items:(NSArray<IMBottomSheetItem *> *)items {
    if (!host || items.count == 0) { return; }
    UIViewController *vc = IMBottomSheetViewControllerForView(host);
    if (!vc || vc.presentedViewController) { return; }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
    for (IMBottomSheetItem *it in items) {
        dispatch_block_t handler = it.handler;
        [sheet addAction:[UIAlertAction actionWithTitle:it.title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if (handler) { handler(); }
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:sheet animated:YES completion:nil];
}

@end
