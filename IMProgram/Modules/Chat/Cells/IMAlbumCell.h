#import <UIKit/UIKit.h>
#import "IMMessageCell.h"

@class IMMessageModel;
@class IMUploadProgress;
@class IMDownloadProgress;

NS_ASSUME_NONNULL_BEGIN

@interface IMAlbumCell : IMMessageCell
@property (nonatomic, copy, nullable) void (^onTapItem)(IMMessageModel *message);
@property (nonatomic, copy, nullable) UIMenu *_Nullable (^menuForItem)(IMMessageModel *message);

/// 逐格下载门控（M4-7，草图 §02-C「相册宫格：每格独立下载态」）：
/// 返回 nil = 该格就绪（正常显缩略图/▶）；非 nil = 未下载/下载中/暂停/失败，显 ↓ 或环形进度，
/// 该格**不加载原图**、点击走 onDownloadItem 而非 onTapItem。
/// 由 VC 在 `configureWithMembers:` **前**设置（bind 时逐格回调查询）。
@property (nonatomic, copy, nullable) IMDownloadProgress *_Nullable (^downloadStateForItem)(IMMessageModel *message);
/// 门控格点击（开始下载 / 暂停 / 继续 / 重试，由 VC 按当前态路由）。
@property (nonatomic, copy, nullable) void (^onDownloadItem)(IMMessageModel *message);

/// 某成员下载进度**就地更新**（M4-7）：只刷该格的进度环/图标，不重建宫格、不 reloadRows。
/// 宿主在高频 onProgress 回调里调用（否则每片一次 reload 会卡死主线程）。
- (void)updateDownloadProgress:(nullable IMDownloadProgress *)progress forMessage:(IMMessageModel *)message;

/// 点拒收系统行的恢复入口（当前仅 200103 非好友 → 「发送好友申请」）。
/// 仅当成员 noteCode 命中可恢复码时该行才可点，否则系统行是纯文案。
@property (nonatomic, copy, nullable) void (^onNoteActionTap)(void);

/// 多选态逐格勾选（2a）：编辑态每格右上角显勾选框；查询该格是否已选 / 点格切换该格选中。
/// selecting 由 cell 的编辑态驱动；VC 提供这两个块。左侧系统圈仍表示「整组全选」（见 VC Selection）。
@property (nonatomic, copy, nullable) BOOL (^isMemberSelected)(IMMessageModel *message);
@property (nonatomic, copy, nullable) void (^onToggleMember)(IMMessageModel *message);
/// 按最新 isMemberSelected 就地重刷各格勾选框（左侧系统圈全选/全不选后、VC 调用）。
- (void)refreshTileSelectionStates;
- (void)configureWithMembers:(NSArray<IMMessageModel *> *)members
                        mine:(BOOL)mine
                        host:(NSString *)host
                    previews:(NSDictionary<NSString *, UIImage *> *)previews
                    progress:(NSDictionary<NSString *, IMUploadProgress *> *)progress
                  senderName:(nullable NSString *)senderName
                  senderRole:(IMGroupRole)senderRole;
- (void)refreshWithPreviews:(NSDictionary<NSString *, UIImage *> *)previews
                   progress:(NSDictionary<NSString *, IMUploadProgress *> *)progress;
// onAvatarTap / applyUnreadDivider: 由 IMMessageCell 基类提供。

- (void)applyGroupAvatarURL:(nullable NSString *)url
                       seed:(NSString *)seed
                       name:(nullable NSString *)name
                 showAvatar:(BOOL)showAvatar
                     gutter:(BOOL)gutter;
@end

NS_ASSUME_NONNULL_END
