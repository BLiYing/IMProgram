//  IMMediaPicker.h
//  可复用媒体选择器（原生 PHPickerViewController，零依赖）：
//  多选 ≤limit（聊天=9，头像=1 可复用）、图片/Live 图/视频；选完弹「发送 / 发送原图」。
//  M4+ 秒上屏重构：回调返回**惰性句柄**（选择器关闭即回调，不做任何重活）——
//  压缩（图片长边≤2048 JPEG0.8）/ 转码（视频 720p mp4）/ 体积校验（≤2GB）全部延后到
//  loadData（调用方逐项串行触发），缩略图另走 loadThumbnail 快速出图 → 聊天页可先上屏占位。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern const long long kIMMaxVideoBytes; // 视频体积上限（与服务端 2GB 一致，后续 C3 改读服务端配置）

/// 一个已就绪（已按需压缩）的媒体项——loadData 的产物，可直接上传。
@interface IMPickedMedia : NSObject
@property (nonatomic, strong) NSData   *data;
/// 视频最终产物落在磁盘（转码产物或原件临时文件）：非空表示字节**不在内存**（data=nil），
/// 由取用方负责搬走或删除。上限提到 2GB 后视频绝不能整包进 NSData。
@property (nonatomic, strong, nullable) NSURL *fileURL;
/// 待上传字节数：data 路径 = data.length；fileURL 路径 = 文件大小。
@property (nonatomic, assign) long long byteCount;
@property (nonatomic, copy)   NSString *fileName;   ///< 带扩展名（如 photo.jpg / video.mp4）
@property (nonatomic, copy)   NSString *mimeType;
@property (nonatomic, assign) BOOL      isVideo;
/// **最终产物**（压缩/转码后）的像素尺寸，已按 EXIF/视频 preferredTransform 校正为显示方向；
/// CGSizeZero=未知。随消息上行（media_w/media_h），收端据此按原比例渲染气泡。
@property (nonatomic, assign) CGSize    pixelSize;
/// 视频时长（毫秒）；0=非视频或未知。随消息上行（duration），收端在封面左上角显 mm:ss。
@property (nonatomic, assign) int64_t   durationMillis;
/// 最终产物的视频编码四字符码（如 avc1 / hvc1）；仅日志用，空=非视频或读不到。
@property (nonatomic, copy, nullable) NSString *videoCodec;
@end

/// 惰性媒体句柄：持有 NSItemProvider，重活（压缩/转码）延后到 loadData。
/// 句柄内部串行队列保证 loadThumbnail / loadData 互斥（视频临时文件复用不冲突）。
@interface IMPickedMediaHandle : NSObject
@property (nonatomic, assign, readonly) BOOL isVideo;
/// 预览级缩略图（视频=首帧 / 图片=降采样 ≤600px）；主线程回调，失败回 nil（调用方显灰占位）。
- (void)loadThumbnail:(void (^)(UIImage *_Nullable thumb))completion;
/// 最终待上传数据（图片压缩或原图字节 / 视频转码，含 ≤2GB 校验）；主线程回调，nil=加载失败或超限。
- (void)loadData:(void (^)(IMPickedMedia *_Nullable item))completion;

/// 带转码进度的变体：progress 在主线程按 0..1 回调（仅视频转码阶段有值，图片与直传不回调）。
/// 调用方据此把「压缩」与「上传」融合成一条连续进度。
- (void)loadData:(void (^)(IMPickedMedia *_Nullable item))completion
        progress:(nullable void (^)(double fraction))progress;

/// 文件面板专用：读取相册资源原始字节，不压缩、不转码，并保留扩展名。
- (void)loadFileData:(void (^)(IMPickedMedia *_Nullable item))completion;
@end

@interface IMMediaPicker : NSObject

/// 弹出系统相册多选 →「发送 / 发送原图」→ **立即**回调惰性句柄（主线程；用户取消 → 空数组）。
/// 单例持有进行中的会话，选择器消失后自动释放。
+ (void)presentFromViewController:(UIViewController *)host
                            limit:(NSInteger)limit
                handlesCompletion:(void (^)(NSArray<IMPickedMediaHandle *> *handles))completion;

/// 头像/单图场景：**仅显示图片**（无视频）、选完**不弹「发送 / 原图」动作表**，直接回调（压缩后句柄）。
/// limit=1 时选一张即自动关闭选择器并回调 → 调用方直接上传设头像。用户取消 → 空数组。
+ (void)presentImagePickerFromViewController:(UIViewController *)host
                                       limit:(NSInteger)limit
                           handlesCompletion:(void (^)(NSArray<IMPickedMediaHandle *> *handles))completion;

/// 文件面板相册入口：图片/视频多选，选完直接回调原始资源句柄，不显示媒体压缩选项。
+ (void)presentFilePickerFromViewController:(UIViewController *)host
                                      limit:(NSInteger)limit
                          handlesCompletion:(void (^)(NSArray<IMPickedMediaHandle *> *handles))completion;

@end

NS_ASSUME_NONNULL_END
