//
//  IMReadTickTests.m —— 已读勾图标：尺寸比例 / template / 缓存 / 富文本结构。
//

#import <XCTest/XCTest.h>
#import "IMReadTick.h"
#import "IMChatMessageLogic.h"
#import "IMMessageModel.h"
#import "IMMessageCell.h"
#import "IMFriendPickerViewController.h"
#import "IMGroupAdminLogic.h"
#import "IMGroupInfo.h"

@interface IMReadTickTests : XCTestCase
@end

@implementation IMReadTickTests

- (void)testSizesFollowViewBoxRatio {
    UIImage *one = [IMReadTick imageDouble:NO height:10];
    UIImage *two = [IMReadTick imageDouble:YES height:10];
    XCTAssertEqualWithAccuracy(one.size.width, 13, 0.01);
    XCTAssertEqualWithAccuracy(two.size.width, 18, 0.01);
    XCTAssertEqualWithAccuracy(two.size.height, 10, 0.01);
}

- (void)testTemplateAndCached {
    UIImage *a = [IMReadTick imageDouble:YES height:9.5];
    XCTAssertEqual(a.renderingMode, UIImageRenderingModeAlwaysTemplate);
    XCTAssertTrue(a == [IMReadTick imageDouble:YES height:9.5], @"同参数应命中缓存");
}

- (void)testMetaStructure {
    UIFont *f = [UIFont systemFontOfSize:10];
    NSAttributedString *s = [IMReadTick metaWithTime:@"12:30" read:YES font:f
                                           timeColor:UIColor.grayColor tickColor:UIColor.blueColor];
    XCTAssertEqual(s.length, 6u); // 5 字符时间 + 1 个附件
    XCTAssertEqualObjects([s.string substringToIndex:5], @"12:30");
    NSTextAttachment *att = [s attribute:NSAttachmentAttributeName atIndex:5 effectiveRange:NULL];
    XCTAssertNotNil(att);
    XCTAssertEqualWithAccuracy(att.bounds.size.height, 9.5, 0.4);
    XCTAssertEqualWithAccuracy(att.bounds.size.width, 17.1, 0.4);
    XCTAssertEqualObjects([s attribute:NSKernAttributeName atIndex:4 effectiveRange:NULL], @(kIMReadTickGap));
    XCTAssertNil([s attribute:NSKernAttributeName atIndex:0 effectiveRange:NULL]);
}

- (void)testEmptyTimeOnlyTick {
    NSAttributedString *s = [IMReadTick metaWithTime:nil read:NO font:[UIFont systemFontOfSize:11]
                                           timeColor:UIColor.grayColor tickColor:UIColor.grayColor];
    XCTAssertEqual(s.length, 1u);
}

#pragma mark - 相册状态勾（READ_TICK_DESIGN §4）

static IMMessageModel *AlbumMsg(IMMessageStatus st, int64_t seq) {
    IMMessageModel *m = [IMMessageModel new];
    m.status = st; m.convSeq = seq;
    return m;
}

- (void)testAlbumTickRule {
    NSArray *sent = @[AlbumMsg(IMMessageStatusSent, 10), AlbumMsg(IMMessageStatusSent, 11)];
    XCTAssertEqual(IMAlbumTickStateForMembers(sent, NO, 99), IMAlbumTickNone, @"对方相册不画");
    XCTAssertEqual(IMAlbumTickStateForMembers(@[], YES, 99), IMAlbumTickNone);
    XCTAssertEqual(IMAlbumTickStateForMembers(sent, YES, 0), IMAlbumTickSent);
    XCTAssertEqual(IMAlbumTickStateForMembers(sent, YES, 10), IMAlbumTickSent, @"只读到首张 → 仍单勾（看末条）");
    XCTAssertEqual(IMAlbumTickStateForMembers(sent, YES, 11), IMAlbumTickRead);
    XCTAssertEqual(IMAlbumTickStateForMembers(sent, YES, kIMPeerReadSeqHidden), IMAlbumTickNone, @"超级群不画");
    NSArray *sending = @[AlbumMsg(IMMessageStatusSent, 10), AlbumMsg(IMMessageStatusSending, 0)];
    XCTAssertEqual(IMAlbumTickStateForMembers(sending, YES, 99), IMAlbumTickSending);
    NSArray *failed = @[AlbumMsg(IMMessageStatusSent, 10), AlbumMsg(IMMessageStatusFailed, 0)];
    XCTAssertEqual(IMAlbumTickStateForMembers(failed, YES, 99), IMAlbumTickNone);
}

- (void)testAdminPickerSubtitle {
    IMFriendPickerViewController *vc = [[IMFriendPickerViewController alloc] initWithHost:@"h" userID:@"u" candidates:@[]
                                                                               excludedIDs:nil title:@"T" confirmTitle:@"C" onDone:^(NSArray *ids) {}];
    XCTAssertEqualObjects([vc im_navigationSubtitle], @"", @"默认不出副标题");
    vc.maxSelection = 5; vc.showsSelectionInSubtitle = YES;
    XCTAssertTrue([[vc im_navigationSubtitle] containsString:@"0"]);
    XCTAssertTrue([[vc im_navigationSubtitle] containsString:@"5"]);
}

- (void)testRemainingAdminSlots {
    NSMutableArray *ms = [NSMutableArray array];
    for (int i = 0; i < 7; i++) { IMGroupMember *m = [IMGroupMember new]; m.role = (i < 2 ? IMGroupRoleAdmin : IMGroupRoleMember); [ms addObject:m]; }
    XCTAssertEqual([IMGroupAdminLogic remainingAdminSlotsFromMembers:ms], 3u);
    for (IMGroupMember *m in ms) { m.role = IMGroupRoleAdmin; }
    XCTAssertEqual([IMGroupAdminLogic remainingAdminSlotsFromMembers:ms], 0u);
    XCTAssertEqual([IMGroupAdminLogic remainingAdminSlotsFromMembers:nil], 5u);
}

@end
