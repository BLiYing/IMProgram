//  IMCallHistoryPaginator.m

#import "IMCallHistoryPaginator.h"

@implementation IMCallHistoryPaginator {
    NSString *_selfUID;
    NSInteger _pageSize;
    IMCallHistoryFetchBlock _fetcher;
    id _nextCursor;
    /// 每次 reload 加一：迟到的旧翻页请求回调一律不算数（同 IMRtcCall 的 generation 防护思路）。
    NSUInteger _generation;
}

- (instancetype)initWithSelfUID:(NSString *)selfUID pageSize:(NSInteger)pageSize fetcher:(IMCallHistoryFetchBlock)fetcher {
    if ((self = [super init])) {
        _selfUID = [selfUID copy];
        _pageSize = MAX(pageSize, 1);
        _fetcher = [fetcher copy];
        _allRecords = @[];
        _filter = IMCallHistoryFilterAll;
    }
    return self;
}

- (NSArray<IMCallHistoryRecord *> *)filteredRecords {
    return IMCallHistoryApplyFilter(self.allRecords, self.filter, _selfUID);
}

- (void)reloadWithMinVisible:(NSInteger)minVisible completion:(void (^)(NSError *_Nullable))completion {
    _generation++;
    NSUInteger gen = _generation;
    _allRecords = @[];
    _nextCursor = nil;
    _reachedEnd = NO;
    _loading = YES;
    [self continueFetchGeneration:gen startFilteredCount:0 minVisible:minVisible completion:completion];
}

- (void)loadMoreWithMinVisible:(NSInteger)minVisible completion:(void (^)(NSError *_Nullable))completion {
    if (_loading || _reachedEnd) {
        if (completion) { completion(nil); }
        return;
    }
    NSUInteger gen = _generation;
    _loading = YES;
    NSInteger startCount = (NSInteger)self.filteredRecords.count;
    [self continueFetchGeneration:gen startFilteredCount:startCount minVisible:minVisible completion:completion];
}

/// 拉一页并按需自动续拉（仅「未接」视图会续拉，见类头注释）；`gen` 与当前 `_generation` 不符即作废，
/// 不回调（更新的 reload/loadMore 已经接管，旧调用方不该再收到一次回调覆盖新状态）。
- (void)continueFetchGeneration:(NSUInteger)gen startFilteredCount:(NSInteger)startCount
                       minVisible:(NSInteger)minVisible completion:(void (^)(NSError *_Nullable))completion {
    __weak typeof(self) ws = self;
    _fetcher(_nextCursor, _pageSize, ^(NSArray<IMCallHistoryRecord *> *records, id nextCursor, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || gen != self->_generation) { return; }
        if (error) {
            self->_loading = NO;
            if (completion) { completion(error); }
            return;
        }
        self->_allRecords = [self->_allRecords arrayByAddingObjectsFromArray:records ?: @[]];
        self->_nextCursor = nextCursor;
        self->_reachedEnd = (self->_nextCursor == nil);
        NSInteger gained = (NSInteger)self.filteredRecords.count - startCount;
        BOOL shouldContinue = self->_filter == IMCallHistoryFilterMissed && !self->_reachedEnd && gained < minVisible;
        if (shouldContinue) {
            [self continueFetchGeneration:gen startFilteredCount:startCount minVisible:minVisible completion:completion];
            return;
        }
        self->_loading = NO;
        if (completion) { completion(nil); }
    });
}

@end
