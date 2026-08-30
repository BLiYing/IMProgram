//  IMFriendStateStore.h
//  「这个 uid 是不是我的好友」的**进程内快照**：uid → accepted 与否。
//
//  为什么要这层：单聊资料页在 `init` 那一刻就得决定显示哪一套界面（好友＝消息/呼叫/视频 + 备注·设置·页签
//  三张卡；非好友＝只有一个「加好友」）。关系是服务端的，`GET /friends` 回来要几十到几百毫秒，
//  期间只能先猜一个——原先无条件猜 YES，于是**点非好友的名片进来会先闪一遍好友界面再变成加好友**
//  （用户 2026-08-30 报的 bug）。本表把"上一次已经知道的答案"留在内存里，让那一刻能猜对。
//
//  喂入口只有两处，都是**全集**：
//   · `IMHTTPService.friendsWithToken:`（不带 status / status=accepted）——每次拉好友都会顺路刷新，
//     所以加/删好友之后自然是新的，无需各页手动同步；
//   · `IMDatabase.cachedFriends`（本地 im_friend_local 快照）——冷启动第一次进资料页时的种子。
//
//  **"不知道"是一个真实状态**：从没喂过全集时 `friendStateForUser:` 返回 nil，调用方自己决定回落
//  （资料页回落乐观 YES：绝大多数单聊入口本来就是好友）。若把"没喂过"与"不在表里"混为一谈，
//  就会在冷启动时把好友显示成陌生人——那是比原 bug 更难看的反向闪烁。
//
//  账号隔离与 IMRemarkStore 同款：内部按 IMDatabase 当前 owner_uid 记账，换号即整表清空。

#import <Foundation/Foundation.h>

@class IMUserCard;

NS_ASSUME_NONNULL_BEGIN

@interface IMFriendStateStore : NSObject

+ (instancetype)sharedStore;

/// uid 是不是我的好友（accepted）。**从未喂过全集时返回 nil＝不知道**，调用方自行回落。
- (nullable NSNumber *)friendStateForUser:(nullable NSString *)userID;

/// 用好友列表喂入。
/// authoritative=YES 表示这批是**全集**（`GET /friends` 不带 status / status=accepted）：
/// 这批没提到的 uid 一律视为已非好友（删好友才收得回来），并把本表标记为「已知」。
/// 传子集（blocked/pending 等）时必须传 NO：只按卡片逐个更新，不做清扫、也不改变「已知」标志。
- (void)ingestFriends:(nullable NSArray<IMUserCard *> *)cards authoritative:(BOOL)authoritative;

/// 用**本地好友快照**（im_friend_local，全集）播种。
/// 只在本表还「不知道」且快照非空时生效：空快照可能只是"从没同步过"，据此判所有人非好友是错的。
- (void)seedFromLocalSnapshot:(nullable NSArray<IMUserCard *> *)cards;

@end

NS_ASSUME_NONNULL_END
