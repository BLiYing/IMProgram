#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMImageCell : UITableViewCell
@property (nonatomic, copy, nullable) void (^onTap)(UIImage *_Nullable image);
- (void)configureWithURL:(NSString *)fullURL
                 isVideo:(BOOL)isVideo
                    mine:(BOOL)mine
            previewImage:(nullable UIImage *)preview
              senderName:(nullable NSString *)senderName;
- (void)setUploadProgress:(float)progress;
- (void)applyGroupAvatarURL:(nullable NSString *)url
                       seed:(NSString *)seed
                       name:(nullable NSString *)name
                 showAvatar:(BOOL)showAvatar
                     gutter:(BOOL)gutter;
@end

NS_ASSUME_NONNULL_END
