//  IMBatchRunner.m

#import "IMBatchRunner.h"

/// 一次批量执行的状态。不持有任何 block（work / completion 以外），在途的 done 块会持有它，全部结束即释放——
/// 没有「block 自引用 + 执行中置 nil」那种悬空风险。
@interface IMBatchJob : NSObject
- (instancetype)initWithItems:(NSArray *)items limit:(NSUInteger)limit
                         work:(void (^)(id, void (^)(NSError *_Nullable)))work
                   completion:(void (^)(NSArray *, NSArray *))completion;
- (void)start;
@end

@implementation IMBatchJob {
    NSArray *_items;
    NSUInteger _limit;
    NSUInteger _next, _finished;
    NSMutableSet<NSNumber *> *_failedIdx;
    void (^_work)(id, void (^)(NSError *_Nullable));
    void (^_completion)(NSArray *, NSArray *);
}

- (instancetype)initWithItems:(NSArray *)items limit:(NSUInteger)limit
                         work:(void (^)(id, void (^)(NSError *_Nullable)))work
                   completion:(void (^)(NSArray *, NSArray *))completion {
    if ((self = [super init])) {
        _items = [items copy];
        _limit = MAX((NSUInteger)1, limit);
        _failedIdx = [NSMutableSet set];
        _work = [work copy];
        _completion = [completion copy];
    }
    return self;
}

- (void)start { [self pump]; }

- (void)pump {
    while (_next < _items.count && (_next - _finished) < _limit) {
        NSUInteger idx = _next++;
        __block BOOL called = NO; // 守卫：done 被重复调用不重复计数
        _work(_items[idx], ^(NSError *error) {
            if (called) { return; }
            called = YES;
            [self finishIndex:idx error:error];
        });
    }
}

- (void)finishIndex:(NSUInteger)idx error:(NSError *)error {
    if (error) { [_failedIdx addObject:@(idx)]; }
    _finished++;
    if (_finished < _items.count) { [self pump]; return; }
    NSMutableArray *ok = [NSMutableArray array], *bad = [NSMutableArray array];
    for (NSUInteger i = 0; i < _items.count; i++) { [([_failedIdx containsObject:@(i)] ? bad : ok) addObject:_items[i]]; }
    void (^done)(NSArray *, NSArray *) = _completion;
    _completion = nil;
    done(ok, bad);
}

@end

@implementation IMBatchRunner

+ (void)forEach:(NSArray *)items
    concurrency:(NSUInteger)limit
           work:(void (^)(id item, void (^done)(NSError *_Nullable error)))work
     completion:(void (^)(NSArray *succeeded, NSArray *failed))completion {
    if (items.count == 0) { completion(@[], @[]); return; }
    [[[IMBatchJob alloc] initWithItems:items limit:limit work:work completion:completion] start];
}

@end
