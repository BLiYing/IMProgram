//  IMMediaViewerViewController.h
//  可复用的全屏媒体查看器：图片（缩放）或视频（首帧封面 + 居中播放按钮 → 点击整页播放/暂停 +
//  进度条 + 倍速 + 查看原视频 + 保存到相册）。聊天气泡点击、会话媒体库点击共用本查看器。

#import <UIKit/UIKit.h>
#import "IMPopoverCard.h"

NS_ASSUME_NONNULL_BEGIN

@protocol IMMediaViewerContentDelegate;

@interface IMMediaViewerViewController : UIViewController

/// 「更多」菜单的外部动作（定位到聊天位置/收藏/复制/转发等，由调用方按消息上下文提供）。
/// 非空时查看器显示「⋯」按钮 → IMPopoverCard 锚点菜单（内置一项「下载」在最前）。
/// 外部动作触发时查看器**先自行关闭**再执行 handler（定位/转发都发生在聊天页）。
@property (nonatomic, copy, nullable) NSArray<IMPopoverCardItem *> *moreActions;

/// 在会话媒体时间线中的下标（任务3·翻页容器写入并据此算前后页；单独打开时无意义）。
@property (nonatomic) NSUInteger imMediaIndex;

/// 无壳模式（任务3·翻页容器托管）：YES=**只画内容**（可缩放图片 / 视频画面+封面+中央播放键+底部进度条），
/// **不画** ✕/下载/媒体库/更多（这些由容器 IMMediaPagerViewController 的固定层统一绘制并绑定当前页，
/// 翻页时不随内容滑动）。单击画面不再关闭/直接播放，改转发给 contentDelegate（由容器切 chrome 显隐）。
/// 默认 NO：详情/记录/收藏等**单独打开**的入口保持原行为（自带全套控件）。
@property (nonatomic) BOOL chromeless;

/// 无壳模式下由容器（翻页页）设置，接收单击 / 播放态变化事件。
@property (nonatomic, weak, nullable) id<IMMediaViewerContentDelegate> contentDelegate;

#pragma mark 供翻页容器固定层驱动/查询当前页（chromeless 下使用）
@property (nonatomic, readonly) BOOL isVideoContent;   ///< 当前页是否视频
@property (nonatomic, readonly) BOOL isVideoPlaying;    ///< 视频是否正在播放（暂停/未开播=NO）
@property (nonatomic, readonly) BOOL hasGalleryEntry;   ///< 是否配了「媒体库」入口（决定容器是否显示媒体库键）
- (void)togglePlayback;                                 ///< 容器中央播放键调用
- (void)invokeOpenGallery;                              ///< 容器媒体库键调用（先关查看器再回调）
- (void)saveToAlbum;                                    ///< 容器下载键调用（保存到相册）
- (void)setAuxControlsHidden:(BOOL)hidden;              ///< 沉浸态：隐藏倍速/查看原视频（进度条+时间保留）

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

/// 无壳内容页 → 容器（翻页页）回调。
@protocol IMMediaViewerContentDelegate <NSObject>
/// 单击画面：容器据此切换 chrome（工具按钮）显隐（沉浸态）。
- (void)mediaViewerContentDidSingleTap:(IMMediaViewerViewController *)vc;
/// 视频播放态变化：容器据此管理 3s 自动隐藏（播放中才隐藏；暂停常显）。
- (void)mediaViewerContent:(IMMediaViewerViewController *)vc playingChanged:(BOOL)playing;
@end

NS_ASSUME_NONNULL_END
