#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMViewedMediaStore.h"

/// 「看过」登记：按账号隔离 / 重启仍在（同一 defaults 新建实例）/ 末 500 条封顶 / 清空 / 幂等通知。
@interface IMViewedMediaStoreTests : XCTestCase
@end

@implementation IMViewedMediaStoreTests {
    NSUserDefaults *_defaults;
    NSString *_suite;
}

- (void)setUp {
    [super setUp];
    _suite = [NSString stringWithFormat:@"im.test.viewed.%@", NSUUID.UUID.UUIDString];
    _defaults = [[NSUserDefaults alloc] initWithSuiteName:_suite];
}

- (void)tearDown {
    [_defaults removePersistentDomainForName:_suite];
    [super tearDown];
}

- (IMViewedMediaStore *)storeForUser:(NSString *)uid {
    IMViewedMediaStore *s = [[IMViewedMediaStore alloc] initWithDefaults:_defaults];
    s.userIDProvider = ^NSString *{ return uid; };
    return s;
}

- (void)testMarkAndHitAndIdempotent {
    IMViewedMediaStore *s = [self storeForUser:@"u1"];
    XCTAssertFalse([s isViewedURL:@"http://h/a.jpg"]);
    [s markViewedURL:@"http://h/a.jpg"];
    [s markViewedURL:@"http://h/a.jpg"];
    XCTAssertTrue([s isViewedURL:@"http://h/a.jpg"]);
    XCTAssertEqual([[_defaults arrayForKey:@"im.viewedMedia.u1"] count], 1u);
}

- (void)testPersistsAcrossInstances {
    [[self storeForUser:@"u1"] markViewedURL:@"http://h/a.jpg"];
    XCTAssertTrue([[self storeForUser:@"u1"] isViewedURL:@"http://h/a.jpg"]); // 重启后仍在
}

- (void)testIsolatedPerUserAndNoUserNoop {
    [[self storeForUser:@"u1"] markViewedURL:@"http://h/a.jpg"];
    XCTAssertFalse([[self storeForUser:@"u2"] isViewedURL:@"http://h/a.jpg"]);
    IMViewedMediaStore *anon = [self storeForUser:@""];
    [anon markViewedURL:@"http://h/b.jpg"];
    XCTAssertFalse([anon isViewedURL:@"http://h/b.jpg"]);  // 未登录不记
    [anon markViewedURL:nil];                              // 空 url 不崩
}

- (void)testCapKeepsNewest500 {
    IMViewedMediaStore *s = [self storeForUser:@"u1"];
    for (int i = 0; i < 502; i++) { [s markViewedURL:[NSString stringWithFormat:@"http://h/%d.jpg", i]]; }
    XCTAssertFalse([s isViewedURL:@"http://h/0.jpg"]);     // 最旧两条被挤掉
    XCTAssertFalse([s isViewedURL:@"http://h/1.jpg"]);
    XCTAssertTrue([s isViewedURL:@"http://h/2.jpg"]);
    XCTAssertTrue([s isViewedURL:@"http://h/501.jpg"]);
    XCTAssertEqual([[_defaults arrayForKey:@"im.viewedMedia.u1"] count], 500u);
}

- (void)testClearCurrentUserOnlyClearsThatUser {
    IMViewedMediaStore *s1 = [self storeForUser:@"u1"];
    IMViewedMediaStore *s2 = [self storeForUser:@"u2"];
    [s1 markViewedURL:@"http://h/a.jpg"];
    [s2 markViewedURL:@"http://h/a.jpg"];
    [s1 clearCurrentUser];
    XCTAssertFalse([s1 isViewedURL:@"http://h/a.jpg"]);
    XCTAssertTrue([[self storeForUser:@"u2"] isViewedURL:@"http://h/a.jpg"]);
    XCTAssertFalse([[self storeForUser:@"u1"] isViewedURL:@"http://h/a.jpg"]); // 磁盘也清了
}

@end
