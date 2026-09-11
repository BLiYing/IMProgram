//  IMChatSearchPaging.m

#import "IMChatSearchPaging.h"

const NSInteger IMChatSearchMaxEmptyPages = 5;

NSArray<NSNumber *> *IMChatSearchPrependOlderHits(NSArray<NSNumber *> *currentAscending,
                                                  NSArray<NSNumber *> *page,
                                                  NSInteger *outAdded) {
    int64_t oldest = currentAscending.count > 0 ? currentAscending.firstObject.longLongValue : INT64_MAX;
    NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
    NSMutableArray<NSNumber *> *older = [NSMutableArray array];
    for (NSNumber *n in page) {
        int64_t seq = n.longLongValue;
        if (seq <= 0 || seq >= oldest || [seen containsObject:n]) { continue; }
        [seen addObject:n];
        [older addObject:@(seq)];
    }
    [older sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) { return [a compare:b]; }];
    if (outAdded) { *outAdded = (NSInteger)older.count; }
    [older addObjectsFromArray:currentAscending];
    return older;
}

BOOL IMChatSearchCanGoOlder(NSInteger hitIndex, NSInteger hitCount, BOOL hasMorePages, BOOL loadingOlder) {
    if (hitCount <= 0) { return NO; }
    if (hitIndex > 0) { return YES; }
    return hasMorePages && !loadingOlder;
}
