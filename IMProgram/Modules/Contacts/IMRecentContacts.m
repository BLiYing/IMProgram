//  IMRecentContacts.m

#import "IMRecentContacts.h"
#import "IMConversation.h"
#import "IMAccountIdentity.h"

const NSUInteger kIMRecentContactsLimit = 5;

static BOOL IMIsRecentContactCandidate(IMConversation *c, NSString *selfUID, BOOL (^isDeletedUser)(NSString *)) {
    if (c.isGroup || c.peer.length == 0 || c.convID.length == 0) { return NO; }
    if ([c.peer isEqualToString:selfUID] || IMIsSystemUserID(c.peer)) { return NO; }
    if (c.timestamp <= 0) { return NO; } // 没有最后一条消息（解析时 last_message 为空 → 时间保持 0）
    if (c.peerDeleted || (isDeletedUser && isDeletedUser(c.peer))) { return NO; }
    return YES;
}

NSArray<IMConversation *> *IMRecentContacts(NSArray<IMConversation *> *conversations, NSString *selfUID,
                                            BOOL (^isDeletedUser)(NSString *peerUID)) {
    NSMutableArray<IMConversation *> *candidates = [NSMutableArray array];
    for (IMConversation *c in conversations) {
        if (IMIsRecentContactCandidate(c, selfUID, isDeletedUser)) { [candidates addObject:c]; }
    }
    [candidates sortUsingComparator:^NSComparisonResult(IMConversation *a, IMConversation *b) {
        if (a.timestamp != b.timestamp) { return a.timestamp > b.timestamp ? NSOrderedAscending : NSOrderedDescending; }
        return [a.convID compare:b.convID options:NSLiteralSearch]; // 码元序，不随 locale 变（三端对齐）
    }];
    if (candidates.count <= kIMRecentContactsLimit) { return [candidates copy]; }
    return [candidates subarrayWithRange:NSMakeRange(0, kIMRecentContactsLimit)];
}
