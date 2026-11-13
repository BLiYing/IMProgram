//  IMContactsHomeTests.m
//  通讯录首页改版（../IMServer/docs/design/ORG_DIRECTORY_DESIGN.md §7）：入口行「我的好友」右值 = 好友数；
//  「最近联系」跟着会话列表广播重算，一个都没有时整段不出现；首页不再铺好友行。
//  app-hosted 测试，头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Modules/Contacts/IMContactsViewController.h"
#import "../IMProgram/Common/IMLocalization.h"
#import "../IMProgram/Common/IMMenuAction.h"
#import "../IMProgram/Models/IMConversation.h"
#import "../IMProgram/Models/IMUserCard.h"
#import "../IMProgram/Modules/Contacts/IMFriendRoster.h"
#import "../IMProgram/Common/IMRemarkStore.h"
#import <objc/runtime.h>

static NSString * const kHomeTestUID = @"u-home-test";

@interface IMContactsViewController (Testing) <UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<IMMenuAction *> *entries;
@property (nonatomic, copy) NSArray<IMConversation *> *recentContacts;
@property (nonatomic, assign) BOOL refreshInFlight;
- (void)applyRoster:(IMFriendRoster *)roster;
@end

/// 数 reloadData 次数：测试里把首页表格的 isa 换成它（不加 ivar，object_setClass 安全）。
static NSInteger sHomeReloadCount;
@interface IMHomeCountingTableView : UITableView
@end
@implementation IMHomeCountingTableView
- (void)reloadData { sHomeReloadCount++; [super reloadData]; }
@end

@interface IMContactsHomeTests : XCTestCase
@property (nonatomic, strong) NSMutableArray<IMContactsViewController *> *shown;
@end

@implementation IMContactsHomeTests

- (void)setUp {
    [super setUp];
    self.shown = [NSMutableArray array];
}

- (void)tearDown {
    for (IMContactsViewController *vc in self.shown) { [vc viewDidDisappear:NO]; } // 摘掉重连刷新等可见态
    // XCTest 的用例对象活到整轮结束：不放掉的话这些页面会一直收好友事件 / 本机关系变更通知并去 reload，
    // 改掉 IMHTTPService 的全局 host，把后面的 HTTP 单测带红。
    self.shown = nil;
    [super tearDown];
}

- (IMContactsViewController *)loadedController {
    IMContactsViewController *vc = [[IMContactsViewController alloc] initWithHost:@"http://127.0.0.1:8080" userID:kHomeTestUID];
    vc.view.frame = CGRectMake(0, 0, 402, 874);
    [vc.view layoutIfNeeded];
    return vc;
}

/// 模拟切到通讯录 Tab。先把「请求在途」置上，让切入刷新的节流判据跳过网络（单测不拉接口）。
- (void)showController:(IMContactsViewController *)vc {
    vc.refreshInFlight = YES;
    [vc viewWillAppear:NO];
    [self.shown addObject:vc];
    [vc.view layoutIfNeeded];
}

- (IMContactsViewController *)visibleController {
    IMContactsViewController *vc = [self loadedController];
    [self showController:vc];
    return vc;
}

- (IMConversation *)singleWithID:(NSString *)convID peer:(NSString *)peer name:(NSString *)name timestamp:(int64_t)timestamp {
    IMConversation *c = [IMConversation new];
    c.convID = convID;
    c.peer = peer;
    c.peerNickname = name;
    c.timestamp = timestamp;
    return c;
}

- (void)broadcast:(NSArray<IMConversation *> *)conversations owner:(NSString *)owner {
    [NSNotificationCenter.defaultCenter postNotificationName:IMConversationListDidChangeNotification object:nil
        userInfo:@{ kIMConversationListKey: conversations, kIMConversationListOwnerKey: owner }];
}

/// 一个 cell 里所有可见 UILabel 的文字（入口 cell 是 .m 内私有类，按上屏文字断言）。
- (NSArray<NSString *> *)labelTextsInCell:(UITableViewCell *)cell {
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:cell.contentView];
    while (queue.count > 0) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([view isKindOfClass:UILabel.class] && !view.hidden && ((UILabel *)view).text.length > 0) {
            [texts addObject:((UILabel *)view).text];
        }
        [queue addObjectsFromArray:view.subviews];
    }
    return texts;
}

/// 经数据源现配一个 cell（看「此刻该显示什么」）。
- (NSArray<NSString *> *)labelTextsInRow:(NSInteger)row section:(NSInteger)section of:(IMContactsViewController *)vc {
    return [self labelTextsInCell:[vc tableView:vc.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]]];
}

/// 表格上**正在显示**的那个 cell（看「屏幕上真的刷新了没有」）。
- (NSArray<NSString *> *)onScreenTextsInRow:(NSInteger)row section:(NSInteger)section of:(IMContactsViewController *)vc {
    [vc.tableView layoutIfNeeded];
    UITableViewCell *cell = [vc.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
    XCTAssertNotNil(cell, @"该行应在屏");
    return cell ? [self labelTextsInCell:cell] : @[];
}

- (NSInteger)rowOfEntry:(NSString *)actionID in:(IMContactsViewController *)vc {
    for (NSUInteger i = 0; i < vc.entries.count; i++) {
        if ([vc.entries[i].actionId isEqualToString:actionID]) { return (NSInteger)i; }
    }
    return NSNotFound;
}

- (IMFriendRoster *)rosterWith:(NSArray<NSDictionary *> *)dicts {
    return [IMFriendRoster rosterWithFriends:[IMUserCard cardsFromArray:dicts]];
}

/// 好友再多首页也只有入口区：好友行搬去「我的好友」页了；右值只写数字，待处理申请不计入。
/// 断言的是**屏幕上那个 cell**：applyRoster: 里不刷入口区的话，右值会停在旧数上。
- (void)testMyFriendsEntryValueRefreshesOnScreenAfterRoster {
    IMContactsViewController *vc = [self visibleController];
    NSInteger row = [self rowOfEntry:@"myFriends" in:vc];
    XCTAssertNotEqual(row, NSNotFound, @"入口区要有「我的好友」");
    XCTAssertEqual(row, (NSInteger)vc.entries.count - 1, @"「我的好友」排在既有入口之后");
    [vc applyRoster:[self rosterWith:@[]]];
    XCTAssertEqualObjects([self onScreenTextsInRow:row section:0 of:vc], (@[IMLocalized(@"contacts.entry.my_friends"), @"0"]));

    [vc applyRoster:[self rosterWith:@[
        @{ @"user_id": @"u-2", @"nickname": @"张三", @"status": @"accepted" },
        @{ @"user_id": @"u-3", @"nickname": @"李四", @"status": @"accepted" },
        @{ @"user_id": @"u-4", @"nickname": @"王五", @"status": @"pending" },
    ]]];
    XCTAssertEqual(vc.tableView.numberOfSections, 1, @"没有最近联系时只有入口区，好友不再铺在首页");
    XCTAssertEqualObjects([self onScreenTextsInRow:row section:0 of:vc], (@[IMLocalized(@"contacts.entry.my_friends"), @"2"]),
                          @"applyRoster: 后屏幕上的好友数要跟着变");
    NSInteger requestRow = [self rowOfEntry:@"friendRequests" in:vc];
    XCTAssertEqualObjects([self onScreenTextsInRow:requestRow section:0 of:vc], (@[IMLocalized(@"friend.requests.title"), @"1"]),
                          @"「新的朋友」仍显待确认数徽标");
}

/// 会话列表一广播（本页在屏），最近联系就按纯函数的结果重排；清空后整段消失。
- (void)testRecentSectionFollowsConversationListBroadcast {
    IMContactsViewController *vc = [self visibleController];
    [self broadcast:@[] owner:kHomeTestUID];
    XCTAssertEqual(vc.tableView.numberOfSections, 1, @"还没有任何会话：整段不出现");

    IMConversation *group = [self singleWithID:@"g1" peer:@"" name:@"群" timestamp:900];
    group.isGroup = YES;
    [self broadcast:@[[self singleWithID:@"c1" peer:@"u-1" name:@"较早的人" timestamp:100],
                      group,
                      [self singleWithID:@"c2" peer:@"u-2" name:@"最近的人" timestamp:300]]
              owner:kHomeTestUID];
    XCTAssertEqual(vc.tableView.numberOfSections, 2);
    XCTAssertEqualObjects([vc tableView:vc.tableView titleForHeaderInSection:1], IMLocalized(@"contacts.recent.title"));
    XCTAssertEqual([vc.tableView numberOfRowsInSection:1], 2, @"群聊不进最近联系");
    XCTAssertEqualObjects([self labelTextsInRow:0 section:1 of:vc].lastObject, @"最近的人");
    XCTAssertEqualObjects([self labelTextsInRow:1 section:1 of:vc].lastObject, @"较早的人");
    XCTAssertFalse([vc respondsToSelector:@selector(sectionIndexTitlesForTableView:)], @"首页没有右侧索引");

    [self broadcast:@[group] owner:kHomeTestUID];
    XCTAssertEqual(vc.tableView.numberOfSections, 1, @"单聊都没了：整段消失");
}

/// 不在屏（用户停在「消息」Tab）时收到广播只存不算；切回来（viewWillAppear）才算，结果与即时算一致。
- (void)testHiddenPageDefersRecomputeUntilVisible {
    IMContactsViewController *vc = [self visibleController];
    [self broadcast:@[[self singleWithID:@"c1" peer:@"u-1" name:@"甲" timestamp:100]] owner:kHomeTestUID];
    XCTAssertEqualObjects([vc.recentContacts valueForKey:@"convID"], (@[@"c1"]));

    [vc viewDidDisappear:NO];
    [self broadcast:@[[self singleWithID:@"c1" peer:@"u-1" name:@"甲" timestamp:100],
                      [self singleWithID:@"c2" peer:@"u-2" name:@"乙" timestamp:200]] owner:kHomeTestUID];
    XCTAssertEqualObjects([vc.recentContacts valueForKey:@"convID"], (@[@"c1"]), @"不可见时不重算");
    [[NSNotificationCenter defaultCenter] postNotificationName:IMRemarkStoreDidChangeNotification object:nil];
    XCTAssertEqualObjects([vc.recentContacts valueForKey:@"convID"], (@[@"c1"]), @"不可见时备注变更也只置脏");

    [vc viewWillAppear:NO];
    XCTAssertEqualObjects([vc.recentContacts valueForKey:@"convID"], (@[@"c2", @"c1"]), @"变为可见后按最新数组算");
    XCTAssertEqual([vc.tableView numberOfRowsInSection:1], 2);
    XCTAssertEqualObjects([self labelTextsInRow:0 section:1 of:vc].lastObject, @"乙");
}

/// 上屏内容（成员 / 顺序 / 显示名 / 头像）没变就不 reloadData——消息一条条进来，会话数组每次都换新对象。
- (void)testUnchangedSignatureSkipsReloadData {
    IMContactsViewController *vc = [self visibleController];
    object_setClass(vc.tableView, IMHomeCountingTableView.class);
    sHomeReloadCount = 0;
    [self broadcast:@[[self singleWithID:@"c1" peer:@"u-1" name:@"甲" timestamp:100]] owner:kHomeTestUID];
    XCTAssertEqual(sHomeReloadCount, 1, @"第一次有内容要刷");

    IMConversation *sameButNewer = [self singleWithID:@"c1" peer:@"u-1" name:@"甲" timestamp:150];
    sameButNewer.unread = 3;
    [self broadcast:@[sameButNewer] owner:kHomeTestUID];
    XCTAssertEqual(sHomeReloadCount, 1, @"签名不变（时间 / 未读变了不算）不刷");
    XCTAssertEqual(vc.recentContacts.firstObject, sameButNewer, @"对象仍换成最新的（进聊天要带最新位点）");

    [self broadcast:@[[self singleWithID:@"c1" peer:@"u-1" name:@"甲改名" timestamp:150]] owner:kHomeTestUID];
    XCTAssertEqual(sHomeReloadCount, 2, @"显示名变了要刷");
}

/// 备注 / 注销登记变更（IMRemarkStoreDidChangeNotification）→ 在屏时就地重算显示名。
- (void)testRemarkChangeRecomputesRecentContacts {
    IMContactsViewController *vc = [self visibleController];
    IMConversation *c = [self singleWithID:@"c1" peer:@"u-remark-test" name:@"旧名" timestamp:100];
    [self broadcast:@[c] owner:kHomeTestUID];
    XCTAssertEqualObjects([self onScreenTextsInRow:0 section:1 of:vc].lastObject, @"旧名");

    c.peerNickname = @"新名"; // 同一对象：显示名变了但没有新的会话广播，只有备注通知
    [[NSNotificationCenter defaultCenter] postNotificationName:IMRemarkStoreDidChangeNotification object:nil];
    XCTAssertEqualObjects([self onScreenTextsInRow:0 section:1 of:vc].lastObject, @"新名");
}

/// 别的账号的会话列表广播（换号过渡期旧页面发的）不能进本页。
- (void)testBroadcastFromAnotherAccountIsIgnored {
    IMContactsViewController *vc = [self visibleController];
    [self broadcast:@[[self singleWithID:@"c1" peer:@"u-1" name:@"别人的联系人" timestamp:100]] owner:@"u-someone-else"];
    XCTAssertEqual(vc.recentContacts.count, 0u);
    XCTAssertEqual(vc.tableView.numberOfSections, 1);
}

/// 页面还没加载（没切到通讯录 Tab）时收到的广播也要记住，首次显示就是最新的。
- (void)testBroadcastBeforeViewLoadIsKept {
    IMContactsViewController *vc = [[IMContactsViewController alloc] initWithHost:@"http://127.0.0.1:8080" userID:kHomeTestUID];
    [self broadcast:@[[self singleWithID:@"c1" peer:@"u-1" name:@"早到的人" timestamp:100]] owner:kHomeTestUID];
    XCTAssertFalse(vc.isViewLoaded, @"广播不该把页面提前加载出来");
    vc.view.frame = CGRectMake(0, 0, 402, 874);
    [self showController:vc];
    XCTAssertEqual(vc.tableView.numberOfSections, 2);
    XCTAssertEqualObjects([self labelTextsInRow:0 section:1 of:vc].lastObject, @"早到的人");
}

@end
