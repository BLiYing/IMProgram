#import <UIKit/UIKit.h>

@class IMMessageModel;
@class IMUploadProgress;

NS_ASSUME_NONNULL_BEGIN

/// 单张图片/视频气泡。缩略图**按媒体原始比例**渲染（media_w/media_h，未知时回退方形占位，
/// 加载出真实尺寸后由外部 reload 重排），上面叠三个角标：
///   - 左上：视频时长 `1:05`（上传中改显「已传 / 总大小」，两者互斥不重叠）；
///   - 右下：发送时间 + 自己消息的 ✓/✓✓ 已读态；
///   - 居中：播放按钮（视频）。
@interface IMImageCell : UITableViewCell

@property (nonatomic, copy, nullable) void (^onTap)(UIImage *_Nullable image);
/// 老消息没有 media_w/media_h 时，异步出图后才知道真实比例 → 回调聊天页刷一次行高（无动画）。
@property (nonatomic, copy, nullable) void (^onMediaSizeResolved)(void);

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
