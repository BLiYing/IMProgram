//  IMCustomerServiceViewController.h
//  在线客服（Beacon 访客 H5）的自有 WKWebView 页：键盘上方留位、禁缩放、UA 追加 BeaconApp/<ver> (iOS)。
//  与 Android WebViewScreen 对齐。beaconBridge 暂缓，未实现。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMCustomerServiceViewController : UIViewController

- (instancetype)initWithURL:(NSURL *)url;
/// title 非空时固定用它做标题（多公司时是公司名，BEACON_CS_DESIGN §2.2），不被网页 <title> 替换。
- (instancetype)initWithURL:(NSURL *)url title:(nullable NSString *)title;
- (instancetype)initWithNibName:(nullable NSString *)n bundle:(nullable NSBundle *)b NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)c NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
