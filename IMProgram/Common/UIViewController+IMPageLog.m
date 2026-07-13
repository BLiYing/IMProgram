//  UIViewController+IMPageLog.m

#import "UIViewController+IMPageLog.h"
#import "IMLog.h"
#import <objc/runtime.h>

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
    // 过滤 UIKit 自带的容器/包装控制器，只留真正“看得见的页面”，避免刷屏。
    NSString *cls = NSStringFromClass(self.class);
    if ([cls hasPrefix:@"UI"] || [cls hasPrefix:@"_UI"]) { return; }

    NSString *title = self.title.length ? self.title
                    : (self.navigationItem.title.length ? self.navigationItem.title : @"-");
    IMLog(@"📄 页面出现：%@（标题：%@）", cls, title);
}

@end
