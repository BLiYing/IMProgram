//  IMQRImage.h
//  二维码本地生成（CIQRCodeGenerator）与图片解码（CIDetector）。
//  服务端只发内容串，图片端上生成——省带宽、离线可看、不必处理图片缓存失效。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMQRImage : NSObject

/// 由内容串生成二维码图片（容错级 M，边长 size 点，最近邻放大保持锐利）。失败返回 nil。
+ (nullable UIImage *)imageForString:(NSString *)string size:(CGFloat)size;

/// 解出图里**全部**二维码文本，按码面积从大到小去重排序。
/// 一图多码（群公告截图常同时有群码与客服码）时交给用户选，**不默认取第一个**。
+ (NSArray<NSString *> *)decodeAllInImage:(UIImage *)image;

@end

NS_ASSUME_NONNULL_END
