#import "IMSocketManager+ClearAll.h"
#import "IMSocketManager+Private.h"
#import "IMLog.h"

/// 定义在 IMChatViewController.m；此处只要名字，不引整个聊天页头。
extern NSNotificationName const IMChatConversationClearedNotification;

@implementation IMSocketManager (ClearAll)

- (BOOL)applyClearAllItems:(NSArray<IMClearAllItem *> *)items {
    if (items.count == 0) { return YES; }
    __block NSDictionary<NSString *, NSNumber *> *removedByConv = nil;
    BOOL performed = [self performDatabaseOperation:^(IMDatabase *database) {
        removedByConv = [database clearConversationsToFloors:items];
    }];
    if (!performed || !removedByConv) { return NO; }
    NSMutableArray<NSString *> *touched = [NSMutableArray array]; // 有消息被清的会话：通知聊天页
    for (IMClearAllItem *it in items) {
        if (it.clearedAt > 0) { [self noteConvClearedUpTo:it.clearedAt forConv:it.convID]; } // 内存游标 / 缺口标记（只增）
        if ([removedByConv[it.convID] integerValue] > 0) { [touched addObject:it.convID]; }
    }
    NSArray<NSString *> *convIDs = [items valueForKeyPath:@"convID"];
    dispatch_async(_queue, ^{                                                 // 在上面各 noteConvClearedUpTo 之后（_queue 串行）
        for (NSString *cid in convIDs) { [self->_backlog clearHistoryFloorForConv:cid]; }
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSString *cid in touched) {
            [NSNotificationCenter.defaultCenter postNotificationName:IMChatConversationClearedNotification
                                                              object:nil userInfo:@{ kIMConvIDKey: cid }];
        }
    });
    IMLogSocket(@"清除所有对话 批量清除到位点 convs=%lu touched=%lu", (unsigned long)items.count, (unsigned long)touched.count);
    return YES;
}

@end
