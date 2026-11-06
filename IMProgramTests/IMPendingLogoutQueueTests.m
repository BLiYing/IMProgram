//  IMPendingLogoutQueueTests.m
//  退出登录吊销的持久化重试（LOGOUT_REVOKE_RETRY_DESIGN）。存储和发送都注入，不碰网络与真 Keychain；
//  Keychain 实现单独一条往返用例。

#import <XCTest/XCTest.h>

#import "IMHTTPService+Private.h"
#import "IMPendingLogoutQueue.h"

@interface IMPLFakeStorage : NSObject <IMPendingLogoutStorage>
@property (nonatomic, strong, nullable) NSData *data;
@property (nonatomic, assign) BOOL readFails;
@property (nonatomic, assign) BOOL writeFails;
@end

@implementation IMPLFakeStorage
- (BOOL)readData:(NSData **)data {
    if (self.readFails) { return NO; }
    *data = self.data;
    return YES;
}
- (BOOL)writeData:(NSData *)data {
    if (self.writeFails) { return NO; }
    self.data = data;
    return YES;
}
@end

@interface IMPendingLogoutQueueTests : XCTestCase
@property (nonatomic, strong) IMPLFakeStorage *storage;
@property (nonatomic, strong) NSMutableArray<NSString *> *sentTokens;
@property (nonatomic, strong) NSMutableArray<NSURL *> *sentURLs;
@property (nonatomic, strong, nullable) NSError *nextError;
/// 非空时只对这枚凭据返回 nextError，其余成功。
@property (nonatomic, copy, nullable) NSString *errorOnlyForToken;
@end

@implementation IMPendingLogoutQueueTests

- (void)setUp {
    [super setUp];
    self.storage = [IMPLFakeStorage new];
    self.sentTokens = [NSMutableArray array];
    self.sentURLs = [NSMutableArray array];
    self.nextError = nil;
    self.errorOnlyForToken = nil;
}

- (IMPendingLogoutQueue *)makeQueue {
    __weak typeof(self) weakSelf = self;
    IMPendingLogoutQueue *queue = [[IMPendingLogoutQueue alloc] initWithStorage:self.storage
                                                                         sender:^(NSString *token, NSURL *url, void (^completion)(NSError *)) {
        typeof(self) self = weakSelf;
        [self.sentTokens addObject:token];
        [self.sentURLs addObject:url];
        BOOL applies = self.errorOnlyForToken.length == 0 || [self.errorOnlyForToken isEqualToString:token];
        completion(applies ? self.nextError : nil);
    }];
    queue.retryInterval = 3600; // 用例里不靠定时重试，靠显式 flush
    return queue;
}

- (NSURL *)url {
    return [NSURL URLWithString:@"https://im.example.com/api/v1/logout/refresh"];
}

- (NSError *)networkError {
    return [IMHTTPService.sharedService errorWithMessage:@"offline"];
}

- (NSError *)bizError:(NSInteger)code {
    return [IMHTTPService.sharedService errorWithCode:code message:@"x"];
}

#pragma mark - 重试判定

- (void)testShouldRetryClassification {
    XCTAssertFalse(IMPendingLogoutShouldRetry(nil));
    XCTAssertTrue(IMPendingLogoutShouldRetry([self networkError]));
    XCTAssertTrue(IMPendingLogoutShouldRetry([NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]));
    XCTAssertTrue(IMPendingLogoutShouldRetry([self bizError:100002]), @"限流");
    XCTAssertTrue(IMPendingLogoutShouldRetry([self bizError:100003]), @"服务端内部错误");
    XCTAssertFalse(IMPendingLogoutShouldRetry([self bizError:100001]), @"参数错误，重试也不会好");
    XCTAssertFalse(IMPendingLogoutShouldRetry([self bizError:100101]));
}

#pragma mark - 主流程

- (void)testSuccessRemovesCredentialFromStorage {
    IMPendingLogoutQueue *queue = [self makeQueue];
    [queue enqueueRefreshToken:@"t1" url:[self url]];
    XCTAssertEqualObjects(self.sentTokens, @[@"t1"]);
    XCTAssertEqualObjects(self.sentURLs, @[[self url]]);
    XCTAssertEqual(queue.pendingCount, 0u);
    XCTAssertNil(self.storage.data, @"成功后不能留着凭据");
}

- (void)testNetworkFailureKeepsCredentialThenRetrySucceeds {
    self.nextError = [self networkError];
    IMPendingLogoutQueue *queue = [self makeQueue];
    [queue enqueueRefreshToken:@"t1" url:[self url]];
    XCTAssertEqual(queue.pendingCount, 1u);
    XCTAssertNotNil(self.storage.data);

    self.nextError = nil;
    [queue flush];
    XCTAssertEqual(queue.pendingCount, 0u);
    XCTAssertNil(self.storage.data);
    XCTAssertEqual(self.sentTokens.count, 2u);
}

- (void)testServerRejectionDropsCredential {
    self.nextError = [self bizError:100001];
    IMPendingLogoutQueue *queue = [self makeQueue];
    [queue enqueueRefreshToken:@"t1" url:[self url]];
    XCTAssertEqual(queue.pendingCount, 0u);
    XCTAssertNil(self.storage.data);
}

/// 关键场景：断网退出后杀进程，下次启动（可能已换账号）仍能补吊销，且发往当初的服务器。
- (void)testCredentialSurvivesRestartAndKeepsOriginalServer {
    self.nextError = [self networkError];
    [[self makeQueue] enqueueRefreshToken:@"t1" url:[self url]];
    [self.sentTokens removeAllObjects];
    [self.sentURLs removeAllObjects];

    self.nextError = nil;
    IMPendingLogoutQueue *restarted = [self makeQueue];
    XCTAssertEqual(restarted.pendingCount, 1u);
    [restarted flush];
    XCTAssertEqualObjects(self.sentTokens, @[@"t1"]);
    XCTAssertEqualObjects(self.sentURLs, @[[self url]]);
    XCTAssertEqual(restarted.pendingCount, 0u);
}

- (void)testOneFailureDoesNotBlockOthers {
    self.nextError = [self networkError];
    self.errorOnlyForToken = @"down";
    IMPendingLogoutQueue *queue = [self makeQueue];
    [queue enqueueRefreshToken:@"down" url:[self url]];
    [queue enqueueRefreshToken:@"ok" url:[self url]];
    XCTAssertTrue([self.sentTokens containsObject:@"ok"]);
    XCTAssertEqual(queue.pendingCount, 1u, @"只留下失败的那条");
}

- (void)testExpiredCredentialIsDroppedWithoutSending {
    self.nextError = [self networkError];
    IMPendingLogoutQueue *queue = [self makeQueue];
    [queue enqueueRefreshToken:@"t1" url:[self url]];
    [self.sentTokens removeAllObjects];

    NSDate *later = [NSDate dateWithTimeIntervalSinceNow:181 * 24 * 3600];
    queue.now = ^{ return later; };
    [queue flush];
    XCTAssertEqual(self.sentTokens.count, 0u);
    XCTAssertEqual(queue.pendingCount, 0u);
    XCTAssertNil(self.storage.data);
}

- (void)testQueueSizeIsCapped {
    self.nextError = [self networkError];
    IMPendingLogoutQueue *queue = [self makeQueue];
    for (int i = 0; i < 20; i++) {
        [queue enqueueRefreshToken:[NSString stringWithFormat:@"t%d", i] url:[self url]];
    }
    XCTAssertEqual(queue.pendingCount, 16u);
}

#pragma mark - 存储失败

/// 设备未解锁时读 Keychain 会失败：不能把这当成空，否则下一次写会把已存的凭据覆盖掉。
- (void)testReadFailureDoesNotOverwriteStoredCredentials {
    self.nextError = [self networkError];
    [[self makeQueue] enqueueRefreshToken:@"old" url:[self url]];
    NSData *stored = self.storage.data;
    XCTAssertNotNil(stored);

    self.storage.readFails = YES;
    IMPendingLogoutQueue *queue = [self makeQueue];
    [queue enqueueRefreshToken:@"new" url:[self url]];
    XCTAssertEqualObjects(self.storage.data, stored, @"读失败期间不能写");

    self.storage.readFails = NO;
    XCTAssertEqual(queue.pendingCount, 2u, @"恢复后合并，两条都在");
    NSArray *persisted = [NSJSONSerialization JSONObjectWithData:self.storage.data options:0 error:NULL];
    XCTAssertEqual(persisted.count, 2u, @"合并结果要补写");
}

- (void)testWriteFailureStillRetriesFromMemory {
    self.storage.writeFails = YES;
    self.nextError = [self networkError];
    IMPendingLogoutQueue *queue = [self makeQueue];
    [queue enqueueRefreshToken:@"t1" url:[self url]];
    XCTAssertEqual(queue.pendingCount, 1u);

    self.nextError = nil;
    [queue flush];
    XCTAssertEqual(queue.pendingCount, 0u);
}

/// 发送途中又退出一次：不能漏发。
- (void)testEnqueueDuringFlushIsSent {
    NSMutableArray<void (^)(NSError *)> *completions = [NSMutableArray array];
    NSMutableArray<NSString *> *sent = [NSMutableArray array];
    IMPendingLogoutQueue *queue = [[IMPendingLogoutQueue alloc] initWithStorage:self.storage
                                                                         sender:^(NSString *token, NSURL *url, void (^completion)(NSError *)) {
        [sent addObject:token];
        [completions addObject:[completion copy]];
    }];
    [queue enqueueRefreshToken:@"t1" url:[self url]];
    [queue enqueueRefreshToken:@"t2" url:[self url]];
    XCTAssertEqualObjects(sent, @[@"t1"], @"一轮进行中，第二条先不发");

    completions[0](nil);
    XCTAssertEqualObjects(sent, (@[@"t1", @"t2"]));
    completions[1](nil);
    XCTAssertEqual(queue.pendingCount, 0u);
}

#pragma mark - Keychain

- (void)testKeychainStorageRoundTrip {
    IMPendingLogoutKeychainStorage *storage = [[IMPendingLogoutKeychainStorage alloc] initWithService:@"im.pendingLogout.tests"];
    [storage writeData:nil];
    NSData *payload = [@"payload" dataUsingEncoding:NSUTF8StringEncoding];
    if (![storage writeData:payload]) {
        XCTSkip(@"当前测试宿主没有 Keychain 权限（未签名）");
    }
    NSData *read = nil;
    XCTAssertTrue([storage readData:&read]);
    XCTAssertEqualObjects(read, payload);

    NSData *updated = [@"updated" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([storage writeData:updated], @"已存在时走更新");
    XCTAssertTrue([storage readData:&read]);
    XCTAssertEqualObjects(read, updated);

    XCTAssertTrue([storage writeData:nil]);
    XCTAssertTrue([storage readData:&read], @"不存在不算读失败");
    XCTAssertNil(read);
}

@end
