#import <UIKit/UIKit.h>

@class IMMessageModel;
@class IMUploadProgress;

NS_ASSUME_NONNULL_BEGIN

@interface IMBubbleCell : UITableViewCell

/// 文件消息上传中的进度（nil=非上传态）。文件气泡第二行据此显「已传 / 总大小 · 点击暂停」。
/// 必须在 configure 之前设置：气泡正文是一次性拼好的富文本。
@property (nonatomic, strong, nullable) IMUploadProgress *uploadProgress;
- (void)configureWithMessage:(IMMessageModel *)message
                        mine:(BOOL)mine
                 peerReadSeq:(int64_t)peerReadSeq
                   dayHeader:(nullable NSString *)dayHeader
          showsUnreadDivider:(BOOL)showsDivider
                  senderName:(nullable NSString *)senderName
               replyThumbURL:(nullable NSString *)replyThumbURL
           replyThumbIsVideo:(BOOL)replyThumbIsVideo;
- (void)applyGroupAvatarURL:(nullable NSString *)url
                       seed:(NSString *)seed
                       name:(nullable NSString *)name
                 showAvatar:(BOOL)showAvatar
                     gutter:(BOOL)gutter;
@end

NS_ASSUME_NONNULL_END
