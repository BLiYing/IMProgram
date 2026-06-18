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

+ (UIMenu *)menuWithActions:(NSArray<IMMenuAction *> *)actions {
    NSMutableArray<UIMenuElement *> *children = [NSMutableArray arrayWithCapacity:actions.count];
    for (IMMenuAction *action in actions) {
        UIImage *image = action.systemImageName.length > 0 ? [UIImage systemImageNamed:action.systemImageName] : nil;
        void (^handler)(void) = action.handler;
        UIAction *ui = [UIAction actionWithTitle:action.title image:image identifier:action.actionId
                                         handler:^(__kindof UIAction *a) {
            [IMAnimator lightImpact];  // 触发任一菜单动作给一次轻触感（Telegram 式）
            if (handler) { handler(); }
        }];
        if (action.destructive) { ui.attributes = UIMenuElementAttributesDestructive; }
        [children addObject:ui];
    }
    return [UIMenu menuWithTitle:@"" children:children];
}

@end
