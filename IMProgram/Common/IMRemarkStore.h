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

/// 显示名：备注 > fallback（一般传昵称）> uid。各页取显示名的统一口径。
- (NSString *)displayNameForUser:(nullable NSString *)userID fallback:(nullable NSString *)fallback;

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
