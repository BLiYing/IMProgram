//  IMFilePreviewPresenter.h
//  文件消息预览的**唯一呈现口**：聊天页气泡 / 会话详情文件 tab / 收藏页文件项统一走这里，
//  拿到本地文件 URL 后一律 QuickLook——三处此前各自持 `quickLookURL` + 实现同一份 dataSource，
//  实为一段代码的三份拷贝（且详情页发送方误走 SFSafari 打远端 URL，行为不一致）。

#import <Foundation/Foundation.h>
@class UIViewController;

NS_ASSUME_NONNULL_BEGIN

@interface IMFilePreviewPresenter : NSObject

/// 用 QLPreviewController present 指定本地文件；本类实例被 associated object 挂在 QL 上保活，
/// dismiss 后一起释放，调用方无需持有。local 或 vc 为空即静默返回。
+ (void)presentURL:(nullable NSURL *)local fromViewController:(nullable UIViewController *)vc;

@end

NS_ASSUME_NONNULL_END
