//  IMMediaPicker.h
//  可复用媒体选择器（原生 PHPickerViewController，零依赖）：
//  多选 ≤limit（聊天=9，头像=1 可复用）、图片/Live 图/视频；选完弹「发送 / 发送原图」。
//  M4+ 秒上屏重构：回调返回**惰性句柄**（选择器关闭即回调，不做任何重活）——
//  压缩（图片长边≤2048 JPEG0.8）/ 转码（视频 720p mp4）/ 体积校验（≤100MB）全部延后到
//  loadData（调用方逐项串行触发），缩略图另走 loadThumbnail 快速出图 → 聊天页可先上屏占位。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern const long long kIMMaxVideoBytes; // 视频体积上限（与服务端 100MB 一致，后续 C3 改读服务端配置）

/// 一个已就绪（已按需压缩）的媒体项——loadData 的产物，可直接上传。
@interface IMPickedMedia : NSObject
@property (nonatomic, strong) NSData   *data;
@property (nonatomic, copy)   NSString *fileName;   ///< 带扩展名（如 photo.jpg / video.mp4）
@property (nonatomic, copy)   NSString *mimeType;
@property (nonatomic, assign) BOOL      isVideo;
@end

/// 惰性媒体句柄：持有 NSItemProvider，重活（压缩/转码）延后到 loadData。
/// 句柄内部串行队列保证 loadThumbnail / loadData 互斥（视频临时文件复用不冲突）。
@interface IMPickedMediaHandle : NSObject
@property (nonatomic, assign, readonly) BOOL isVideo;
/// 预览级缩略图（视频=首帧 / 图片=降采样 ≤600px）；主线程回调，失败回 nil（调用方显灰占位）。
- (void)loadThumbnail:(void (^)(UIImage *_Nullable thumb))completion;
/// 最终待上传数据（图片压缩或原图字节 / 视频转码 720p 或原文件，含 ≤100MB 校验）；
/// 主线程回调，nil=加载失败或超限。
- (void)loadData:(void (^)(IMPickedMedia *_Nullable item))completion;
@end

@interface IMMediaPicker : NSObject

/// 弹出系统相册多选 →「发送 / 发送原图」→ **立即**回调惰性句柄（主线程；用户取消 → 空数组）。
/// 单例持有进行中的会话，选择器消失后自动释放。
+ (void)presentFromViewController:(UIViewController *)host
                            limit:(NSInteger)limit
                handlesCompletion:(void (^)(NSArray<IMPickedMediaHandle *> *handles))completion;

@end

NS_ASSUME_NONNULL_END
