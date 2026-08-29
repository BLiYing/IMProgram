//  IMMediaPicker.h
//  可复用媒体选择器（原生 PHPickerViewController，零依赖）：
//  多选 ≤limit（聊天=9，头像=1 可复用）、图片/Live 图/视频；选完弹「发送 / 发送原图」。
//  M4+ 秒上屏重构：回调返回**惰性句柄**（选择器关闭即回调，不做任何重活）——
//  压缩（图片长边≤2048 JPEG0.8）/ 转码（视频 720p mp4）/ 体积校验（≤2GB）全部延后到
//  loadData（调用方逐项串行触发），缩略图另走 loadThumbnail 快速出图 → 聊天页可先上屏占位。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern const long long kIMMaxVideoBytes; // 视频体积上限（与服务端 2GB 一致，后续 C3 改读服务端配置）

/// 「拍摄」入口**现录**视频的时长上限（秒）。注意与相册选片区分：**相册选的视频不限时长**
/// （只受 kIMMaxVideoBytes 约束，用户拍板），这里限的只是相机当场录的那一段，因为它多出两条约束：
///   1. 转码超时是写死的 120s（见 exportVideoAtURL:）——超时会**回落发原编码**，
///      设备开「高效」格式时收端 Chrome/Firefox 只能看封面点不开；
///   2. 录制原件先整份落 tmp（1080p30 ≈17Mbps → 60s ≈130MB），时长翻倍磁盘与转码耗时同步翻倍。
/// 60s 转码后 ≈18MB，落在分片上传区间（可暂停续传）。要发更长的：走「照片」（相册，不限时长）
/// 或「文件」（原件直传，不转码）。
extern const NSTimeInterval kIMCameraVideoMaxSeconds;

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

/// 文件面板专用（磁盘路径）：把相册原始资源导出为**临时文件**——不压缩、不转码、绝不进内存，
/// 2GB 级视频也安全。回调主线程；成功时 item.fileURL 非空（所有权移交调用方）、data 恒为 nil。
- (void)loadFileURL:(void (^)(IMPickedMedia *_Nullable item))completion;

/// 选择器返回瞬间即可用的建议文件名（含扩展名，best-effort）：乐观气泡不必等导出完成。
/// 拿不到 suggestedName 时回落 photo.jpg / video.mov。
- (NSString *)suggestedFileName;
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

#pragma mark 相机（系统相机，照片 + 录像双模式）

/// 给系统相机 picker 套上本项目口径：照片/视频双模式、录制上限 kIMCameraVideoMaxSeconds、
/// 画质取设备默认（High）。**不设 sourceType**——那是调用方的事，且在无相机的设备/模拟器上
/// 设成 Camera 会直接抛异常（本方法因此可在单测里不碰相机地断言配置）。
///
/// videoQuality 刻意不用 IFrame1280x720：那是**全 I 帧**编码（~29Mbps），文件比设备默认还大，
/// 只会拖慢后续转码；分辨率的活交给 AVAssetExportPreset1280x720。
+ (void)configureCameraPicker:(nullable UIImagePickerController *)picker;

/// 把相机录制产物（本地 tmp 文件）包成惰性句柄，直接喂给相册那条发送链路
/// （乐观气泡 → 720p H.264 转码 → 落盘落库 → 分片上传 → 补传封面 → 发 video 消息）。
/// **不拷贝**：文件所有权移交句柄——转码成功后原件被删；句柄未 loadData 就释放时由 dealloc 兜底删除。
/// url 为空或文件不存在返回 nil。
+ (nullable IMPickedMediaHandle *)handleForRecordedVideoAtURL:(nullable NSURL *)url;

@end

NS_ASSUME_NONNULL_END
