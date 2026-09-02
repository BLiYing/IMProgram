#import "IMBacklogTracker.h"

// 400 = 2 页（服务端单页 200）。正常用户离线一晚攒的量远在此之下，走的还是老路径、什么都没变；
// 只有"10 万条大群"这种会话才会被判 too_long 留成缺口——而那种会话本来就不该被当成本地齐全。
const int64_t IMSyncMaxGap = 400;

@implementation IMBacklogTracker {
    NSMutableSet<NSString *> *_superConvs;
    NSMutableDictionary<NSString *, NSNumber *> *_headSeq;
    NSMutableSet<NSString *> *_gappedConvs;
    NSMutableDictionary<NSString *, NSNumber *> *_pendingReceipts;
    BOOL _flushScheduled;
}

- (instancetype)init {
    if (self = [super init]) {
        _superConvs = [NSMutableSet set];
        _headSeq = [NSMutableDictionary dictionary];
        _gappedConvs = [NSMutableSet set];
        _pendingReceipts = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)setSuper:(BOOL)isSuper forConv:(NSString *)convID {
    if (convID.length == 0) { return; }
    if (isSuper) { [_superConvs addObject:convID]; } else { [_superConvs removeObject:convID]; }
}

- (int64_t)maxGapForConv:(NSString *)convID {
    return (convID.length > 0 && [_superConvs containsObject:convID]) ? 0 : IMSyncMaxGap;
}

- (void)noteHead:(int64_t)head forConv:(NSString *)convID {
    if (convID.length == 0 || head <= 0) { return; }
    if (head > _headSeq[convID].longLongValue) { _headSeq[convID] = @(head); }
}

- (int64_t)headForConv:(NSString *)convID {
    return convID.length > 0 ? _headSeq[convID].longLongValue : 0;
}

- (void)markGapForConv:(NSString *)convID {
    if (convID.length > 0) { [_gappedConvs addObject:convID]; }
}

- (void)clearGapForConv:(NSString *)convID {
    if (convID.length > 0) { [_gappedConvs removeObject:convID]; }
}

- (BOOL)hasGapForConv:(NSString *)convID {
    return convID.length > 0 && [_gappedConvs containsObject:convID];
}

- (BOOL)queueReceiptForConv:(NSString *)convID upTo:(int64_t)convSeq {
    if (convID.length == 0 || convSeq <= 0) { return NO; }
    if (convSeq > _pendingReceipts[convID].longLongValue) { _pendingReceipts[convID] = @(convSeq); }
    if (_flushScheduled) { return NO; }
    _flushScheduled = YES;
    return YES;
}

- (void)drainReceipts:(void (^)(NSString *, int64_t))emit {
    _flushScheduled = NO;
    if (_pendingReceipts.count == 0 || emit == nil) { [_pendingReceipts removeAllObjects]; return; }
    NSDictionary<NSString *, NSNumber *> *batch = [_pendingReceipts copy];
    [_pendingReceipts removeAllObjects];
    [batch enumerateKeysAndObjectsUsingBlock:^(NSString *convID, NSNumber *upTo, BOOL *stop) {
        emit(convID, upTo.longLongValue);
    }];
}

- (void)reset {
    [_superConvs removeAllObjects];
    [_headSeq removeAllObjects];
    [_gappedConvs removeAllObjects];
    [_pendingReceipts removeAllObjects];
    _flushScheduled = NO;
}

@end
