//  IMJoinRequestsViewController.h
//  待审入群申请列表（G3，群主/管理员）：同意/拒绝。被 push（容器注入液态标题栏），用普通 VC + UITableView。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMJoinRequestsViewController : UIViewController

/// token=鉴权；convID=群；onChanged=审批后回调（供上层刷新 pending_count 角标）。
- (instancetype)initWithToken:(NSString *)token
                       convID:(NSString *)convID
                    onChanged:(nullable void (^)(void))onChanged;

@end

NS_ASSUME_NONNULL_END
