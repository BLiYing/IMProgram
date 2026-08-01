//  IMPopoverCard.m
//  统一使用 UIKit 的系统 action sheet；iOS 26 由系统提供 Liquid Glass 外观与按压反馈。

#import "IMPopoverCard.h"

@implementation IMPopoverCardItem
+ (instancetype)itemWithTitle:(NSString *)title symbol:(NSString *)symbol
                  destructive:(BOOL)destructive handler:(void (^)(void))handler {
    IMPopoverCardItem *it = [IMPopoverCardItem new];
    it.title = title; it.symbol = symbol; it.destructive = destructive; it.handler = handler;
    return it;
}
@end

static UIViewController *IMViewControllerForView(UIView *view) {
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:UIViewController.class]) { return (UIViewController *)responder; }
        responder = responder.nextResponder;
    }
    return nil;
}

@implementation IMPopoverCard

+ (UIAlertController *)sheetWithItems:(NSArray<IMPopoverCardItem *> *)items {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (IMPopoverCardItem *it in items) {
        UIAlertActionStyle style = it.destructive ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault;
        void (^handler)(void) = it.handler;
        [sheet addAction:[UIAlertAction actionWithTitle:it.title style:style handler:^(__unused UIAlertAction *action) {
            if (handler) { handler(); }
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    return sheet;
}

+ (BOOL)isPresentingInHostView:(UIView *)host {
    UIViewController *vc = IMViewControllerForView(host);
    return [vc.presentedViewController isKindOfClass:UIAlertController.class];
}

+ (void)presentFromAnchor:(UIView *)anchor inHostView:(UIView *)host items:(NSArray<IMPopoverCardItem *> *)items {
    if (items.count == 0 || !anchor || !host || [self isPresentingInHostView:host]) { return; }
    UIViewController *vc = IMViewControllerForView(host);
    if (!vc) { return; }

    UIAlertController *sheet = [self sheetWithItems:items];

    // iPad 使用锚点弹出；iPhone 由系统转为底部 action sheet。两者都由 UIKit 管理动画和 Glass。
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = anchor;
        popover.sourceRect = anchor.bounds;
        popover.permittedArrowDirections = UIPopoverArrowDirectionUp;
    }
    [vc presentViewController:sheet animated:YES completion:nil];
}

+ (void)presentFromBarButtonItem:(UIBarButtonItem *)barButtonItem
                      inHostView:(UIView *)host
                           items:(NSArray<IMPopoverCardItem *> *)items {
    if (items.count == 0 || !barButtonItem || !host || [self isPresentingInHostView:host]) { return; }
    UIViewController *vc = IMViewControllerForView(host);
    if (!vc || vc.presentedViewController) { return; }

    UIAlertController *sheet = [self sheetWithItems:items];
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.barButtonItem = barButtonItem;
        popover.permittedArrowDirections = UIPopoverArrowDirectionUp;
    }
    [vc presentViewController:sheet animated:YES completion:nil];
}

@end
