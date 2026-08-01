#import <UIKit/UIKit.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMBubbleCell : UITableViewCell
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
