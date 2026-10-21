//  IMConversationSelection.m

#import "IMConversationSelection.h"
#import "IMConversation.h"

@implementation IMConversationSelection {
    NSMutableSet<NSString *> *_ids;
}

- (instancetype)init {
    if ((self = [super init])) { _ids = [NSMutableSet set]; }
    return self;
}

- (NSUInteger)count { return _ids.count; }
- (NSSet<NSString *> *)selectedIDs { return [_ids copy]; }

+ (BOOL)conversationHasUnread:(IMConversation *)c {
    return c.unread > 0 || c.markedUnread;
}

- (BOOL)isSelected:(NSString *)convID { return convID.length > 0 && [_ids containsObject:convID]; }

- (BOOL)toggle:(NSString *)convID {
    if (convID.length == 0) { return NO; }
    if ([_ids containsObject:convID]) { [_ids removeObject:convID]; return NO; }
    [_ids addObject:convID];
    return YES;
}

- (void)select:(NSString *)convID { if (convID.length > 0) { [_ids addObject:convID]; } }
- (void)deselect:(NSString *)convID { if (convID.length > 0) { [_ids removeObject:convID]; } }
- (void)clear { [_ids removeAllObjects]; }

- (void)selectAllIn:(NSArray<IMConversation *> *)list {
    for (IMConversation *c in list) { [self select:c.convID]; }
}

- (BOOL)isAllSelectedIn:(NSArray<IMConversation *> *)list {
    if (list.count == 0) { return NO; }
    for (IMConversation *c in list) { if (![self isSelected:c.convID]) { return NO; } }
    return YES;
}

- (BOOL)pruneToExistingIn:(NSArray<IMConversation *> *)list {
    NSMutableSet<NSString *> *alive = [NSMutableSet setWithCapacity:list.count];
    for (IMConversation *c in list) { if (c.convID.length > 0) { [alive addObject:c.convID]; } }
    NSUInteger before = _ids.count;
    [_ids intersectSet:alive];
    return _ids.count != before;
}

- (BOOL)hasUnreadIn:(NSArray<IMConversation *> *)list {
    for (IMConversation *c in list) {
        if ([self isSelected:c.convID] && [IMConversationSelection conversationHasUnread:c]) { return YES; }
    }
    return NO;
}

- (NSArray<IMConversation *> *)selectedConversationsIn:(NSArray<IMConversation *> *)list {
    NSMutableArray<IMConversation *> *out = [NSMutableArray array];
    for (IMConversation *c in list) { if ([self isSelected:c.convID]) { [out addObject:c]; } }
    return out;
}

@end
