//  IMGroupBanListViewController.h
//  群黑名单页（G2）：列出被移出并永久/冷却拉黑的成员，滑动可解除。仅群主/管理员可达。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMGroupBanListViewController : UITableViewController

- (instancetype)initWithConvID:(NSString *)convID;

@end

NS_ASSUME_NONNULL_END
