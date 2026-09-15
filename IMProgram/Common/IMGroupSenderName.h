//  IMGroupSenderName.h
//  群聊气泡**发送者名字**取哪一份（2026-09-15，用户报：A 改了昵称，A 以前发的消息仍显示旧昵称，
//  只有新消息是新昵称；而新设备第一次登录进这个群则全是新昵称）。
//
//  根因：每条消息落库时带着一份 from_nickname **快照**（服务端下发那一刻现算：群昵称 > 昵称），
//  而此前取名是**快照优先**、成员表只作回退。本地库里的老消息不会被重写，老快照就一直是旧名；
//  新设备的消息是现从服务端拉的，快照恰好是新名——所以「第一次登录没问题」。Web 刷新也一样：
//  刷新读的是 IndexedDB 里的老快照，C3 之后已下载的段不会再向服务端要一遍。
//
//  改为**成员表优先**（进会话 / 群事件都现拉，它回答的才是「现在叫什么」），快照降为成员表查不到时的兜底；
//  兜底里再优先取**本窗该发送者最新一条**的快照——超级群不下发成员表（只有群主 + 管理员），
//  那里这是唯一能跟上改名的来源。成员表是进会话时拉的，会话开着期间对方改了名再发消息，
//  成员表就旧了、反而压过新快照：由 IMGroupMemberNicknameStale 判出来重拉一次。
//
//  ⚠️ 对端：im-web `src/chatNaming.ts` 的 senderLabel、im-android `data/SenderNames.kt`。三端这条链必须同序（SYMMETRY 已登记）。
//  这里只管**公开名**（不含备注）：结果会随合并转发发出去，备注由调用方在外面再套一层。

#import <Foundation/Foundation.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

/// 公开名取哪一个：成员表 > 本窗该发送者最新快照 > 本条快照。全空返回 nil（调用方再问全局资料缓存、再落占位）。
NSString *_Nullable IMGroupSenderPublicName(NSString *_Nullable memberNickname,
                                            NSString *_Nullable latestSnapshot,
                                            NSString *_Nullable ownSnapshot);

/// messages 按显示序（旧 → 新）；从尾部往前找 sender 最近一条带昵称快照的消息，返回那份快照。没有返回 nil。
NSString *_Nullable IMLatestSenderNickname(NSArray<IMMessageModel *> *messages, NSString *_Nullable sender);

/// 实时收到本会话群消息时，成员表里这个人的名字是否已过期：两边都有值且不相等。
/// 成员表查不到（超级群普通成员 / 还没拉到）或消息没带昵称时一律不算——那种情况重拉也拿不到更多。
BOOL IMGroupMemberNicknameStale(NSString *_Nullable memberNickname, NSString *_Nullable inboundNickname);

NS_ASSUME_NONNULL_END
