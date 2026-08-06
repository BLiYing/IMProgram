#import <UIKit/UIKit.h>

@class IMMessageModel;
@class IMUploadProgress;
@class IMDownloadProgress;

NS_ASSUME_NONNULL_BEGIN

@interface IMAlbumCell : UITableViewCell
@property (nonatomic, copy, nullable) void (^onTapItem)(IMMessageModel *message);
@property (nonatomic, copy, nullable) UIMenu *_Nullable (^menuForItem)(IMMessageModel *message);

/// 逐格下载门控（M4-7，草图 §02-C「相册宫格：每格独立下载态」）：
/// 返回 nil = 该格就绪（正常显缩略图/▶）；非 nil = 未下载/下载中/暂停/失败，显 ↓ 或环形进度，
/// 该格**不加载原图**、点击走 onDownloadItem 而非 onTapItem。
/// 由 VC 在 `configureWithMembers:` **前**设置（bind 时逐格回调查询）。
@property (nonatomic, copy, nullable) IMDownloadProgress *_Nullable (^downloadStateForItem)(IMMessageModel *message);
/// 门控格点击（开始下载 / 暂停 / 继续 / 重试，由 VC 按当前态路由）。
@property (nonatomic, copy, nullable) void (^onDownloadItem)(IMMessageModel *message);

/// 点拒收系统行的恢复入口（当前仅 200103 非好友 → 「发送好友申请」）。
/// 仅当成员 noteCode 命中可恢复码时该行才可点，否则系统行是纯文案。
@property (nonatomic, copy, nullable) void (^onNoteActionTap)(void);
- (void)configureWithMembers:(NSArray<IMMessageModel *> *)members
                        mine:(BOOL)mine
                        host:(NSString *)host
                    previews:(NSDictionary<NSString *, UIImage *> *)previews
                    progress:(NSDictionary<NSString *, IMUploadProgress *> *)progress
                  senderName:(nullable NSString *)senderName;
- (void)refreshWithPreviews:(NSDictionary<NSString *, UIImage *> *)previews
                   progress:(NSDictionary<NSString *, IMUploadProgress *> *)progress;
- (void)applyGroupAvatarURL:(nullable NSString *)url
                       seed:(NSString *)seed
                       name:(nullable NSString *)name
                 showAvatar:(BOOL)showAvatar
                     gutter:(BOOL)gutter;
@end

NS_ASSUME_NONNULL_END
