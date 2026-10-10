//  IMFriendRequestSections.m

#import "IMFriendRequestSections.h"
#import "IMUserCard.h"

const NSInteger kIMRecentAddedDays = 30;
const NSInteger kIMRecentAddedMax = 50;

static const int64_t kIMMillisPerDay = 24LL * 60 * 60 * 1000;

@implementation IMFriendRequestSections

+ (instancetype)sectionsWithCards:(NSArray<IMUserCard *> *)cards nowMs:(int64_t)nowMs {
    NSMutableArray<IMUserCard *> *incoming = [NSMutableArray array];
    NSMutableArray<IMUserCard *> *outgoing = [NSMutableArray array];
    NSMutableArray<IMUserCard *> *added = [NSMutableArray array];
    int64_t cutoff = nowMs - kIMRecentAddedDays * kIMMillisPerDay;
    for (IMUserCard *c in cards ?: @[]) {
        switch (c.status) {
            case IMFriendStatusPending: [incoming addObject:c]; break;
            case IMFriendStatusRequested: [outgoing addObject:c]; break;
            case IMFriendStatusAccepted:
                if (c.updatedAt >= cutoff) { [added addObject:c]; }
                break;
            default: break;
        }
    }
    // 稳定降序：同一时间戳保持服务端原顺序。
    [added sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(IMUserCard *a, IMUserCard *b) {
        if (a.updatedAt == b.updatedAt) { return NSOrderedSame; }
        return a.updatedAt > b.updatedAt ? NSOrderedAscending : NSOrderedDescending;
    }];
    if (added.count > (NSUInteger)kIMRecentAddedMax) {
        [added removeObjectsInRange:NSMakeRange((NSUInteger)kIMRecentAddedMax, added.count - (NSUInteger)kIMRecentAddedMax)];
    }
    IMFriendRequestSections *s = [IMFriendRequestSections new];
    s->_incoming = [incoming copy];
    s->_outgoing = [outgoing copy];
    s->_added = [added copy];
    return s;
}

- (BOOL)isEmpty { return _incoming.count + _outgoing.count + _added.count == 0; }

@end
