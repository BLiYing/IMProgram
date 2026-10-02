//  IMDatabase+ClearFloor.h
//  「清空聊天记录」的**本机清空位点** cleared_up_to（IMServer/docs/design/OFFLINE_BACKLOG_DESIGN.md §6.7，
//  三端统一；Android 先行：im-android `data/ClearFloor.kt`）。
//
//  为什么需要它：清空只清本机、不动服务端。区间清单是「本地有哪几段」的目录，清空之后
//  「本地没有、服务端有」与「还没下载」在清单上长得一样——进会话会把刚清掉的历史拉回来。
//  位点把「用户**主动**不要这一段」与「**还没**下载这一段」分开：
//   · 只增不减（MAX 语义）；会话列表 HTTP 快照整行重写时必须保住它（writeCachedConversations:）；
//   · ≤ 位点的消息一律不再落库（sync 页 / window 页 / 实时 / 任何写 im_message_local 的路径都经
//     writeIncomingMessage:，闸在那里）、不算缺口、不再向服务端要；位点之后的新消息照常收；
//   · 有效可见下界 = max(服务端 historyFloor, cleared_up_to) —— 两个下界各自独立存、用时取大
//     （纯函数在 IMChatWindowPlan.h 的 IMChatEffectiveFloor）。
//
//  独立分文件 category 的原因同 IMDatabase+Ranges / +MuteState：IMDatabase.m 已顶到 1500 行体量上限，
//  新逻辑不再进主文件（clearMessagesForConv: 本身也从主文件搬来了）。

#import "IMDatabase.h"
#import "IMMessageModel.h"
#import <FMDB/FMDB.h>

NS_ASSUME_NONNULL_BEGIN

/// 清空那一刻该取的位点 = 本机所知的会话最新位置：head / 会话缓存里的最新 seq / 同步游标 / 本地最大消息 seq 取大，
/// 并且**只增不减**（不低于已有位点）。与 im-android `ClearFloor.floorAtClear` 同口径。
extern int64_t IMClearFloorAtClear(int64_t head, int64_t latestConvSeq, int64_t synced, int64_t maxLocalSeq,
                                   int64_t existingClearedUpTo);

/// 在**已开启**的 db 上读该会话的清空位点（读小表 im_conv_clear_floor_local；没清过 = 0）。落库闸与 `conv:coversFrom:to:` 共用。
extern int64_t IMClearedUpToInDB(FMDatabase *db, NSString *owner, NSString *convID);

/// 把会话行的 synced_conv_seq 抬到不低于清空位点（MAX，只增）。convID 为 nil = 该账号所有会话行。
/// 会话行是缓存（删除会话 / 列表不再返回 / 整表回灌都会重建），重建出来的壳行 synced=0，不抬的话
/// 下一个 sync_req 从 0 起，把用户清掉的历史又拉回来。`writeCachedConversations:` 与壳行创建处调用。
extern BOOL IMRaiseSyncedToClearFloorInDB(FMDatabase *db, NSString *owner, NSString * _Nullable convID);

/// 丢掉 `convSeq <= clearedUpTo` 的消息（convSeq<=0 的待发消息保留）。位点 <=0 原样返回。
/// **落库、UI 投递、回执、提醒必须共用同一份「实际保留集合」**（CONVENTIONS §4.7 汇聚点）：网络层在落库**之前**用它过滤，
/// 之后的 saveIncomingPage / deliverSyncedPage / 回执位点都只用过滤后的集合；库里的落库闸是第二道防线。
extern NSArray<IMMessageModel *> *IMDropClearedMessages(NSArray<IMMessageModel *> *messages, int64_t clearedUpTo);

@interface IMDatabase (ClearFloor)

/// 本地清空某会话的全部消息（仅本端，不影响对端；对应详情页「清空聊天记录」）。返回删除条数。
/// **一个事务**：删消息 + 清区间清单（im_conv_range_local 该会话）+ 抬「本机清空位点」cleared_up_to（只增不减）
/// + synced_conv_seq 推到不小于位点；之后 ≤ 位点的消息不再落库、不算缺口、不再向服务端要（OFFLINE_BACKLOG_DESIGN §6.7）。
/// 位点 = max(head_conv_seq, 会话缓存里的最新 seq, synced_conv_seq, 本地最大消息 seq, 既有位点)，**写进独立小表**
/// `im_conv_clear_floor_local`（不依赖会话行：会话行会被「删除会话」/ 列表不再返回而删掉，位点不能跟着没）。
- (NSInteger)clearMessagesForConv:(NSString *)convID;

/// 该会话的本机清空位点；没清过 / 无会话行 = 0。
- (int64_t)clearedUpToForConv:(NSString *)convID;

/// 迁移：建独立小表 im_conv_clear_floor_local(owner_uid, conv_id, cleared_up_to, PK(owner_uid,conv_id))，**只在表刚建出来的那一次**：
///   · 库里有旧的 im_conversation_local.cleared_up_to 列（本特性的早期实现）→ 把 >0 的值拷进小表（MAX 语义，幂等，旧列留着不再读写）；
///   · 没有该列（升级前的老库）→ 升级回填：对 synced_conv_seq>0 的会话，位点 =（synced 以内最小本地消息 seq − 1）；
///     synced 以内本地一条没有则 = synced。
/// 建表与拷贝 / 回填**同一个事务**：失败整体回滚，下次启动重试。之后位点只由清空动作维护——再按「本地没有的那一截」推，
/// 会把用户没清过的缺口误当清空。必须在 createTables 的 `_queue inDatabase:` 块内、会话表与消息表建表之后调用。
- (void)migrateClearedUpToColumnDB:(FMDatabase *)db;

@end

NS_ASSUME_NONNULL_END
