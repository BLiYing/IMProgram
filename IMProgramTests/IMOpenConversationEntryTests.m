//  IMOpenConversationEntryTests.m
//  「由会话行打开聊天」的共用入口（IMChatViewController openConversation:…）与会话列表广播：
//  - 共用入口进会话即清手动「标为未读」：先 GET 服务端当前设置，PUT 带服务端的置顶 / 免打扰（手上的会话对象可能是
//    旧快照，整体替换会把旧值写回）、muteUntil 省略；读失败不清。清完镜像本地并广播，会话列表据此立即改角标。
//    通讯录「最近联系」以前自己抄一份 open，漏了清标未读（已确认的 bug）。
//  - 会话列表页 conversations setter 真的发出 IMConversationListDidChangeNotification，userInfo 两个 key 正确。
//  会话列表页一律用测试专用 uid 构造，并在 tearDown 恢复 IMChatFolderStore 的 owner（宿主就是真 App）。
//  app-hosted 测试，头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Modules/Chat/IMChatViewController.h"
#import "../IMProgram/Modules/Conversation/IMConversationListViewController+Private.h"
#import "../IMProgram/Models/IMConversation.h"
#import "../IMProgram/Network/IMHTTPService.h"
#import "../IMProgram/Network/IMProtocol.h"
#import "../IMProgram/Network/IMSocketManager.h"
#import "../IMProgram/Database/IMDatabase.h"
#import "../IMProgram/Common/IMChatFolderStore.h"

static NSString *const kOpenStubConv = @"open-entry-stub-conv";

/// 拦本测试专用会话的 GET / PUT …/settings：GET 按 sOpenStubGetReply 回包，PUT 记录请求体并回 ok。
@interface IMOpenEntrySettingsStub : NSURLProtocol
@end
@implementation IMOpenEntrySettingsStub
static NSMutableArray<NSDictionary *> *sOpenStubRequests; // @{ method, body }
static NSDictionary *sOpenStubGetReply;
+ (NSMutableArray<NSDictionary *> *)requests { if (!sOpenStubRequests) { sOpenStubRequests = [NSMutableArray array]; } return sOpenStubRequests; }
+ (BOOL)canInitWithRequest:(NSURLRequest *)r { return [r.URL.path containsString:kOpenStubConv] && [r.URL.path hasSuffix:@"/settings"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }
- (void)startLoading {
    NSData *d = self.request.HTTPBody;
    if (!d && self.request.HTTPBodyStream) {
        NSInputStream *in = self.request.HTTPBodyStream; [in open];
        NSMutableData *m = [NSMutableData data]; uint8_t buf[1024]; NSInteger n;
        while ((n = [in read:buf maxLength:sizeof buf]) > 0) { [m appendBytes:buf length:(NSUInteger)n]; }
        [in close]; d = m;
    }
    id o = d.length > 0 ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    NSString *method = self.request.HTTPMethod ?: @"GET";
    NSDictionary *reply;
    @synchronized (IMOpenEntrySettingsStub.class) {
        [IMOpenEntrySettingsStub.requests addObject:@{ @"method": method, @"body": [o isKindOfClass:NSDictionary.class] ? o : @{} }];
        reply = [method isEqualToString:@"GET"] ? sOpenStubGetReply : nil;
    }
    reply = reply ?: @{ @"code": @0, @"message": @"ok", @"data": @{} };
    NSData *resp = [NSJSONSerialization dataWithJSONObject:reply options:0 error:NULL];
    NSHTTPURLResponse *r = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1"
                                                     headerFields:@{ @"Content-Type": @"application/json" }];
    [self.client URLProtocol:self didReceiveResponse:r cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:resp];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

@interface IMOpenConversationEntryTests : XCTestCase
@property (nonatomic, copy) NSString *oldHost;
@property (nonatomic, copy, nullable) NSString *oldFolderOwner;
@end

@implementation IMOpenConversationEntryTests

- (void)setUp {
    [super setUp];
    IMHTTPService *svc = IMHTTPService.sharedService;
    self.oldHost = svc.host;
    if (svc.host.length == 0) { svc.host = @"127.0.0.1:59392"; }
    self.oldFolderOwner = [IMChatFolderStore.shared valueForKey:@"ownerUID"];
    @synchronized (IMOpenEntrySettingsStub.class) { [IMOpenEntrySettingsStub.requests removeAllObjects]; sOpenStubGetReply = nil; }
    [NSURLProtocol registerClass:IMOpenEntrySettingsStub.class];
}

- (void)tearDown {
    [NSURLProtocol unregisterClass:IMOpenEntrySettingsStub.class];
    @synchronized (IMOpenEntrySettingsStub.class) { sOpenStubGetReply = nil; }
    IMHTTPService.sharedService.host = self.oldHost;
    // 会话列表页 init 会让文件夹仓库 adopt 测试 uid：还给原账号（原先没有 owner 就清回 nil）。
    if (self.oldFolderOwner.length > 0) { [IMChatFolderStore.shared adoptUserID:self.oldFolderOwner]; }
    else { [IMChatFolderStore.shared setValue:nil forKey:@"ownerUID"]; }
    [super tearDown];
}

/// 本机手上的「旧快照」：置顶 + 免打扰 + 标未读（服务端那边置顶 / 免打扰其实已被别的设备取消）。
- (IMConversation *)staleMarkedSingle {
    IMConversation *c = [IMConversation new];
    c.convID = kOpenStubConv;
    c.peer = @"u-open-peer";
    c.peerNickname = @"对端";
    c.timestamp = 100;
    c.pinnedAt = 1234;
    c.muted = YES;
    c.muteUntil = 4102444800000;
    c.markedUnread = YES;
    return c;
}

- (NSArray<NSDictionary *> *)requests {
    @synchronized (IMOpenEntrySettingsStub.class) { return [IMOpenEntrySettingsStub.requests copy]; }
}

- (IMChatViewController *)openStubConversation:(IMConversation *)c {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[UIViewController new]];
    return [IMChatViewController openConversation:c inNavigationController:nav
                                             host:@"127.0.0.1:59392" userID:@"u-open-self" token:@"t"];
}

/// 共用入口清「标为未读」：PUT 带的是**服务端**当前的置顶 / 免打扰（本地快照是旧的），muteUntil 省略；
/// 清完内存对象跟着服务端、并广播给会话列表（立即重算角标）。
- (void)testClearMarkedUnreadPutsServerSettingsNotStaleSnapshot {
    @synchronized (IMOpenEntrySettingsStub.class) {
        sOpenStubGetReply = @{ @"code": @0, @"message": @"ok",
                               @"data": @{ @"pinned_at": @0, @"muted": @NO, @"mute_until": @0, @"marked_unread": @YES } };
    }
    IMConversation *c = [self staleMarkedSingle];
    [self expectationForNotification:IMConversationSettingsDidMirrorLocallyNotification object:c handler:nil];
    IMChatViewController *chat = [self openStubConversation:c];
    XCTAssertNotNil(chat, @"应打开聊天页");
    XCTAssertEqualObjects(chat.convID, IMConversationID(@"u-open-self", @"u-open-peer"));
    [self waitForExpectationsWithTimeout:5 handler:nil];

    NSPredicate *put = [NSPredicate predicateWithBlock:^BOOL(id obj, NSDictionary *bindings) {
        return [[[(IMOpenConversationEntryTests *)obj requests] valueForKey:@"method"] containsObject:@"PUT"];
    }];
    [self expectationForPredicate:put evaluatedWithObject:self handler:nil];
    [self waitForExpectationsWithTimeout:5 handler:nil];

    NSArray<NSDictionary *> *reqs = [self requests];
    XCTAssertEqualObjects([reqs valueForKey:@"method"], (@[@"GET", @"PUT"]), @"先读服务端当前设置再写");
    NSDictionary *body = reqs.lastObject[@"body"];
    XCTAssertEqualObjects(body[@"marked_unread"], @NO);
    XCTAssertEqualObjects(body[@"pinned_at"], @0, @"整体替换：带服务端的置顶，不能把本地旧快照的置顶写回去");
    XCTAssertEqualObjects(body[@"muted"], @NO, @"整体替换：带服务端的免打扰，不能把本地旧快照的免打扰写回去");
    XCTAssertNil(body[@"mute_until"], @"只清标未读：muteUntil 省略，服务端保留原到期时间");
    XCTAssertFalse(c.markedUnread, @"清完本地即时镜像");
    XCTAssertEqual(c.pinnedAt, 0, @"内存对象跟着服务端对齐");
    XCTAssertFalse(c.muted);
}

/// 读服务端设置失败：不清（没有可靠基线就不发整体替换 PUT），本地标记保留，也不广播。
- (void)testReadFailureLeavesMarkedUnreadAlone {
    @synchronized (IMOpenEntrySettingsStub.class) { sOpenStubGetReply = @{ @"code": @100001, @"message": @"boom" }; }
    IMConversation *c = [self staleMarkedSingle];
    __block NSInteger mirrored = 0;
    id token = [NSNotificationCenter.defaultCenter addObserverForName:IMConversationSettingsDidMirrorLocallyNotification object:c
                                                                queue:nil usingBlock:^(NSNotification *note) { mirrored++; }];
    XCTAssertNotNil([self openStubConversation:c]);
    NSPredicate *got = [NSPredicate predicateWithBlock:^BOOL(id obj, NSDictionary *bindings) {
        return [(IMOpenConversationEntryTests *)obj requests].count > 0;
    }];
    [self expectationForPredicate:got evaluatedWithObject:self handler:nil];
    [self waitForExpectationsWithTimeout:5 handler:nil];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    [NSNotificationCenter.defaultCenter removeObserver:token];
    XCTAssertEqualObjects([[self requests] valueForKey:@"method"], (@[@"GET"]), @"读失败不发 PUT");
    XCTAssertTrue(c.markedUnread, @"读失败不清，等会话列表拿到权威数据");
    XCTAssertEqual(mirrored, 0);
}

/// 没有被标未读：不读也不写，照常打开。
- (void)testNotMarkedTouchesNoSettings {
    IMConversation *c = [self staleMarkedSingle];
    c.markedUnread = NO;
    XCTAssertNotNil([self openStubConversation:c]);
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    XCTAssertEqual([self requests].count, 0u);
}

- (IMConversationListViewController *)isolatedList {
    // 专用 uid：广播不会被宿主 App 的真通讯录页收下；文件夹仓库 owner 在 tearDown 还原。
    return [[IMConversationListViewController alloc] initWithHost:@"127.0.0.1:59392" userID:@"u-list-entry-test"];
}

/// 会话列表页换数组即广播：通讯录首页「最近联系」靠它（userInfo = 全量会话数组 + 所属账号）。
- (void)testConversationListSetterBroadcastsArrayAndOwner {
    IMConversationListViewController *list = [self isolatedList];
    IMConversation *a = [IMConversation new];
    a.convID = @"bc-a";
    IMConversation *b = [IMConversation new];
    b.convID = @"bc-b";
    NSArray<IMConversation *> *conversations = @[a, b];

    __block NSNotification *received = nil;
    id token = [NSNotificationCenter.defaultCenter addObserverForName:IMConversationListDidChangeNotification object:list
                                                                queue:nil usingBlock:^(NSNotification *note) { received = note; }];
    list.conversations = conversations;
    [NSNotificationCenter.defaultCenter removeObserver:token];

    XCTAssertNotNil(received, @"setter 要广播");
    XCTAssertEqual(received.userInfo[kIMConversationListKey], conversations, @"带的就是这份全量数组");
    XCTAssertEqualObjects(received.userInfo[kIMConversationListOwnerKey], @"u-list-entry-test", @"带所属账号，首页据此丢弃别的账号的广播");
}

/// 别处（「最近联系」/ 横幅，手里是另一个实例）清掉标未读后，会话列表按 convID 立即同步自己那份（角标随之重算）。
- (void)testListAdoptsLocallyMirroredSettingsImmediately {
    IMConversationListViewController *list = [self isolatedList];
    IMConversation *mine = [self staleMarkedSingle];
    list.conversations = @[mine];

    IMConversation *elsewhere = [self staleMarkedSingle]; // 同一会话、另一个实例
    elsewhere.markedUnread = NO;
    elsewhere.pinnedAt = 0;
    elsewhere.muted = NO;
    elsewhere.muteUntil = 0;
    [NSNotificationCenter.defaultCenter postNotificationName:IMConversationSettingsDidMirrorLocallyNotification object:elsewhere];

    XCTAssertFalse(mine.markedUnread, @"列表那份要立即去掉标未读，不等 conv_update 回推");
    XCTAssertEqual(mine.pinnedAt, 0);
    XCTAssertFalse(mine.muted);
}

@end
