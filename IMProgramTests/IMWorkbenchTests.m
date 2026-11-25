//  IMWorkbenchTests.m
//  工作台纯规则（WORKBENCH_DESIGN §1.1 / §3 / §6）：分段、地址放行、去票据、选公司，以及 server-config 的 workbench_units 解析。

#import <XCTest/XCTest.h>
#import "../IMProgram/Modules/Workbench/IMWorkbench.h"
#import "../IMProgram/Network/IMServerConfigStore.h"

@interface IMWorkbenchTests : XCTestCase
@end

@implementation IMWorkbenchTests

- (NSArray<NSString *> *)titles:(NSArray<IMWorkbenchSection *> *)sections {
    NSMutableArray *out = [NSMutableArray array];
    for (IMWorkbenchSection *s in sections) { [out addObject:[NSString stringWithFormat:@"%@:%lu", s.title, (unsigned long)s.apps.count]]; }
    return out;
}

- (void)testSectionsKeepServerOrderAndUngroupedLast {
    NSArray *groups = @[
        @{ @"name": @"办公", @"apps": @[@{ @"app_id": @"a" }, @{ @"app_id": @"b" }] },
        @{ @"name": @"服务", @"apps": @[@{ @"app_id": @"c" }] },
        @{ @"name": @"空组", @"apps": @[] },
        @{ @"name": @"", @"apps": @[@{ @"app_id": @"d" }, @{ @"bad": @1 }] },
    ];
    NSArray *got = [self titles:[IMWorkbench sectionsFromGroups:groups otherTitle:@"其他" soleTitle:@"我的应用"]];
    XCTAssertEqualObjects(got, (@[@"办公:2", @"服务:1", @"其他:1"]), @"空组丢掉、坏项丢掉、没分组叫其他");
}

- (void)testSoleUngroupedSectionUsesSoleTitle {
    NSArray *groups = @[@{ @"name": @"", @"apps": @[@{ @"app_id": @"a" }] }];
    XCTAssertEqualObjects([self titles:[IMWorkbench sectionsFromGroups:groups otherTitle:@"其他" soleTitle:@"我的应用"]], @[@"我的应用:1"]);
    XCTAssertEqualObjects([self titles:[IMWorkbench sectionsFromGroups:groups otherTitle:@"其他" soleTitle:nil]], @[@"其他:1"], @"商店不换名");
    XCTAssertEqual([IMWorkbench sectionsFromGroups:(id)@"bad" otherTitle:@"其他" soleTitle:nil].count, 0u);
}

- (void)testAllowedWebURL {
    NSDictionary<NSString *, NSNumber *> *cases = @{
        @"https://app.example.com/x?im_ticket=1": @YES,
        @"http://app.example.com/": @NO,
        @"http://127.0.0.1:8790/": @YES,
        @"http://LOCALHOST:8790/": @YES,
        @"http://192.168.1.9/": @YES,
        @"http://172.16.0.1/": @YES,
        @"http://172.32.0.1/": @NO,
        @"http://10.1.2.3/": @YES,
        @"http://010.1.2.3/": @NO,
        @"http://2130706433/": @NO,
        @"http://mac.local/": @YES,
        @"http://[::1]:8790/": @YES,
        @"http://user@127.0.0.1/": @NO,
        @"javascript:alert(1)": @NO,
        @"ftp://127.0.0.1/": @NO,
    };
    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *raw, NSNumber *want, BOOL *stop) {
        XCTAssertEqual([IMWorkbench isAllowedWebURL:[NSURL URLWithString:raw]], want.boolValue, @"%@", raw);
    }];
    XCTAssertFalse([IMWorkbench isAllowedWebURL:nil]);
}

- (void)testRemoveTicket {
    NSURL *u = [IMWorkbench urlByRemovingTicket:[NSURL URLWithString:@"https://a.example/p?x=1&im_ticket=T&y=2#f"]];
    XCTAssertEqualObjects(u.absoluteString, @"https://a.example/p?x=1&y=2#f");
    u = [IMWorkbench urlByRemovingTicket:[NSURL URLWithString:@"https://a.example/p?im_ticket=T"]];
    XCTAssertEqualObjects(u.absoluteString, @"https://a.example/p");
    u = [IMWorkbench urlByRemovingTicket:[NSURL URLWithString:@"https://a.example/a%20b?im%5Fticket=T&x=%41"]];
    XCTAssertEqualObjects(u.absoluteString, @"https://a.example/a%20b?x=%41", @"编码写法的票据也去掉，其余逐字保留");
}

- (void)testPickUnit {
    NSArray *units = @[@{ @"unit_id": @"u1", @"name": @"华南" }, @{ @"unit_id": @"u2", @"name": @"华东" }];
    XCTAssertEqualObjects([IMWorkbench pickUnitIDFrom:units saved:@"u2"], @"u2");
    XCTAssertEqualObjects([IMWorkbench pickUnitIDFrom:units saved:@"gone"], @"u1", @"记住的那家没了就用第一家");
    XCTAssertNil([IMWorkbench pickUnitIDFrom:@[] saved:@"u1"]);
}

- (void)testServerConfigParsesWorkbenchUnits {
    IMServerConfigStore *store = [IMServerConfigStore new];
    XCTAssertEqual(store.workbenchUnits.count, 0u, @"未加载时为空数组");
    NSDictionary *cfg = @{ @"workbench_units": @[
        @{ @"unit_id": @"u1", @"name": @"华南", @"code": @"S1" }, @{ @"name": @"没有 id" }, @"bad",
    ] };
    BOOL changed = [store applyServerConfig:cfg];
    XCTAssertTrue(changed);
    XCTAssertEqualObjects(store.workbenchUnits, (@[@{ @"unit_id": @"u1", @"name": @"华南", @"code": @"S1" }]));
    NSDictionary *same = @{ @"workbench_units": @[@{ @"unit_id": @"u1", @"name": @"华南", @"code": @"S1" }] };
    XCTAssertFalse([store applyServerConfig:same]);
    XCTAssertTrue([store applyServerConfig:@{}], @"工作台没了也算变化（Tab 要收起）");
    XCTAssertEqual(store.workbenchUnits.count, 0u);
}

@end
