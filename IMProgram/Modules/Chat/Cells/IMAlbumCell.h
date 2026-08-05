#import <UIKit/UIKit.h>

@class IMMessageModel;
@class IMUploadProgress;

NS_ASSUME_NONNULL_BEGIN

@interface IMAlbumCell : UITableViewCell
@property (nonatomic, copy, nullable) void (^onTapItem)(IMMessageModel *message);
@property (nonatomic, copy, nullable) UIMenu *_Nullable (^menuForItem)(IMMessageModel *message);

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
