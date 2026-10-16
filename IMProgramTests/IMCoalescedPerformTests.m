//
//  IMCoalescedPerformTests.m
//  群帧连发时的合并式延迟调用：窗口内多次请求只执行一次；可撤销。
//

#import <XCTest/XCTest.h>
#import "NSObject+IMCoalescedPerform.h"

@interface IMCoalesceProbe : NSObject
@property (nonatomic) NSInteger hits;
- (void)hit;
@end
@implementation IMCoalesceProbe
- (void)hit { self.hits += 1; }
@end

@interface IMCoalescedPerformTests : XCTestCase
@end

@implementation IMCoalescedPerformTests

- (void)spinFor:(NSTimeInterval)seconds {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

- (void)testBurstRunsOnce {
    IMCoalesceProbe *p = [IMCoalesceProbe new];
    for (int i = 0; i < 100; i++) { [p im_coalescedPerform:@selector(hit) afterDelay:0.05]; }
    [self spinFor:0.3];
    XCTAssertEqual(p.hits, 1);
}

- (void)testCancelPreventsRun {
    IMCoalesceProbe *p = [IMCoalesceProbe new];
    [p im_coalescedPerform:@selector(hit) afterDelay:0.05];
    [p im_cancelCoalescedPerform:@selector(hit)];
    [self spinFor:0.2];
    XCTAssertEqual(p.hits, 0);
}

- (void)testCanRunAgainAfterFiring {
    IMCoalesceProbe *p = [IMCoalesceProbe new];
    [p im_coalescedPerform:@selector(hit) afterDelay:0.02];
    [self spinFor:0.15];
    [p im_coalescedPerform:@selector(hit) afterDelay:0.02];
    [self spinFor:0.15];
    XCTAssertEqual(p.hits, 2);
}

@end
