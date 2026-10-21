//  IMDatabase+AutoDelete.h
//  自动删除消息的本机存储与清理（AUTO_DELETE_DESIGN §3.1/§3.4）。
//
//  会话档位 auto_delete_sec 存**独立小表** im_conv_auto_delete_local(owner_uid, conv_id, sec)，不加到
//  im_conversation_local：该表每次列表刷新都 DELETE 全表重写，且 IMDatabase.m 已顶 1500 行（同 +ClearFloor 的取舍）。
//  老库没有这张表 = 全部 0。清理走**本地物理删行**（同「仅为我删除」的本地例程，不调服务端 hide）。

#import "IMDatabase.h"
#import "IMConversation.h"
#import "IMPinnedMessage.h"
#import <FMDB/FMDB.h>

NS_ASSUME_NONNULL_BEGIN

/// 落库闸：这条入站消息是否已按所在会话的档位过期（用内存缓存，整页 10 万条不会多出 10 万次 SELECT）。
/// `writeIncomingMessage:` 内调用——与「清空位点闸」同位置同语义：整条丢弃、返回 YES。
extern BOOL IMAutoDeleteDropsMessage(FMDatabase *db, NSString *owner, IMMessageModel *message);

@interface IMDatabase (AutoDelete)

/// 老库迁移 / 建表：必须在 createTables 的 `_queue inDatabase:` 块内调用，幂等。
- (void)migrateAutoDeleteTableDB:(FMDatabase *)db;

/// 本会话档位；无记录 = 0。
- (int64_t)autoDeleteSecForConv:(NSString *)convID;

/// 写入一个会话的档位（conv_update / GET settings / 本机改后落库）。返回「值是否变了」。
- (BOOL)setAutoDeleteSec:(int64_t)sec forConv:(NSString *)convID;

/// 用 GET /conversations 的整份结果覆盖：列表里出现的会话 = 其 autoDeleteSec；列表里没有的会话行删掉。
- (void)persistAutoDeleteFromConversations:(NSArray<IMConversation *> *)conversations;

/// 这条入站（convSeq>0）消息按其会话档位与本机时钟是否已过期。网络层「入库前」的早退判据（实时路径）。
- (BOOL)autoDeleteDropsIncoming:(IMMessageModel *)message;

/// 去掉已过期的（同会话一批，档位只查一次；convSeq<=0 的待发消息保留）。sync 整页 UI 投递用。
- (NSArray<IMMessageModel *> *)messagesDroppingAutoDeleteExpired:(NSArray<IMMessageModel *> *)messages;

/// 置顶列表是服务端直出的（不过滤过期消息）：按本会话档位去掉已过期的置顶项（timestamp 为消息发出时间）。
- (NSArray<IMPinnedMessage *> *)pinnedItemsDroppingAutoDeleteExpired:(NSArray<IMPinnedMessage *> *)items convID:(NSString *)convID;

/// 所有档位 > 0 的会话 → 档位。
- (NSDictionary<NSString *, NSNumber *> *)autoDeleteActiveConvs;

/// 清理一个会话里已过期的本地消息（`timestamp <= floorTs`，convSeq>0）。一个事务：删行 + 会话摘要/未读本地重算
/// （预览 = 剩余最后一条；没有则空预览；会话行保留，游标/区间/清空位点一概不动）。返回被删的 conv_seq。
- (NSArray<NSNumber *> *)deleteExpiredMessagesForConv:(NSString *)convID floorTs:(int64_t)floorTs;

@end

NS_ASSUME_NONNULL_END
