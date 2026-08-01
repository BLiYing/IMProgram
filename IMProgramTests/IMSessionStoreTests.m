#import <XCTest/XCTest.h>

#import "IMSessionStore.h"

@interface IMSessionStoreTests : XCTestCase
@end

@implementation IMSessionStoreTests

- (void)setUp {
    [super setUp];
    [IMSessionStore clear];
}

- (void)tearDown {
    [IMSessionStore clear];
    [super tearDown];
}

- (void)testSavedSessionRemainsAvailableWithoutNetworkToken {
    [IMSessionStore saveHost:@"http://127.0.0.1:1" userID:@"offline-user" password:@"secret"];

    XCTAssertTrue(IMSessionStore.hasSession);
    XCTAssertEqualObjects(IMSessionStore.host, @"http://127.0.0.1:1");
    XCTAssertEqualObjects(IMSessionStore.userID, @"offline-user");
    XCTAssertEqualObjects(IMSessionStore.password, @"secret");
}

@end
