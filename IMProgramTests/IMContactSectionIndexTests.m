//  IMContactSectionIndexTests.m
//  联系人 A–Z 分组索引单测：拼音首字母分桶、多音姓氏归正确桶、组内拼音序（姓在前）、# 桶末位、边界。
//  app-hosted 测试，头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Models/IMUserCard.h"
#import "../IMProgram/Modules/Contacts/IMContactSectionIndex.h"

@interface IMContactSectionIndexTests : XCTestCase
@end

@implementation IMContactSectionIndexTests

/// 造一张好友卡（displayName 由 nickname 回退 uid）。
- (IMUserCard *)cardWithNickname:(NSString *)nick uid:(NSString *)uid {
    NSArray<IMUserCard *> *cards = [IMUserCard cardsFromArray:@[ @{ @"user_id": uid, @"nickname": nick } ]];
    return cards.firstObject;
}

#pragma mark - 分组首字母

- (void)testSectionKeyBasics {
    XCTAssertEqualObjects([IMContactSectionIndex sectionKeyForName:@"李四"], @"L");
    XCTAssertEqualObjects([IMContactSectionIndex sectionKeyForName:@"Alice"], @"A");
    XCTAssertEqualObjects([IMContactSectionIndex sectionKeyForName:@"123"], @"#");
    XCTAssertEqualObjects([IMContactSectionIndex sectionKeyForName:@""], @"#");
    XCTAssertEqualObjects([IMContactSectionIndex sectionKeyForName:nil], @"#");
}

- (void)testSectionKeyPolyphonicSurnames {
    // 普通话默认拼音会取错音的姓，应归到正确的桶而非首音桶。
    XCTAssertEqualObjects([IMContactSectionIndex sectionKeyForName:@"曾国藩"], @"Z"); // 非 C(céng)
    XCTAssertEqualObjects([IMContactSectionIndex sectionKeyForName:@"仇英"], @"Q");   // 非 C(chóu)
    XCTAssertEqualObjects([IMContactSectionIndex sectionKeyForName:@"单雄信"], @"S"); // 非 D(dān)
    XCTAssertEqualObjects([IMContactSectionIndex sectionKeyForName:@"解缙"], @"X");   // 非 J(jiě)
}

#pragma mark - 分桶 / 排序

- (void)testBucketingSortingAndIndex {
    NSArray<IMUserCard *> *cards = @[
        [self cardWithNickname:@"刘备" uid:@"u1"],   // L / liu
        [self cardWithNickname:@"张三" uid:@"u2"],   // Z
        [self cardWithNickname:@"李四" uid:@"u3"],   // L / li
        [self cardWithNickname:@"林冲" uid:@"u4"],   // L / lin
        [self cardWithNickname:@"123数字" uid:@"u5"],// #
    ];
    IMContactSectionIndex *idx = [[IMContactSectionIndex alloc] initWithCards:cards];

    // 标题：A–Z 升序在前，# 末位；即右侧纵向索引尺内容。
    XCTAssertEqualObjects(idx.titles, (@[ @"L", @"Z", @"#" ]));
    XCTAssertEqual([idx numberOfSections], 3);
    XCTAssertEqualObjects([idx titleForSection:0], @"L");
    XCTAssertEqualObjects([idx titleForSection:2], @"#");

    // L 组内全串拼音序（姓在前）：李(li)< 林(lin)< 刘(liu)。
    XCTAssertEqual([idx numberOfRowsInSection:0], 3);
    XCTAssertEqualObjects([idx cardAtSection:0 row:0].displayName, @"李四");
    XCTAssertEqualObjects([idx cardAtSection:0 row:1].displayName, @"林冲");
    XCTAssertEqualObjects([idx cardAtSection:0 row:2].displayName, @"刘备");

    // Z / # 桶各一人。
    XCTAssertEqual([idx numberOfRowsInSection:1], 1);
    XCTAssertEqualObjects([idx cardAtSection:1 row:0].displayName, @"张三");
    XCTAssertEqualObjects([idx cardAtSection:2 row:0].displayName, @"123数字");
}

/// 分桶走的是内部「复用已算拼音」那条路（不是公开的 sectionKeyForName:），多音姓氏也要在索引里归对桶。
- (void)testIndexBucketsPolyphonicSurnames {
    IMContactSectionIndex *idx = [[IMContactSectionIndex alloc] initWithCards:@[
        [self cardWithNickname:@"曾国藩" uid:@"u1"],
        [self cardWithNickname:@"单雄信" uid:@"u2"],
    ]];
    XCTAssertEqualObjects(idx.titles, (@[ @"S", @"Z" ]));
    XCTAssertEqualObjects([idx cardAtSection:1 row:0].displayName, @"曾国藩");
}

#pragma mark - 异步构建

/// 后台构建与同步构建结果一致，且 completion 回到主线程（调用方在回调里直接 reloadData）。
- (void)testAsyncBuildMatchesSyncAndCallsBackOnMain {
    NSArray<IMUserCard *> *cards = @[
        [self cardWithNickname:@"刘备" uid:@"u1"],
        [self cardWithNickname:@"Alice" uid:@"u2"],
        [self cardWithNickname:@"李四" uid:@"u3"],
        [self cardWithNickname:@"123数字" uid:@"u4"],
    ];
    IMContactSectionIndex *sync = [[IMContactSectionIndex alloc] initWithCards:cards];
    XCTestExpectation *done = [self expectationWithDescription:@"async build"];
    [IMContactSectionIndex buildWithCards:cards completion:^(IMContactSectionIndex *index) {
        XCTAssertTrue(NSThread.isMainThread);
        XCTAssertEqualObjects(index.titles, sync.titles);
        for (NSInteger s = 0; s < sync.numberOfSections; s++) {
            XCTAssertEqual([index numberOfRowsInSection:s], [sync numberOfRowsInSection:s]);
            for (NSInteger r = 0; r < [sync numberOfRowsInSection:s]; r++) {
                XCTAssertEqual([index cardAtSection:s row:r], [sync cardAtSection:s row:r]);
            }
        }
        [done fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testAsyncBuildNilCards {
    XCTestExpectation *done = [self expectationWithDescription:@"async nil"];
    [IMContactSectionIndex buildWithCards:nil completion:^(IMContactSectionIndex *index) {
        XCTAssertEqual([index numberOfSections], 0);
        [done fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

#pragma mark - 边界

- (void)testEmptyAndOutOfRange {
    IMContactSectionIndex *idx = [[IMContactSectionIndex alloc] initWithCards:@[]];
    XCTAssertEqual([idx numberOfSections], 0);
    XCTAssertEqual(idx.titles.count, 0);
    XCTAssertEqual([idx numberOfRowsInSection:0], 0);
    XCTAssertEqualObjects([idx titleForSection:0], @"");
    XCTAssertNil([idx cardAtSection:0 row:0]);
    XCTAssertNil([idx cardAtSection:5 row:5]);

    IMContactSectionIndex *nilIdx = [[IMContactSectionIndex alloc] initWithCards:nil];
    XCTAssertEqual([nilIdx numberOfSections], 0);
}

@end
