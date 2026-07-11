//  IMConversationMediaViewController.h
//  会话媒体库：按时间顺序展示本会话所有图片/视频缩略图网格；点击复用 IMMediaViewerViewController 查看
//  （与聊天气泡点击同一查看逻辑，只是此处不再显示「媒体库」按钮）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 媒体项（轻量值对象），供媒体库与查看器传递。
@interface IMMediaItem : NSObject
@property (nonatomic, copy)   NSString *url;   ///< 已拼好 host 的完整媒体地址
@property (nonatomic, assign) BOOL      isVideo;
@property (nonatomic, assign) int64_t   timestamp; ///< 毫秒
+ (instancetype)itemWithURL:(NSString *)url isVideo:(BOOL)isVideo timestamp:(int64_t)timestamp;
@end

@interface IMConversationMediaViewController : UIViewController
/// items 按调用方顺序展示（建议已按时间排序）。
+ (instancetype)galleryWithItems:(NSArray<IMMediaItem *> *)items;
@end

NS_ASSUME_NONNULL_END
