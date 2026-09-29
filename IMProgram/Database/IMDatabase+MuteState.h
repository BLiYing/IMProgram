//  IMDatabase+MuteState.h
//  定时免打扰（NOTIFICATIONS_P1_DESIGN §4/§6.2 第二批）本地存储的老库迁移。
//  独立分文件 category 的原因同 IMDatabase+Ranges——IMDatabase.m 已顶到体量门禁上限（1500 行，
//  改动前 1499、几乎没有余量），新迁移逻辑一律不再进主文件，主文件只留一处调用口子
//  （createTables 的 `_queue inDatabase:` 块内，紧跟 head_conv_seq 迁移之后）。

#import "IMDatabase.h"
#import <FMDB/FMDB.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMDatabase (MuteState)

/// 老库迁移：im_conversation_local 补 mute_until 列（幂等，ADD COLUMN 失败落日志）。
/// 必须在 createTables 的 `_queue inDatabase:` 块内、CREATE TABLE 之后调用；新库建表时该列已随
/// CREATE TABLE 语句就位，本方法在新库上是一次无副作用的空转（PRAGMA table_info 查得到列即返回）。
- (void)migrateMuteUntilColumnDB:(FMDatabase *)db;

@end

NS_ASSUME_NONNULL_END
