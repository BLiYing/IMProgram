//  IMSocketManager+ClearAll.h
//  「清除所有对话」的批量落地（对每个会话各做一次 §6.7.1「清除到位点」，整批单事务）。
//  IMSocketManager.m 已接近体量上限，所以放 category。

#import "IMSocketManager.h"
#import "IMDatabase+ClearAll.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMSocketManager (ClearAll)

/// 在**后台线程**调用。单事务批量清库（`-[IMDatabase clearConversationsToFloors:]`，与单条删除会话共用库内例程），
/// 成功后对每个会话推内存游标 / 缺口标记、丢服务端下界缓存，并对有消息被清的会话广播
/// `IMChatConversationClearedNotification`（打开着的聊天页清内存、保持打开）。幂等：随后到达的 conv_update(delete) 回声无副作用。
/// 返回库是否落地成功（账号上下文失效 / 事务回滚 → NO，内存状态不动）。
- (BOOL)applyClearAllItems:(NSArray<IMClearAllItem *> *)items;

@end

NS_ASSUME_NONNULL_END
