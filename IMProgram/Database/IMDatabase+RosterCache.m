//  IMDatabase+RosterCache.m
//  接口与拆分理由见 IMDatabase+RosterCache.h。

#import "IMDatabase+RosterCache.h"
#import "IMDatabase+Ranges.h"   // dbQueue（category 拿不到 IMDatabase 的 _queue 实例变量）
#import "IMUserCard.h"
#import "IMGroupInfo.h"
#import "IMFriendStateStore.h"
#import "IMRemarkStore.h"
#import "IMLog.h"

#import <FMDB/FMDB.h>

@implementation IMDatabase (RosterCache)

- (NSArray<IMUserCard *> *)cachedFriends {
    NSString *owner = [self ownerUserID];
    NSMutableArray<IMUserCard *> *out = [NSMutableArray array];
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:
            @"SELECT * FROM im_friend_local WHERE owner_uid=? ORDER BY sort_order ASC", owner];
        if (!rs) { IMLogDatabase(@"读取好友缓存失败 owner=%@: %@", owner, db.lastErrorMessage); return; }
        while ([rs next]) {
            IMUserCard *c = [IMUserCard new];
            c.userID = [rs stringForColumn:@"user_id"] ?: @"";
            c.nickname = [rs stringForColumn:@"nickname"] ?: @"";
            c.remark = [rs stringForColumn:@"remark"] ?: @"";
            c.avatarURL = [rs stringForColumn:@"avatar_url"] ?: @"";
            c.status = (IMFriendStatus)[rs longForColumn:@"status"];
            c.blocked = [rs boolForColumn:@"blocked"];
            c.updatedAt = [rs longLongIntForColumn:@"updated_at"];
            if (c.userID.length > 0) { [out addObject:c]; }
        }
        [rs close];
    }];
    // 冷启动/离线首屏也要有备注名：本地好友快照是全集，直接喂给全局显示名缓存。
    [IMRemarkStore.sharedStore ingestFriends:out authoritative:YES];
    // 同理播种「谁是我的好友」：冷启动第一次进单聊资料页时，它是唯一能同步拿到的关系来源。
    [IMFriendStateStore.sharedStore seedFromLocalSnapshot:out];
    return out;
}

- (void)replaceCachedFriends:(NSArray<IMUserCard *> *)friends {
    NSString *owner = [self ownerUserID];
    [self.dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        if (![db executeUpdate:@"DELETE FROM im_friend_local WHERE owner_uid=?", owner]) {
            IMLogDatabase(@"清理旧好友缓存失败 owner=%@: %@", owner, db.lastErrorMessage);
            *rollback = YES; return;
        }
        [friends enumerateObjectsUsingBlock:^(IMUserCard *c, NSUInteger idx, BOOL *stop) {
            if (c.userID.length == 0) { return; }
            BOOL ok = [db executeUpdate:
                @"INSERT INTO im_friend_local (owner_uid,user_id,sort_order,nickname,avatar_url,status,blocked,updated_at,remark) VALUES (?,?,?,?,?,?,?,?,?)",
                owner, c.userID, @(idx), c.nickname ?: @"", c.avatarURL ?: @"",
                @(c.status), @(c.blocked), @(c.updatedAt), c.remark ?: @""];
            if (!ok) {
                IMLogDatabase(@"写入好友缓存失败 owner=%@ uid=%@: %@", owner, c.userID, db.lastErrorMessage);
                *rollback = YES; *stop = YES;
            }
        }];
    }];
}

- (NSArray<IMGroupInfo *> *)cachedGroups {
    NSString *owner = [self ownerUserID];
    NSMutableArray<IMGroupInfo *> *out = [NSMutableArray array];
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:
            @"SELECT * FROM im_group_local WHERE owner_uid=? ORDER BY sort_order ASC", owner];
        if (!rs) { IMLogDatabase(@"读取群组缓存失败 owner=%@: %@", owner, db.lastErrorMessage); return; }
        while ([rs next]) {
            IMGroupInfo *g = [IMGroupInfo new];
            g.convID = [rs stringForColumn:@"conv_id"] ?: @"";
            g.name = [rs stringForColumn:@"name"] ?: @"";
            g.avatarURL = [rs stringForColumn:@"avatar_url"] ?: @"";
            g.owner = [rs stringForColumn:@"owner"] ?: @"";
            NSString *ownerNick = [rs stringForColumn:@"owner_nickname"];
            g.ownerNickname = ownerNick.length > 0 ? ownerNick : nil;
            NSString *ownerName = [rs stringForColumn:@"owner_username"];
            g.ownerUsername = ownerName.length > 0 ? ownerName : nil;
            g.createdAt = [rs longLongIntForColumn:@"created_at"];
            g.myRole = (IMGroupRole)[rs longForColumn:@"my_role"];
            g.members = @[]; // 列表不需要成员详情；进群聊详情时再联网权威拉取
            if (g.convID.length > 0) { [out addObject:g]; }
        }
        [rs close];
    }];
    return out;
}

- (void)replaceCachedGroups:(NSArray<IMGroupInfo *> *)groups {
    NSString *owner = [self ownerUserID];
    [self.dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        if (![db executeUpdate:@"DELETE FROM im_group_local WHERE owner_uid=?", owner]) {
            IMLogDatabase(@"清理旧群组缓存失败 owner=%@: %@", owner, db.lastErrorMessage);
            *rollback = YES; return;
        }
        [groups enumerateObjectsUsingBlock:^(IMGroupInfo *g, NSUInteger idx, BOOL *stop) {
            if (g.convID.length == 0) { return; }
            BOOL ok = [db executeUpdate:
                @"INSERT INTO im_group_local (owner_uid,conv_id,sort_order,name,avatar_url,owner,owner_nickname,owner_username,created_at,my_role) VALUES (?,?,?,?,?,?,?,?,?,?)",
                owner, g.convID, @(idx), g.name ?: @"", g.avatarURL ?: @"", g.owner ?: @"",
                g.ownerNickname ?: @"", g.ownerUsername ?: @"", @(g.createdAt), @(g.myRole)];
            if (!ok) {
                IMLogDatabase(@"写入群组缓存失败 owner=%@ conv=%@: %@", owner, g.convID, db.lastErrorMessage);
                *rollback = YES; *stop = YES;
            }
        }];
    }];
}

@end
