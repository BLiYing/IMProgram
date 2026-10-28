//  IMDataExportTests.m
//  导出我的数据（DATA_EXPORT_DESIGN）：任务对象解析、状态机映射、冷却小时数、按钮可用性、下载地址、
//  REST 错误码（200011 retry_after_sec）与页面各态可见性。app-hosted；HTTP 用 NSURLProtocol 只拦 /users/me/exports。

#import <XCTest/XCTest.h>

#import "IMDataExport.h"
#import "IMServerEndpoint.h"
#import "IMExportDataViewController.h"
#import "IMHTTPService.h"
#import "IMHTTPService+Export.h"

@interface IMExportStubProtocol : NSURLProtocol
@property (class, nonatomic, copy) NSDictionary *response;
@property (class, nonatomic, copy) NSString *lastPath;
@end
@implementation IMExportStubProtocol
static NSDictionary *sExpResp; static NSString *sExpPath;
+ (NSDictionary *)response { return sExpResp; }
+ (void)setResponse:(NSDictionary *)v { sExpResp = v; }
+ (NSString *)lastPath { return sExpPath; }
+ (void)setLastPath:(NSString *)v { sExpPath = v; }
+ (BOOL)canInitWithRequest:(NSURLRequest *)r { return [r.URL.path hasPrefix:@"/api/v1/users/me/exports"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }
- (void)startLoading {
    sExpPath = self.request.URL.path;
    NSData *data = [NSJSONSerialization dataWithJSONObject:sExpResp ?: @{ @"code": @0, @"data": [NSNull null] } options:0 error:NULL];
    NSHTTPURLResponse *r = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1"
                                                     headerFields:@{ @"Content-Type": @"application/json" }];
    [self.client URLProtocol:self didReceiveResponse:r cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

/// 读页面私有视图用（运行时 KVC，不改生产可见性）。
@interface IMExportDataViewController (TestAccess)
- (void)render;
- (void)startSucceededWithJob:(IMExportJob *)job;
- (void)latestFinishedWithJob:(nullable IMExportJob *)job error:(nullable NSError *)error epoch:(NSUInteger)epoch;
- (void)stopPolling;
- (void)refreshLatest;
+ (nullable UIViewController *)topPresentableFrom:(nullable UIViewController *)root;
@end

@interface IMDataExportTests : XCTestCase
@end

@implementation IMDataExportTests {
    NSString *_sHost;
}

- (void)setUp {
    [super setUp];
    _sHost = IMHTTPService.sharedService.host;
    IMHTTPService.sharedService.host = @"127.0.0.1:59391";
    sExpResp = nil; sExpPath = nil;
    [NSURLProtocol registerClass:IMExportStubProtocol.class];
}

- (void)tearDown {
    [NSURLProtocol unregisterClass:IMExportStubProtocol.class];
    IMHTTPService.sharedService.host = _sHost;
    [super tearDown];
}

- (IMExportJob *)jobWithStatus:(NSString *)status extra:(NSDictionary *)extra {
    NSMutableDictionary *d = [@{ @"id": @"j1", @"status": status } mutableCopy];
    [d addEntriesFromDictionary:extra];
    return [IMExportJob jobFromJSON:d];
}

#pragma mark - 任务对象解析

- (void)test_解析完整任务对象 {
    NSDictionary *json = @{ @"id": @"exp_9", @"status": @"done", @"include_media": @NO, @"formats": @[@"html"],
        @"progress": @{ @"done_convs": @12, @"total_convs": @12 },
        @"result": @{ @"size_bytes": @134217728, @"conv_count": @12, @"msg_count": @8431 },
        @"created_at": @1761465600000, @"finished_at": @1761469200000, @"expires_at": @1761555600000, @"error_code": @0 };
    IMExportJob *job = [IMExportJob jobFromJSON:json];
    XCTAssertEqualObjects(job.jobID, @"exp_9");
    XCTAssertEqual(job.status, IMExportStatusDone);
    XCTAssertEqual(job.doneConvs, 12); XCTAssertEqual(job.totalConvs, 12);
    XCTAssertEqual(job.sizeBytes, 134217728LL);
    XCTAssertEqual(job.convCount, 12); XCTAssertEqual(job.msgCount, 8431);
    XCTAssertEqualWithAccuracy(job.expiresAt.timeIntervalSince1970, 1761555600, 0.5);
    XCTAssertEqualWithAccuracy(job.finishedAt.timeIntervalSince1970, 1761469200, 0.5);
}

- (void)test_解析_空_脏数据不崩 {
    XCTAssertNil([IMExportJob jobFromJSON:nil]);
    XCTAssertNil([IMExportJob jobFromJSON:NSNull.null]);
    XCTAssertNil([IMExportJob jobFromJSON:@{}]);           // data:null 经通用解包回成空字典
    XCTAssertNil([IMExportJob jobFromJSON:@[@1]]);
    IMExportJob *job = [IMExportJob jobFromJSON:@{ @"id": @77, @"status": @"weird", @"progress": @"x", @"result": @[] }];
    XCTAssertEqualObjects(job.jobID, @"77");
    XCTAssertEqual(job.status, IMExportStatusUnknown);
    XCTAssertEqual(job.totalConvs, 0); XCTAssertEqual(job.sizeBytes, 0LL);
    XCTAssertNil(job.expiresAt);
}

- (void)test_status字符串映射 {
    NSDictionary *expect = @{ @"queued": @(IMExportStatusQueued), @"running": @(IMExportStatusRunning), @"done": @(IMExportStatusDone),
                              @"failed": @(IMExportStatusFailed), @"canceled": @(IMExportStatusCanceled), @"expired": @(IMExportStatusExpired) };
    for (NSString *k in expect) { XCTAssertEqual(IMExportStatusFromString(k), [expect[k] integerValue], @"%@", k); }
    XCTAssertEqual(IMExportStatusFromString(@"nope"), IMExportStatusUnknown);
    XCTAssertEqual(IMExportStatusFromString(nil), IMExportStatusUnknown);
}

#pragma mark - 状态机映射

- (void)test_任务到页面状态 {
    NSDate *now = [NSDate dateWithTimeIntervalSince1970:1.8e9];
    NSNumber *future = @((int64_t)(1.8e9 + 1000) * 1000), *past = @((int64_t)(1.8e9 - 1000) * 1000);
    XCTAssertEqual(IMExportViewStateForJob(nil, now), IMExportViewStateConfig);
    XCTAssertEqual(IMExportViewStateForJob([self jobWithStatus:@"queued" extra:@{}], now), IMExportViewStateRunning);
    XCTAssertEqual(IMExportViewStateForJob([self jobWithStatus:@"running" extra:@{}], now), IMExportViewStateRunning);
    XCTAssertEqual(IMExportViewStateForJob([self jobWithStatus:@"done" extra:@{ @"expires_at": future }], now), IMExportViewStateDone);
    XCTAssertEqual(IMExportViewStateForJob([self jobWithStatus:@"done" extra:@{}], now), IMExportViewStateDone);
    XCTAssertEqual(IMExportViewStateForJob([self jobWithStatus:@"done" extra:@{ @"expires_at": past }], now), IMExportViewStateConfig);
    XCTAssertEqual(IMExportViewStateForJob([self jobWithStatus:@"failed" extra:@{}], now), IMExportViewStateFailed);
    XCTAssertEqual(IMExportViewStateForJob([self jobWithStatus:@"canceled" extra:@{}], now), IMExportViewStateConfig);
    XCTAssertEqual(IMExportViewStateForJob([self jobWithStatus:@"expired" extra:@{}], now), IMExportViewStateConfig);
    XCTAssertEqual(IMExportViewStateForJob([self jobWithStatus:@"???" extra:@{}], now), IMExportViewStateConfig);
}

- (void)test_综合状态_冷却与失败确认 {
    NSDate *now = [NSDate dateWithTimeIntervalSince1970:1000];
    NSDate *later = [NSDate dateWithTimeIntervalSince1970:5000], *earlier = [NSDate dateWithTimeIntervalSince1970:100];
    IMExportJob *failed = [self jobWithStatus:@"failed" extra:@{}];
    IMExportJob *running = [self jobWithStatus:@"running" extra:@{}];
    XCTAssertEqual(IMExportResolveViewState(nil, nil, later, now), IMExportViewStateCooldown);
    XCTAssertEqual(IMExportResolveViewState(nil, nil, earlier, now), IMExportViewStateConfig, @"冷却到点回配置");
    XCTAssertEqual(IMExportResolveViewState(running, nil, later, now), IMExportViewStateRunning, @"任务态优先于冷却");
    XCTAssertEqual(IMExportResolveViewState(failed, nil, nil, now), IMExportViewStateFailed);
    XCTAssertEqual(IMExportResolveViewState(failed, @"j1", nil, now), IMExportViewStateConfig, @"点过重试 → 回配置");
    XCTAssertEqual(IMExportResolveViewState(failed, @"other", nil, now), IMExportViewStateFailed);
    XCTAssertEqual(IMExportResolveViewState(failed, @"j1", later, now), IMExportViewStateCooldown);
}

#pragma mark - 冷却小时数 / 按钮 / 进度

- (void)test_冷却小时数向上取整且至少1 {
    XCTAssertEqual(IMExportCooldownHours(0), 1);
    XCTAssertEqual(IMExportCooldownHours(-5), 1);
    XCTAssertEqual(IMExportCooldownHours(1), 1);
    XCTAssertEqual(IMExportCooldownHours(3600), 1);
    XCTAssertEqual(IMExportCooldownHours(3601), 2);
    XCTAssertEqual(IMExportCooldownHours(18 * 3600 - 1), 18);
    XCTAssertEqual(IMExportCooldownHours(86400), 24);
}

- (void)test_开始按钮可用性规则 {
    XCTAssertTrue(IMExportCanStart(@"pw", YES, YES, NO, NO));
    XCTAssertTrue(IMExportCanStart(@"pw", YES, NO, NO, NO));
    XCTAssertTrue(IMExportCanStart(@"pw", NO, YES, NO, NO));
    XCTAssertFalse(IMExportCanStart(@"", YES, YES, NO, NO), @"密码空");
    XCTAssertFalse(IMExportCanStart(nil, YES, YES, NO, NO));
    XCTAssertFalse(IMExportCanStart(@"pw", NO, NO, NO, NO), @"两种格式都未勾");
    XCTAssertFalse(IMExportCanStart(@"pw", YES, YES, YES, NO), @"请求中");
    XCTAssertFalse(IMExportCanStart(@"pw", YES, YES, NO, YES), @"冷却中");
}

- (void)test_进度比例夹取 {
    XCTAssertEqualWithAccuracy(IMExportProgressFraction(3, 12), 0.25, 0.0001);
    XCTAssertEqual(IMExportProgressFraction(5, 0), 0);
    XCTAssertEqual(IMExportProgressFraction(15, 12), 1);
    XCTAssertEqual(IMExportProgressFraction(-1, 12), 0);
}

#pragma mark - 下载地址 / 文案

- (void)test_下载地址拼接 {
    NSURL *u = IMExportDownloadURL(@"/api/v1/exports/download?t=abc.def", @"10.0.0.5:8080");
    XCTAssertEqualObjects(u.host, @"10.0.0.5");
    XCTAssertEqualObjects(u.port, @8080);
    XCTAssertEqualObjects(u.path, @"/api/v1/exports/download");
    XCTAssertEqualObjects(u.query, @"t=abc.def");
    XCTAssertNil(IMExportDownloadURL(@"https://cdn.example.com/x.zip?t=1", @"h:1"), @"外域绝对地址一律拒绝");
    XCTAssertNil(IMExportDownloadURL(@"http://evil.test:8080/x.zip", @"10.0.0.5:8080"));
    XCTAssertNil(IMExportDownloadURL(@"https://10.0.0.5:9999/x.zip", @"10.0.0.5:8080"), @"端口不同也不是本服务器");
    NSString *own = [IMServerEndpoint.shared absoluteURLStringForHost:@"10.0.0.5:8080" relativePath:@"/api/v1/exports/download?t=1"];
    XCTAssertEqualObjects(IMExportDownloadURL(own, @"10.0.0.5:8080").absoluteString, own, @"本服务器的绝对地址放行");
    XCTAssertNil(IMExportDownloadURL(@"", @"h:1"));
    XCTAssertNil(IMExportDownloadURL(nil, @"h:1"));
    XCTAssertNil(IMExportDownloadURL(@"/x", @""), @"没有服务器地址");
    XCTAssertNil(IMExportDownloadURL(@"relative/no-slash", @"h:1"));
}

- (void)test_文件名与摘要 {
    IMExportJob *job = [self jobWithStatus:@"done" extra:@{ @"finished_at": @1761469200000,
        @"result": @{ @"size_bytes": @1000000, @"conv_count": @12, @"msg_count": @8431 } }];
    XCTAssertTrue([IMExportFileName(job, NSDate.date) hasPrefix:@"im-export-2025"]);
    XCTAssertTrue([IMExportFileName(job, NSDate.date) hasSuffix:@".zip"]);
    XCTAssertTrue([IMExportFileName(nil, NSDate.date) hasPrefix:@"im-export-"]);
    NSString *s = IMExportSummaryText(job);
    NSString *digits = [s stringByReplacingOccurrencesOfString:@"," withString:@""];
    XCTAssertTrue([digits containsString:@"12"] && [digits containsString:@"8431"], @"%@", s);
    XCTAssertNil(IMExportExpiresText([self jobWithStatus:@"done" extra:@{}]));
    XCTAssertNotNil(IMExportExpiresText([self jobWithStatus:@"done" extra:@{ @"expires_at": @1761555600000 }]));
}

#pragma mark - REST

- (void)test_冷却错误码保留并带retry_after_sec {
    sExpResp = @{ @"code": @200011, @"message": @"cooldown", @"data": @{ @"retry_after_sec": @3700 } };
    XCTestExpectation *e = [self expectationWithDescription:@"start"];
    [IMHTTPService.sharedService startExportWithToken:@"t" password:@"pw" includeMedia:NO formats:@[@"html"]
                                           completion:^(IMExportJob *job, NSError *err) {
        XCTAssertNil(job);
        XCTAssertEqual(err.code, IMErrCodeExportCooldown);
        XCTAssertEqualObjects(err.userInfo[IMErrorRetryAfterSecKey], @3700);
        XCTAssertTrue(err.localizedDescription.length > 0);
        XCTAssertFalse([err.localizedDescription isEqualToString:@"cooldown"], @"应走本地化文案而非服务端原文");
        [e fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
    XCTAssertEqualObjects(sExpPath, @"/api/v1/users/me/exports");
}

- (void)test_繁忙与密码错保留业务码 {
    for (NSNumber *code in @[@200010, @200002]) {
        sExpResp = @{ @"code": code, @"message": @"x" };
        XCTestExpectation *e = [self expectationWithDescription:code.stringValue];
        [IMHTTPService.sharedService startExportWithToken:@"t" password:@"pw" includeMedia:YES formats:@[@"html", @"json"]
                                               completion:^(IMExportJob *job, NSError *err) {
            XCTAssertNil(job);
            XCTAssertEqual(err.code, code.integerValue);
            XCTAssertNil(err.userInfo[IMErrorRetryAfterSecKey]);
            [e fulfill];
        }];
        [self waitForExpectationsWithTimeout:5 handler:nil];
    }
}

- (void)test_latest无任务回nil且无错 {
    sExpResp = @{ @"code": @0, @"data": [NSNull null] };
    XCTestExpectation *e = [self expectationWithDescription:@"latest"];
    [IMHTTPService.sharedService fetchLatestExportWithToken:@"t" completion:^(IMExportJob *job, NSError *err) {
        XCTAssertNil(job); XCTAssertNil(err);
        [e fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
    XCTAssertEqualObjects(sExpPath, @"/api/v1/users/me/exports/latest");
}

- (void)test_latest解析任务_download_url与cancel路径 {
    sExpResp = @{ @"code": @0, @"data": @{ @"id": @"j7", @"status": @"running", @"progress": @{ @"done_convs": @3, @"total_convs": @12 } } };
    XCTestExpectation *e1 = [self expectationWithDescription:@"latest"];
    [IMHTTPService.sharedService fetchLatestExportWithToken:@"t" completion:^(IMExportJob *job, NSError *err) {
        XCTAssertEqualObjects(job.jobID, @"j7"); XCTAssertEqual(job.doneConvs, 3);
        [e1 fulfill];
    }];
    [self waitForExpectations:@[e1] timeout:5];
    sExpResp = @{ @"code": @0, @"data": @{ @"url": @"/api/v1/exports/download?t=zz", @"expires_in": @600 } };
    XCTestExpectation *e2 = [self expectationWithDescription:@"url"];
    [IMHTTPService.sharedService exportDownloadURLForJob:@"j7" token:@"t" completion:^(NSString *url, NSError *err) {
        XCTAssertEqualObjects(url, @"/api/v1/exports/download?t=zz"); XCTAssertNil(err);
        [e2 fulfill];
    }];
    [self waitForExpectations:@[e2] timeout:5];
    XCTAssertEqualObjects(sExpPath, @"/api/v1/users/me/exports/j7/download_url");
    sExpResp = @{ @"code": @0, @"data": @{} };
    XCTestExpectation *e3 = [self expectationWithDescription:@"cancel"];
    [IMHTTPService.sharedService cancelExport:@"j7" token:@"t" completion:^(NSError *err) { XCTAssertNil(err); [e3 fulfill]; }];
    [self waitForExpectations:@[e3] timeout:5];
    XCTAssertEqualObjects(sExpPath, @"/api/v1/users/me/exports/j7/cancel");
}

- (void)test_download_url缺url字段算失败 {
    sExpResp = @{ @"code": @0, @"data": @{ @"expires_in": @600 } };
    XCTestExpectation *e = [self expectationWithDescription:@"url"];
    [IMHTTPService.sharedService exportDownloadURLForJob:@"j7" token:@"t" completion:^(NSString *url, NSError *err) {
        XCTAssertNil(url); XCTAssertNotNil(err);
        [e fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

#pragma mark - 页面各态可见性

- (IMExportDataViewController *)loadedVC {
    IMExportDataViewController *vc = [[IMExportDataViewController alloc] initWithHost:@"127.0.0.1:59391" userID:@"u1"];
    [vc loadViewIfNeeded];
    return vc;
}

- (void)applyJob:(IMExportJob *)job toVC:(IMExportDataViewController *)vc {
    [vc setValue:job forKey:@"job"];
    [vc render];
}

- (void)test_页面各态按钮可见性 {
    IMExportDataViewController *vc = [self loadedVC];
    UIButton *start = [vc valueForKey:@"startButton"], *cancel = [vc valueForKey:@"cancelButton"];
    UIButton *download = [vc valueForKey:@"downloadButton"], *retry = [vc valueForKey:@"retryButton"];
    XCTAssertFalse(start.hidden); XCTAssertFalse(start.enabled, @"配置态密码空 → 置灰");
    XCTAssertTrue(cancel.hidden); XCTAssertTrue(download.hidden); XCTAssertTrue(retry.hidden);

    [self applyJob:[self jobWithStatus:@"running" extra:@{ @"progress": @{ @"done_convs": @3, @"total_convs": @12 } }] toVC:vc];
    XCTAssertTrue(start.hidden); XCTAssertFalse(cancel.hidden); XCTAssertTrue(download.hidden);
    UIProgressView *bar = [vc valueForKey:@"progressView"];
    XCTAssertEqualWithAccuracy(bar.progress, 0.25, 0.001);

    [self applyJob:[self jobWithStatus:@"done" extra:@{ @"result": @{ @"size_bytes": @1, @"conv_count": @1, @"msg_count": @2 } }] toVC:vc];
    XCTAssertFalse(download.hidden); XCTAssertTrue(cancel.hidden); XCTAssertTrue(start.hidden);

    [self applyJob:[self jobWithStatus:@"failed" extra:@{}] toVC:vc];
    XCTAssertFalse(retry.hidden); XCTAssertTrue(download.hidden);
    [retry sendActionsForControlEvents:UIControlEventTouchUpInside];
    XCTAssertTrue(retry.hidden); XCTAssertFalse(start.hidden, @"重试 → 回配置态");
}

- (void)test_页面冷却态按钮置灰且显示小时数 {
    IMExportDataViewController *vc = [self loadedVC];
    [vc setValue:[NSDate dateWithTimeIntervalSinceNow:5 * 3600 - 10] forKey:@"cooldownUntil"];
    [vc render];
    UIButton *start = [vc valueForKey:@"startButton"];
    XCTAssertFalse(start.hidden); XCTAssertFalse(start.enabled);
    UILabel *cool = [vc valueForKey:@"cooldownLabel"];
    XCTAssertFalse(cool.superview.hidden);
    XCTAssertTrue([cool.text containsString:@"5"], @"%@", cool.text);
}

- (void)test_下载失败码_服务端token失效回401也算已失效 {
    XCTAssertTrue(IMExportDownloadFailureIsGone(401), @"服务端 TokenInvalid(100101) 映射 HTTP 401");
    XCTAssertTrue(IMExportDownloadFailureIsGone(403));
    XCTAssertTrue(IMExportDownloadFailureIsGone(404));
    XCTAssertTrue(IMExportDownloadFailureIsGone(410));
    XCTAssertFalse(IMExportDownloadFailureIsGone(500));
    XCTAssertFalse(IMExportDownloadFailureIsGone(-1), @"传输层失败可直接重试，不算失效");
    XCTAssertFalse(IMExportDownloadFailureIsGone(-2));
}

- (void)test_旧epoch的latest回包不落地 {
    XCTAssertTrue(IMExportShouldApplyLatest(3, 3));
    XCTAssertFalse(IMExportShouldApplyLatest(3, 4), @"开始导出后，更早发出的 latest 是旧状态");
}

- (void)test_开始导出成功推进epoch且旧回包不覆盖进行中任务 {
    IMExportDataViewController *vc = [self loadedVC];
    NSUInteger before = [[vc valueForKey:@"stateEpoch"] unsignedIntegerValue];
    [vc setValue:@YES forKey:@"fetching"];
    [vc startSucceededWithJob:[self jobWithStatus:@"running" extra:@{}]];
    XCTAssertEqual([[vc valueForKey:@"stateEpoch"] unsignedIntegerValue], before + 1);
    // 旧回包（发起时 epoch=before）：无任务 → 不得把页面打回配置态
    [vc latestFinishedWithJob:nil error:nil epoch:before];
    UIButton *cancel = [vc valueForKey:@"cancelButton"];
    XCTAssertFalse(cancel.hidden, @"仍在进行中态");
    XCTAssertNotNil([vc valueForKey:@"job"]);
    [vc stopPolling];
}

#pragma mark - 冷却由 finished_at 推出 / pendingRefresh / 分享落点

- (void)test_冷却截止由latest任务的finished_at加24h推出 {
    NSDate *now = [NSDate date];
    int64_t nowMs = (int64_t)([now timeIntervalSince1970] * 1000);
    int64_t ago2h = nowMs - 2 * 3600 * 1000, ago25h = nowMs - 25 * 3600 * 1000;
    IMExportJob *expired = [self jobWithStatus:@"expired" extra:@{ @"finished_at": @(ago2h) }];
    XCTAssertEqual(IMExportResolveViewState(expired, nil, nil, now), IMExportViewStateCooldown, @"重启后无本地冷却，也由任务推出");
    XCTAssertEqualWithAccuracy([IMExportCooldownUntil(expired, nil, now) timeIntervalSinceDate:now], 22 * 3600, 2);
    IMExportJob *old = [self jobWithStatus:@"expired" extra:@{ @"finished_at": @(ago25h) }];
    XCTAssertEqual(IMExportResolveViewState(old, nil, nil, now), IMExportViewStateConfig, @"已过 24h 回配置态");
    XCTAssertNil(IMExportCooldownUntil(old, nil, now));
    IMExportJob *doneGone = [self jobWithStatus:@"done" extra:@{ @"finished_at": @(ago2h), @"expires_at": @(ago2h + 1000) }];
    XCTAssertEqual(IMExportResolveViewState(doneGone, nil, nil, now), IMExportViewStateCooldown, @"done 但文件已过期：同 Web 仍按 finished_at 冷却");
    XCTAssertNil(IMExportCooldownUntil([self jobWithStatus:@"failed" extra:@{ @"finished_at": @(ago2h) }], nil, now));
    XCTAssertNil(IMExportCooldownUntil([self jobWithStatus:@"canceled" extra:@{ @"finished_at": @(ago2h) }], nil, now));
    XCTAssertNil(IMExportCooldownUntil([self jobWithStatus:@"expired" extra:@{}], nil, now), @"无 finished_at 不推");
    NSDate *local = [now dateByAddingTimeInterval:23 * 3600];
    XCTAssertEqualObjects(IMExportCooldownUntil(expired, local, now), local, @"本地更晚取较大者");
    XCTAssertEqualObjects(IMExportCooldownUntil(nil, local, now), local);
    XCTAssertNil(IMExportCooldownUntil(nil, [now dateByAddingTimeInterval:-5], now), @"本地冷却已过期");
}

- (void)test_页面重启后进页由任务推出冷却态 {
    IMExportDataViewController *vc = [self loadedVC];
    int64_t ago2h = (int64_t)([NSDate date].timeIntervalSince1970 * 1000) - 2 * 3600 * 1000;
    [self applyJob:[self jobWithStatus:@"expired" extra:@{ @"finished_at": @(ago2h) }] toVC:vc];
    XCTAssertNil([vc valueForKey:@"cooldownUntil"], @"内存里没有本地冷却");
    UILabel *cool = [vc valueForKey:@"cooldownLabel"];
    XCTAssertFalse(cool.superview.hidden);
    XCTAssertTrue([cool.text containsString:@"22"], @"%@", cool.text);
    UIButton *start = [vc valueForKey:@"startButton"];
    XCTAssertFalse(start.enabled);
}

- (void)test_在途请求时refreshLatest置pendingRefresh且结束后补发一次 {
    IMExportDataViewController *vc = [self loadedVC];
    [vc setValue:@YES forKey:@"fetching"];
    [vc refreshLatest];
    XCTAssertTrue([[vc valueForKey:@"pendingRefresh"] boolValue], @"在途时不丢，记下补发");
    NSUInteger epoch = [[vc valueForKey:@"stateEpoch"] unsignedIntegerValue];
    [vc latestFinishedWithJob:nil error:nil epoch:epoch];
    XCTAssertFalse([[vc valueForKey:@"pendingRefresh"] boolValue]);
    XCTAssertTrue([[vc valueForKey:@"fetching"] boolValue], @"已补发一次新请求");
}

- (void)test_分享面板落点取最上层可展示VC {
    UIViewController *root = [UIViewController new];
    XCTAssertEqual([IMExportDataViewController topPresentableFrom:root], root);
    XCTAssertNil([IMExportDataViewController topPresentableFrom:nil]);
    UIWindow *w = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
    w.rootViewController = root; [w makeKeyAndVisible];
    UIViewController *a = [UIViewController new];
    [root presentViewController:a animated:NO completion:nil];
    XCTAssertEqual([IMExportDataViewController topPresentableFrom:root], a, @"已有 presented 时落到它上面");
}

@end
