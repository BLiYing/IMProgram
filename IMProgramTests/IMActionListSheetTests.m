//  IMActionListSheetTests.m
//  IMActionListSheet：选中项 ✓ 的颜色要跟窗口 tint（viewWillAppear 入窗后重取），而不是构建时（未入窗）的系统默认蓝。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMActionListSheet.h"

@interface IMActionListSheetTests : XCTestCase
@end

@implementation IMActionListSheetTests

static void IMALSCollectChecks(UIView *v, NSMutableArray<UILabel *> *out) {
    if ([v isKindOfClass:UILabel.class] && [((UILabel *)v).text isEqualToString:@"✓"]) { [out addObject:(UILabel *)v]; }
    for (UIView *s in v.subviews) { IMALSCollectChecks(s, out); }
}

- (void)testSelectedCheckmarkUsesWindowTintAtAppear {
    UIColor *tint = [UIColor colorWithRed:1 green:0 blue:0.5 alpha:1]; // 与系统默认蓝明显不同
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    window.tintColor = tint;
    UIViewController *host = [UIViewController new];
    window.rootViewController = host;
    [window makeKeyAndVisible];

    IMActionListItem *on = [IMActionListItem itemWithTitle:@"A" selected:YES handler:^{}];
    IMActionListItem *off = [IMActionListItem itemWithTitle:@"B" selected:NO handler:^{}];
    [IMActionListSheet presentFrom:host title:@"T" items:@[on, off]];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.6]];

    UIViewController *sheet = host.presentedViewController;
    XCTAssertNotNil(sheet, @"弹窗应已弹出");
    NSMutableArray<UILabel *> *checks = [NSMutableArray array];
    IMALSCollectChecks(sheet.view, checks);
    XCTAssertEqual(checks.count, 1u, @"只有选中项带 ✓");
    CGFloat r1 = 0, g1 = 0, b1 = 0, a1 = 0, r2 = 0, g2 = 0, b2 = 0, a2 = 0;
    [checks.firstObject.textColor getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
    [tint getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
    XCTAssertEqualWithAccuracy(r1, r2, 0.01, @"✓ 红分量应等于窗口 tint");
    XCTAssertEqualWithAccuracy(g1, g2, 0.01);
    XCTAssertEqualWithAccuracy(b1, b2, 0.01, @"✓ 蓝分量应等于窗口 tint（而不是创建时的默认蓝）");
    [sheet dismissViewControllerAnimated:NO completion:nil];
    window.hidden = YES;
}

@end
