//  IMMediaViewerViewController.h
//  可复用的全屏媒体查看器：图片（缩放）或视频（首帧封面 + 居中播放按钮 → 点击整页播放/暂停 +
//  进度条 + 倍速 + 查看原视频 + 保存到相册）。聊天气泡点击、会话媒体库点击共用本查看器。

#import <UIKit/UIKit.h>
#import "IMBottomSheet.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMMediaViewerViewController : UIViewController

/// 「更多」面板的外部动作（定位到聊天位置/收藏/复制/转发等，由调用方按消息上下文提供）。
/// 非空时查看器显示「⋯」按钮 → IMBottomSheet（内置一项「下载」在最前）。
/// 外部动作触发时查看器**先自行关闭**再执行 handler（定位/转发都发生在聊天页）。
@property (nonatomic, copy, nullable) NSArray<IMBottomSheetItem *> *moreActions;

/// 展示单个媒体。
/// @param fullURL        已拼好 host 的完整媒体地址（图片或视频）。
/// @param isVideo        YES=视频（首帧+播放器），NO=图片（缩放查看）。
/// @param preloadedImage 图片可传入气泡已加载好的图先占位（避免二次等待）；视频忽略。
/// @param onOpenGallery  非空则右下角显示「媒体库」网格按钮；点击时查看器先关闭自身再回调（由聊天页去 push 媒体库）。
+ (instancetype)viewerWithURL:(NSString *)fullURL
                      isVideo:(BOOL)isVideo
               preloadedImage:(nullable UIImage *)preloadedImage
                onOpenGallery:(nullable dispatch_block_t)onOpenGallery;

@end

NS_ASSUME_NONNULL_END
