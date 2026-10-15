//  IMLocateInChatIcon.h
//  「定位到聊天位置」共用图标：聊天气泡轮廓 + 气泡内斜向箭头（↗，「在聊天里打开这条」）。
//  UIBezierPath 按设计稿同一份路径（24×24 viewBox，笔画 1.8，圆头圆角）渲染成 template UIImage——
//  同 IMReadTick，不入 xcassets，路径即真相；颜色靠 tintColor。三端同一份路径：
//  IMServer docs/design/PINNED_PANEL_DESIGN.md §8 / sketches/PINNED_PANEL_UX_SKETCH.html ⑦。
//  本期只用于置顶面板；全 app 其余「定位」入口的替换放最后一期统一做。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMLocateInChatIcon : NSObject

/// side×side 的 template 图（按 viewBox 等比缩放，笔画同比放大），按 side + 屏幕 scale 缓存。
+ (UIImage *)imageWithSide:(CGFloat)side;

/// viewBox（24×24）坐标系下的完整路径（气泡轮廓 + 箭头两笔），供测试与自定义绘制。
+ (UIBezierPath *)pathInViewBox;

@end

NS_ASSUME_NONNULL_END
