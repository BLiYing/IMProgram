//  IMQRScannerViewController.h
//  扫一扫（QRCODE P0）：全屏相机取景 + 相册识别 + 手电筒，底部两页签「扫码 / 我的二维码」
//  （扫完常被对方回扫，页签切换比"退出再进另一个页面"少两步）。
//  本页只负责**识别 + 调 `/qr/resolve`**，不做落地跳转——结果经 onResult 交回宿主由 IMQRResultRouter 路由，
//  这样"扫码结果落到哪个页面"只有一处实现。

#import <UIKit/UIKit.h>

@class IMQRResolved;

NS_ASSUME_NONNULL_BEGIN

@interface IMQRScannerViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID NS_DESIGNATED_INITIALIZER;

/// 识别并解析完成（本页已自行 dismiss）。resolved/error 二者其一非空；raw 为扫到的原文。
@property (nonatomic, copy, nullable) void (^onResult)(IMQRResolved *_Nullable resolved,
                                                       NSString *raw,
                                                       NSError *_Nullable error);

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nib bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
