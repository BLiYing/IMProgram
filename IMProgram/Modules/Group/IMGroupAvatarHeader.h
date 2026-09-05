//  IMGroupAvatarHeader.h
//  群头像编辑头（90pt 圆 + 中央相机提示 + 主色 caption），作 tableHeaderView 用。
//
//  原是 `IMGroupManageViewController.m` 里的文件私有类；2026-09-05 建群第二步
//  （`IMGroupCreateViewController`）要用同一形态，提到这里两页共用。
//  **群管理页行为逐字不变**：它仍直接读写 avatar / cam / caption 三个视图，
//  新加的 `initial`（无头像时的占位首字）只有建群页用，不设即不显示。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMGroupAvatarHeader : UIView

@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UIImageView *cam;      ///< 中间相机提示：已有头像时隐藏
@property (nonatomic, strong) UILabel *caption;
/// 无头像时圈内的占位首字（建群页取群名首字；群管理页不用，保持相机图标）。
@property (nonatomic, strong) UILabel *initial;

/// 一次性设置圈内形态：有 image 显图；无图时 placeholder 非空显首字、否则显相机。
/// 三个视图的显隐互斥关系收在这里，免得调用方各写一遍（写漏一个就是相机和首字叠在一起）。
- (void)applyAvatarImage:(nullable UIImage *)image
             placeholder:(nullable NSString *)placeholder
                 caption:(NSString *)caption;

@end

NS_ASSUME_NONNULL_END
