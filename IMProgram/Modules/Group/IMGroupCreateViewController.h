//  IMGroupCreateViewController.h
//  **建群第二步**：群头像（可选）/ 群名称（必填，预填「我、A、B」）/ 成员回显（可 ✕，不可删到 0）。
//  设计稿：IMServer/docs/design/sketches/GROUP_CREATE_UX_SKETCH.html。
//
//  取代了原先「选好友 →『创建』→ 弹 UIAlertController 输群名」的形态——alert 里放不下头像、
//  没有字数计数、也没法预填后再让人改。原流程在 IMGroupListViewController 与
//  IMConversationListViewController 里**各抄了一份**，一并收敛到本页 + 下面的 start 入口。
//
//  ⚠️ 本页是 `UIViewController` + 内嵌 `UITableView`，**不是 UITableViewController**：
//  push 页用 TVC 会让注入的液态标题栏整体下移（本项目踩过三次）。

#import <UIKit/UIKit.h>

@class IMGroupInfo;
@class IMUserCard;

NS_ASSUME_NONNULL_BEGIN

@interface IMGroupCreateViewController : UIViewController

/// members 是第一步的勾选结果（**保持勾选顺序**，预填群名按这个序）。
/// host 只用于发请求前对齐 `IMHTTPService.sharedService.host`（与选好友页同一套路）。
- (instancetype)initWithHost:(NSString *)host
                     members:(NSArray<IMUserCard *> *)members
                   onCreated:(void (^)(IMGroupInfo *group))onCreated NS_DESIGNATED_INITIALIZER;

/// 从选好友页回来时更新成员。用户**手改过群名就不动群名**，否则按新成员重算预填名。
- (void)updateMembers:(NSArray<IMUserCard *> *)members;

/// **建群入口**（两处调用点共用）：push 选好友页（右上「下一步」）→ push 本页。
/// 「＋ 添加」是 pop 回选好友页，再点「下一步」时更新**同一个**本页实例——
/// 无脑 push 会在栈里叠出第二份一模一样的建群页。
+ (void)startInNavigationController:(UINavigationController *)nav
                               host:(NSString *)host
                             userID:(NSString *)userID
                          onCreated:(void (^)(IMGroupInfo *group))onCreated;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
