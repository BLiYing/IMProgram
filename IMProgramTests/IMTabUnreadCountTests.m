//  IMTabUnreadCountTests.m
//  底部「消息」Tab 蓝点的计数（IMTabUnreadCount）。
//
//  与 im-web `src/components/SidebarTabs.test.tsx`（badgeCountOf）、im-android `TabUnreadTest` 同一组用例
//  （IMServer/docs/SYMMETRY.md 登记）。此前 iOS 这颗点根本没画，只有 Android 有（2026-09-15 用户报）。

#import <XCTest/XCTest.h>

#import "IMConversation.h"
#import "IMUnreadBadge.h"

@interface IMTabUnreadCountTests : XCTestCase
@end

@implementation IMTabUnreadCountTests

static IMConversation *Conv(NSInteger unread, BOOL muted, BOOL mention, BOOL marked) {
    IMConversation *c = [IMConversation new];
    c.unread = unread;
    c.muted = muted;
    c.mentionUnread = mention;
    c.markedUnread = marked;
    return c;
}

- (void)test_没有会话或全部已读为0 {
    XCTAssertEqual(IMTabUnreadCount(@[]), 0);
    XCTAssertEqual(IMTabUnreadCount(@[Conv(0, NO, NO, NO), Conv(0, NO, NO, NO)]), 0);
}

- (void)test_未免打扰的会话按条数累加 {
    XCTAssertEqual(IMTabUnreadCount(@[Conv(3, NO, NO, NO), Conv(4, NO, NO, NO)]), 7);
}

- (void)test_免打扰的会话不计 {
    XCTAssertEqual(IMTabUnreadCount(@[Conv(2, NO, NO, NO), Conv(99, YES, NO, NO)]), 2);
}

/// @ 穿透免打扰，但只记 1：它说的是「这里有事」，不把 40 条静音消息都算进来。
- (void)test_免打扰里被at只记1 {
    XCTAssertEqual(IMTabUnreadCount(@[Conv(40, YES, YES, NO)]), 1);
}

- (void)test_手动标为未读不点亮Tab {
    XCTAssertEqual(IMTabUnreadCount(@[Conv(0, NO, NO, YES)]), 0);
}

@end
