//  IMQRCardView.h
//  名片码 / 群码共用的展示卡片：头像 + 名称/副标题 + 二维码 + 说明。
//  码区**恒白底黑码**（不随深色模式反色）——反色码大量扫码器识别不了，这里的可扫性优先于观感统一。
//  卡片本身只做展示，不联网：内容由宿主（IMQRCardViewController / 扫一扫页的「我的二维码」页签）灌入。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMQRCardView : UIView

/// 灌入一张卡片。qrString 为空时码区显示占位（加载中/取码失败），其余字段照常展示。
- (void)configureWithAvatarURL:(nullable NSString *)avatarURL
                          seed:(NSString *)seed
                          name:(NSString *)name
                      subtitle:(nullable NSString *)subtitle
                      qrString:(nullable NSString *)qrString
                          hint:(nullable NSString *)hint;

/// 当前二维码图片（供保存到相册/分享）；未取到码时为 nil。
@property (nonatomic, strong, readonly, nullable) UIImage *qrImage;

@end

NS_ASSUME_NONNULL_END
