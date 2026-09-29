//  IMNotifExceptionPickerFilterTests.m
//  IMNotifExceptionPickerMatches 纯函数单测（Common/IMNotifExceptionPickerFilter.h）：
//  「添加例外」会话选择页的过滤判据——只列该类型、还没免打扰、非系统通知的会话。

#import <XCTest/XCTest.h>
#import "../IMProgram/Common/IMNotifExceptionPickerFilter.h"
#import "../IMProgram/Common/IMAccountIdentity.h"

@interface IMNotifExceptionPickerFilterTests : XCTestCase
@end

@implementation IMNotifExceptionPickerFilterTests

- (void)testPrivateUnmutedConversationMatchesPrivatePage {
    XCTAssertTrue(IMNotifExceptionPickerMatches(NO, NO, @"u_1001", NO));
}

- (void)testAlreadyMutedConversationIsExcluded {
    XCTAssertFalse(IMNotifExceptionPickerMatches(NO, YES, @"u_1001", NO));
    XCTAssertFalse(IMNotifExceptionPickerMatches(YES, YES, nil, YES));
}

- (void)testSystemNoticeConversationIsExcludedFromPrivatePage {
    XCTAssertFalse(IMNotifExceptionPickerMatches(NO, NO, IMSystemUserID, NO));
}

- (void)testSystemCheckOnlyAppliesToPrivateConversations {
    // 群聊没有「peer」这个维度，即便误传了系统 uid 也不该被这条规则误伤。
    XCTAssertTrue(IMNotifExceptionPickerMatches(YES, NO, IMSystemUserID, YES));
}

- (void)testGroupUnmutedConversationMatchesGroupPage {
    XCTAssertTrue(IMNotifExceptionPickerMatches(YES, NO, nil, YES));
}

- (void)testTypeMismatchIsExcluded {
    XCTAssertFalse(IMNotifExceptionPickerMatches(YES, NO, nil, NO)); // 群聊会话，私聊页不该列
    XCTAssertFalse(IMNotifExceptionPickerMatches(NO, NO, @"u_1001", YES)); // 私聊会话，群聊页不该列
}

@end
