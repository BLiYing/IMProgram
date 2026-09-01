//
//  IMUserProfileCache.h
//  **uid → 显示名/头像** 的全局解析器：进程内缓存 + 批量补洞（POST /api/v1/users/batch）。
//
//  ## 为什么需要它
//  各页此前把「群成员表」当身份字典用——拿 uid 回查 `IMGroupInfo.members` 取头像/显名。
//  这个假设有两个洞：
//   · **超级群不下发成员表**（2 万人，只发群主+管理员），于是普通成员的气泡头像全变首字母圈；
//   · 普通群也有洞：**退群的人留下的历史消息**同样查不到（只是少见，一直没人报）。
//
//  Telegram 的做法是身份跟着**消息**走（每个响应带 `users:Vector<User>`）+ `users.getUsers`
//  批量补洞。本类是后者：谁都可以问「这个 uid 是谁」，问不到的攒一批一次性拉回来。
//
//  ## 用法
//  同步问 `cardForUserID:`：命中就立刻返回，**没命中返回 nil 并在后台排队解析**，
//  解析完发 `IMUserProfileCacheDidResolveNotification`，调用方收到后重刷对应的行/气泡即可。
//  也就是说调用方要接受「第一帧可能没有」——那一帧照旧走各自的兜底（首字母圈 / 未命名用户）。
//
//  ## 不做什么
//  · **不管备注**：备注是本机私有数据，`IMRemarkStore` 才是权威，调用方在本类结果之上覆盖。
//  · **不管在线态**：批量接口不下发（隐私 + 成本），要在线态请走 `GET /users/{id}`。
//  · **不落库**：进程内缓存，重启即空。身份变化（改名换头像）本来就该重新解析一次。
//
#import <Foundation/Foundation.h>

@class IMUserCard;
@class IMGroupMember;

NS_ASSUME_NONNULL_BEGIN

/// 有一批 uid 刚被解析出来（或确认查无此人）。`userInfo[@"user_ids"]` = NSArray<NSString *>。
/// 收到后重刷界面上用到这些 uid 的地方即可（表格 reloadData / 气泡重设头像）。
FOUNDATION_EXPORT NSNotificationName const IMUserProfileCacheDidResolveNotification;

@interface IMUserProfileCache : NSObject

+ (instancetype)sharedCache;

/// 取名片。**命中返回；没命中返回 nil 并排队解析**（合并 50ms 内的所有请求，每批 ≤100 个）。
/// 可在 cellForRow 之类的热路径里放心调用：同一个 uid 不会重复发请求，查无此人也有负缓存。
- (nullable IMUserCard *)cardForUserID:(nullable NSString *)userID;

/// 只查缓存，**绝不发起请求**。用于「有就锦上添花、没有也不值得为它联网」的地方。
- (nullable IMUserCard *)peekCardForUserID:(nullable NSString *)userID;

/// 预热一批 uid（如聊天页当前窗口内的全部发送者）。已命中/已在飞的会被自动跳过。
- (void)prefetchUserIDs:(nullable NSArray<NSString *> *)userIDs;

/// 用**已有数据**喂缓存，省掉一次网络：群成员表、好友列表、找人结果都该顺手喂一把。
/// 只补不覆盖已有的更完整记录？不——一律覆盖：这些来源都比缓存新。
- (void)ingestCards:(nullable NSArray<IMUserCard *> *)cards;
- (void)ingestGroupMembers:(nullable NSArray<IMGroupMember *> *)members;

@end

NS_ASSUME_NONNULL_END
