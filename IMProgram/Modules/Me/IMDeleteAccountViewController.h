//  IMDeleteAccountViewController.h
//  注销账号二级页（设计：IMServer/docs/design/DELETE_ACCOUNT_DESIGN.md §3 §4；草图 sketches/DELETE_ACCOUNT_UX_SKETCH.html）。
//  警示头 + 4 条后果 + 冷静期提示条 + 密码框 + 红按钮；群主阻断态；UIAlertController 二次确认；
//  成功后清会话 + 清本机聊天缓存，回登录页并提示 delete_account.done_hint。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 红按钮可点条件：密码非空、非阻断态、非请求在途。
FOUNDATION_EXPORT BOOL IMDeleteAccountCanSubmit(NSString *_Nullable password, BOOL blocked, BOOL busy);

/// 阻断态最多列出的群数（其余折成「等 N 个」）。
FOUNDATION_EXPORT NSInteger const IMDeleteAccountMaxListedGroups;

/// 阻断提示里实际列出的群（前 IMDeleteAccountMaxListedGroups 个）。
FOUNDATION_EXPORT NSArray<NSDictionary<NSString *, NSString *> *> *IMDeleteAccountListedGroups(
    NSArray<NSDictionary<NSString *, NSString *> *> *groups);

/// 未列出的群数（>=0）。
FOUNDATION_EXPORT NSInteger IMDeleteAccountHiddenGroupCount(NSArray<NSDictionary<NSString *, NSString *> *> *groups);

@interface IMDeleteAccountViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSString *)n bundle:(nullable NSBundle *)b NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)c NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
