//  IMExportDownloaderTests.m
//  导出下载进度（DATA_EXPORT_DESIGN §1 下载中 / §5）：节流纯函数、回调线程、未知总长度、失败恢复、下载中卡片可见性。
//  下载用 NSURLProtocol 桩（IMExportDownloader setProtocolClassesForTesting:），不碰网络。

#import <XCTest/XCTest.h>

#import "IMExportDownloader.h"
#import "IMDataExport.h"
#import "IMExportDataViewController.h"

/// /dl-stub?status=200&len=known|unknown&chunks=N：每块 10KB，块间 sleep 3ms。
@interface IMDownloadStubProtocol : NSURLProtocol
@end
@implementation IMDownloadStubProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)r { return [r.URL.path isEqualToString:@"/dl-stub"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }
- (void)startLoading {
    NSURLComponents *c = [NSURLComponents componentsWithURL:self.request.URL resolvingAgainstBaseURL:NO];
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *i in c.queryItems) { q[i.name] = i.value; }
    NSInteger status = [q[@"status"] integerValue] ?: 200, chunks = [q[@"chunks"] integerValue] ?: 10;
    NSInteger chunk = 10 * 1024;
    BOOL known = ![q[@"len"] isEqualToString:@"unknown"];
    NSHTTPURLResponse *r = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:status HTTPVersion:@"HTTP/1.1"
        headerFields:known ? @{ @"Content-Length": [NSString stringWithFormat:@"%ld", (long)(chunk * chunks)] } : @{}];
    [self.client URLProtocol:self didReceiveResponse:r cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    NSData *d = [NSMutableData dataWithLength:chunk];
    for (NSInteger i = 0; i < chunks; i++) { [self.client URLProtocol:self didLoadData:d]; [NSThread sleepForTimeInterval:0.003]; }
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

@interface IMExportDataViewController (DLTestAccess)
- (void)render;
- (void)downloadFailedWithMessage:(NSString *)msg refresh:(BOOL)refresh;
@end

@interface IMExportDownloaderTests : XCTestCase
@end

@implementation IMExportDownloaderTests

- (void)setUp { [IMExportDownloader setProtocolClassesForTesting:@[IMDownloadStubProtocol.class]]; }
- (void)tearDown { [IMExportDownloader setProtocolClassesForTesting:nil]; }

- (NSURL *)stubURL:(NSString *)query { return [NSURL URLWithString:[@"http://stub.test/dl-stub?" stringByAppendingString:query]]; }

#pragma mark 节流

- (void)test_节流_首次必发_收齐必发_100ms或1百分点才发 {
    XCTAssertTrue(IMExportDownloadShouldEmitProgress(-1, 10, 0, 1, 1000), @"首次必发");
    XCTAssertFalse(IMExportDownloadShouldEmitProgress(10.00, 10.05, 100, 105, 1000), @"50ms 且 0.5% → 丢");
    XCTAssertTrue(IMExportDownloadShouldEmitProgress(10.00, 10.20, 100, 101, 1000), @"满 100ms → 发");
    XCTAssertTrue(IMExportDownloadShouldEmitProgress(10.00, 10.01, 100, 110, 1000), @"推进 1% → 发");
    XCTAssertTrue(IMExportDownloadShouldEmitProgress(10.00, 10.01, 995, 1000, 1000), @"收齐必发");
    XCTAssertFalse(IMExportDownloadShouldEmitProgress(10.00, 10.05, 100, 9000, -1), @"未知总长度只按时间节流");
    XCTAssertTrue(IMExportDownloadShouldEmitProgress(10.00, 10.20, 100, 101, -1));
}

#pragma mark 下载（桩）

- (void)test_已知总长度_进度主线程回调_节流且末次收齐_完成后不再回调 {
    XCTestExpectation *done = [self expectationWithDescription:@"done"];
    __block int count = 0; __block int64_t lastW = 0, lastE = 0; __block BOOL allMain = YES, afterDone = NO, completed = NO;
    [IMExportDownloader downloadFromURL:[self stubURL:@"chunks=200"] fileName:@"im-dl-test-1.zip"
        progress:^(int64_t w, int64_t e) {
            if (!NSThread.isMainThread) { allMain = NO; }
            if (completed) { afterDone = YES; }
            count++; lastW = w; lastE = e;
        } completion:^(NSURL *file, NSError *err) {
            XCTAssertTrue(NSThread.isMainThread); XCTAssertNil(err); XCTAssertNotNil(file);
            completed = YES;
            if (file) { [NSFileManager.defaultManager removeItemAtURL:file error:NULL]; }
            [done fulfill];
        }];
    [self waitForExpectationsWithTimeout:20 handler:nil];
    // 让可能残留的已排队 progress 块跑完，确认没有「完成后」的回调。
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    XCTAssertTrue(allMain, @"回调必须在主线程");
    XCTAssertFalse(afterDone, @"completion 之后不得再回调 progress");
    XCTAssertEqual(lastE, 200 * 10 * 1024);
    XCTAssertEqual(lastW, lastE, @"末次必须收齐");
    XCTAssertGreaterThan(count, 0);
    XCTAssertLessThan(count, 200, @"200 个分块被节流合并");
}

- (void)test_未知总长度_expected非正 {
    XCTestExpectation *done = [self expectationWithDescription:@"done"];
    __block BOOL sawProgress = NO, allUnknown = YES;
    [IMExportDownloader downloadFromURL:[self stubURL:@"len=unknown&chunks=20"] fileName:@"im-dl-test-2.zip"
        progress:^(int64_t w, int64_t e) { sawProgress = YES; if (e > 0) { allUnknown = NO; } }
        completion:^(NSURL *file, NSError *err) {
            XCTAssertNil(err);
            if (file) { [NSFileManager.defaultManager removeItemAtURL:file error:NULL]; }
            [done fulfill];
        }];
    [self waitForExpectationsWithTimeout:20 handler:nil];
    XCTAssertTrue(sawProgress); XCTAssertTrue(allUnknown, @"无 Content-Length → expected <= 0");
}

- (void)test_HTTP失败_给状态码错误且无文件 {
    XCTestExpectation *done = [self expectationWithDescription:@"done"];
    [IMExportDownloader downloadFromURL:[self stubURL:@"status=401&chunks=1"] fileName:@"im-dl-test-3.zip" progress:nil
        completion:^(NSURL *file, NSError *err) {
            XCTAssertNil(file);
            XCTAssertEqualObjects(err.domain, IMExportDownloadErrorDomain);
            XCTAssertEqual(err.code, 401);
            [done fulfill];
        }];
    [self waitForExpectationsWithTimeout:20 handler:nil];
}

- (void)test_取消_回NSURLErrorCancelled {
    XCTestExpectation *done = [self expectationWithDescription:@"done"];
    NSURLSessionDownloadTask *t = [IMExportDownloader downloadFromURL:[self stubURL:@"chunks=2000"] fileName:@"im-dl-test-4.zip" progress:nil
        completion:^(NSURL *file, NSError *err) {
            XCTAssertNil(file);
            XCTAssertEqualObjects(err.domain, NSURLErrorDomain);
            XCTAssertEqual(err.code, NSURLErrorCancelled);
            [done fulfill];
        }];
    [t cancel];
    [self waitForExpectationsWithTimeout:20 handler:nil];
}

#pragma mark 页面

- (IMExportDataViewController *)doneVC {
    IMExportDataViewController *vc = [[IMExportDataViewController alloc] initWithHost:@"10.0.0.5:8080" userID:@"u1"];
    [vc loadViewIfNeeded];
    IMExportJob *job = [IMExportJob jobFromJSON:@{ @"id": @"j1", @"status": @"done", @"expires_at": @(([NSDate.date timeIntervalSince1970] + 86400) * 1000),
        @"result": @{ @"size_bytes": @128000000, @"conv_count": @1, @"msg_count": @2 } }];
    [vc setValue:job forKey:@"job"];
    [vc render];
    return vc;
}

- (void)test_页面下载中_卡片与醒目提醒_隐藏下载按钮_失败恢复 {
    IMExportDataViewController *vc = [self doneVC];
    UIButton *download = [vc valueForKey:@"downloadButton"];
    UILabel *keep = [vc valueForKey:@"keepOpenLabel"], *detail = [vc valueForKey:@"dlDetail"];
    UIProgressView *bar = [vc valueForKey:@"dlProgress"];
    UIView *ind = [vc valueForKey:@"dlIndeterminate"];
    XCTAssertFalse(download.hidden); XCTAssertTrue(keep.superview.hidden, @"完成态不显示下载提醒");

    [vc setValue:@YES forKey:@"downloading"];
    [vc setValue:@(51200000) forKey:@"dlWritten"]; [vc setValue:@(128000000) forKey:@"dlExpected"];
    [vc setValue:@YES forKey:@"dlHasProgress"];
    [vc render];
    XCTAssertTrue(download.hidden, @"下载中隐藏「下载」按钮");
    XCTAssertFalse(keep.superview.hidden);
    XCTAssertTrue([[vc valueForKey:@"doneFootLabel"] superview].hidden, @"下载中不显示「文件将于…删除」页脚");
    XCTAssertEqual(keep.font.pointSize, 14);
    XCTAssertEqualObjects(keep.textColor, UIColor.systemRedColor);
    XCTAssertTrue(keep.font.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold);
    XCTAssertFalse(detail.hidden);
    XCTAssertTrue([detail.text containsString:@"/"] || [detail.text containsString:@" of "], @"%@", detail.text);
    XCTAssertEqualWithAccuracy(bar.progress, 0.4, 0.001);
    XCTAssertTrue(ind.hidden, @"已知长度不显示不定长滑块");

    [vc setValue:@(0) forKey:@"dlExpected"];  // 未知总长度
    [vc render];
    XCTAssertFalse(ind.hidden, @"未知总长度走不定长");
    XCTAssertFalse([detail.text containsString:@" of "]); XCTAssertFalse([detail.text containsString:@"/"]);

    [vc downloadFailedWithMessage:nil refresh:NO]; // 失败 → 回完成态
    XCTAssertFalse(download.hidden); XCTAssertTrue(keep.superview.hidden);
    XCTAssertEqual([[vc valueForKey:@"dlWritten"] longLongValue], 0, @"进度复位");
    XCTAssertTrue(ind.hidden);
}

@end
