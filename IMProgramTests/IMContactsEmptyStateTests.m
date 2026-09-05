//  IMContactsEmptyStateTests.m
//  通讯录空态文案的落点：必须随表格内容排在入口行**下方**，不能浮在 self.view 中心。
//  app-hosted 测试，头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Modules/Contacts/IMContactsViewController.h"
#import "../IMProgram/Common/IMMenuAction.h"
#import "../IMProgram/Models/IMUserCard.h"

/// 被测私有成员（类扩展里合成的属性 + .m 内私有方法），测试内声明即可调用。
@interface IMContactsViewController (Testing)
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSArray<IMMenuAction *> *entries;
- (void)applyFriends:(NSArray *)friends;
@end

@interface IMContactsEmptyStateTests : XCTestCase
@end

@implementation IMContactsEmptyStateTests

- (IMContactsViewController *)loadedControllerWithNoFriends {
    IMContactsViewController *vc = [[IMContactsViewController alloc] initWithHost:@"http://127.0.0.1:8080" userID:@"u-test"];
    vc.view.frame = CGRectMake(0, 0, 402, 874); // iPhone 17 Pro Max 竖屏点尺寸
    [vc.view layoutIfNeeded];
    [vc applyFriends:@[]];
    [vc.view layoutIfNeeded];
    return vc;
}

/// 空态文案原先是 centerY 居中在 self.view 上，而顶部入口区（群聊/新的朋友/公众号/服务号）
/// 恰好在大标题导航栏之下延伸到屏幕正中——两段文字直接叠在一起（2026-09-05 用户实测）。
/// 判据不写死具体坐标（换机型/加一条入口就假绿），而是钉住**结构**：文案属于表格内容流，
/// 且排在最后一条入口行之后。老实现里它压根不是 tableView 的后代，这条即报红。
- (void)testEmptyHintFlowsAfterEntryRowsInsteadOfFloatingOverThem {
    IMContactsViewController *vc = [self loadedControllerWithNoFriends];

    XCTAssertFalse(vc.emptyLabel.hidden, @"没有好友时空态文案要显示");
    XCTAssertTrue([vc.emptyLabel isDescendantOfView:vc.tableView],
                  @"空态文案必须随表格内容排布（表尾），浮在 self.view 上迟早撞上入口行");

    NSInteger last = (NSInteger)vc.entries.count - 1;
    CGRect lastEntry = [vc.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:last inSection:0]];
    CGRect hint = [vc.tableView convertRect:vc.emptyLabel.bounds fromView:vc.emptyLabel];
    XCTAssertGreaterThanOrEqual(CGRectGetMinY(hint), CGRectGetMaxY(lastEntry),
                                @"空态文案压在最后一条入口（服务号）上了");
    XCTAssertGreaterThan(CGRectGetHeight(hint), 0.0, @"表尾不参与 Auto Layout，必须自己算出高度");
}

/// 有好友时不留表尾空白（不然列表底部凭空多出一段留白）。
- (void)testEmptyFooterGoesAwayWhenThereAreFriends {
    IMContactsViewController *vc = [self loadedControllerWithNoFriends];
    XCTAssertNotNil(vc.tableView.tableFooterView);

    NSArray *friends = [IMUserCard cardsFromArray:@[ @{ @"user_id": @"u-2", @"nickname": @"张三", @"status": @"accepted" } ]];
    [vc applyFriends:friends];
    XCTAssertNil(vc.tableView.tableFooterView, @"有好友了还挂着空态表尾 = 列表底部一段莫名留白");
}

@end
