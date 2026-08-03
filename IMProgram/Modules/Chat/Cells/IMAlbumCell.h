#import <UIKit/UIKit.h>

@class IMMessageModel;
@class IMUploadProgress;

NS_ASSUME_NONNULL_BEGIN

@interface IMAlbumCell : UITableViewCell
@property (nonatomic, copy, nullable) void (^onTapItem)(IMMessageModel *message);
@property (nonatomic, copy, nullable) UIMenu *_Nullable (^menuForItem)(IMMessageModel *message);
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
