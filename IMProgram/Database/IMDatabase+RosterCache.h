//  IMDatabase+RosterCache.h
//  好友 / 群组名册的本地快照（任务5·断网离线首屏）。

#import "IMDatabase.h"

@class IMUserCard;
@class IMGroupInfo;

NS_ASSUME_NONNULL_BEGIN

/// 好友快照的**内容指纹**：user_id → 落库的其余各列（昵称 / 头像 / 状态 / 拉黑 / 更新时间 / 备注）。
/// 两份名单指纹相等 ⇔ `replaceCachedFriends:` 写进去的内容相同，调用方据此跳过重写（2000 人删了重插一遍约 16ms）。
/// **不含顺序**：服务端按 updated_at 排序，同时间戳时顺序不稳定；各读者要么按拼音重排、要么按 uid 查。
/// 落库列有增减必须同步改这里，否则那一列的变化会被判成「没变」而漏写（IMContactGroupCacheTests 逐列钉住）。
FOUNDATION_EXPORT NSDictionary<NSString *, NSArray *> *IMCachedFriendsFingerprint(NSArray<IMUserCard *> *friends);

/// 通讯录两张名册（好友、我的群）的本地缓存读写。
///
/// 单开 category 而不是继续堆在 IMDatabase.m（同 +Ranges 的理由，CODING_STYLE §7 ②）：
/// 那个文件已触体量红线，而这四个方法自成一个概念——**它们不是消息层**，
/// 回答的是"没网的时候通讯录/群列表拿什么先画出来"，与会话/消息读写共用队列但互不相干。
///
/// 两张表都是**整表替换**语义：服务端列表是全集，本地快照要能反映"在别处删掉的项"。
@interface IMDatabase (RosterCache)

/// 好友快照（离线首屏）。顺带把备注喂给 IMRemarkStore、把好友关系喂给 IMFriendStateStore——
/// 冷启动时它们是这两个全局缓存唯一能同步拿到的种子。
- (NSArray<IMUserCard *> *)cachedFriends;

/// 整表替换好友快照（`GET /friends` 成功后调用）。返回是否真的写成：任一语句失败即整笔回滚、返回 NO
/// ——据指纹「没变就不写」的调用方必须只在 YES 时记指纹，否则一次写失败后再也不会重试。
- (BOOL)replaceCachedFriends:(NSArray<IMUserCard *> *)friends;

/// 我的群快照（离线首屏）。**`members` 恒为空数组**——列表页不需要成员明细，
/// 进群详情页时再联网权威拉取；依赖成员的调用方不要拿它当数据源。
- (NSArray<IMGroupInfo *> *)cachedGroups;

/// 整表替换群快照（`GET /groups` 成功后调用）。
- (void)replaceCachedGroups:(NSArray<IMGroupInfo *> *)groups;

@end

NS_ASSUME_NONNULL_END
