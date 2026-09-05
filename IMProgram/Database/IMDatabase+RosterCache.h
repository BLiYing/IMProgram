//  IMDatabase+RosterCache.h
//  好友 / 群组名册的本地快照（任务5·断网离线首屏）。

#import "IMDatabase.h"

@class IMUserCard;
@class IMGroupInfo;

NS_ASSUME_NONNULL_BEGIN

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

/// 整表替换好友快照（`GET /friends` 成功后调用）。
- (void)replaceCachedFriends:(NSArray<IMUserCard *> *)friends;

/// 我的群快照（离线首屏）。**`members` 恒为空数组**——列表页不需要成员明细，
/// 进群详情页时再联网权威拉取；依赖成员的调用方不要拿它当数据源。
- (NSArray<IMGroupInfo *> *)cachedGroups;

/// 整表替换群快照（`GET /groups` 成功后调用）。
- (void)replaceCachedGroups:(NSArray<IMGroupInfo *> *)groups;

@end

NS_ASSUME_NONNULL_END
