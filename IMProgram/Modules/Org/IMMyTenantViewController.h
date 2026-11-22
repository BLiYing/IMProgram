//  IMMyTenantViewController.h
//  设置 ▸ 填写邀请码（交互稿 I-12）：只给无集团用户与客户——填邀请码 + 客户已绑的子公司（「已绑定 · 集团名」）。员工没有这一页。
//  IMOrgJoinViewController：无集团用户点通讯录「组织架构」看到的空态（交互稿 I-6b），按钮进填写邀请码。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMMyTenantViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

@interface IMOrgJoinViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

/// 纯函数（单测）：设置页「填写邀请码」行与页内填码段——无集团，或身份是客户（还能再绑本集团别的子公司），且邀请码功能开着；员工不显示。
FOUNDATION_EXPORT BOOL IMMyTenantShowsInvite(BOOL hasTenant, BOOL isCustomer, BOOL inviteEnabled);

NS_ASSUME_NONNULL_END
