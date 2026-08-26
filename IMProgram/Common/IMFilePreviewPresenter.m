//  IMFilePreviewPresenter.m

#import "IMFilePreviewPresenter.h"
#import <UIKit/UIKit.h>
#import <QuickLook/QuickLook.h>
#import <objc/runtime.h>

@interface IMFilePreviewPresenter () <QLPreviewControllerDataSource>
@property (nonatomic, strong) NSURL *previewURL;
@end

@implementation IMFilePreviewPresenter

+ (void)presentURL:(NSURL *)local fromViewController:(UIViewController *)vc {
    if (!local || !vc) { return; }
    IMFilePreviewPresenter *presenter = [IMFilePreviewPresenter new];
    presenter.previewURL = local;
    QLPreviewController *ql = [QLPreviewController new];
    ql.dataSource = presenter;
    // QL 只弱引 dataSource——把 presenter 挂在 QL 上共生共死，dismiss 释放 QL 即释放 presenter。
    objc_setAssociatedObject(ql, (__bridge const void *)IMFilePreviewPresenter.class,
                             presenter, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [vc presentViewController:ql animated:YES completion:nil];
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return _previewURL ? 1 : 0;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    return _previewURL;
}

@end
