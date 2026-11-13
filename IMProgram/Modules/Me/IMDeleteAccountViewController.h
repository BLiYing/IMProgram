//  IMDeleteAccountViewController.h
//  注销账号二级页（设计：IMServer/docs/design/DELETE_ACCOUNT_DESIGN.md §3 §4；草图 sketches/DELETE_ACCOUNT_UX_SKETCH.html）。
//  警示头 + 4 条后果 + 冷静期提示条 + 红按钮（点后二次确认 → 确认身份弹层）；群主阻断态；UIAlertController 二次确认；
//  版式（警示头 / 后果卡 / 红按钮）取自共用的 IMDangerPageViewController。
//  成功后清会话 + 清本机聊天缓存，回登录页并提示 delete_account.done_hint。

#import "IMDangerPageViewController.h"

NS_ASSUME_NONNULL_BEGIN

/// 红按钮可点条件：非阻断态（身份确认与在途都在弹层里，PHONE_AUTH_DESIGN §7；页面自身不进在途态）。
FOUNDATION_EXPORT BOOL IMDeleteAccountCanSubmit(BOOL blocked);

/// 阻断态最多列出的群数（其余折成「等 N 个」）。
FOUNDATION_EXPORT NSInteger const IMDeleteAccountMaxListedGroups;

/// 阻断提示里实际列出的群（前 IMDeleteAccountMaxListedGroups 个）。
FOUNDATION_EXPORT NSArray<NSDictionary<NSString *, NSString *> *> *IMDeleteAccountListedGroups(
    NSArray<NSDictionary<NSString *, NSString *> *> *groups);

/// 未列出的群数（>=0）。
FOUNDATION_EXPORT NSInteger IMDeleteAccountHiddenGroupCount(NSArray<NSDictionary<NSString *, NSString *> *> *groups);

@interface IMDeleteAccountViewController : IMDangerPageViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSString *)n bundle:(nullable NSBundle *)b NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)c NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
