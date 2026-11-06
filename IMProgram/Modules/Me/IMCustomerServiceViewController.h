//  IMCustomerServiceViewController.h
//  在线客服（Beacon 访客 H5）的自有 WKWebView 页：键盘上方留位、禁缩放、UA 追加 BeaconApp/<ver> (iOS)。
//  与 Android WebViewScreen 对齐。beaconBridge 暂缓，未实现。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMCustomerServiceViewController : UIViewController

- (instancetype)initWithURL:(NSURL *)url;
- (instancetype)initWithNibName:(nullable NSString *)n bundle:(nullable NSBundle *)b NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)c NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
