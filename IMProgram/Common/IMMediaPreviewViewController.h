//  IMMediaPreviewViewController.h
//  自建相册选择器的预览页：左右翻 + 双指缩放、顶栏 返回 / i/N / 选中圆、底栏 原图 + 发送。
//  **视频只显首帧不播放**（播放不是选择器的职责），底部胶囊写明「预览不播放」。
//  与宫格页共用 IMMediaPickSession，所以编号 / 上限 / 总大小两页一套规则。

#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

@class IMMediaPickSession;

NS_ASSUME_NONNULL_BEGIN

@interface IMMediaPreviewViewController : UIViewController

/// provider 按下标取资源（宫格整个相册可能几万张，不预先展开成数组）。
- (instancetype)initWithSession:(IMMediaPickSession *)session
                          count:(NSInteger)count
                     startIndex:(NSInteger)startIndex
                   assetAtIndex:(PHAsset *(^)(NSInteger index))provider;

@property (nonatomic, copy, nullable) void (^onSelectionChanged)(void); ///< 选中 / 原图变化，宫格页据此重绘
@property (nonatomic, copy, nullable) void (^onClose)(void);
@property (nonatomic, copy, nullable) void (^onSend)(void);

@end

NS_ASSUME_NONNULL_END
