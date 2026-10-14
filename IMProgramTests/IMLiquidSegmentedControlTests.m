//  IMLiquidSegmentedControlTests.m
//  分段控件的布局口径：底轨贴合内容宽度并居中（不再把富余宽度均分给各段）；角标计入段宽。
//  防回归：此前收藏页只有一个分类时，唯一的 Tab 被拉成整行（设计 CHAT_FOLDERS_DESIGN.md §6.1）。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMLiquidSegmentedControl.h"

@interface IMLiquidSegmentedControlTests : XCTestCase
@end

@implementation IMLiquidSegmentedControlTests

- (IMLiquidSegmentedControl *)controlWithTitles:(NSArray<NSString *> *)titles width:(CGFloat)width {
    IMLiquidSegmentedControl *c = [[IMLiquidSegmentedControl alloc] initWithFrame:CGRectMake(0, 0, width, 40)];
    c.titles = titles;
    [c layoutIfNeeded];
    return c;
}

/// 底轨（第一个子视图）。
- (UIView *)trackOf:(IMLiquidSegmentedControl *)c { return c.subviews.firstObject; }

- (void)testFewTabsHugContentAndCenter {
    IMLiquidSegmentedControl *c = [self controlWithTitles:@[@"全部"] width:358];
    CGFloat w = CGRectGetWidth([self trackOf:c].frame);
    XCTAssertLessThan(w, 120, @"单个 Tab 不应被拉满整行，got %.1f", w);
    XCTAssertEqualWithAccuracy(CGRectGetMidX([self trackOf:c].frame), 358 / 2.0, 1.0, @"底轨应居中");
    XCTAssertEqualWithAccuracy([c sizeThatFits:CGSizeMake(358, 40)].width, w, 1.0, @"sizeThatFits 即内容宽");
}

- (void)testTwoTabsNotStretchedToHalfEach {
    IMLiquidSegmentedControl *c = [self controlWithTitles:@[@"全部", @"工作"] width:358];
    XCTAssertLessThan(CGRectGetWidth([self trackOf:c].frame), 200);
}

- (void)testBadgeWidensSegment {
    IMLiquidSegmentedControl *c = [self controlWithTitles:@[@"全部", @"工作"] width:358];
    CGFloat before = CGRectGetWidth([self trackOf:c].frame);
    [c setBadgeTexts:@[@"12", @""] muted:@[@NO, @NO]];
    [c layoutIfNeeded];
    XCTAssertGreaterThan(CGRectGetWidth([self trackOf:c].frame), before, @"角标应计入段宽");
}

- (void)testOverflowFillsAndScrolls {
    NSMutableArray *t = [NSMutableArray array];
    for (int i = 0; i < 12; i++) { [t addObject:[NSString stringWithFormat:@"文件夹%d", i]]; }
    IMLiquidSegmentedControl *c = [self controlWithTitles:t width:358];
    XCTAssertEqualWithAccuracy(CGRectGetWidth([self trackOf:c].frame), 358, 0.5, @"放不下：底轨顶满可用宽度（内部横向滚动）");
}

- (void)testSegmentIndexAtPoint {
    IMLiquidSegmentedControl *c = [self controlWithTitles:@[@"全部", @"工作"] width:358];
    CGFloat cx = CGRectGetMidX([self trackOf:c].frame);
    XCTAssertEqual([c segmentIndexAtPoint:CGPointMake(cx - 20, 20)], 0);
    XCTAssertEqual([c segmentIndexAtPoint:CGPointMake(cx + 20, 20)], 1);
    XCTAssertEqual([c segmentIndexAtPoint:CGPointMake(2, 20)], NSNotFound);
}

@end
