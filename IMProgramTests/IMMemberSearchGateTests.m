//  IMMemberSearchGateTests.m
//  成员搜索入口的**出现判据**（IMShouldOfferMemberSearch）。
//
//  为什么值得单测：这条判据只有一句话，但用错字段的后果是静默的——
//  超级群刚进来 group.members 里只有我自己，若按 members.count 判，2 万人的群会被当成
//  「1 人小群」而不给搜索入口，恰恰是最需要搜索的那个场景没有入口。
//  这类 bug 不崩不报错，只能靠断言钉死。
//  app-hosted 测试，头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Models/IMGroupInfo.h"
#import "../IMProgram/Modules/Group/IMGroupMemberSearchViewController.h"

@interface IMMemberSearchGateTests : XCTestCase
@end

@implementation IMMemberSearchGateTests

/// 造一个群：memberCount 为服务端下发的真实总数，members 为**已加载**的那些。
static IMGroupInfo *MakeGroup(NSInteger memberCount, NSUInteger loadedMembers) {
    IMGroupInfo *g = [IMGroupInfo new];
    g.convID = @"g_test";
    g.memberCount = memberCount;
    NSMutableArray<IMGroupMember *> *ms = [NSMutableArray array];
    for (NSUInteger i = 0; i < loadedMembers; i++) {
        IMGroupMember *m = [IMGroupMember new];
        m.userID = [NSString stringWithFormat:@"u%lu", (unsigned long)i];
        [ms addObject:m];
    }
    g.members = ms;
    return g;
}

- (void)testNilGroupHasNoSearch {
    XCTAssertFalse(IMShouldOfferMemberSearch(nil), @"没有群资料时不该给入口");
}

- (void)testSmallGroupHasNoSearch {
    // 几十人的群整张列表就在眼前，为 5 个人打一次网络请求不合理。
    XCTAssertFalse(IMShouldOfferMemberSearch(MakeGroup(10, 10)));
    XCTAssertFalse(IMShouldOfferMemberSearch(MakeGroup(kIMMemberSearchMinMembers, kIMMemberSearchMinMembers)),
                   @"恰好等于阈值不给（判据是**超过**）");
}

- (void)testLargeGroupHasSearch {
    XCTAssertTrue(IMShouldOfferMemberSearch(MakeGroup(kIMMemberSearchMinMembers + 1, 20)));
    XCTAssertTrue(IMShouldOfferMemberSearch(MakeGroup(2000, 2000)), @"2000 人普通群同样要给");
}

/// **本测试的核心**：判据必须是 memberCount，不是已加载的 members.count。
- (void)testSuperGroupJudgedByMemberCountNotLoadedRows {
    // 超级群实况：服务端只回我自己（1 行），真实人数 20000。
    IMGroupInfo *superGroup = MakeGroup(20000, 1);
    XCTAssertTrue(IMShouldOfferMemberSearch(superGroup),
                  @"按 members.count(=1) 判会把 2 万人的群当小群、不给搜索入口——"
                  @"而那正是最需要搜索的场景");

    // 翻了一页之后（50 行已加载）同样要给。
    XCTAssertTrue(IMShouldOfferMemberSearch(MakeGroup(20000, 50)));
}

/// memberCount 缺失（老服务端/未下发）时回退到已加载行数，不能因此崩或恒 NO。
- (void)testFallsBackToLoadedCountWhenMemberCountMissing {
    XCTAssertFalse(IMShouldOfferMemberSearch(MakeGroup(0, 10)));
    XCTAssertTrue(IMShouldOfferMemberSearch(MakeGroup(0, kIMMemberSearchMinMembers + 1)));
}

#pragma mark - 滚到底自动续拉（PERF-members-autoload）

// 判据本身只有两行，但错一点后果都不小：提前量取反 = 一进页面就把 400 页全拉下来；
// 用 == 而不是 >= = 滚快一点就整个错过、"自动"变成"永远不动"。

/// 列表开头不拉；进入末尾提前量才拉。
- (void)testAutoLoadTriggersOnlyNearTheEnd {
    const NSInteger loaded = 50;
    XCTAssertFalse(IMShouldAutoLoadMoreMembers(0, loaded, YES, NO), @"第一行就拉 = 一进页面把 400 页全拉下来");
    XCTAssertFalse(IMShouldAutoLoadMoreMembers(loaded - kIMMemberAutoLoadLeadRows - 1, loaded, YES, NO));
    XCTAssertTrue(IMShouldAutoLoadMoreMembers(loaded - kIMMemberAutoLoadLeadRows, loaded, YES, NO), @"提前量边界（含）应触发");
    XCTAssertTrue(IMShouldAutoLoadMoreMembers(loaded - 1, loaded, YES, NO), @"最后一行当然要触发");
}

/// **用 >= 而不是 ==**：快速甩动/reloadData 后行会被跳着显示，只认相等就会整个错过。
- (void)testAutoLoadStillFiresWhenRowsAreSkipped {
    XCTAssertTrue(IMShouldAutoLoadMoreMembers(999, 50, YES, NO), @"下标越过末尾（跳着显示）仍应触发");
}

/// 没有下一页 / 已在路上 一律不拉——本函数不去抖，全靠这两个闸门挡住重复请求。
- (void)testAutoLoadRespectsGuards {
    XCTAssertFalse(IMShouldAutoLoadMoreMembers(49, 50, NO, NO), @"没有下一页");
    XCTAssertFalse(IMShouldAutoLoadMoreMembers(49, 50, YES, YES), @"在途中，重复触发会拉重同一页");
}

/// 首页还没回来（loaded=0）不抢跑：首屏加载由各页自己发起，这里插一脚会打两次同一个请求。
- (void)testAutoLoadDoesNotRaceFirstPage {
    XCTAssertFalse(IMShouldAutoLoadMoreMembers(0, 0, YES, NO));
}

@end
