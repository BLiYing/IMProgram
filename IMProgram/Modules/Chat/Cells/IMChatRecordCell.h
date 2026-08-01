#import <UIKit/UIKit.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMChatRecordCell : UITableViewCell
@property (nonatomic, copy, nullable) void (^onTap)(void);
- (void)configureWithMessage:(IMMessageModel *)message mine:(BOOL)mine;
@end

NS_ASSUME_NONNULL_END
