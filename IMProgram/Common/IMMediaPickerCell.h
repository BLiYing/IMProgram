//  IMMediaPickerCell.h
//  自建相册选择器的宫格格子（规格见 docs/design/MEDIA_PICKER_IOS_DESIGN.md §2.1）：
//  正方形缩略图 + 右上角编号圆 + 右下角视频时长角标；选中压暗、不可选置灰。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMMediaPickerCell : UICollectionViewCell

/// 当前格对应的资源 id；异步回填缩略图时用它防复用错位。
@property (nonatomic, copy, nullable) NSString *assetID;
/// 正在进行的缩略图请求（复用前由控制器取消）。
@property (nonatomic, assign) int32_t imageRequestID;

- (void)setThumbnail:(nullable UIImage *)image;
/// number: 0 = 未选；>0 = 编号。duration: <0 表示图片（不显角标）。dimmed: 置灰（>2GB 等）。
- (void)configureWithNumber:(NSInteger)number videoDuration:(NSTimeInterval)duration dimmed:(BOOL)dimmed;

@end

NS_ASSUME_NONNULL_END
