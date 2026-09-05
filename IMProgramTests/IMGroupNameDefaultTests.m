//  IMGroupNameDefaultTests.m
//  建群默认群名（IMGroupNameDefault.h）。与 Web `src/groupName.test.ts` **同一组用例**：
//  两端规则必须逐字一致，否则同一批人在两个端上建群会得到不同的默认群名。

#import <XCTest/XCTest.h>
#import "IMGroupNameDefault.h"

@interface IMGroupNameDefaultTests : XCTestCase
@end

@implementation IMGroupNameDefaultTests

- (void)testPublicUserNameFallsBackNicknameThenUsernameThenUserID {
    XCTAssertEqualObjects(IMPublicUserName(@"小明", @"ming", @"1001"), @"小明");
    XCTAssertEqualObjects(IMPublicUserName(@"  ", @"ming", @"1001"), @"@ming");
    XCTAssertEqualObjects(IMPublicUserName(nil, nil, @"1001"), @"1001");
    XCTAssertEqualObjects(IMPublicUserName(nil, nil, nil), @"");
}

- (void)testJoinsInOrder {
    // 调用方把自己排在第一位，这里只验"按给定顺序拼"。
    XCTAssertEqualObjects(IMDefaultGroupName(@[@"小明", @"张三", @"李四"], IMMaxGroupNameLength), @"小明、张三、李四");
}

- (void)testSkipsEmptyNames {
    XCTAssertEqualObjects(IMDefaultGroupName(@[@"小明", @"", @"  ", @"张三"], IMMaxGroupNameLength), @"小明、张三");
    XCTAssertEqualObjects(IMDefaultGroupName(@[], IMMaxGroupNameLength), @"");
    XCTAssertEqualObjects(IMDefaultGroupName(@[@"", @" "], IMMaxGroupNameLength), @"");
}

- (void)testFitsExactlyWithoutEllipsis {
    // 6+1+5+1+4+1+4+1+4 = 27 ≤ 30，五个名字全进去
    NSString *out = IMDefaultGroupName(@[@"产品经理小王", @"设计师小李", @"前端小张", @"后端小赵", @"测试小孙"], IMMaxGroupNameLength);
    XCTAssertEqualObjects(out, @"产品经理小王、设计师小李、前端小张、后端小赵、测试小孙");
    XCTAssertEqual(IMGroupNameRuneLength(out), 27u);
}

- (void)testStopsAtFirstNameThatDoesNotFitWithoutEllipsis {
    // 每个 6 字：6 / 13 / 20 / 27 都放得下，第 5 个要到 34 → 停在 4 个，**不补省略号**
    NSString *out = IMDefaultGroupName(@[@"一二三四五六", @"一二三四五六", @"一二三四五六", @"一二三四五六", @"一二三四五六"],
                                       IMMaxGroupNameLength);
    XCTAssertEqualObjects(out, @"一二三四五六、一二三四五六、一二三四五六、一二三四五六");
    XCTAssertEqual(IMGroupNameRuneLength(out), 27u);
    XCTAssertFalse([out hasSuffix:@"…"]);
}

- (void)testTightLimitKeepsOnlyFirstName {
    XCTAssertEqualObjects(IMDefaultGroupName(@[@"一二三四五六", @"一二三四五六"], 10), @"一二三四五六");
}

- (void)testFirstNameItselfTooLongIsHardTruncated {
    NSString *long40 = [@"" stringByPaddingToLength:40 withString:@"字" startingAtIndex:0];
    NSString *out = IMDefaultGroupName(@[long40], IMMaxGroupNameLength);
    XCTAssertEqual(IMGroupNameRuneLength(out), IMMaxGroupNameLength);
    XCTAssertFalse([out hasSuffix:@"…"]);   // 同样不补省略号
}

- (void)testCountsRunesNotUTF16Units {
    // 😀 是非 BMP 字符（UTF-16 占 2 个单元），服务端按 rune 数 1 计——两端必须同口径。
    XCTAssertEqual(IMGroupNameRuneLength(@"😀😀😀"), 3u);
    XCTAssertEqual(@"😀😀😀".length, 6u);                       // 对照：NSString.length 是 UTF-16 长度
    XCTAssertEqualObjects(IMGroupNameTruncateToRunes(@"😀😀😀", 2), @"😀😀");
    NSString *emoji20 = [@"" stringByPaddingToLength:40 withString:@"😀" startingAtIndex:0]; // 20 个 😀
    XCTAssertEqualObjects(IMDefaultGroupName(@[emoji20, @"张三"], 10),
                          [@"" stringByPaddingToLength:20 withString:@"😀" startingAtIndex:0]); // 10 个 😀
}

@end
