//  IMRemarkStore.h
//  好友备注名（remark）的**全局单一来源**：uid → 我给他起的备注（仅自己可见）。
//
//  为什么要这层：备注名会出现在会话列表 / 聊天页标题 / 通讯录 / 选人页 / 转发页 / 详情页 /
//  全局搜索等一大堆页面。若各页各自从「自己那份数据」里取（会话行的 peer_remark、好友项的
//  remark、资料卡的 remark），改一次备注就得逐页重拉才能一致。这里把三个来源汇成一份内存表，
//  改动只发一条通知，所有页面按 uid 查同一个值——「改完全局同步」的收敛点。
//
//  权威值仍在服务端（`im_friend.remark`）：本表只是显示缓存，冷启动由 SQLite 快照回填、
//  联网后由 /friends 与 /conversations 覆盖、本人其它设备的改动由 WS friend(event=remark) 帧推来。
//  账号隔离：内部按 IMDatabase 当前 owner_uid 记账，检测到换号即整表清空（不串号显示别人的备注）。

#import <Foundation/Foundation.h>

@class IMConversation;
@class IMUserCard;

NS_ASSUME_NONNULL_BEGIN

/// 备注名有变更（本端改 / 其它设备改 / 列表刷新带来新值）。主线程发出。
/// userInfo[kIMRemarkPeerIDKey] = 变更的对端 uid；**批量刷新时该键缺席**，收端应整体刷新。
extern NSString * const IMRemarkStoreDidChangeNotification;
extern NSString * const kIMRemarkPeerIDKey;

@interface IMRemarkStore : NSObject

+ (instancetype)sharedStore;

/// 我给 uid 起的备注；无备注返回 nil（空串按"无备注"归一化，调用方不必再判空串）。
- (nullable NSString *)remarkForUser:(nullable NSString *)userID;

/// 显示名：**已注销 > 备注** > fallback（一般传昵称）> uid。各页取显示名的统一口径。
/// 已注销用户（`isDeletedUser:`）恒显「已注销用户」(delete_account.deleted_user)，压过备注 / 群昵称 / 服务端昵称
/// （PROTOCOL §6.16.3：服务端虽已把 nickname 置成中文「已注销用户」、清了 remark，但那是固定中文，且旧缓存里还留着原名）。
- (NSString *)displayNameForUser:(nullable NSString *)userID fallback:(nullable NSString *)fallback;

/// 该 uid 是否已知为「已注销用户」（冷静期内与匿名化后一视同仁）。账号级隔离 + 落 UserDefaults（冷启动先于网络就显示对）。
/// 注销账号清本机缓存：清掉当前账号的已注销登记（含 UserDefaults 落盘）。
- (void)wipeDeletedMarksForCurrentOwner;
- (BOOL)isDeletedUser:(nullable NSString *)userID;

/// 登记 / 撤销「已注销」标记。由各解析点（用户名片 / 群成员 / 会话行 peer_deleted）在**每次**解析时调用——
/// 恢复账号后服务端不再带 `deleted`，所以 NO 也要传，才能撤销。值真的变了才发通知（带 peerID）。线程安全。
- (void)setUser:(nullable NSString *)userID deleted:(BOOL)deleted;

/// 单点更新（本端改备注的乐观更新 / WS friend(event=remark) 帧）。remark 传 nil 或空串=清除。
/// 值真的变了才发通知，故可安全地在每次列表刷新里重复调用。
- (void)applyRemark:(nullable NSString *)remark forUser:(NSString *)userID;

/// 用好友列表喂入备注。
/// authoritative=YES 表示这批是**全集**（`GET /friends` 不带 status / status=accepted、或本地好友快照）：
/// 表里没被这批提到的 uid 会被清掉，"在别处清空了备注"才收得回来。
/// 传子集（status=blocked/pending 等）时**必须** authoritative=NO，否则会把其他好友的备注误清空。
- (void)ingestFriends:(nullable NSArray<IMUserCard *> *)cards authoritative:(BOOL)authoritative;

/// 用会话列表增量合并（/conversations 只带**有会话的**单聊对端，不是全集，故不做删除）。
- (void)ingestConversations:(nullable NSArray<IMConversation *> *)conversations;

@end

NS_ASSUME_NONNULL_END
