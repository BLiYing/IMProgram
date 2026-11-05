//  IMShareSelection.m

#import "IMShareSelection.h"
#import "IMConversation.h"
#import "IMUserCard.h"
#import "IMGroupInfo.h"
#import "IMProtocol.h"
#import "IMAccountIdentity.h"
#import "IMRemarkStore.h"

@implementation IMShareSelection {
    NSMutableArray<IMConversation *> *_items;
}

- (instancetype)initWithLimit:(NSUInteger)limit {
    if ((self = [super init])) {
        _limit = limit;
        _items = [NSMutableArray array];
    }
    return self;
}

- (NSUInteger)count { return _items.count; }
- (NSArray<IMConversation *> *)conversations { return [_items copy]; }

- (NSInteger)indexOfConvID:(NSString *)convID {
    if (convID.length == 0) { return NSNotFound; }
    for (NSUInteger i = 0; i < _items.count; i++) {
        if ([_items[i].convID isEqualToString:convID]) { return (NSInteger)i; }
    }
    return NSNotFound;
}

- (BOOL)containsConvID:(NSString *)convID { return [self indexOfConvID:convID] != NSNotFound; }

- (IMShareToggleResult)toggle:(IMConversation *)conversation {
    NSString *cid = conversation.convID;
    if (cid.length == 0) { return IMShareToggleInvalid; }
    NSInteger idx = [self indexOfConvID:cid];
    if (idx != NSNotFound) {
        [_items removeObjectAtIndex:(NSUInteger)idx];
        return IMShareToggleRemoved;
    }
    if (_limit > 0 && _items.count >= _limit) { return IMShareToggleCapped; }
    [_items addObject:conversation];
    return IMShareToggleAdded;
}

- (BOOL)removeConvID:(NSString *)convID {
    NSInteger idx = [self indexOfConvID:convID];
    if (idx == NSNotFound) { return NO; }
    [_items removeObjectAtIndex:(NSUInteger)idx];
    return YES;
}

- (void)clear { [_items removeAllObjects]; }

+ (IMConversation *)conversationForFriend:(IMUserCard *)card selfUID:(NSString *)selfUID {
    if (selfUID.length == 0 || card.userID.length == 0) { return nil; }
    IMConversation *c = [IMConversation new];
    c.convID = IMConversationID(selfUID, card.userID);
    c.isGroup = NO;
    c.peer = card.userID;
    c.peerNickname = card.nickname;
    c.peerAvatarURL = card.avatarURL;
    c.peerRemark = card.remark;
    c.peerDeleted = card.deleted;
    return c;
}

+ (IMConversation *)conversationForGroup:(IMGroupInfo *)group {
    if (group.convID.length == 0) { return nil; }
    IMConversation *c = [IMConversation new];
    c.convID = group.convID;
    c.isGroup = YES;
    c.peer = @"";
    c.name = group.name;
    c.avatarURL = group.avatarURL;
    c.memberCount = group.memberCount;
    c.isSuper = group.isSuper;
    return c;
}

+ (BOOL)isShareableFriend:(IMUserCard *)card {
    if (card.userID.length == 0) { return NO; }
    if (card.deleted || [IMRemarkStore.sharedStore isDeletedUser:card.userID]) { return NO; }
    if (card.blocked) { return NO; }
    if (IMIsSystemUserID(card.userID)) { return NO; }
    return YES;
}

+ (NSArray<IMConversation *> *)conversations:(NSArray<IMConversation *> *)candidates
                           excludingConvIDs:(NSSet<NSString *> *)excluded {
    NSMutableArray<IMConversation *> *out = [NSMutableArray arrayWithCapacity:candidates.count];
    for (IMConversation *c in candidates) {
        if (c.convID.length == 0 || [excluded containsObject:c.convID]) { continue; }
        [out addObject:c];
    }
    return out;
}

@end
