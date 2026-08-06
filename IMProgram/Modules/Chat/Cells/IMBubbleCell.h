#import <UIKit/UIKit.h>

@class IMMessageModel;
@class IMUploadProgress;
@class IMDownloadProgress;

NS_ASSUME_NONNULL_BEGIN

@interface IMBubbleCell : UITableViewCell

/// 长按菜单高亮/收起动画的目标视图（=气泡本体）：系统默认会截整行全宽快照，露出难看的底色托盘。
@property (nonatomic, strong, readonly) UIView *previewTargetView;

/// 文件消息上传中的进度（nil=非上传态）。文件气泡左侧图标位据此变圆环状态机
///（排队✕ / 上传中⏸ / 已暂停↑ / 失败↻，与媒体气泡中心按钮同一套 glyph），第二行显进度文案。
/// 必须在 configure 之前设置：configure 一次性布好整条气泡。
@property (nonatomic, strong, nullable) IMUploadProgress *uploadProgress;

/// 文件消息**下载**态（收到的文件，M4-7；nil=不显下载态）。与 uploadProgress 互斥：
/// 自己发的用 uploadProgress，收到的用 downloadProgress。图标位据此变圆环状态机（未下载↓ / 下载中⏸ / 暂停↓ / 失败↻ / 就绪=文件图标）。
@property (nonatomic, strong, nullable) IMDownloadProgress *downloadProgress;

/// 文件气泡左侧图标位被点按（上传中/失败态：暂停↔继续 / 重试 / 取消；下载态：下载 / 暂停↔继续 / 重试）。
/// 完成/就绪态图标不可点，点击整条气泡=打开文件（走 VC 的表级手势）。
@property (nonatomic, copy, nullable) void (^onFileControlTap)(void);
/// 点群聊对方头像 → 进该成员资料页（VC 在群聊对方气泡上挂载；单聊/自己不挂）。
@property (nonatomic, copy, nullable) void (^onAvatarTap)(void);
/// 点拒收系统行的恢复入口（当前仅 200103 非好友 → 「发送好友申请」）。
/// 仅当 message.noteCode 命中可操作码时该行才可点，否则系统行是纯文案。
@property (nonatomic, copy, nullable) void (^onNoteActionTap)(void);
- (void)configureWithMessage:(IMMessageModel *)message
                        mine:(BOOL)mine
                 peerReadSeq:(int64_t)peerReadSeq
                   dayHeader:(nullable NSString *)dayHeader
          showsUnreadDivider:(BOOL)showsDivider
                  senderName:(nullable NSString *)senderName
               replyThumbURL:(nullable NSString *)replyThumbURL
           replyThumbIsVideo:(BOOL)replyThumbIsVideo
               replyFromName:(nullable NSString *)replyFromName;
- (void)applyGroupAvatarURL:(nullable NSString *)url
                       seed:(NSString *)seed
                       name:(nullable NSString *)name
                 showAvatar:(BOOL)showAvatar
                     gutter:(BOOL)gutter;
@end

NS_ASSUME_NONNULL_END
