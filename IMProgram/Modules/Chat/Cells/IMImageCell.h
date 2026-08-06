#import <UIKit/UIKit.h>

@class IMMessageModel;
@class IMUploadProgress;
@class IMDownloadProgress;

NS_ASSUME_NONNULL_BEGIN

/// 单张图片/视频气泡。缩略图**按媒体原始比例**渲染（media_w/media_h，未知时回退方形占位，
/// 加载出真实尺寸后由外部 reload 重排），上面叠三个角标：
///   - 左上：视频时长 `1:05`（上传中改显「已传 / 总大小」，两者互斥不重叠）；
///   - 右下：发送时间 + 自己消息的 ✓/✓✓ 已读态；
///   - 居中：播放按钮（视频）。
@interface IMImageCell : UITableViewCell

/// 长按菜单高亮/收起动画的目标视图（=缩略图本体）。
@property (nonatomic, strong, readonly) UIView *previewTargetView;

/// 已知像素尺寸的媒体在气泡里的显示高度（与 cell 内部同一套缩放规则）；
/// 尺寸未知（<=0）返回方形占位边长。供聊天页 estimatedHeightForRow 精确估高，消除上滑行高跳变。
+ (CGFloat)displayHeightForPixelWidth:(CGFloat)pixelW pixelHeight:(CGFloat)pixelH;

@property (nonatomic, copy, nullable) void (^onTap)(UIImage *_Nullable image);

/// 门控态（M4-7）：收到的媒体按自动下载策略"未下载"——显模糊占位（图片）/封面（视频）
/// + 中心 ↓ + 尺寸角标，不加载原图 / 不放行播放。由 VC 在 configure **前**设置；
/// tap 时触发 onDownloadTap 而非 onTap。
@property (nonatomic, assign) BOOL gated;
/// 门控态下的下载进度（视频走 IMMediaDownloader 有真进度：环形 + ⏸/↻）。
/// nil 或 NotStarted = 只显 ↓；图片没有分片下载器，恒传 nil。同样必须在 configure **前**设置。
@property (nonatomic, strong, nullable) IMDownloadProgress *downloadProgress;
/// 门控态下点击（开始下载 / 暂停 / 继续 / 重试，由 VC 按当前态路由）。
@property (nonatomic, copy, nullable) void (^onDownloadTap)(void);

/// 下载进度**就地更新**（M4-7）：宿主在高频 onProgress 回调里调用，只改中心图标/角标/进度环，
/// 不重配 cell、不触发 reloadRows——否则每片一次 reload 会卡死主线程并让自适应高度的行上下跳变。
- (void)updateDownloadProgress:(nullable IMDownloadProgress *)progress;
/// 老消息没有 media_w/media_h 时，异步出图后才知道真实比例 → 携带量出的像素尺寸回调聊天页：
/// 写回模型+落库（下次进会话行高首帧即正确）并刷一次行高（无动画）。
@property (nonatomic, copy, nullable) void (^onMediaSizeResolved)(CGSize pixelSize);

/// 点拒收系统行的恢复入口（当前仅 200103 非好友 → 「发送好友申请」）。
/// 仅当 message.noteCode 命中可恢复码时该行才可点，否则系统行是纯文案。
@property (nonatomic, copy, nullable) void (^onNoteActionTap)(void);

/// fullURL 为空=尚未上传完成（只显本地预览、不发起网络加载）。
/// posterURL 为视频封面的完整 URL（message.poster 补 host 后）：**有封面就绝不去抽帧**——
/// 抽帧要对远端视频发 range 请求拉几 MB，而封面只是一张几十 KB 的 JPEG。
/// 尺寸/时长/时间/已读态全部取自 message，故直接传模型而非逐个参数。
- (void)configureWithMessage:(IMMessageModel *)message
                     fullURL:(NSString *)fullURL
                   posterURL:(nullable NSString *)posterURL
                        mine:(BOOL)mine
                 peerReadSeq:(int64_t)peerReadSeq
                previewImage:(nullable UIImage *)preview
                  senderName:(nullable NSString *)senderName;

/// nil=不在上传中（隐藏进度、恢复时长角标）。
- (void)setUploadProgress:(nullable IMUploadProgress *)progress;

- (void)applyGroupAvatarURL:(nullable NSString *)url
                       seed:(NSString *)seed
                       name:(nullable NSString *)name
                 showAvatar:(BOOL)showAvatar
                     gutter:(BOOL)gutter;
@end

NS_ASSUME_NONNULL_END
