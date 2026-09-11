//  IMFriendPickerIndexTests.m
//  选好友页的 A–Z 分组改在后台算（候选是 2000 人好友全集时，同步算会让打开页面 / 每敲一个字都卡）：
//  分组回来后行必须真的出现，搜索必须真的收窄——只算不赋值 / 不 reloadData，页面就一直是空的或不跟手。
//  用注入候选，不联网。app-hosted 测试。

#import <XCTest/XCTest.h>

#import "IMFriendPickerViewController.h"
#import "IMUserCard.h"

/// 被测私有成员（类扩展里合成的属性 + 搜索框代理方法），测试内声明即可调用。
@interface IMFriendPickerViewController (Testing)
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText;
@end

@interface IMFriendPickerIndexTests : XCTestCase
@end

@implementation IMFriendPickerIndexTests

- (IMUserCard *)cardWithID:(NSString *)uid nickname:(NSString *)nick {
    return [IMUserCard cardsFromArray:@[ @{ @"user_id": uid, @"nickname": nick, @"status": @"accepted" } ]].firstObject;
}

- (void)waitUntilTable:(UITableView *)table hasSections:(NSInteger)sections {
    NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(UITableView *t, NSDictionary *bindings) {
        return t.numberOfSections == sections;
    }];
    [self expectationForPredicate:p evaluatedWithObject:table handler:nil];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testCandidatesAppearAndSearchNarrowsAfterBackgroundIndexBuild {
    NSArray<IMUserCard *> *candidates = @[
        [self cardWithID:@"pk-1" nickname:@"刘备"],
        [self cardWithID:@"pk-2" nickname:@"张三"],
        [self cardWithID:@"pk-3" nickname:@"李四"],
    ];
    IMFriendPickerViewController *vc =
        [[IMFriendPickerViewController alloc] initWithHost:@"http://127.0.0.1:8080" userID:@"pk-me"
                                                candidates:candidates excludedIDs:nil
                                                     title:@"选择好友" confirmTitle:@"确定"
                                                    onDone:^(NSArray<NSString *> *selectedIDs) {}];
    vc.view.frame = CGRectMake(0, 0, 402, 874);
    [vc.view layoutIfNeeded];

    [self waitUntilTable:vc.tableView hasSections:2]; // L（李四、刘备）+ Z（张三）
    XCTAssertEqual([vc.tableView numberOfRowsInSection:0], 2);
    XCTAssertEqual([vc.tableView numberOfRowsInSection:1], 1);

    vc.searchBar.text = @"张";
    [vc searchBar:vc.searchBar textDidChange:@"张"];
    [self waitUntilTable:vc.tableView hasSections:1];
    XCTAssertEqual([vc.tableView numberOfRowsInSection:0], 1);
}

@end
