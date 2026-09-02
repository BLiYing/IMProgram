#import "IMHTTPService+ConvQueries.h"
#import "IMHTTPService+Private.h"

@implementation IMConvCalendarDay
@end

@implementation IMHTTPService (ConvQueries)

/// 查询串转义：关键词可能带空格、`&`、中文，不转义会把 URL 拼坏（表现是"搜中文没结果"）。
static NSString *IMQueryEscape(NSString *raw) {
    return [raw stringByAddingPercentEncodingWithAllowedCharacters:
            NSCharacterSet.URLQueryAllowedCharacterSet] ?: @"";
}

- (void)searchConvMessagesWithToken:(NSString *)token
                             convID:(NSString *)convID
                            keyword:(NSString *)keyword
                            fromUID:(nullable NSString *)fromUID
                              limit:(NSInteger)limit
                         completion:(void (^)(NSArray<NSNumber *> *, BOOL, NSError *_Nullable))completion {
    if (!completion) { return; }
    NSMutableString *path = [NSMutableString stringWithFormat:
        @"/api/v1/conversations/%@/messages/search?q=%@", [self pathEscape:convID], IMQueryEscape(keyword ?: @"")];
    if (fromUID.length > 0) { [path appendFormat:@"&from=%@", IMQueryEscape(fromUID)]; }
    if (limit > 0) { [path appendFormat:@"&limit=%ld", (long)limit]; }
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:@"搜索失败" completion:^(NSDictionary *data, NSError *error) {
        if (error) { completion(@[], NO, error); return; }
        NSArray *raw = [data[@"items"] isKindOfClass:NSArray.class] ? data[@"items"] : @[];
        NSMutableArray<NSNumber *> *seqs = [NSMutableArray arrayWithCapacity:raw.count];
        for (id one in raw) {
            if (![one isKindOfClass:NSDictionary.class]) { continue; } // 脏项跳过，别让一条坏数据废掉整次搜索
            int64_t sq = [one[@"conv_seq"] longLongValue];
            if (sq > 0) { [seqs addObject:@(sq)]; }
        }
        // 服务端按 conv_seq **倒序**下发（cursor 分页需要），而命中集的既有契约是**升序**
        // （▲▼ 上一条/下一条、默认跳最新都按下标走）。在此处一次反转，调用方不必知道这个差异。
        [seqs sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) { return [a compare:b]; }];
        completion(seqs, [data[@"has_more"] boolValue], nil);
    }];
}

- (void)convCalendarWithToken:(NSString *)token
                       convID:(NSString *)convID
                       fromMs:(int64_t)fromMs
                         toMs:(int64_t)toMs
                  utcOffsetMs:(int64_t)utcOffsetMs
                   completion:(void (^)(NSArray<IMConvCalendarDay *> *, NSError *_Nullable))completion {
    if (!completion) { return; }
    NSString *path = [NSString stringWithFormat:
        @"/api/v1/conversations/%@/calendar?from=%lld&to=%lld&utc_offset_ms=%lld",
        [self pathEscape:convID], fromMs, toMs, utcOffsetMs];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:@"加载日历失败" completion:^(NSDictionary *data, NSError *error) {
        if (error) { completion(@[], error); return; }
        NSArray *raw = [data[@"days"] isKindOfClass:NSArray.class] ? data[@"days"] : @[];
        NSMutableArray<IMConvCalendarDay *> *days = [NSMutableArray arrayWithCapacity:raw.count];
        for (id one in raw) {
            if (![one isKindOfClass:NSDictionary.class]) { continue; }
            IMConvCalendarDay *d = [IMConvCalendarDay new];
            d.dayStartMs = [one[@"day_start_ms"] longLongValue];
            d.count = [one[@"count"] integerValue];
            d.firstConvSeq = [one[@"first_conv_seq"] longLongValue];
            if (d.dayStartMs > 0) { [days addObject:d]; }
        }
        completion(days, nil);
    }];
}

@end
