//  IMCallHistoryPaginator.m

#import "IMCallHistoryPaginator.h"

@implementation IMCallHistoryPaginator {
    NSString *_selfUID;
    NSInteger _pageSize;
    IMCallHistoryFetchBlock _fetcher;
    id _nextCursor;
    /// 每次 reload 加一：迟到的旧翻页请求回调一律不算数（同 IMRtcCall 的 generation 防护思路）。
    NSUInteger _generation;
    /// reload 发出、首页还没回来：旧列表/游标先不动，首页成功才整体替换（失败就原样保留，同 Android/Web）。
    BOOL _reloadPending;
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
    _reloadPending = YES;
    _loading = YES;
    [self continueFetchGeneration:gen minVisible:minVisible completion:completion];
}

- (void)loadMoreWithMinVisible:(NSInteger)minVisible completion:(void (^)(NSError *_Nullable))completion {
    if (_loading || _reachedEnd) {
        if (completion) { completion(nil); }
        return;
    }
    NSUInteger gen = _generation;
    _loading = YES;
    [self continueFetchGeneration:gen minVisible:minVisible completion:completion];
}

/// 拉一页并按需自动续拉（仅「未接」视图会续拉，见类头注释）；`gen` 与当前 `_generation` 不符即作废，
/// 不回调（更新的 reload/loadMore 已经接管，旧调用方不该再收到一次回调覆盖新状态）。
- (void)continueFetchGeneration:(NSUInteger)gen minVisible:(NSInteger)minVisible completion:(void (^)(NSError *_Nullable))completion {
    __weak typeof(self) ws = self;
    _fetcher(_reloadPending ? nil : _nextCursor, _pageSize, ^(NSArray<IMCallHistoryRecord *> *records, id nextCursor, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || gen != self->_generation) { return; }
        if (error) {
            self->_reloadPending = NO; // 旧列表与游标原样保留：页面只显示底部错误，不整屏变「加载失败」
            self->_loading = NO;
            if (completion) { completion(error); }
            return;
        }
        self->_allRecords = self->_reloadPending ? (records ?: @[])
            : [self->_allRecords arrayByAddingObjectsFromArray:records ?: @[]];
        self->_reloadPending = NO;
        self->_nextCursor = nextCursor;
        self->_reachedEnd = (self->_nextCursor == nil);
        // 续拉判据用**当前**过滤后的总量，不是本轮拉取的增量（/code-review 2026-09-29 发现两个问题：
        // ① 原先按「调用时刻」快照的 startCount 算增量，若在拉取途中切换了 filter，两次计数基于不同
        //    filter 算出来，对不上；② 用增量本身也不对——已经够一屏时只是这页恰好没有新未接记录，
        //    增量判据会误判"不够"而继续拉。改成绝对量判据后两个问题一起消失，且天然不怕 filter 中途变，
        //    因为 self.filteredRecords 每次都用当前 self.filter 现算，不依赖任何调用时刻快照。
        BOOL shouldContinue = self->_filter == IMCallHistoryFilterMissed && !self->_reachedEnd
            && (NSInteger)self.filteredRecords.count < minVisible;
        if (shouldContinue) {
            [self continueFetchGeneration:gen minVisible:minVisible completion:completion];
            return;
        }
        self->_loading = NO;
        if (completion) { completion(nil); }
    });
}

@end
