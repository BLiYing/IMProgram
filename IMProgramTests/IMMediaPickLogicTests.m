//  IMMediaPickLogicTests.m
//  自建相册选择器的纯逻辑。与 Android `MediaPickTest` 同口径（对称登记在 IMServer docs/SYMMETRY.md）。

#import <XCTest/XCTest.h>
#import "IMMediaPickLogic.h"

@interface IMMediaPickLogicTests : XCTestCase
@end

@implementation IMMediaPickLogicTests

#pragma mark 有序选中

- (void)testLimitIsNineAndMatchesAlbumGrid {
    // 与 Android MediaPick.LIMIT / 聊天相册宫格上限同值；改这个数要三端一起改。
    XCTAssertEqual(kIMMediaPickLimit, 9);
}

- (void)testToggleKeepsSelectionOrder {
    NSArray<NSString *> *s = @[];
    s = [IMMediaPickLogic toggledSelection:s assetID:@"a" limit:9];
    s = [IMMediaPickLogic toggledSelection:s assetID:@"b" limit:9];
    s = [IMMediaPickLogic toggledSelection:s assetID:@"c" limit:9];
    XCTAssertEqualObjects(s, (@[@"a", @"b", @"c"]));
    XCTAssertEqual([IMMediaPickLogic numberOfAssetID:@"b" inSelection:s], 2);
}

- (void)testDeselectingMiddleShiftsLaterNumbersDown {
    NSArray<NSString *> *s = @[@"1", @"2", @"3", @"4"];
    s = [IMMediaPickLogic toggledSelection:s assetID:@"2" limit:9];
    XCTAssertEqualObjects(s, (@[@"1", @"3", @"4"]));
    XCTAssertEqual([IMMediaPickLogic numberOfAssetID:@"3" inSelection:s], 2); // 不是 3
    XCTAssertEqual([IMMediaPickLogic numberOfAssetID:@"4" inSelection:s], 3);
    XCTAssertEqual([IMMediaPickLogic numberOfAssetID:@"2" inSelection:s], 0); // 未选 = 0
}

- (void)testToggleOverLimitReturnsNilButStillAllowsDeselect {
    NSMutableArray<NSString *> *nine = [NSMutableArray array];
    for (int i = 0; i < 9; i++) { [nine addObject:[NSString stringWithFormat:@"%d", i]]; }
    XCTAssertNil([IMMediaPickLogic toggledSelection:nine assetID:@"x" limit:9]);
    NSArray<NSString *> *less = [IMMediaPickLogic toggledSelection:nine assetID:@"4" limit:9];
    XCTAssertEqual(less.count, 8u); // 满了仍可取消
}

#pragma mark 可选判定

- (void)testSelectableRule {
    XCTAssertTrue([IMMediaPickLogic isSelectableWithSizeBytes:kIMMediaSizeUnknown]); // 体积未知 ≠ 不可选
    XCTAssertTrue([IMMediaPickLogic isSelectableWithSizeBytes:1]);
    XCTAssertTrue([IMMediaPickLogic isSelectableWithSizeBytes:2048LL * 1024 * 1024]);   // 恰好 2GB 可选
    XCTAssertFalse([IMMediaPickLogic isSelectableWithSizeBytes:2048LL * 1024 * 1024 + 1]);
    XCTAssertFalse([IMMediaPickLogic isSelectableWithSizeBytes:0]);                       // 0 字节 = 坏资源
    XCTAssertTrue([IMMediaPickLogic isTooLargeWithSizeBytes:3LL << 30]);
    XCTAssertFalse([IMMediaPickLogic isTooLargeWithSizeBytes:0]);
}

#pragma mark 体积 / 时长文案

- (void)testTotalBytesOnlyCountsKnownSelectedItems {
    NSDictionary<NSString *, NSNumber *> *sizes = @{@"a": @100, @"b": @(kIMMediaSizeUnknown), @"c": @50, @"z": @999};
    XCTAssertEqual(([IMMediaPickLogic totalBytesForSelection:@[@"a", @"b", @"c"] sizes:sizes]), 150); // 未知不累加、未选不累加
    XCTAssertEqual(([IMMediaPickLogic totalBytesForSelection:@[@"b"] sizes:sizes]), 0);               // 全未知 = 0（不显示括号）
    XCTAssertEqual(([IMMediaPickLogic totalBytesForSelection:@[] sizes:sizes]), 0);
}

- (void)testSizeLabelUses1024BaseWithOneDecimal {
    XCTAssertEqualObjects([IMMediaPickLogic sizeLabelForBytes:0], @"0 B");
    XCTAssertEqualObjects([IMMediaPickLogic sizeLabelForBytes:512], @"512 B");
    XCTAssertEqualObjects([IMMediaPickLogic sizeLabelForBytes:1024], @"1.0 KB");
    XCTAssertEqualObjects([IMMediaPickLogic sizeLabelForBytes:1536], @"1.5 KB");
    XCTAssertEqualObjects([IMMediaPickLogic sizeLabelForBytes:5 * 1024 * 1024], @"5.0 MB");
    XCTAssertEqualObjects([IMMediaPickLogic sizeLabelForBytes:2048LL * 1024 * 1024], @"2.00 GB");
}

- (void)testDurationLabel {
    XCTAssertEqualObjects([IMMediaPickLogic durationLabelForSeconds:0], @"0:00");
    XCTAssertEqualObjects([IMMediaPickLogic durationLabelForSeconds:9.9], @"0:09"); // 向下取整
    XCTAssertEqualObjects([IMMediaPickLogic durationLabelForSeconds:75], @"1:15");
    XCTAssertEqualObjects([IMMediaPickLogic durationLabelForSeconds:3600], @"60:00");
    XCTAssertEqualObjects([IMMediaPickLogic durationLabelForSeconds:-3], @"0:00");
}

#pragma mark 列数

- (void)testColumnCountIsFourOnPhonesAndGrowsOnWideScreens {
    XCTAssertEqual([IMMediaPickLogic columnCountForWidth:320], 4);
    XCTAssertEqual([IMMediaPickLogic columnCountForWidth:430], 4);
    XCTAssertEqual([IMMediaPickLogic columnCountForWidth:820], 8);
}

@end
