//  IMMyTenantViewController.h
//  我 ▸ 我的集团（交互稿 I-12）：填邀请码（无集团 / 客户）+ 我在集团里的位置（员工）或已绑子公司（客户）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMMyTenantViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

/// 纯函数（单测）：要不要显示「填写邀请码」段——无集团，或身份是客户（还能再绑本集团别的子公司）；员工不显示。
FOUNDATION_EXPORT BOOL IMMyTenantShowsInvite(BOOL hasTenant, BOOL isCustomer, BOOL inviteEnabled);

NS_ASSUME_NONNULL_END
