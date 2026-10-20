//  IMDeleteAccountTests.m
//  注销账号（DELETE_ACCOUNT_DESIGN.md）：destructive 行居中、资料页入口只读态可见/编辑态隐藏、
//  HTTP 解析（owned_groups / delete_at / 业务码保留）、阻断态纯逻辑、注销清库只动当前账号。
//  app-hosted 测试。HTTP 用 NSURLProtocol 只拦本测试专用用户名/密码，宿主 App 的真实请求不碰。

#import <XCTest/XCTest.h>

#import "IMDatabase.h"
#import "IMDatabase+AccountWipe.h"
#import "IMDeleteAccountViewController.h"
#import "IMHTTPService.h"
#import "IMHTTPService+Account.h"
#import "IMMessageModel.h"
#import "IMProfileEditViewController.h"
#import "IMUserCard.h"
#import "IMLocalization.h"

static NSString *const kStubPw = @"im-acct-stub-pw";

@interface IMAcctStubProtocol : NSURLProtocol
@property (class, nonatomic, copy) NSDictionary *response;
@property (class, nonatomic, copy) NSString *lastPath;
@end
@implementation IMAcctStubProtocol
static NSDictionary *sAcctResp; static NSString *sAcctPath;
+ (NSDictionary *)response { return sAcctResp; }
+ (void)setResponse:(NSDictionary *)v { sAcctResp = v; }
+ (NSString *)lastPath { return sAcctPath; }
+ (void)setLastPath:(NSString *)v { sAcctPath = v; }
+ (BOOL)canInitWithRequest:(NSURLRequest *)r {
    NSString *p = r.URL.path;
    if (![p isEqualToString:@"/api/v1/account/delete"] && ![p isEqualToString:@"/api/v1/account/restore"]) { return NO; }
    NSData *d = r.HTTPBody;
    if (!d && r.HTTPBodyStream) {
        NSInputStream *in = r.HTTPBodyStream; [in open];
        NSMutableData *m = [NSMutableData data]; uint8_t buf[512]; NSInteger n;
        while ((n = [in read:buf maxLength:sizeof buf]) > 0) { [m appendBytes:buf length:(NSUInteger)n]; }
        [in close]; d = m;
    }
    id o = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    return [o isKindOfClass:NSDictionary.class] && [o[@"password"] isEqualToString:kStubPw];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }
- (void)startLoading {
    sAcctPath = self.request.URL.path;
    NSData *data = [NSJSONSerialization dataWithJSONObject:sAcctResp ?: @{ @"code": @0, @"data": @{} } options:0 error:NULL];
    NSHTTPURLResponse *r = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1"
                                                     headerFields:@{ @"Content-Type": @"application/json" }];
    [self.client URLProtocol:self didReceiveResponse:r cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

/// IMSettingsRow 是 IMSettingsViewController.m 里的文件私有类；这里只声明测试要调的工厂方法，实例经运行时取类。
@interface NSObject (IMSettingsRowTestShim)
+ (instancetype)rowWithId:(NSString *)rowId title:(NSString *)title image:(nullable NSString *)image
                   iconBg:(nullable UIColor *)iconBg right:(nullable NSString *)right
              destructive:(BOOL)destructive handler:(nullable void (^)(void))handler;
@end

@interface IMDeleteAccountTests : XCTestCase
@end

@implementation IMDeleteAccountTests {
    NSString *_sHost;
}

- (void)setUp {
    [super setUp];
    _sHost = IMHTTPService.sharedService.host;
    if (_sHost.length == 0) { IMHTTPService.sharedService.host = @"127.0.0.1:59391"; }
    sAcctResp = nil; sAcctPath = nil;
    [NSURLProtocol registerClass:IMAcctStubProtocol.class];
}

- (void)tearDown {
    [NSURLProtocol unregisterClass:IMAcctStubProtocol.class];
    IMHTTPService.sharedService.host = _sHost;
    [super tearDown];
}

#pragma mark - destructive 行居中（IMSettingsCell 私有类，经运行时取）

- (UITableViewCell *)settingsCellWithDestructive:(BOOL)destructive {
    Class rowCls = NSClassFromString(@"IMSettingsRow"), cellCls = NSClassFromString(@"IMSettingsCell");
    XCTAssertNotNil(rowCls); XCTAssertNotNil(cellCls);
    id row = [rowCls rowWithId:@"x" title:@"退出登录" image:(destructive ? nil : @"gear") iconBg:UIColor.systemBlueColor
                         right:nil destructive:destructive handler:nil];
    UITableViewCell *cell = [[cellCls alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"row"];
    cell.frame = CGRectMake(0, 0, 375, 50);
    [cell performSelector:NSSelectorFromString(@"configureWithRow:") withObject:row];
    [cell setNeedsLayout]; [cell layoutIfNeeded];
    [cell.contentView layoutIfNeeded];
    return cell;
}

- (void)test_destructive行_标题水平居中且图标隐藏 {
    UITableViewCell *cell = [self settingsCellWithDestructive:YES];
    UILabel *title = [cell valueForKey:@"_titleLabel"];
    UIView *icon = [cell valueForKey:@"_iconBg"];
    XCTAssertTrue(icon.hidden);
    CGFloat titleMid = CGRectGetMidX([title.superview convertRect:title.frame toView:cell.contentView]);
    XCTAssertEqualWithAccuracy(titleMid, CGRectGetMidX(cell.contentView.bounds), 0.5);
    XCTAssertEqualObjects(title.textColor, UIColor.systemRedColor);
    XCTAssertEqual(title.font.pointSize, 17);
}

- (void)test_普通行_标题不居中且图标可见 {
    UITableViewCell *cell = [self settingsCellWithDestructive:NO];
    UILabel *title = [cell valueForKey:@"_titleLabel"];
    UIView *icon = [cell valueForKey:@"_iconBg"];
    XCTAssertFalse(icon.hidden);
    XCTAssertGreaterThan(CGRectGetMinX(title.frame), CGRectGetMaxX(icon.frame));
    XCTAssertLessThan(CGRectGetMidX(title.frame), CGRectGetMidX(cell.contentView.bounds) - 10);
}

- (void)test_cell复用_destructive回到普通行后恢复左锚 {
    Class rowCls = NSClassFromString(@"IMSettingsRow"), cellCls = NSClassFromString(@"IMSettingsCell");
    UITableViewCell *cell = [[cellCls alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"row"];
    cell.frame = CGRectMake(0, 0, 375, 50);
    id red = [rowCls rowWithId:@"a" title:@"退出登录" image:nil iconBg:nil right:nil destructive:YES handler:nil];
    id plain = [rowCls rowWithId:@"b" title:@"设置" image:@"gear" iconBg:UIColor.systemBlueColor right:nil destructive:NO handler:nil];
    [cell performSelector:NSSelectorFromString(@"configureWithRow:") withObject:red];
    [cell layoutIfNeeded];
    [cell performSelector:NSSelectorFromString(@"configureWithRow:") withObject:plain];
    [cell layoutIfNeeded];
    UILabel *title = [cell valueForKey:@"_titleLabel"];
    XCTAssertLessThan(CGRectGetMidX(title.frame), CGRectGetMidX(cell.contentView.bounds) - 10);
}

#pragma mark - 资料页入口

- (UIButton *)deleteRowOf:(IMProfileEditViewController *)vc {
    UIButton *b = [vc valueForKey:@"deleteAccountRow"];
    XCTAssertNotNil(b);
    return b;
}

- (void)test_资料页只读态显示注销入口_编辑态隐藏 {
    IMProfileEditViewController *vc = [[IMProfileEditViewController alloc] initWithHost:@"127.0.0.1:1" userID:@"u1"];
    [vc loadViewIfNeeded];
    UIButton *row = [self deleteRowOf:vc];
    UIView *readonlyStack = [vc valueForKey:@"readonlyStack"];
    XCTAssertFalse(readonlyStack.hidden);
    XCTAssertTrue([row isDescendantOfView:readonlyStack]);
    XCTAssertEqual(row.titleLabel.font.pointSize, 17);
    XCTAssertEqualObjects([row titleColorForState:UIControlStateNormal], UIColor.systemRedColor);
    XCTAssertEqual(row.contentHorizontalAlignment, UIControlContentHorizontalAlignmentCenter);

    [vc performSelector:NSSelectorFromString(@"enterEditing")];
    XCTAssertTrue(readonlyStack.hidden, @"编辑态整个只读容器（含注销组）隐藏");
}

- (void)test_资料页直进编辑态_注销入口不显示 {
    IMProfileEditViewController *vc = [[IMProfileEditViewController alloc] initWithHost:@"127.0.0.1:1" userID:@"u1"];
    vc.startsEditing = YES;
    [vc loadViewIfNeeded];
    UIView *readonlyStack = [vc valueForKey:@"readonlyStack"];
    XCTAssertTrue(readonlyStack.hidden);
}

#pragma mark - 解析

- (void)test_delete_at_秒_毫秒_ISO都能解析 {
    XCTAssertEqualWithAccuracy(IMParseDeleteAt(@(1792000000)).timeIntervalSince1970, 1792000000, 0.1);
    XCTAssertEqualWithAccuracy(IMParseDeleteAt(@(1792000000000)).timeIntervalSince1970, 1792000000, 0.1);
    XCTAssertEqualWithAccuracy(IMParseDeleteAt(@"2026-10-23T00:00:00Z").timeIntervalSince1970, 1792713600, 0.1);
    XCTAssertEqualWithAccuracy(IMParseDeleteAt(@"2026-10-23T00:00:00.500Z").timeIntervalSince1970, 1792713600.5, 0.1);
    XCTAssertNil(IMParseDeleteAt(@(0)));
    XCTAssertNil(IMParseDeleteAt(@"garbage"));
    XCTAssertNil(IMParseDeleteAt([NSNull null]));
}

- (void)test_owned_groups_容忍多种形态和脏数据 {
    NSArray *g = IMParseOwnedGroups(@[ @{ @"group_id": @"g_1", @"name": @"产品" }, @{ @"id": @"g_2", @"name": @"羽毛球" },
                                       @"纯字符串群名", @{ @"name": @"" }, @42, [NSNull null] ]);
    XCTAssertEqual(g.count, 3u);
    XCTAssertEqualObjects(g[0][@"id"], @"g_1");
    XCTAssertEqualObjects(g[1][@"name"], @"羽毛球");
    XCTAssertEqualObjects(g[2][@"name"], @"纯字符串群名");
    XCTAssertEqual(IMParseOwnedGroups(@"not array").count, 0u);
    XCTAssertEqual(IMParseOwnedGroups(nil).count, 0u);
}

- (void)test_阻断态逻辑_最多列3个_其余折叠 {
    NSMutableArray *gs = [NSMutableArray array];
    for (int i = 0; i < 5; i++) { [gs addObject:@{ @"id": [NSString stringWithFormat:@"g%d", i], @"name": @"n" }]; }
    XCTAssertEqual(IMDeleteAccountListedGroups(gs).count, 3u);
    XCTAssertEqual(IMDeleteAccountHiddenGroupCount(gs), 2);
    XCTAssertEqual(IMDeleteAccountHiddenGroupCount(@[ gs[0] ]), 0);
    XCTAssertEqual(IMDeleteAccountListedGroups(@[]).count, 0u);
}

- (void)test_按钮可点条件 {
    XCTAssertFalse(IMDeleteAccountCanSubmit(@"", NO, NO), @"空密码置灰");
    XCTAssertFalse(IMDeleteAccountCanSubmit(nil, NO, NO));
    XCTAssertTrue(IMDeleteAccountCanSubmit(@"x", NO, NO));
    XCTAssertFalse(IMDeleteAccountCanSubmit(@"x", YES, NO), @"群主阻断态置灰");
    XCTAssertFalse(IMDeleteAccountCanSubmit(@"x", NO, YES), @"在途置灰");
}

#pragma mark - HTTP（桩）

- (NSError *)deleteWithResponse:(NSDictionary *)resp {
    sAcctResp = resp;
    __block NSError *err; XCTestExpectation *e = [self expectationWithDescription:@"del"];
    [IMHTTPService.sharedService deleteAccountWithToken:@"tok" password:kStubPw completion:^(NSError *er) { err = er; [e fulfill]; }];
    [self waitForExpectations:@[e] timeout:10];
    return err;
}

- (void)test_delete成功_回nil且打到delete路径 {
    NSError *err = [self deleteWithResponse:@{ @"code": @0, @"data": @{} }];
    XCTAssertNil(err);
    XCTAssertEqualObjects(sAcctPath, @"/api/v1/account/delete");
}

- (void)test_delete群主阻断_保留100103码并带owned_groups {
    NSError *err = [self deleteWithResponse:@{ @"code": @100103, @"message": @"no permission",
        @"data": @{ @"owned_groups": @[ @{ @"id": @"g_a", @"name": @"产品讨论组" } ] } }];
    XCTAssertEqual(err.code, IMErrCodeNoPermission);
    NSArray *g = err.userInfo[IMErrorOwnedGroupsKey];
    XCTAssertEqual(g.count, 1u);
    XCTAssertEqualObjects(g[0][@"name"], @"产品讨论组");
}

- (void)test_delete密码错_保留200002码且无owned_groups {
    NSError *err = [self deleteWithResponse:@{ @"code": @200002, @"message": @"wrong password" }];
    XCTAssertEqual(err.code, 200002);
    XCTAssertNil(err.userInfo[IMErrorOwnedGroupsKey]);
}

- (void)test_restore_打到restore路径并回nil {
    sAcctResp = @{ @"code": @0, @"data": @{} };
    XCTestExpectation *e = [self expectationWithDescription:@"restore"];
    __block NSError *err;
    [IMHTTPService.sharedService restoreAccountWithUsername:@"u" password:kStubPw completion:^(NSError *er) { err = er; [e fulfill]; }];
    [self waitForExpectations:@[e] timeout:10];
    XCTAssertNil(err);
    XCTAssertEqualObjects(sAcctPath, @"/api/v1/account/restore");
}

- (void)test_登录冷静期错误_附delete_at且码不变 {
    NSError *base = [NSError errorWithDomain:@"d" code:IMErrCodeAccountPendingDeletion userInfo:@{ NSLocalizedDescriptionKey: @"m" }];
    NSError *e = IMErrorByAttachingAccountInfo(base, @{ @"code": @200005, @"data": @{ @"delete_at": @(1792000000) } });
    XCTAssertEqual(e.code, IMErrCodeAccountPendingDeletion);
    XCTAssertEqualObjects(e.localizedDescription, @"m");
    XCTAssertNotNil(e.userInfo[IMErrorDeleteAtKey]);
    XCTAssertEqual(IMErrorByAttachingAccountInfo(base, nil), base);
}

#pragma mark - 已注销用户显示

- (void)test_deleted为true_显示已注销用户_忽略昵称 {
    IMUserCard *c = [IMUserCard cardsFromArray:@[ @{ @"user_id": @"u9", @"nickname": @"李默", @"deleted": @YES } ]].firstObject;
    XCTAssertTrue(c.deleted);
    XCTAssertEqualObjects(c.displayName, IMLocalized(@"delete_account.deleted_user"));
    IMUserCard *ok = [IMUserCard cardsFromArray:@[ @{ @"user_id": @"u8", @"nickname": @"李默" } ]].firstObject;
    XCTAssertFalse(ok.deleted);
    XCTAssertEqualObjects(ok.displayName, @"李默");
}

#pragma mark - 注销清库

- (void)test_注销清库_只删当前账号_别人的原样保留 {
    NSString *name = [NSString stringWithFormat:@"im-wipe-test-%@.sqlite", NSUUID.UUID.UUIDString];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    IMDatabase *db = [[IMDatabase alloc] initWithFileURL:url];
    IMMessageModel *(^msg)(NSString *) = ^IMMessageModel *(NSString *conv) {
        return [IMMessageModel receivedMessageWithNewMsgData:@{ @"server_msg_id": [conv stringByAppendingString:@"-1"], @"conv_id": conv,
            @"from": @"peer", @"content": @"hi", @"content_type": @"text", @"conv_seq": @1, @"timestamp": @1788000000001 }];
    };
    [db useOwnerUserID:@"owner_a"];
    [db saveIncomingMessage:msg(@"g_a") advancingSyncedConvSeq:1];
    [db useOwnerUserID:@"owner_b"];
    [db saveIncomingMessage:msg(@"g_b") advancingSyncedConvSeq:1];

    [db useOwnerUserID:@"owner_a"];
    XCTAssertEqual([db messagesForConv:@"g_a"].count, 1u);
    XCTAssertTrue([db wipeAllDataForCurrentOwner]);
    XCTAssertEqual([db messagesForConv:@"g_a"].count, 0u);
    XCTAssertEqual([db syncedConvSeqForConv:@"g_a"], 0);

    [db useOwnerUserID:@"owner_b"];
    XCTAssertEqual([db messagesForConv:@"g_b"].count, 1u, @"别的账号的缓存不能被误删");
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)test_注销清库_待发暂存引用只取当前账号的 {
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"im-wipe-pending-%@.sqlite", NSUUID.UUID.UUIDString]]];
    IMDatabase *db = [[IMDatabase alloc] initWithFileURL:url];
    IMMessageModel *(^msg)(NSString *, NSString *) = ^IMMessageModel *(NSString *conv, NSString *content) {
        return [IMMessageModel receivedMessageWithNewMsgData:@{ @"server_msg_id": [conv stringByAppendingString:@"-1"], @"conv_id": conv,
            @"from": @"peer", @"content": content, @"content_type": @"text", @"conv_seq": @1, @"timestamp": @1788000000001 }];
    };
    [db useOwnerUserID:@"owner_a"];
    [db saveIncomingMessage:msg(@"g_a", @"im-pending://a1.jpg") advancingSyncedConvSeq:1];
    [db useOwnerUserID:@"owner_b"];
    [db saveIncomingMessage:msg(@"g_b", @"im-pending://b1.jpg") advancingSyncedConvSeq:1];
    [db useOwnerUserID:@"owner_a"];
    XCTAssertEqualObjects([db pendingMediaLocalRefsForCurrentOwner], (@[ @"im-pending://a1.jpg" ]));
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)test_注销清库_未选账号时拒绝执行 {
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"im-wipe-guard-%@.sqlite", NSUUID.UUID.UUIDString]]];
    IMDatabase *db = [[IMDatabase alloc] initWithFileURL:url];
    XCTAssertFalse([db wipeAllDataForCurrentOwner]);
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

@end
