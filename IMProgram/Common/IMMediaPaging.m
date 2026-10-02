//  IMMediaPaging.m

#import "IMMediaPaging.h"
#import "IMMessageModel.h"

NSArray<IMMessageModel *> *IMMediaPagingPrependOlder(NSArray<IMMessageModel *> *currentAscending,
                                                     NSArray<IMMessageModel *> *page,
                                                     int64_t clearedUpTo,
                                                     NSInteger *outAdded) {
    int64_t oldest = currentAscending.count > 0 ? currentAscending.firstObject.convSeq : INT64_MAX;
    NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
    NSMutableArray<IMMessageModel *> *older = [NSMutableArray array];
    for (IMMessageModel *m in page) {
        int64_t seq = m.convSeq;
        if (seq <= 0 || seq >= oldest || seq <= clearedUpTo || m.recalledAt > 0 || m.content.length == 0) { continue; }
        if ([seen containsObject:@(seq)]) { continue; }
        [seen addObject:@(seq)];
        [older addObject:m];
    }
    [older sortUsingComparator:^NSComparisonResult(IMMessageModel *a, IMMessageModel *b) {
        return a.convSeq < b.convSeq ? NSOrderedAscending : (a.convSeq > b.convSeq ? NSOrderedDescending : NSOrderedSame);
    }];
    if (outAdded) { *outAdded = (NSInteger)older.count; }
    [older addObjectsFromArray:currentAscending];
    return older;
}

NSArray<IMMessageModel *> *IMMediaPagingAppendNewer(NSArray<IMMessageModel *> *currentAscending,
                                                    NSArray<IMMessageModel *> *page,
                                                    int64_t clearedUpTo,
                                                    NSInteger *outAdded) {
    int64_t newest = currentAscending.count > 0 ? currentAscending.lastObject.convSeq : 0;
    NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
    NSMutableArray<IMMessageModel *> *newer = [NSMutableArray array];
    for (IMMessageModel *m in page) {
        int64_t seq = m.convSeq;
        if (seq <= 0 || seq <= newest || seq <= clearedUpTo || m.recalledAt > 0 || m.content.length == 0) { continue; }
        if ([seen containsObject:@(seq)]) { continue; }
        [seen addObject:@(seq)];
        [newer addObject:m];
    }
    [newer sortUsingComparator:^NSComparisonResult(IMMessageModel *a, IMMessageModel *b) {
        return a.convSeq < b.convSeq ? NSOrderedAscending : (a.convSeq > b.convSeq ? NSOrderedDescending : NSOrderedSame);
    }];
    if (outAdded) { *outAdded = (NSInteger)newer.count; }
    return [currentAscending arrayByAddingObjectsFromArray:newer];
}

BOOL IMMediaPagingHasMore(BOOL hasMore, int64_t nextCursor, int64_t clearedUpTo) {
    return hasMore && nextCursor > 0 && nextCursor > clearedUpTo + 1;
}
