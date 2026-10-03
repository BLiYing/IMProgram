//  IMMediaServerTimeline.m

#import "IMMediaServerTimeline.h"
#import "IMMediaPaging.h"
#import "IMMessageModel.h"
#import "IMHTTPService.h"
#import "IMHTTPService+ConvQueries.h"

const NSInteger IMMediaServerTimelineMaxEmptyPages = 5;
static const NSInteger kPageLimit = 60; // 与 Android / Web 同值

@implementation IMMediaServerTimeline {
    NSString *_convID, *_kind;
    int64_t _cleared;
    int64_t _cursor;
    int64_t _newerCursor;   // 「向更新」的服务端游标（has_more 时 = 本页最大 conv_seq）
    NSMutableArray<IMMessageModel *> *_messages;
}

- (instancetype)initWithConvID:(NSString *)convID kind:(NSString *)kind clearedUpTo:(int64_t)clearedUpTo {
    if ((self = [super init])) {
        _convID = [convID copy]; _kind = [kind copy]; _cleared = clearedUpTo;
        _messages = [NSMutableArray array];
    }
    return self;
}

- (NSArray<IMMessageModel *> *)messages { return _messages; }

- (void)seedWithMessages:(NSArray<IMMessageModel *> *)ascending hasMore:(BOOL)hasMore {
    _messages = [ascending mutableCopy];
    _hasMore = hasMore;
    _cursor = _messages.firstObject.convSeq; // 空 = 0 = 从最新一页起
}

- (void)loadOlder:(void (^)(NSInteger, NSError *_Nullable))completion {
    if (_loading || !_hasMore) { if (completion) { completion(0, nil); } return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { _hasMore = NO; if (completion) { completion(0, [NSError errorWithDomain:@"IMMedia" code:401 userInfo:nil]); } return; }
    _loading = YES;
    [self fetchAttempt:0 token:token completion:completion];
}

- (void)fetchAttempt:(NSInteger)attempt token:(NSString *)token completion:(void (^)(NSInteger, NSError *_Nullable))completion {
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService convMediaWithToken:token convID:_convID kind:_kind cursor:_cursor limit:kPageLimit
                                         completion:^(NSArray<IMMessageModel *> *page, BOOL more, int64_t next, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (error) {
                self->_loading = NO; self->_hasMore = NO; // 离线 / 失败：停在已有的那段，调用方说一句
                if (completion) { completion(0, error); }
                return;
            }
            self->_cursor = next;
            BOOL moreAbove = IMMediaPagingHasMore(more, next, self->_cleared);
            NSInteger added = 0;
            NSArray<IMMessageModel *> *merged = IMMediaPagingPrependOlder(self->_messages, page, self->_cleared, &added);
            if (added == 0 && moreAbove && attempt < IMMediaServerTimelineMaxEmptyPages) {
                [self fetchAttempt:attempt + 1 token:token completion:completion];
                return;
            }
            self->_messages = [merged mutableCopy];
            self->_hasMore = moreAbove;
            self->_loading = NO;
            if (completion) { completion(added, nil); }
        });
    }];
}

- (void)loadNewer:(void (^)(NSInteger, NSError *_Nullable))completion {
    if (_loadingNewer || !_hasMoreNewer) { if (completion) { completion(0, nil); } return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { _hasMoreNewer = NO; if (completion) { completion(0, [NSError errorWithDomain:@"IMMedia" code:401 userInfo:nil]); } return; }
    _loadingNewer = YES;
    [self fetchNewerAttempt:0 token:token totalAdded:0 completion:completion];
}

/// 服务端空页却仍 has_more（逐人隐藏过滤掉一整页）：用服务端给的游标（本页最大 conv_seq）接着往后翻，最多再翻
/// `IMMediaServerTimelineMaxEmptyPages` 页（同 loadOlder）；不是原地拿「本地最后一条」重复请求。
- (void)fetchNewerAttempt:(NSInteger)attempt token:(NSString *)token totalAdded:(NSInteger)total
               completion:(void (^)(NSInteger, NSError *_Nullable))completion {
    int64_t after = MAX(_messages.lastObject.convSeq, _newerCursor);
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService convMediaNewerWithToken:token convID:_convID kind:_kind after:after limit:kPageLimit
                                              completion:^(NSArray<IMMessageModel *> *page, BOOL more, int64_t next, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (error) {
                self->_loadingNewer = NO; self->_hasMoreNewer = NO; // 离线 / 失败：停在已有的，调用方说一句
                if (completion) { completion(total, error); }
                return;
            }
            if (more && next > 0) { self->_newerCursor = next; }
            NSInteger added = 0;
            NSArray<IMMessageModel *> *merged = IMMediaPagingAppendNewer(self->_messages, page, self->_cleared, &added);
            self->_messages = [merged mutableCopy];
            if (added == 0 && more && attempt < IMMediaServerTimelineMaxEmptyPages) {
                [self fetchNewerAttempt:attempt + 1 token:token totalAdded:total completion:completion];
                return;
            }
            self->_hasMoreNewer = more && added > 0; // 到头 / 上限用尽仍没有可并进来的 → 停，别空转
            self->_loadingNewer = NO;
            if (completion) { completion(total + added, nil); }
        });
    }];
}

- (void)removeMessagesWithConvSeqs:(NSSet<NSNumber *> *)seqs {
    NSIndexSet *idx = [_messages indexesOfObjectsPassingTest:^BOOL(IMMessageModel *m, NSUInteger i, BOOL *stop) {
        return [seqs containsObject:@(m.convSeq)];
    }];
    if (idx.count > 0) { [_messages removeObjectsAtIndexes:idx]; }
}

@end
