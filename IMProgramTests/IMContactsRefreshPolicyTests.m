//  IMContactsRefreshPolicyTests.m
//  通讯录切入刷新节流判据：从未拉过必拉、在途不重发、间隔内不拉、时钟倒退按过期。
//  背景：2026-09-06 为治切 Tab 卡顿把切入刷新整句删掉，好友缓存又只有通讯录页写 → 整页空白。
//  app-hosted 测试，头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Modules/Contacts/IMContactsViewController.h"

@interface IMContactsRefreshPolicyTests : XCTestCase
@end

@implementation IMContactsRefreshPolicyTests

/// 从未拉成功过：必须拉（否则列表永远只有空种子）。now 取小于 interval 的值——CACurrentMediaTime
/// 从开机起算，刚开机时本来就很小；取大值的话「从未拉过」这条分支删掉也照样绿。
- (void)testNeverRefreshedAlwaysRefreshes {
    XCTAssertTrue(IMContactsShouldRefreshOnAppear(NO, 0, 10, 30));
}

/// 在途：哪怕从未拉过也不重复发。
- (void)testInFlightSuppresses {
    XCTAssertFalse(IMContactsShouldRefreshOnAppear(YES, 0, 1000, 30));
    XCTAssertFalse(IMContactsShouldRefreshOnAppear(YES, 900, 1000, 30));
}

/// 间隔边界：不足不拉，恰好到点就拉。
- (void)testIntervalBoundary {
    XCTAssertFalse(IMContactsShouldRefreshOnAppear(NO, 1000, 1029.9, 30));
    XCTAssertTrue(IMContactsShouldRefreshOnAppear(NO, 1000, 1030, 30));
    XCTAssertTrue(IMContactsShouldRefreshOnAppear(NO, 1000, 5000, 30));
}

/// 时钟倒退（now 早于上次）：按过期处理，别被卡在「永远不到点」。
- (void)testClockGoingBackwardsRefreshes {
    XCTAssertTrue(IMContactsShouldRefreshOnAppear(NO, 1000, 10, 30));
}

@end
