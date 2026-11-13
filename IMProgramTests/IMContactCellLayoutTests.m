//  IMContactCellLayoutTests.m
//  共享 IMContactCell 的名字位置：好友选择 / 黑名单 / 找人 / 新的朋友等页面走 configureWithCard:，
//  无副标题时名字仍贴头像上沿（2026-11-13 前的版式）；只有「最近联系」用的 configureWithDisplayName:
//  在无副标题时把名字垂直居中。
//  app-hosted 测试，头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Modules/Contacts/IMContactCells.h"
#import "../IMProgram/Models/IMUserCard.h"

@interface IMContactCellLayoutTests : XCTestCase
@end

@implementation IMContactCellLayoutTests

- (IMContactCell *)cell {
    IMContactCell *cell = [[IMContactCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"t"];
    cell.frame = CGRectMake(0, 0, 402, 68);
    return cell;
}

- (CGRect)frameOf:(NSString *)ivar in:(IMContactCell *)cell {
    [cell setNeedsLayout];
    [cell layoutIfNeeded];
    UIView *view = [cell valueForKey:ivar];
    return [cell.contentView convertRect:view.bounds fromView:view];
}

- (IMUserCard *)card {
    return [IMUserCard cardsFromArray:@[ @{ @"user_id": @"u-1", @"nickname": @"张三", @"status": @"accepted" } ]].firstObject;
}

/// configureWithCard: 无副标题：名字上沿 = 头像上沿 + 2，与有副标题时同一位置（改动前的版式）。
- (void)testConfigureWithCardKeepsTitleTopAlignedWithoutSubtitle {
    IMContactCell *withSub = [self cell];
    [withSub configureWithCard:[self card] subtitle:@"@zhangsan"];
    CGRect titleWithSub = [self frameOf:@"_title" in:withSub];

    IMContactCell *cell = [self cell];
    [cell configureWithCard:[self card] subtitle:nil];
    CGRect avatar = [self frameOf:@"_avatar" in:cell];
    CGRect title = [self frameOf:@"_title" in:cell];
    XCTAssertEqualWithAccuracy(CGRectGetMinY(title), CGRectGetMinY(avatar) + 2, 0.5, @"名字贴头像上沿，不居中");
    XCTAssertEqualWithAccuracy(CGRectGetMinY(title), CGRectGetMinY(titleWithSub), 0.5, @"有无副标题名字位置一致");
}

/// 同一个 cell 先被「最近联系」配置过（居中）再被名片配置：要复位回上沿。
- (void)testConfigureWithCardResetsCenteredPlacementOnReuse {
    IMContactCell *cell = [self cell];
    [cell configureWithDisplayName:@"最近的人" avatarURL:nil avatarSeed:@"u-1" subtitle:nil];
    [cell configureWithCard:[self card] subtitle:nil];
    CGRect avatar = [self frameOf:@"_avatar" in:cell];
    CGRect title = [self frameOf:@"_title" in:cell];
    XCTAssertEqualWithAccuracy(CGRectGetMinY(title), CGRectGetMinY(avatar) + 2, 0.5);
}

/// 「最近联系」那条配置路径：无副标题时名字相对头像垂直居中。
- (void)testConfigureWithDisplayNameCentersTitleWithoutSubtitle {
    IMContactCell *cell = [self cell];
    [cell configureWithDisplayName:@"最近的人" avatarURL:nil avatarSeed:@"u-1" subtitle:nil];
    CGRect avatar = [self frameOf:@"_avatar" in:cell];
    CGRect title = [self frameOf:@"_title" in:cell];
    XCTAssertEqualWithAccuracy(CGRectGetMidY(title), CGRectGetMidY(avatar), 0.5);
}

@end
