//  IMDatabase+AutoDelete.h
//  自动删除消息的本机存储与清理（AUTO_DELETE_DESIGN §3.1/§3.4）。
//
//  会话级自动删除设置（v2：sec + from，AUTO_DELETE_DESIGN §2/§3.4）存**独立小表**
//  im_conv_auto_delete_local(owner_uid, conv_id, sec, from_ms)，不加到 im_conversation_local：该表每次列表刷新都
//  DELETE 全表重写，且 IMDatabase.m 已顶 1500 行（同 +ClearFloor 的取舍）。老库没有这张表 = 全部 0（关）。
//  v1 个人档位（只有 sec 列）升级时整表清掉，不迁移——以服务端会话级值为准。
//  清理走**本地物理删行**（同「仅为我删除」的本地例程，不调服务端 hide）；过期集合 = 时间窗口 [from, now-sec*1000]。

#import "IMDatabase.h"
#import "IMConversation.h"
#import "IMPinnedMessage.h"
#import "IMAutoDelete.h"
#import <FMDB/FMDB.h>

NS_ASSUME_NONNULL_BEGIN

/// 落库闸：这条入站消息是否已按所在会话的设置过期（用内存缓存，整页 10 万条不会多出 10 万次 SELECT）。
/// `writeIncomingMessage:` 内调用——与「清空位点闸」同位置同语义：整条丢弃、返回 YES。
extern BOOL IMAutoDeleteDropsMessage(FMDatabase *db, NSString *owner, IMMessageModel *message);

@interface IMDatabase (AutoDelete)

/// 老库迁移 / 建表：必须在 createTables 的 `_queue inDatabase:` 块内调用，幂等。
- (void)migrateAutoDeleteTableDB:(FMDatabase *)db;

/// 本会话设置；无记录 = 关。
- (IMAutoDeleteConfig *)autoDeleteConfigForConv:(NSString *)convID;
- (int64_t)autoDeleteSecForConv:(NSString *)convID;

/// 写入一个会话的设置（conv_update / GET settings / PUT 回包）。sec 与 from 一起覆盖。返回「sec 或 from 是否变了」。
- (BOOL)setAutoDeleteConfig:(IMAutoDeleteConfig *)config forConv:(NSString *)convID;
- (BOOL)setAutoDeleteSec:(int64_t)sec from:(int64_t)from forConv:(NSString *)convID;

/// 用 GET /conversations 的整份结果覆盖：列表里出现的会话 = 其 sec+from；列表里没有的会话行删掉。
- (void)persistAutoDeleteFromConversations:(NSArray<IMConversation *> *)conversations;

/// 这条入站（convSeq>0）消息按其会话设置与本机时钟是否已过期。网络层「入库前」的早退判据（实时路径）。
- (BOOL)autoDeleteDropsIncoming:(IMMessageModel *)message;

/// 去掉已过期的（同会话一批，设置只查一次；convSeq<=0 的待发消息保留）。sync 整页 UI 投递用。
- (NSArray<IMMessageModel *> *)messagesDroppingAutoDeleteExpired:(NSArray<IMMessageModel *> *)messages;

/// 置顶列表是服务端直出的（不过滤过期消息）：按本会话设置去掉已过期的置顶项（timestamp 为消息发出时间）。
- (NSArray<IMPinnedMessage *> *)pinnedItemsDroppingAutoDeleteExpired:(NSArray<IMPinnedMessage *> *)items convID:(NSString *)convID;

/// 所有开着（sec>0）的会话 → 设置。
- (NSDictionary<NSString *, IMAutoDeleteConfig *> *)autoDeleteActiveConvs;

/// 清理一个会话里已过期的本地消息（`from <= timestamp <= now - sec*1000`，convSeq>0；from 之前的一律保留）。
/// 一个事务：删行 + 会话摘要/未读本地重算（预览 = 最后一条未过期的可见消息，可越过窗口取 from 之前的；没有则空预览；
/// 会话行保留，timestamp / 游标 / 区间 / 清空位点一概不动）。返回被删的 conv_seq。
- (NSArray<NSNumber *> *)deleteExpiredMessagesForConv:(NSString *)convID config:(IMAutoDeleteConfig *)config nowMs:(int64_t)nowMs;

/// 只重算会话行的预览 / 未读（不删消息行）：摘要所指的最后一条（conversations.timestamp）落在过期窗口内才动，
/// 预览取本地最后一条未过期可见消息（msg_op 事件行不入库，天然跳过），没有则空预览；timestamp 不清零（排序位置不变）。
/// 用于本机没有对应消息行、只有会话列表缓存的场景。返回会话行是否有变化。
- (BOOL)refreshAutoDeleteSummaryForConv:(NSString *)convID config:(IMAutoDeleteConfig *)config nowMs:(int64_t)nowMs;

/// 清掉「已被服务端列表整份写过摘要」标记（模拟冷启动只剩缓存；测试用）。
- (void)resetServerSyncedSummaryMarks;

@end


NS_ASSUME_NONNULL_END
