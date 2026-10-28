#import "IMSocketManager+ConvClear.h"
#import "IMSocketManager+Private.h"
#import "IMDatabase+ClearFloor.h"
#import "IMLog.h"

/// 定义在 IMChatViewController.m；此处只要名字，不引整个聊天页头。
extern NSNotificationName const IMChatConversationClearedNotification;

@implementation IMSocketManager (ConvClear)

- (int64_t)clearConvToFloor:(NSString *)convID serverClearedAt:(int64_t)serverClearedAt database:(IMDatabase *)database {
    if (convID.length == 0) { return 0; }
    NSInteger removed = [database clearMessagesForConv:convID toServerClearedAt:serverClearedAt];
    int64_t floor = [database clearedUpToForConv:convID];
    IMLog(@"清除到位点 conv=%@ server_cleared_at=%lld floor=%lld removed=%ld", convID, serverClearedAt, floor, (long)removed);
    [self noteConvClearedUpTo:floor forConv:convID];                       // 内存游标 / 缺口标记
    dispatch_async(_queue, ^{ [self->_backlog clearHistoryFloorForConv:convID]; }); // 服务端下界缓存作废（_queue 串行，在上一步之后）
    if (removed > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{   // 打开着的聊天页清内存并刷新
            [NSNotificationCenter.defaultCenter postNotificationName:IMChatConversationClearedNotification
                                                              object:nil userInfo:@{ kIMConvIDKey: convID }];
        });
    }
    return floor;
}

- (BOOL)applyConvDeleteFrame:(NSDictionary *)data convID:(NSString *)convID {
    return [self performDatabaseOperation:^(IMDatabase *database) {
        int64_t clearedAt = IMClearedAtFromJSON([data isKindOfClass:NSDictionary.class] ? data[@"cleared_at"] : nil);
        BOOL revived = [database convRevivedAfterClearedAt:clearedAt forConv:convID]; // 迟到的回显：新消息已让会话复活
        [self clearConvToFloor:convID serverClearedAt:clearedAt database:database];   // 先于删行：要读行里的 head
        if (!revived) { [database deleteCachedConversation:convID]; }                   // 复活的会话保留行与位点之上的新消息
    }];
}

- (NSUInteger)alignClearFloorsFromConversations:(NSArray<IMConversation *> *)conversations database:(IMDatabase *)database {
    NSUInteger n = 0;
    for (IMConversation *c in conversations) {
        if (c.convID.length == 0 || c.clearedAt <= 0) { continue; }
        if (c.clearedAt <= [database clearedUpToForConv:c.convID]) { continue; }
        [self clearConvToFloor:c.convID serverClearedAt:c.clearedAt database:database];
        n++;
    }
    return n;
}

@end
