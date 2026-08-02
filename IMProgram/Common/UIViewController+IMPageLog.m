//  UIViewController+IMPageLog.m

#import "UIViewController+IMPageLog.h"
#import "IMLog.h"
#import <objc/runtime.h>

BOOL IMShouldLogPageClassName(NSString *className) {
    return [className hasPrefix:@"IM"];
}

@implementation UIViewController (IMPageLog)

+ (void)load {
    // 进程启动时只交换一次实现，之后所有 viewDidAppear: 都会先走我们的日志再调原实现。
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SEL originalSel = @selector(viewDidAppear:);
        SEL swizzledSel = @selector(im_pagelog_viewDidAppear:);
        Method original = class_getInstanceMethod(self, originalSel);
        Method swizzled = class_getInstanceMethod(self, swizzledSel);
        method_exchangeImplementations(original, swizzled);
    });
}

- (void)im_pagelog_viewDidAppear:(BOOL)animated {
    // 此时 self 指向真实控制器；交换后此方法体即原 viewDidAppear: 的入口。
    [self im_pagelog_logCurrentPage];
    [self im_pagelog_viewDidAppear:animated]; // 已交换 → 实际调用系统原实现，不会递归。
}

- (void)im_pagelog_logCurrentPage {
    // 严格限制为应用自有类。不可读取 DOCRemote… 等系统/三方控制器的 navigationItem；
    // 该属性可能被懒创建，触碰系统私有导航栈会干扰 UIDocumentPicker 的远程视图生命周期。
    NSString *cls = NSStringFromClass(self.class);
    if (!IMShouldLogPageClassName(cls)) { return; }

    NSString *title = self.title.length ? self.title
                    : (self.navigationItem.title.length ? self.navigationItem.title : @"-");
    IMLogUI(@"📄 页面出现：%@（标题：%@）", cls, title);
}

@end
