//  IMChatFolderStoreTests.m
//  IMChatFolderStore 的整表替换语义：版本去重、按 position 排序、limits、落盘与换账号隔离、业务码文案。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMChatFolderStore.h"

static NSDictionary *Snap(int64_t version, NSArray *folders) {
    return @{ @"version": @(version), @"folders": folders };
}
static NSDictionary *F(NSString *fid, NSString *name, NSInteger pos, NSArray *convs) {
    return @{ @"id": fid, @"name": name, @"position": @(pos), @"conv_ids": convs };
}

@interface IMChatFolderStoreTests : XCTestCase
@end

@implementation IMChatFolderStoreTests

- (void)setUp {
    [super setUp];
    IMChatFolderStore *s = IMChatFolderStore.shared;
    [s adoptUserID:@"u_test_a"];
    [s resetForTesting];
    [s adoptUserID:@"u_test_a"];
}

- (void)tearDown {
    [IMChatFolderStore.shared resetForTesting];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"im.chatFolders.u_test_b"];
    [super tearDown];
}

- (void)testAppliesAndSortsByPosition {
    IMChatFolderStore *s = IMChatFolderStore.shared;
    XCTAssertTrue([s applySnapshot:Snap(3, @[F(@"f2", @"B", 1, @[@"x"]), F(@"f1", @"A", 0, @[])])]);
    XCTAssertEqual(s.version, 3);
    XCTAssertEqualObjects([s.folders valueForKey:@"folderID"], (@[@"f1", @"f2"]));
    XCTAssertTrue([[s folderWithID:@"f2"] containsConv:@"x"]);
    XCTAssertEqual([s foldersContainingConv:@"x"].count, 1u);
}

- (void)testStaleAndSameVersionDropped {
    IMChatFolderStore *s = IMChatFolderStore.shared;
    [s applySnapshot:Snap(5, @[F(@"f1", @"A", 0, @[])])];
    XCTAssertFalse([s applySnapshot:Snap(5, @[F(@"f9", @"Z", 0, @[])])], @"同版本（PUT 回包与同版本帧）应丢弃");
    XCTAssertFalse([s applySnapshot:Snap(4, @[])], @"更旧版本（乱序帧）应丢弃");
    XCTAssertEqualObjects([s.folders valueForKey:@"folderID"], (@[@"f1"]));
    XCTAssertTrue([s applySnapshot:Snap(6, @[])], @"更新版本整表替换（含清空）");
    XCTAssertEqual(s.folders.count, 0u);
}

- (void)testMalformedIgnored {
    IMChatFolderStore *s = IMChatFolderStore.shared;
    XCTAssertFalse([s applySnapshot:@{ @"version": @1 }]);                       // 缺 folders
    XCTAssertTrue([s applySnapshot:Snap(2, @[@{ @"id": @"", @"name": @"x" }, F(@"ok", @"OK", 0, @[])])]);
    XCTAssertEqualObjects([s.folders valueForKey:@"folderID"], (@[@"ok"]));      // 非法项被跳过，不连累整表
}

- (void)testLimitsFromServer {
    IMChatFolderStore *s = IMChatFolderStore.shared;
    XCTAssertEqual(s.maxFolders, 10);
    XCTAssertEqual(s.maxConvs, 100);
    [s applySnapshot:@{ @"version": @1, @"folders": @[], @"limits": @{ @"max_folders": @5, @"max_convs": @20, @"max_name": @8 } }];
    XCTAssertEqual(s.maxFolders, 5);
    XCTAssertEqual(s.maxConvs, 20);
    XCTAssertEqual(s.maxNameLength, 8);
}

- (void)testPersistedPerAccountAndIsolation {
    IMChatFolderStore *s = IMChatFolderStore.shared;
    [s applySnapshot:Snap(7, @[F(@"f1", @"A", 0, @[@"c1"])])];
    [s adoptUserID:@"u_test_b"];                        // 换账号：清内存，不带过去
    XCTAssertEqual(s.folders.count, 0u);
    XCTAssertEqual(s.version, 0);
    [s applySnapshot:Snap(1, @[F(@"g1", @"B-only", 0, @[])])];
    [s adoptUserID:@"u_test_a"];                        // 切回：从落盘读回
    XCTAssertEqual(s.version, 7);
    XCTAssertEqualObjects([s.folders valueForKey:@"folderID"], (@[@"f1"]));
}

- (void)testPostsChangeNotification {
    XCTestExpectation *exp = [self expectationForNotification:IMChatFoldersDidChangeNotification object:nil handler:nil];
    [IMChatFolderStore.shared applySnapshot:Snap(1, @[F(@"f1", @"A", 0, @[])])];
    [self waitForExpectations:@[exp] timeout:1];
}

- (void)testUserMessageForFolderCodes {
    NSError *dup = [NSError errorWithDomain:@"x" code:300304 userInfo:@{ NSLocalizedDescriptionKey: @"server text" }];
    XCTAssertNotEqualObjects([IMChatFolderStore userMessageForError:dup], @"server text"); // 业务码走 err.<code> 本地化，不展示服务端 message
    NSError *other = [NSError errorWithDomain:@"x" code:12345 userInfo:@{ NSLocalizedDescriptionKey: @"boom" }];
    XCTAssertEqualObjects([IMChatFolderStore userMessageForError:other], @"boom");
}

@end
