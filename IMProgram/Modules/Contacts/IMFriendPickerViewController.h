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

/// **远端候选源**（超级群用）：设了它就**不做本地过滤**——候选全集在服务端，
/// 每次搜索词变化去服务端查一页，回来的就是要显示的行（仍会再过一遍 excludedIDs）。
///
/// 为什么必须有这条路：超级群的成员是 2 万人，`GET /groups/{id}` 只下发治理集，
/// 端上根本拿不到全集——注入式候选在超级群下要么是空的（加管理员），要么只剩几个管理员
/// （转让群主）。本地过滤等于"在几十个人里搜 2 万人"，界面正常、结果悄悄是错的。
///
/// query 为空 = 取第一页（进页面即有候选）。去抖与过期响应丢弃由本页负责，provider 只管发请求。
/// **须在 push 前设。**
@property (nonatomic, copy, nullable) void (^remoteCandidateSearch)(NSString *query,
        void (^done)(NSArray<IMUserCard *> *_Nullable cards, NSError *_Nullable error));

/// 回查当前候选里某个 uid 的卡片（拿显示名/头像用）。找不到返回 nil。
///
/// 远端候选模式下**这是调用方唯一能拿到名字的地方**：候选来自服务端搜索，
/// 调用方手里那份 group.members 在超级群下只有治理集，按 uid 找必然落空
/// ——转让群主的二次确认曾因此写成「确定把群主转让给 TA？」。
- (nullable IMUserCard *)cardForUserID:(NSString *)userID;

/// 现成的远端候选源：按 q 查 convID 这个群的成员一页，映射成本页要的 IMUserCard。
/// 「超级群加管理员」与「超级群转让群主」两处**逻辑完全相同**，放这里共用，分开写迟早分叉。
/// 复用 GET /groups/{id}/members?q=（服务端按句柄/群昵称/全局昵称三源命中，不含 user_id）。
+ (void (^)(NSString *query, void (^done)(NSArray<IMUserCard *> *_Nullable cards, NSError *_Nullable error)))
    groupMemberSearchForConvID:(NSString *)convID;

/// **单选即确认**：点中一行立即回调 onDone（单元素数组），右上确认按钮隐藏。
/// 转让群主走这一支——那是"选谁"而不是"选一批"，再要求点一次「确定」是多余的一步。
/// 置 YES 时应同时把 maxSelection 设为 1。**须在 push 前设。**
@property (nonatomic, assign) BOOL selectsImmediately;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
