//  IMFriendPickerViewController.h
//  **通用好友多选页**：建群选初始成员 / 群内邀请成员 / 会话详情页加成员 / **分享个人名片**共用。
//  （原名 IMGroupMemberPickerViewController、在 Modules/Group/ 下，2026-08-29 改名并移来 Contacts/：
//   它服务 4 个群场景 + 1 个非群场景，页面标题本就是中性的「选择好友」，名不副实。行为零变化。）
//
//  ⚠️ **本页自身不关闭**，由调用方决定后续导航：全部调用点都是 `pushViewController:` +
//  在 onDone 里 `popToViewController:` 收起。**不要改成模态 present**——present 出来又不收起，
//  紧接着在同一个 VC 上 present 别的东西会被 UIKit 以「已在 presenting」拒绝（名片入口曾因此
//  点「发送」毫无反应，2026-08-29）。
//  列出我的好友（accepted），勾选多个后点右上「确定」回调选中 uid 集。

#import <UIKit/UIKit.h>

@class IMUserCard;

NS_ASSUME_NONNULL_BEGIN

@interface IMFriendPickerViewController : UIViewController

/// excludedIDs：不显示的 uid（如已在群内的成员）；confirmTitle：右上按钮文案（如 创建/邀请）。
/// onDone：用户确认后回调选中的 uid（至少 1 个才可确认）；页面自身不关闭，由调用方决定后续导航。
/// 拉我的好友作候选，页面标题「选择好友」——内部转调下面的注入式初始化。
- (instancetype)initWithHost:(NSString *)host
                      userID:(NSString *)userID
                 excludedIDs:(nullable NSSet<NSString *> *)excludedIDs
                confirmTitle:(NSString *)confirmTitle
                      onDone:(void (^)(NSArray<NSString *> *selectedIDs))onDone;

/// **候选直接注入**（不联网）：调用方已持有名单时用它，candidates=nil 则退回上面的"拉我的好友"。
/// 群管理页的「添加管理员 / 选择新群主」走这一支——候选是**群成员**（可能不是我的好友），
/// 且群管理页初始化时已经拿到全量成员表，再拉一次好友既错又多余。
/// title：页面标题（未选中时显示；选中后统一变「已选 N 人」）。
- (instancetype)initWithHost:(NSString *)host
                      userID:(NSString *)userID
                  candidates:(nullable NSArray<IMUserCard *> *)candidates
                 excludedIDs:(nullable NSSet<NSString *> *)excludedIDs
                       title:(NSString *)title
                confirmTitle:(NSString *)confirmTitle
                      onDone:(void (^)(NSArray<NSString *> *selectedIDs))onDone NS_DESIGNATED_INITIALIZER;

/// 最多可选人数；**0 = 不限**（默认，建群/邀请场景无所谓）。达到上限后未选中行置灰不可点。
/// 分享名片传 9（与转发选择页多选上限一致）——"一次发 200 张名片"是刷屏。
/// 加法式参数：既有 4 个调用点不传即保持原行为。**须在 present 前设。**
@property (nonatomic, assign) NSUInteger maxSelection;

/// 搜索框占位（默认「搜索好友」；候选是群成员时传「搜索群成员」）。**须在 push 前设。**
@property (nonatomic, copy, nullable) NSString *searchPlaceholder;

/// 无候选时的居中空态文案（默认「没有可选的好友」）。**须在 push 前设。**
@property (nonatomic, copy, nullable) NSString *emptyText;

/// 达 maxSelection 后再点未选中行的提示语（如「一次最多添加 5 位管理员」）。
/// 不设（默认）＝沿用"置灰且点不动"的静默行为；设了则行仍可点，点了只吐司、不进选中集
/// ——用户至少知道为什么点不上，而不是对着一排灰行猜。**须在 push 前设。**
@property (nonatomic, copy, nullable) NSString *capToast;

/// **单选即确认**：点中一行立即回调 onDone（单元素数组），右上确认按钮隐藏。
/// 转让群主走这一支——那是"选谁"而不是"选一批"，再要求点一次「确定」是多余的一步。
/// 置 YES 时应同时把 maxSelection 设为 1。**须在 push 前设。**
@property (nonatomic, assign) BOOL selectsImmediately;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
