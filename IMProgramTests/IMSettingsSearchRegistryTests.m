//  IMSettingsSearchRegistryTests.m
//  设置项搜索登记表：登记不变式、匹配（title+path 子串、大小写、trim）、排序、与「我」页一级行 / 路由表的对账。

#import <XCTest/XCTest.h>
#import "IMSettingsSearchRegistry.h"
#import "IMSettingsRouter.h"
#import "IMSettingsViewController.h"
#import "IMMainTabBarController.h"
#import "IMNotificationSettingsViewController.h"
#import "IMNotificationTypeViewController.h"
#import "IMNotificationSoundViewController.h"
#import "IMPrivacySecurityViewController.h"
#import "IMBlockedListViewController.h"
#import "IMChangePasswordViewController.h"
#import "IMDataStorageViewController.h"
#import "IMAutoDownloadNetworkViewController.h"
#import "IMAutoDownloadCategoryViewController.h"

@interface IMSettingsSearchRegistryTests : XCTestCase
@end

@implementation IMSettingsSearchRegistryTests

- (NSArray<IMSettingsSearchEntry *> *)all { return [IMSettingsSearchRegistry allEntries]; }

- (NSArray<NSString *> *)idsOf:(NSArray<IMSettingsSearchEntry *> *)entries {
    NSMutableArray *ids = [NSMutableArray array];
    for (IMSettingsSearchEntry *e in entries) { [ids addObject:e.entryID]; }
    return ids;
}

- (IMSettingsSearchEntry *)entry:(NSString *)entryID {
    for (IMSettingsSearchEntry *e in [self all]) { if ([e.entryID isEqualToString:entryID]) { return e; } }
    XCTFail(@"登记表里没有 %@", entryID);
    return nil;
}

#pragma mark - 登记不变式

- (void)testEntriesAreWellFormed {
    NSMutableSet *seen = [NSMutableSet set];
    for (IMSettingsSearchEntry *e in [self all]) {
        XCTAssertTrue(e.entryID.length > 0 && e.title.length > 0, @"%@ 缺 id/title", e.entryID);
        XCTAssertFalse([seen containsObject:e.entryID], @"id 重复 %@", e.entryID);
        [seen addObject:e.entryID];
        XCTAssertEqual(e.route.count, e.path.count, @"%@ 的 route 与 path 必须逐级对应", e.entryID);
        XCTAssertEqualObjects(e.path.lastObject, e.title, @"%@ 的 path 末项应是自身标题", e.entryID);
        XCTAssertTrue(e.systemImage.length > 0 && e.iconBg, @"%@ 缺图标", e.entryID);
    }
}

/// 登记表里每个页面 id 都必须有路由（纯动作行 shareMyCard 除外），否则搜到却点不开。
- (void)testEveryRouteStepIsBuildable {
    for (IMSettingsSearchEntry *e in [self all]) {
        for (NSString *pageID in e.route) {
            if ([pageID isEqualToString:@"shareMyCard"]) { continue; }
            XCTAssertTrue([IMSettingsRouter canBuildPageID:pageID], @"%@ 的页面 id %@ 没有路由", e.entryID, pageID);
        }
    }
}

- (void)testExcludedItemsAreNotIndexed {
    NSArray *ids = [self idsOf:[self all]];
    XCTAssertFalse([ids containsObject:@"logout"], @"退出登录不进索引");
    XCTAssertFalse([ids containsObject:@"folders"], @"开发中的聊天文件夹不进索引");
}

/// 与「我」页对账：一级行（非破坏性）要么已登记、要么在显式排除名单里；登记的一级条目必须真有这一行。
- (void)testTopLevelEntriesMatchSettingsPageRows {
    IMSettingsViewController *vc = [[IMSettingsViewController alloc] initWithHost:@"http://127.0.0.1:1" userID:@"u_test"];
    NSArray<NSString *> *rowIDs = [vc nonDestructiveRowIDs];
    NSSet *excluded = [NSSet setWithObject:@"folders"]; // 开发中
    NSMutableSet *registeredTop = [NSMutableSet set];
    for (IMSettingsSearchEntry *e in [self all]) {
        if (e.route.count == 1) { [registeredTop addObject:e.entryID]; }
    }
    for (NSString *rid in rowIDs) {
        if ([excluded containsObject:rid]) { continue; }
        XCTAssertTrue([registeredTop containsObject:rid], @"「我」页一级行 %@ 未登记进搜索", rid);
    }
    for (NSString *rid in registeredTop) {
        XCTAssertTrue([rowIDs containsObject:rid], @"登记了「我」页没有的一级行 %@", rid);
    }
}

- (void)testScopeCoversRequiredSecondLevelPages {
    NSArray *ids = [self idsOf:[self all]];
    for (NSString *want in @[@"notifications.private", @"notifications.group", @"notifications.private.sound", @"notifications.group.sound",
                             @"privacy.blocked", @"privacy.changePassword", @"storage.cellular", @"storage.wifi",
                             @"storage.cellular.image", @"storage.cellular.video", @"storage.cellular.file",
                             @"storage.wifi.image", @"storage.wifi.video", @"storage.wifi.file",
                             @"appearance", @"powerSaving", @"language", @"devices"]) {
        XCTAssertTrue([ids containsObject:want], @"缺登记 %@", want);
    }
}

#pragma mark - 副标题

- (void)testSubtitleJoinsPathWithArrow {
    IMSettingsSearchEntry *sound = [self entry:@"notifications.private.sound"];
    XCTAssertEqual(sound.path.count, 3u);
    XCTAssertEqualObjects(sound.subtitle, [sound.path componentsJoinedByString:@" › "]);
    XCTAssertTrue([sound.subtitle containsString:@" › "]);
}

- (void)testTopLevelSubtitleIsNotTitleRepeat {
    IMSettingsSearchEntry *e = [self entry:@"language"];
    XCTAssertNotEqualObjects(e.subtitle, e.title);
    XCTAssertTrue(e.subtitle.length > 0);
}

#pragma mark - 匹配

- (void)testBlankKeywordMatchesNothing {
    XCTAssertEqual([IMSettingsSearchRegistry filterEntries:[self all] keyword:@""].count, 0u);
    XCTAssertEqual([IMSettingsSearchRegistry filterEntries:[self all] keyword:@"  \n"].count, 0u);
    XCTAssertEqual([IMSettingsSearchRegistry filterEntries:[self all] keyword:nil].count, 0u);
}

- (void)testNoHit {
    XCTAssertEqual([IMSettingsSearchRegistry filterEntries:[self all] keyword:@"zzzzqqq"].count, 0u);
}

/// 夹具：固定文案，避免被界面语言牵着走。
- (NSArray<IMSettingsSearchEntry *> *)fixture {
    return @[
        [IMSettingsSearchEntry entryWithID:@"n" title:@"Notifications" path:@[@"Notifications"] systemImage:@"bell" iconBg:nil route:@[@"n"]],
        [IMSettingsSearchEntry entryWithID:@"n.sound" title:@"Sound" path:@[@"Notifications", @"Sound"] systemImage:@"bell" iconBg:nil route:@[@"n", @"n/s"]],
        [IMSettingsSearchEntry entryWithID:@"a.sound" title:@"Sound" path:@[@"Appearance", @"Sound"] systemImage:@"bell" iconBg:nil route:@[@"a", @"a/s"]],
        [IMSettingsSearchEntry entryWithID:@"p" title:@"Privacy" path:@[@"Privacy"] systemImage:@"bell" iconBg:nil route:@[@"p"]],
    ];
}

- (void)testCaseInsensitiveTrimmedSubstringOnTitle {
    NSArray *hits = [IMSettingsSearchRegistry filterEntries:[self fixture] keyword:@"  PRIV "];
    XCTAssertEqualObjects([self idsOf:hits], @[@"p"]);
}

/// 同名条目靠 path 区分：按路径词能把其中一个筛出来。
- (void)testPathDisambiguatesSameTitle {
    XCTAssertEqualObjects([self idsOf:[IMSettingsSearchRegistry filterEntries:[self fixture] keyword:@"sound"]], (@[@"n.sound", @"a.sound"]));
    NSArray *viaPath = [IMSettingsSearchRegistry filterEntries:[self fixture] keyword:@"appearance"];
    XCTAssertEqualObjects([self idsOf:viaPath], @[@"a.sound"]);
}

/// 只在 path 里出现的词也能命中（「Notifications」命中其下的 Sound）。
- (void)testPathOnlyHit {
    XCTAssertTrue([[self idsOf:[IMSettingsSearchRegistry filterEntries:[self fixture] keyword:@"notif"]] containsObject:@"n.sound"]);
}

#pragma mark - 排序

/// title 命中排在仅 path 命中之前；同档保持登记顺序。
- (void)testTitleHitsRankBeforePathOnlyHits {
    NSArray<IMSettingsSearchEntry *> *shuffled = @[
        [IMSettingsSearchEntry entryWithID:@"deep" title:@"Sound" path:@[@"Notifications", @"Sound"] systemImage:@"x" iconBg:nil route:@[@"n", @"n/s"]],
        [IMSettingsSearchEntry entryWithID:@"top" title:@"Notifications" path:@[@"Notifications"] systemImage:@"x" iconBg:nil route:@[@"n"]],
        [IMSettingsSearchEntry entryWithID:@"deep2" title:@"Banner" path:@[@"Notifications", @"Banner"] systemImage:@"x" iconBg:nil route:@[@"n", @"n/b"]],
    ];
    NSArray *hits = [IMSettingsSearchRegistry filterEntries:shuffled keyword:@"notifications"];
    XCTAssertEqualObjects([self idsOf:hits], (@[@"top", @"deep", @"deep2"]));
}

#pragma mark - 真实登记表（用当前语言的真实文案取词，语言无关）

- (void)testRealRegistryFindsNotificationSoundByItsOwnTitleAndPath {
    IMSettingsSearchEntry *sound = [self entry:@"notifications.private.sound"];
    NSArray *hits = [IMSettingsSearchRegistry filterEntries:[self all] keyword:sound.title];
    XCTAssertTrue([[self idsOf:hits] containsObject:@"notifications.private.sound"]);
    XCTAssertTrue([[self idsOf:hits] containsObject:@"notifications.group.sound"], @"同名条目靠 path 区分、都应出现");
    // 按「上级页标题」搜：该页及其下级都在
    NSArray *viaParent = [IMSettingsSearchRegistry filterEntries:[self all] keyword:sound.path[1]];
    XCTAssertTrue([[self idsOf:viaParent] containsObject:@"notifications.private.sound"]);
}

/// 同义词：「提示音」页可被「声音」搜到，且算标题命中档（排在仅路径命中之前）。
- (void)testSoundAliasHitsNotificationSoundPages {
    NSArray *hits = [IMSettingsSearchRegistry filterEntries:[self all] keyword:@"声音"];
    NSArray *ids = [self idsOf:hits];
    XCTAssertTrue([ids containsObject:@"notifications.private.sound"]);
    XCTAssertTrue([ids containsObject:@"notifications.group.sound"]);
    XCTAssertEqual(ids.count, 2u, @"别名只挂在提示音页，不应牵出别的条目");
}

#pragma mark - 路由与父 VC 构造一致 / 无法构建的路由

/// router 构造的页面类型必须与各父 VC tap push 的一致（见 IMSettingsRouter.m 顶部「重复构造点」清单）。
- (void)testRouterBuildsSamePageClassesAsParentPushes {
    NSDictionary<NSString *, Class> *expected = @{
        @"notifications": IMNotificationSettingsViewController.class,
        @"notifications/private": IMNotificationTypeViewController.class,
        @"notifications/group": IMNotificationTypeViewController.class,
        @"notifications/private/sound": IMNotificationSoundViewController.class,
        @"notifications/group/sound": IMNotificationSoundViewController.class,
        @"privacy": IMPrivacySecurityViewController.class,
        @"privacy/blocked": IMBlockedListViewController.class,
        @"privacy/changePassword": IMChangePasswordViewController.class,
        @"storage": IMDataStorageViewController.class,
        @"storage/cellular": IMAutoDownloadNetworkViewController.class,
        @"storage/wifi": IMAutoDownloadNetworkViewController.class,
        @"storage/wifi/video": IMAutoDownloadCategoryViewController.class,
        @"storage/cellular/file": IMAutoDownloadCategoryViewController.class,
    };
    [expected enumerateKeysAndObjectsUsingBlock:^(NSString *pageID, Class cls, BOOL *stop) {
        NSArray *vcs = [IMSettingsRouter viewControllersForRoute:@[pageID] host:@"h" userID:@"1"];
        XCTAssertEqual(vcs.count, 1u, @"%@", pageID);
        XCTAssertTrue([vcs.firstObject isKindOfClass:cls], @"%@ 应建出 %@，实际 %@", pageID, cls, [vcs.firstObject class]);
    }];
}

- (void)testActionRouteIsNotBuildableAsPage {
    XCTAssertTrue([IMSettingsRouter isActionRoute:@[@"shareMyCard"]]);
    XCTAssertNil([IMSettingsRouter viewControllersForRoute:@[@"shareMyCard"] host:@"h" userID:@"1"]);
    XCTAssertFalse([IMSettingsRouter isActionRoute:@[@"nope"]]);
    NSArray<NSString *> *multi = @[@"notifications", @"shareMyCard"];
    XCTAssertFalse([IMSettingsRouter isActionRoute:multi]);
}

/// 无法构建的路由：不崩、不动导航状态（留在原 tab 与搜索页），而不是关掉搜索页却什么都不开。
- (void)testUnbuildableRouteLeavesNavigationUntouched {
    IMMainTabBarController *tab = [[IMMainTabBarController alloc] initWithHost:@"http://127.0.0.1:1" userID:@"1"];
    [tab loadViewIfNeeded];
    UIViewController *before = tab.selectedViewController;
    UINavigationController *searchNav = [[UINavigationController alloc] initWithRootViewController:[UIViewController new]];
    [searchNav pushViewController:[UIViewController new] animated:NO];
    IMSettingsSearchEntry *bad = [IMSettingsSearchEntry entryWithID:@"bogus" title:@"Bogus" path:@[@"Bogus"]
                                                        systemImage:@"x" iconBg:nil route:@[@"no/such/page"]];
    [tab openSettingsSearchEntry:bad fromSearchNavigation:searchNav]; // 不崩即过第一关
    XCTAssertEqual(tab.selectedViewController, before, @"建不出页面不应切 tab");
    XCTAssertEqual(searchNav.viewControllers.count, 2u, @"建不出页面不应关掉搜索页");
}

/// 同义词：「自动下载」命中两个网络页（页面标题里没有这几个字）。
- (void)testAutoDownloadAliasHitsNetworkPages {
    NSArray *ids = [self idsOf:[IMSettingsSearchRegistry filterEntries:[self all] keyword:@"自动下载"]];
    XCTAssertEqualObjects(ids, (@[@"storage.cellular", @"storage.wifi"]));
}

@end
