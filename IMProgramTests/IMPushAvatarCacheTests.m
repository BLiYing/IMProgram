//  IMPushAvatarCacheTests.m
//  通知扩展头像缓存的纯函数（PUSH_M5_DESIGN §3.6）：文件名怎么取、清理删哪些。

#import <XCTest/XCTest.h>
#import "IMPushAvatarCache.h"

@interface IMPushAvatarCacheTests : XCTestCase
@end

@implementation IMPushAvatarCacheTests

- (void)testFileNameIsTheContentAddressedName {
    XCTAssertEqualObjects(IMPushAvatarCacheFileName(@"/avatars/2d0f2d11.jpg"), @"2d0f2d11.jpg");
}

/// 不是自家头像目录下的一个文件，就不进缓存目录（防路径穿越写到别处）。
- (void)testFileNameRejectsOtherPaths {
    for (NSString *bad in @[ @"/uploads/a.jpg", @"/avatars/../x.jpg", @"/avatars/", @"/avatars/a/b.jpg", @"https://evil/avatars/a.jpg" ]) {
        XCTAssertNil(IMPushAvatarCacheFileName(bad), @"%@", bad);
    }
    XCTAssertNil(IMPushAvatarCacheFileName(nil));
}

- (IMPushAvatarCacheEntry *)entry:(NSString *)name kb:(unsigned long long)kb daysAgo:(double)days now:(NSDate *)now {
    return [IMPushAvatarCacheEntry entryWithName:name bytes:kb * 1024 lastUsed:[now dateByAddingTimeInterval:-days * 86400]];
}

- (void)testEvictsEntriesUnusedForTooLong {
    NSDate *now = NSDate.date;
    NSArray *plan = IMPushAvatarCachePlanEviction(@[ [self entry:@"old" kb:10 daysAgo:31 now:now],
                                                     [self entry:@"fresh" kb:10 daysAgo:1 now:now] ],
                                                  now, 30 * 86400, 1024 * 1024);
    XCTAssertEqualObjects(plan, @[ @"old" ]);
}

/// 超过总量：从最久没用的开始删，删到不超为止；最近用过的留着。
- (void)testEvictsLeastRecentlyUsedUntilUnderBudget {
    NSDate *now = NSDate.date;
    NSArray *entries = @[ [self entry:@"c" kb:40 daysAgo:1 now:now],
                          [self entry:@"a" kb:40 daysAgo:5 now:now],
                          [self entry:@"b" kb:40 daysAgo:3 now:now] ];
    NSArray *plan = IMPushAvatarCachePlanEviction(entries, now, 30 * 86400, 90 * 1024);
    XCTAssertEqualObjects(plan, @[ @"a" ]);
    XCTAssertEqualObjects(IMPushAvatarCachePlanEviction(entries, now, 30 * 86400, 50 * 1024), (@[ @"a", @"b" ]));
}

- (void)testNothingToEvictWithinLimits {
    NSDate *now = NSDate.date;
    XCTAssertEqual(IMPushAvatarCachePlanEviction(@[ [self entry:@"a" kb:40 daysAgo:2 now:now] ], now, 30 * 86400, 1024 * 1024).count, 0u);
}

@end
