//  IMDatabase+ClearAll.h
//  「清除所有对话」的批量落地（CLEAR_ALL_CONVERSATIONS_DESIGN §4）。
//  对每个会话各做一次 OFFLINE_BACKLOG_DESIGN §6.7.1 的「清除到位点」（库内实现 IMClearConvToFloorInDB，与单条删除会话共用，
//  不另写一套），但**整批一个事务**——数千会话不能各开一次事务。IMDatabase.m 已满行，所以放 category。

#import "IMDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/// 一个被清会话：服务端回的 conv_id + 位点（`items[].cleared_at`，conv_seq；<=0 = 服务端该会话没有消息）。
@interface IMClearAllItem : NSObject
@property (nonatomic, copy, readonly) NSString *convID;
@property (nonatomic, assign, readonly) int64_t clearedAt;
- (instancetype)initWithConvID:(NSString *)convID clearedAt:(int64_t)clearedAt NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface IMDatabase (ClearAll)

/// 单事务批量清除。每项：cleared_at>0 → 清 conv_seq<=位点的行 + 区间清单 + 写位点（独立小表，会话行删后仍在）+ 推游标
/// （待发消息 conv_seq=0 与位点之后的新消息保留）；cleared_at<=0 → 不碰消息。随后删会话行——但**迟到的新消息已让会话复活**
/// （行 head/latest 或本机消息超过位点）的保留行。幂等：重复调用（含随后到达的 conv_update(delete) 回声）结果不变。
/// 返回 convID → 实际删除的消息条数；任一项失败整批回滚并返回 nil（调用方不得推进内存状态）。
- (nullable NSDictionary<NSString *, NSNumber *> *)clearConversationsToFloors:(NSArray<IMClearAllItem *> *)items;

@end

NS_ASSUME_NONNULL_END
