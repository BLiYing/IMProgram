//  IMMenuAction.m

#import "IMMenuAction.h"
#import "IMAnimator.h"

@implementation IMMenuAction

+ (instancetype)actionWithId:(NSString *)actionId
                       title:(NSString *)title
                       image:(nullable NSString *)systemImageName
                     handler:(nullable void (^)(void))handler {
    IMMenuAction *a = [IMMenuAction new];
    a.actionId = actionId;
    a.title = title;
    a.systemImageName = systemImageName;
    a.destructive = NO;
    a.handler = handler;
    return a;
}

+ (instancetype)destructiveActionWithId:(NSString *)actionId
                                  title:(NSString *)title
                                  image:(nullable NSString *)systemImageName
                                handler:(nullable void (^)(void))handler {
    IMMenuAction *a = [self actionWithId:actionId title:title image:systemImageName handler:handler];
    a.destructive = YES;
    return a;
}

+ (instancetype)submenuWithId:(NSString *)actionId
                        title:(NSString *)title
                        image:(nullable NSString *)systemImageName
                     children:(NSArray<IMMenuAction *> *)children {
    IMMenuAction *a = [self actionWithId:actionId title:title image:systemImageName handler:nil];
    a.children = children;
    return a;
}

/// 单条 IMMenuAction → UIMenuElement：有 children 渲染为子菜单（UIMenu，原生 push 动画），否则 UIAction。
+ (UIMenuElement *)elementForAction:(IMMenuAction *)action {
    UIImage *image = action.systemImageName.length > 0 ? [UIImage systemImageNamed:action.systemImageName] : nil;
    if (action.children.count > 0) {
        NSMutableArray<UIMenuElement *> *subs = [NSMutableArray arrayWithCapacity:action.children.count];
        for (IMMenuAction *child in action.children) { [subs addObject:[self elementForAction:child]]; }
        return [UIMenu menuWithTitle:action.title image:image identifier:action.actionId options:0 children:subs];
    }
    void (^handler)(void) = action.handler;
    UIAction *ui = [UIAction actionWithTitle:action.title image:image identifier:action.actionId
                                     handler:^(__kindof UIAction *a) {
        [IMAnimator lightImpact];  // 触发任一菜单动作给一次轻触感（Telegram 式）
        if (handler) { handler(); }
    }];
    if (action.destructive) { ui.attributes = UIMenuElementAttributesDestructive; }
    return ui;
}

+ (UIMenu *)menuWithActions:(NSArray<IMMenuAction *> *)actions {
    NSMutableArray<UIMenuElement *> *children = [NSMutableArray arrayWithCapacity:actions.count];
    for (IMMenuAction *action in actions) {
        [children addObject:[self elementForAction:action]];
    }
    return [UIMenu menuWithTitle:@"" children:children];
}

@end
