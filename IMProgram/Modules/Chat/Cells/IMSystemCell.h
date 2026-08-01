#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMSystemCell : UITableViewCell
- (void)configureWithText:(NSString *)text;
- (void)configureWithText:(NSString *)text reeditHandler:(nullable void (^)(void))reeditHandler;
@end

NS_ASSUME_NONNULL_END
