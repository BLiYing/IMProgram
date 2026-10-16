//  IMDatabase+AccountWipe.h
//  注销账号后清掉**本机属于该账号的全部聊天缓存**（DELETE_ACCOUNT_DESIGN.md §3.4）。
//  与「退出登录」不同：退出保留本机已下载记录（靠 owner_uid 隔离），注销不保留。
//
//  独立 category：IMDatabase.m 已顶满体量红线，新逻辑不再进主文件。

#import "IMDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMDatabase (AccountWipe)

/// 删除当前 owner 在**所有带 owner_uid 列的表**里的行（消息 / 会话 / 区间 / 位点 / 好友 / 群 …），一个事务。
/// 按 sqlite_master + PRAGMA 枚举，今后新增带 owner_uid 的表自动覆盖，不必回来改这里。
/// 返回是否成功；失败整体回滚（调用方应记日志但不阻塞回登录页）。
- (BOOL)wipeAllDataForCurrentOwner;

@end

NS_ASSUME_NONNULL_END
