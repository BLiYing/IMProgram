//  IMNavigationButton.h
//  导航栏通用按钮外观。保持各模块的加号尺寸、符号配置与主题 Tint 一致。

#import <UIKit/UIKit.h>
#import "IMGlass.h"

NS_ASSUME_NONNULL_BEGIN

NS_INLINE UIButton *IMNavigationAddButton(id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(0, 0, 44, 44);
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightRegular];
    UIButtonConfiguration *buttonConfiguration = IMGlassButtonConfiguration();
    buttonConfiguration.image = [UIImage systemImageNamed:@"plus" withConfiguration:configuration];
    buttonConfiguration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    buttonConfiguration.contentInsets = NSDirectionalEdgeInsetsZero;
    button.configuration = buttonConfiguration; // 真正接收点击的按钮本身即 Glass，保留系统按压/聚合动画
    button.accessibilityLabel = @"添加";
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

NS_ASSUME_NONNULL_END
