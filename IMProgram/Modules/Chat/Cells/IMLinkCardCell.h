#import <UIKit/UIKit.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMLinkCardCell : UITableViewCell
@property (nonatomic, copy, nullable) void (^onTap)(NSString *url);
- (void)configureWithMessage:(IMMessageModel *)message mine:(BOOL)mine;
@end

NS_ASSUME_NONNULL_END
