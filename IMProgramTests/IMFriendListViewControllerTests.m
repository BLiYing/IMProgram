//  IMFriendListViewControllerTests.m
//  「我的好友」页（原通讯录页的好友列表，2026-11-13 搬出；前身 IMContactsEmptyStateTests）：
//  空态文案随表格内容排布、有好友时不留表尾、后台分组完成后好友行真的出现。
//  app-hosted 测试，头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Modules/Contacts/IMFriendListViewController.h"
#import "../IMProgram/Common/IMLocalization.h"
#import "../IMProgram/Models/IMUserCard.h"
#import "../IMProgram/Modules/Contacts/IMFriendRoster.h"

/// 被测私有成员（类扩展里合成的属性 + .m 内私有方法），测试内声明即可调用。
@interface IMFriendListViewController (Testing) <UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSArray<IMUserCard *> *accepted;
- (void)applyRoster:(IMFriendRoster *)roster;
@end

@interface IMFriendListViewControllerTests : XCTestCase
@end

@implementation IMFriendListViewControllerTests

- (IMFriendRoster *)rosterWith:(NSArray<NSDictionary *> *)dicts {
    return [IMFriendRoster rosterWithFriends:[IMUserCard cardsFromArray:dicts]];
}

- (IMFriendListViewController *)loadedControllerWithNoFriends {
    IMFriendListViewController *vc = [[IMFriendListViewController alloc] initWithHost:@"http://127.0.0.1:8080" userID:@"u-test"
                                                                         seedFriends:nil];
    vc.view.frame = CGRectMake(0, 0, 402, 874); // iPhone 17 Pro Max 竖屏点尺寸
    [vc.view layoutIfNeeded];
    [vc applyRoster:[self rosterWith:@[]]];
    [vc.view layoutIfNeeded];
    return vc;
}

/// 空态文案属于表格内容流（表尾），不浮在 self.view 上；表尾不参与 Auto Layout，高度必须自己算出来。
- (void)testEmptyHintLivesInTableFooterWithRealHeight {
    IMFriendListViewController *vc = [self loadedControllerWithNoFriends];

    XCTAssertEqualObjects(vc.title, IMLocalized(@"contacts.entry.my_friends"));
    XCTAssertEqualObjects(vc.emptyLabel.text, IMLocalized(@"contacts.friends.empty"));
    XCTAssertTrue([vc.emptyLabel isDescendantOfView:vc.tableView], @"空态文案必须随表格内容排布（表尾）");
    XCTAssertNotNil(vc.tableView.tableFooterView);
    CGRect hint = [vc.tableView convertRect:vc.emptyLabel.bounds fromView:vc.emptyLabel];
    XCTAssertGreaterThan(CGRectGetHeight(hint), 0.0, @"表尾不参与 Auto Layout，必须自己算出高度");
    XCTAssertEqual(vc.tableView.numberOfSections, 0, @"没有好友就没有字母分组");
}

/// 有好友时不留表尾空白（不然列表底部凭空多出一段留白）；待处理申请不算好友，不能让空态消失。
- (void)testEmptyFooterGoesAwayOnlyWhenThereAreAcceptedFriends {
    IMFriendListViewController *vc = [self loadedControllerWithNoFriends];

    [vc applyRoster:[self rosterWith:@[ @{ @"user_id": @"u-9", @"nickname": @"申请人", @"status": @"pending" } ]]];
    XCTAssertNotNil(vc.tableView.tableFooterView, @"只有待处理申请时仍然是「还没有好友」");

    [vc applyRoster:[self rosterWith:@[ @{ @"user_id": @"u-2", @"nickname": @"张三", @"status": @"accepted" } ]]];
    XCTAssertNil(vc.tableView.tableFooterView, @"有好友了还挂着空态表尾 = 列表底部一段莫名留白");
}

/// 好友 A–Z 分组在后台算（2000 人同步算会卡住数百毫秒）：applyRoster: 当场返回，
/// 索引回来后分组必须真的出现——只算不赋值 / 不 reloadData，列表就一直是空的。
- (void)testFriendRowsAppearAfterBackgroundIndexBuild {
    IMFriendListViewController *vc = [self loadedControllerWithNoFriends];
    [vc applyRoster:[self rosterWith:@[
        @{ @"user_id": @"u-2", @"nickname": @"张三", @"status": @"accepted" },
        @{ @"user_id": @"u-3", @"nickname": @"李四", @"status": @"accepted" },
        @{ @"user_id": @"u-4", @"nickname": @"王五", @"status": @"pending" }, // 申请中的不进好友列表
    ]]];
    NSPredicate *lettersShown = [NSPredicate predicateWithBlock:^BOOL(UITableView *table, NSDictionary *bindings) {
        return table.numberOfSections == 2; // L + Z
    }];
    [self expectationForPredicate:lettersShown evaluatedWithObject:vc.tableView handler:nil];
    [self waitForExpectationsWithTimeout:5 handler:nil];
    XCTAssertEqual([vc.tableView numberOfRowsInSection:0], 1);
    XCTAssertEqual([vc.tableView numberOfRowsInSection:1], 1);
    XCTAssertEqualObjects([vc sectionIndexTitlesForTableView:vc.tableView], (@[@"L", @"Z"]));
}

/// 首页把手上的好友名单当种子交过来：首屏直接用它（不再在主线程读整张好友表），分组照常后台算出来。
- (void)testSeedFriendsFromHomeAreUsedAsFirstScreen {
    NSArray<IMUserCard *> *seed = [IMUserCard cardsFromArray:@[
        @{ @"user_id": @"u-seed-1", @"nickname": @"种子甲", @"status": @"accepted" },
        @{ @"user_id": @"u-seed-2", @"nickname": @"种子乙", @"status": @"accepted" },
    ]];
    IMFriendListViewController *vc = [[IMFriendListViewController alloc] initWithHost:@"http://127.0.0.1:8080" userID:@"u-test"
                                                                         seedFriends:seed];
    XCTAssertEqualObjects([vc.accepted valueForKey:@"userID"], (@[@"u-seed-1", @"u-seed-2"]));
    vc.view.frame = CGRectMake(0, 0, 402, 874);
    [vc.view layoutIfNeeded];
    NSPredicate *shown = [NSPredicate predicateWithBlock:^BOOL(UITableView *table, NSDictionary *bindings) {
        return table.numberOfSections == 1 && [table numberOfRowsInSection:0] == 2; // 都是 Z
    }];
    [self expectationForPredicate:shown evaluatedWithObject:vc.tableView handler:nil];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

@end
