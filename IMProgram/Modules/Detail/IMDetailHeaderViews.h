//  IMDetailHeaderViews.h
//  详情页头部形变用的两个视图：形变头像 + 静态坐标容器。从 IMChatDetailViewController.m 抽出，未改行为。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 形变头像：容器负责圆角/裁剪（随滚动 morph）。首字母底 + 图片都用 frame-based 子视图，layoutSubviews
/// 显式铺满（避免把约束钉在 0×0 起步的 frame-based label 上导致图停在 0×0 的空白怪形）。
@interface IMDetailAvatarView : UIView
@property (nonatomic, strong) UILabel *letter;
@property (nonatomic, strong) UIImageView *photo;
- (void)setAvatarURL:(nullable NSString *)url seed:(NSString *)seed name:(nullable NSString *)name;
@end

/// 承载移动头像 + 固定 Y 的 171pt 液滴 mask/effects 的静态坐标容器（对应 Telegram
/// PeerInfoAvatarListNode.containerNode）。所有子层共享同一 mask，故头像缩到 50pt 也不会被自身 bounds 切成矩形。
/// hitTest 只透传给 interactiveChild（头像），避免大容器吞掉表格触摸。
@interface IMDetailHeaderContainer : UIView
@property (nonatomic, weak) UIView *interactiveChild;
@end

NS_ASSUME_NONNULL_END
