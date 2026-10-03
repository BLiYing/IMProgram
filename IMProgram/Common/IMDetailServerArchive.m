//  IMDetailServerArchive.m

#import "IMDetailServerArchive.h"
#import "IMMediaServerTimeline.h"
#import "IMMessageModel.h"

NSArray<IMMessageModel *> *IMDetailArchiveUnion(NSArray<IMMessageModel *> *local, NSArray<IMMessageModel *> *server) {
    if (server.count == 0) { return local; }
    NSMutableSet<NSNumber *> *seen = [NSMutableSet setWithCapacity:local.count];
    for (IMMessageModel *m in local) { if (m.convSeq > 0) { [seen addObject:@(m.convSeq)]; } }
    NSMutableArray<IMMessageModel *> *out = [local mutableCopy];
    for (IMMessageModel *m in server) {
        if (m.convSeq <= 0 || [seen containsObject:@(m.convSeq)]) { continue; }
        [seen addObject:@(m.convSeq)];
        [out addObject:m];
    }
    return out;
}

@implementation IMDetailServerArchive {
    NSDictionary<NSNumber *, IMMediaServerTimeline *> *_timelines; // kind → 时间线
}

+ (NSString *)serverKindFor:(IMDetailTabKind)kind {
    switch (kind) {
        case IMDetailTabKindMedia: return @"media";
        case IMDetailTabKindFiles: return @"file";
        case IMDetailTabKindVoice: return @"voice";
        default: return nil;
    }
}

+ (BOOL)kindIsArchived:(IMDetailTabKind)kind { return [self serverKindFor:kind] != nil; }

- (instancetype)initWithConvID:(NSString *)convID clearedUpTo:(int64_t)clearedUpTo {
    if ((self = [super init])) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        for (NSNumber *k in @[@(IMDetailTabKindMedia), @(IMDetailTabKindFiles), @(IMDetailTabKindVoice)]) {
            IMMediaServerTimeline *t = [[IMMediaServerTimeline alloc] initWithConvID:convID
                                                                                kind:[IMDetailServerArchive serverKindFor:(IMDetailTabKind)k.integerValue]
                                                                         clearedUpTo:clearedUpTo];
            [t seedWithMessages:@[] hasMore:YES]; // 空打底：从最新一页起
            d[k] = t;
        }
        _timelines = d;
    }
    return self;
}

- (void)loadFirstPages:(void (^)(BOOL))completion {
    dispatch_group_t g = dispatch_group_create();
    __block BOOL anyFailed = NO;
    for (IMMediaServerTimeline *t in _timelines.allValues) {
        dispatch_group_enter(g);
        [t loadOlder:^(NSInteger added, NSError *error) { if (error) { anyFailed = YES; } dispatch_group_leave(g); }];
    }
    dispatch_group_notify(g, dispatch_get_main_queue(), ^{ if (completion) { completion(anyFailed); } });
}

- (void)removeMessagesWithConvSeqs:(NSSet<NSNumber *> *)seqs {
    for (IMMediaServerTimeline *t in _timelines.allValues) { [t removeMessagesWithConvSeqs:seqs]; }
}

- (NSArray<IMMessageModel *> *)mergedWithLocal:(NSArray<IMMessageModel *> *)local {
    NSMutableArray<IMMessageModel *> *all = [NSMutableArray array];
    for (IMMediaServerTimeline *t in _timelines.allValues) { [all addObjectsFromArray:t.messages]; }
    return IMDetailArchiveUnion(local, all);
}

- (BOOL)hasMoreForKind:(IMDetailTabKind)kind { return _timelines[@(kind)].hasMore; }
- (BOOL)isLoadingKind:(IMDetailTabKind)kind { return _timelines[@(kind)].loading; }

- (void)loadMoreForKind:(IMDetailTabKind)kind completion:(void (^)(NSError *_Nullable))completion {
    IMMediaServerTimeline *t = _timelines[@(kind)];
    if (!t) { if (completion) { completion(nil); } return; }
    [t loadOlder:^(NSInteger added, NSError *error) { if (completion) { completion(error); } }];
}

@end
