//  IMEntryCellTests.m
//  LIST_ENTRY_ROW_DESIGN §2：入口行 = 槽 40（图标水平垂直居中）+ 间距 12 + 文字；
//  文字左缘 68 = 下方成员 / 例外行名字左缘；separatorInset.left = 68；行高 ≥ 56。
//  几何靠视图层级断言（无需登录群数据）。

#import <XCTest/XCTest.h>
#import "IMEntryCell.h"

@interface IMEntryCellTests : XCTestCase
@end

@implementation IMEntryCellTests

/// 放进真实 table 里布局（cell 的 layoutMargins 由 table 决定，与线上一致）。
- (IMEntryCell *)laidOutCellWithConfig:(void (^)(IMEntryCell *))config {
    UITableView *tv = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 390, 800) style:UITableViewStylePlain];
    [tv registerClass:IMEntryCell.class forCellReuseIdentifier:@"e"];
    IMEntryCell *cell = [tv dequeueReusableCellWithIdentifier:@"e"];
    config(cell);
    cell.frame = CGRectMake(0, 0, 390, IMEntryCellMinHeight);
    [tv addSubview:cell];
    [cell layoutIfNeeded];
    return cell;
}

- (void)assertGeometry:(IMEntryCell *)cell {
    CGRect slot = [cell convertRect:cell.slotView.bounds fromView:cell.slotView];
    CGRect icon = [cell convertRect:cell.iconView.bounds fromView:cell.iconView];
    CGRect title = [cell convertRect:cell.titleLabel.bounds fromView:cell.titleLabel];
    XCTAssertEqualWithAccuracy(slot.size.width, 40, 0.01);
    // 绝对左边距由 table 的 layoutMargins 决定（线上 16，与成员 / 例外行头像同一条 guide，模拟器像素量过）；
    // 这里钉相对关系：槽左缘 = contentView 左边距；文字左缘 = 槽左缘 + 40 + 12 = 68 - 16。
    XCTAssertEqualWithAccuracy(CGRectGetMinX(slot), cell.contentView.layoutMargins.left, 0.01, @"槽左缘 = 头像左缘 guide");
    XCTAssertEqualWithAccuracy(CGRectGetMinX(title) - CGRectGetMinX(slot), 52, 0.01, @"文字左缘 = 槽左缘 + 52（左边距 16 时 = 68）");
    XCTAssertEqualWithAccuracy(CGRectGetMidX(icon), CGRectGetMidX(slot), 0.51, @"图标水平居中于槽（= 头像圆心竖线 x=36）");
    XCTAssertEqualWithAccuracy(CGRectGetMidY(icon), CGRectGetMidY(slot), 0.51, @"图标垂直居中于槽");
    XCTAssertEqualWithAccuracy(CGRectGetMidX(slot) - CGRectGetMinX(slot), 20, 0.01);
    XCTAssertGreaterThanOrEqual(cell.contentView.bounds.size.height, 56);
    XCTAssertEqualWithAccuracy(cell.titleLabel.font.pointSize, 16, 0.01);
}

- (void)testLinearSymbolRow {
    IMEntryCell *cell = [self laidOutCellWithConfig:^(IMEntryCell *c) {
        [c configureWithSymbol:@"magnifyingglass" title:@"T" titleColor:nil iconTint:nil disclosure:YES];
    }];
    [self assertGeometry:cell];
    XCTAssertEqual(cell.accessoryType, UITableViewCellAccessoryDisclosureIndicator);
    XCTAssertTrue([cell.iconView isKindOfClass:UIImageView.class]);
    XCTAssertNotNil(((UIImageView *)cell.iconView).image);
}

- (void)testAddCircleRow {
    IMEntryCell *cell = [self laidOutCellWithConfig:^(IMEntryCell *c) { [c configureAddCircleWithTitle:@"T"]; }];
    [self assertGeometry:cell];
    CGRect icon = [cell convertRect:cell.iconView.bounds fromView:cell.iconView];
    XCTAssertEqualWithAccuracy(icon.size.width, 32, 0.01, @"例外圆 32");
    XCTAssertEqual(cell.accessoryType, UITableViewCellAccessoryNone);
}

- (void)testReconfigureResetsDetailAndAccessory {
    IMEntryCell *cell = [self laidOutCellWithConfig:^(IMEntryCell *c) {
        [c configureWithSymbol:@"person.3.sequence" title:@"T" titleColor:nil iconTint:nil disclosure:YES];
        [c setDetailAttributedText:[[NSAttributedString alloc] initWithString:@"a\nb"]];
    }];
    XCTAssertFalse(cell.detailLabel.hidden);
    [cell configureWithSymbol:@"ellipsis.circle" title:@"U" titleColor:nil iconTint:nil disclosure:NO];
    XCTAssertTrue(cell.detailLabel.hidden);
    XCTAssertEqual(cell.accessoryType, UITableViewCellAccessoryNone);
}

@end
