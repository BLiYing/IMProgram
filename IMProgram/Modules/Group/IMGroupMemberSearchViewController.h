//
//  IMGroupMemberSearchViewController.h
//  群成员搜索页（push）。草图见 IMServer/docs/design/sketches/GROUP_MEMBER_SEARCH_UX_SKETCH.html。
//
//  为什么单开一页、而不是在成员列表顶上嵌个 UISearchBar：两处成员列表都**吸不住顶**——
//  会话详情页那一段的 header 已经被分段控件（成员/媒体/文件/…）占了；群资料页是
//  InsetGrouped，section header 不吸顶、滚两屏就没了。而 2 万人恰恰是要滚很多屏的场景，
//  「滚了半天没找到才想起来搜」正是最常见的路径。也不用 UISearchController：详情页用的是
//  注入式液态标题栏，往 navigationItem 上挂搜索控制器会和它打架（本仓已有同类前科）。
//
//  push 一整页换来三件事：进来就弹键盘、全屏给结果、返回时浏览态那几百页原样还在。
//
#import <UIKit/UIKit.h>

@class IMGroupInfo, IMGroupMember;

NS_ASSUME_NONNULL_BEGIN

/// 成员搜索入口的出现阈值：群总人数**超过**它才给「搜索成员」那一行。
/// 几十人的群整张列表就在眼前，为 5 个人打一次网络请求不合理。
/// 与 Web 的 `VIRTUALIZE_MEMBERS_FROM` 同值，两端别各调各的。
FOUNDATION_EXPORT const NSInteger kIMMemberSearchMinMembers;

/// 该群是否该给搜索入口。
/// **判据是群总人数（memberCount）而非已加载行数**——超级群刚进来只有 50 行，
/// 看行数会把 2 万人的群判成小群、不给搜索框，那恰恰是最需要搜索的场景。
FOUNDATION_EXPORT BOOL IMShouldOfferMemberSearch(IMGroupInfo *_Nullable group);

/// 「滚到底自动续拉」的提前量：还剩这么多行没显示到，就开始拉下一页。
/// 约 1~2 屏（成员行 60pt，一屏十几行）——滚到底之前下一页就已经在路上，用户看不到"加载中"。
FOUNDATION_EXPORT const NSInteger kIMMemberAutoLoadLeadRows;

/// 是否该自动续拉（PERF-members-autoload，2026-09-01）。**纯函数**，三处成员列表共用同一判据。
///
/// 此前只能手点「加载更多成员」，2 万人群要点 **400 次**。注意这与虚拟化（UITableView 复用）
/// 不是一回事：那个解决"已加载的行不撑爆内存"，这个解决"怎么把它们加载进来"。
///
/// @param displayedIndex  即将显示的那一行在**成员数组里**的下标（已减掉搜索行/告知行等偏移）。
/// @param loadedCount     已加载的成员行数。
/// @param hasMore         服务端说还有下一页。
/// @param loading         下一页已在路上（调用方的在途守卫）——本函数不去抖，靠它挡住重复触发。
FOUNDATION_EXPORT BOOL IMShouldAutoLoadMoreMembers(NSInteger displayedIndex, NSInteger loadedCount,
                                                   BOOL hasMore, BOOL loading);

@interface IMGroupMemberSearchViewController : UIViewController

/// @param group        当前群（取 conv_id 与人数；**不依赖 group.members**——超级群那里只有我自己）。
/// @param onPickMember 选中某人。调用方负责后续跳转（对齐既有口径：先进成员资料页，不直接进聊天）。
- (instancetype)initWithGroup:(IMGroupInfo *)group
                 onPickMember:(void (^)(IMGroupMember *member))onPickMember NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)n bundle:(nullable NSBundle *)b NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
