//  IMFriendCacheWriterTests.m
//  好友快照落库的指纹窗口期（IMFriendCacheWriter）：通讯录首页与「我的好友」页先后拿到同一份名单只写一次；
//  一笔写入还在队列里时再来一份旧名单，不能被误判成「没变」而漏写。
//  app-hosted 测试，头文件按相对路径引入；落库用 im_setWriteOverrideForTesting: 换成计数替身，不碰真库。

#import <XCTest/XCTest.h>

#import "../IMProgram/Modules/Contacts/IMFriendCacheWriter.h"
#import "../IMProgram/Models/IMUserCard.h"
#import "../IMProgram/Database/IMDatabase.h"

@interface IMFriendCacheWriter (Testing)
+ (void)im_setWriteOverrideForTesting:(nullable BOOL (^)(NSArray<IMUserCard *> *friends, IMDatabaseAccountContext *context))writeOverride;
@end

@interface IMFriendCacheWriterTests : XCTestCase
@property (nonatomic, strong) NSMutableArray<NSArray<NSString *> *> *writes; // 每笔写入的 userID 列表
@property (nonatomic, strong) dispatch_semaphore_t gate;                       // 非 nil 时写入先卡在这里
@property (nonatomic, assign) BOOL failWrites;
@property (nonatomic, strong) IMDatabaseAccountContext *context;
@end

@implementation IMFriendCacheWriterTests

- (void)setUp {
    [super setUp];
    self.writes = [NSMutableArray array];
    // 指纹只按指针认账号上下文；替身不碰库，随便一个对象当「同一代账号」即可。
    self.context = (IMDatabaseAccountContext *)[NSObject new];
    __weak typeof(self) weakSelf = self;
    [IMFriendCacheWriter im_setWriteOverrideForTesting:^BOOL(NSArray<IMUserCard *> *friends, IMDatabaseAccountContext *context) {
        __strong typeof(weakSelf) self = weakSelf;
        dispatch_semaphore_t gate = self.gate;
        if (gate) { dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER); }
        @synchronized (self) { [self.writes addObject:[friends valueForKey:@"userID"]]; }
        return !self.failWrites;
    }];
}

- (void)tearDown {
    if (self.gate) { dispatch_semaphore_signal(self.gate); }
    [self drainWrites];
    [IMFriendCacheWriter im_setWriteOverrideForTesting:nil];
    [super tearDown];
}

- (NSArray<IMUserCard *> *)friends:(NSArray<NSString *> *)uids {
    NSMutableArray *dicts = [NSMutableArray array];
    for (NSString *uid in uids) { [dicts addObject:@{ @"user_id": uid, @"nickname": uid, @"status": @"accepted" }]; }
    return [IMUserCard cardsFromArray:dicts];
}

/// 等写队列排空、且写完后的主线程收尾（升级 / 清除待写指纹）也跑完。
- (void)drainWrites {
    XCTestExpectation *e = [self expectationWithDescription:@"drain"];
    dispatch_queue_t q = dispatch_queue_create("drain-probe", DISPATCH_QUEUE_SERIAL);
    // 写队列是私有的：轮询主队列直到计数稳定一小会儿即可（替身写入是同步的，几十毫秒内必然完成）。
    dispatch_async(q, ^{
        [NSThread sleepForTimeInterval:0.2];
        dispatch_async(dispatch_get_main_queue(), ^{
            dispatch_async(dispatch_get_main_queue(), ^{ [e fulfill]; });
        });
    });
    [self waitForExpectations:@[e] timeout:5];
}

- (NSUInteger)writeCount {
    @synchronized (self) { return self.writes.count; }
}

/// 首页与「我的好友」页先后拿到同一份名单（第一笔还没写完）：只写一次。
- (void)testSameRosterFromTwoPagesIsWrittenOnce {
    self.gate = dispatch_semaphore_create(0); // 卡住第一笔，制造「待写」窗口
    [IMFriendCacheWriter persistFriendsIfChanged:[self friends:@[@"u1", @"u2"]] context:self.context];
    [IMFriendCacheWriter persistFriendsIfChanged:[self friends:@[@"u1", @"u2"]] context:self.context];
    dispatch_semaphore_signal(self.gate);
    self.gate = nil;
    [self drainWrites];
    XCTAssertEqual(self.writeCount, 1u, @"同一份名单在待写期间再来，应与待写指纹比出「没变」");

    [IMFriendCacheWriter persistFriendsIfChanged:[self friends:@[@"u1", @"u2"]] context:self.context];
    [self drainWrites];
    XCTAssertEqual(self.writeCount, 1u, @"写成之后同一份名单仍不重写");
}

/// 库里是 A，新名单 B 还在队列里时又来一份 A（如另一页拿着旧结果）：必须再写 A，否则库最终停在 B。
- (void)testOldRosterArrivingWhileNewOneIsPendingIsNotSkipped {
    [IMFriendCacheWriter persistFriendsIfChanged:[self friends:@[@"u1"]] context:self.context];
    [self drainWrites];
    XCTAssertEqual(self.writeCount, 1u);

    self.gate = dispatch_semaphore_create(0);
    [IMFriendCacheWriter persistFriendsIfChanged:[self friends:@[@"u1", @"u2"]] context:self.context]; // B 待写
    [IMFriendCacheWriter persistFriendsIfChanged:[self friends:@[@"u1"]] context:self.context];        // 又来 A
    dispatch_semaphore_signal(self.gate);
    dispatch_semaphore_signal(self.gate);
    self.gate = nil;
    [self drainWrites];
    XCTAssertEqual(self.writeCount, 3u);
    XCTAssertEqualObjects(self.writes.lastObject, (@[@"u1"]), @"按发起顺序落库，最后一笔是 A");
}

/// 写失败回退：库里还是上一份，同一名单下次要重试。
- (void)testFailedWriteIsRetriedNextTime {
    self.failWrites = YES;
    [IMFriendCacheWriter persistFriendsIfChanged:[self friends:@[@"u1"]] context:self.context];
    [self drainWrites];
    XCTAssertEqual(self.writeCount, 1u);
    self.failWrites = NO;
    [IMFriendCacheWriter persistFriendsIfChanged:[self friends:@[@"u1"]] context:self.context];
    [self drainWrites];
    XCTAssertEqual(self.writeCount, 2u, @"失败后不能把它当成已写入");
}

@end
