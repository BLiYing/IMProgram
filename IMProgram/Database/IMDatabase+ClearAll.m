//  IMDatabase+ClearAll.m
//  语义、拆分理由见 IMDatabase+ClearAll.h。

#import "IMDatabase+ClearAll.h"
#import "IMDatabase+ClearFloor.h"
#import "IMDatabase+Ranges.h"   // dbQueue / ownerUserID
#import "IMLog.h"

@implementation IMClearAllItem
- (instancetype)initWithConvID:(NSString *)convID clearedAt:(int64_t)clearedAt {
    self = [super init];
    if (self) { _convID = [convID copy]; _clearedAt = clearedAt; }
    return self;
}
@end

@implementation IMDatabase (ClearAll)

- (NSDictionary<NSString *, NSNumber *> *)clearConversationsToFloors:(NSArray<IMClearAllItem *> *)items {
    if (items.count == 0) { return @{}; }
    NSString *owner = [self ownerUserID];
    NSMutableDictionary<NSString *, NSNumber *> *removedByConv = [NSMutableDictionary dictionaryWithCapacity:items.count];
    __block BOOL ok = YES;
    [self.dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        for (IMClearAllItem *it in items) {
            if (it.convID.length == 0) { continue; }
            BOOL revived = IMConvRevivedInDB(db, owner, it.convID, it.clearedAt); // 先于清理：要读行里的 head
            NSInteger removed = 0;
            if (it.clearedAt > 0 && !IMClearConvToFloorInDB(db, owner, it.convID, it.clearedAt, &removed)) {
                ok = NO; *rollback = YES; return;
            }
            if (!revived && ![db executeUpdate:@"DELETE FROM im_conversation_local WHERE owner_uid=? AND conv_id=?", owner, it.convID]) {
                IMLogDatabase(@"清除所有对话：删会话行失败 conv=%@: %@", it.convID, db.lastErrorMessage);
                ok = NO; *rollback = YES; return;
            }
            removedByConv[it.convID] = @(removed);
        }
    }];
    IMLogDatabase(@"清除所有对话 批量落库 convs=%lu ok=%d", (unsigned long)items.count, ok);
    return ok ? removedByConv : nil;
}

@end
