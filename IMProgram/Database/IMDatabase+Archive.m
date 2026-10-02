//  IMDatabase+Archive.m

#import "IMDatabase+Archive.h"
#import "IMDatabase+Ranges.h"   // dbQueue / ownerUserID

/// IMDatabase.m 类扩展里已有的实现（行→模型唯一映射）；这里只声明选择器，不另写一份映射。
@interface IMDatabase (ArchiveRowMapping)
+ (IMMessageModel *)messageFromResultSet:(FMResultSet *)rs;
@end

@implementation IMDatabase (Archive)

- (NSArray<IMMessageModel *> *)archiveMessagesForConv:(NSString *)convID {
    NSMutableArray<IMMessageModel *> *out = [NSMutableArray array];
    NSString *owner = [self ownerUserID];
    // 排序与 `messagesForConv:` 同序（timestamp 主排、同刻按 conv_seq）——别在这里另起一套顺序
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:
            @"SELECT * FROM im_message_local WHERE owner_uid=? AND conv_id=? AND recalled_at=0 AND content<>'' AND conv_seq>0 "
             "AND (content_type<>'text' OR content LIKE '%://%') ORDER BY timestamp ASC, conv_seq ASC, row_id ASC",
            owner, convID];
        while ([rs next]) { [out addObject:[IMDatabase messageFromResultSet:rs]]; }
        [rs close];
    }];
    return out;
}

@end
