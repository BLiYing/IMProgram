//  IMCustomerServiceViewController.h
//  在线客服（Beacon 访客 H5）的自有 WKWebView 页：键盘上方留位、禁缩放、UA 追加 BeaconApp/<ver> (iOS)。
//  与 Android WebViewScreen 对齐。beaconBridge 暂缓，未实现。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMCustomerServiceViewController : UIViewController

- (instancetype)initWithURL:(NSURL *)url;
/// title 非空时固定用它做标题（多公司时是公司名，BEACON_CS_DESIGN §2.2），不被网页 <title> 替换。
- (instancetype)initWithURL:(NSURL *)url title:(nullable NSString *)title;
/// 工作台应用 / 轮播链接（WORKBENCH_DESIGN §3.2，交互稿 I-5）：左 ✕、右 ⋯（刷新 / 用浏览器打开——外开去掉 im_ticket）；
/// 标题先用 title（应用名），网页 <title> 到了再替换；不带 BeaconApp 标识；内置浏览器只开 https 与本机 / 内网 http，其余交给系统。
- (instancetype)initWorkbenchWithURL:(NSURL *)url title:(nullable NSString *)title;
- (instancetype)initWithNibName:(nullable NSString *)n bundle:(nullable NSBundle *)b NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)c NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
