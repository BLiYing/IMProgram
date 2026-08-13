//  IMQRResultRouter.h
//  扫码结果 → 页面路由（QRCODE P0）。语义判定全在服务端 `/qr/resolve`，本层只按 kind 落到**已有页面**：
//  名片码 → 资料页（加好友/发消息由资料页自己按好友态决定）；群码 → 加群预览；
//  失效码 → 统一提示（不区分过期/被重置/不存在）；外来码 → 原文 + 域名二次确认，**绝不自动跳转**。

#import <UIKit/UIKit.h>

@class IMQRResolved;

NS_ASSUME_NONNULL_BEGIN

@interface IMQRResultRouter : NSObject

/// 落地一个已解析的扫码结果。raw=扫到的原文（凭码入群要回传给 `POST /groups/join`）；vc 提供导航栈与弹窗宿主。
+ (void)routeResolved:(IMQRResolved *)resolved
                  raw:(NSString *)raw
                 host:(NSString *)host
               userID:(NSString *)userID
       fromController:(UIViewController *)vc;

/// resolve / 入群失败的统一提示（`200110` 的文案已在 IMHTTPService 映射为「二维码已失效…」）。
+ (void)presentError:(nullable NSError *)error fromController:(UIViewController *)vc;

@end

NS_ASSUME_NONNULL_END
