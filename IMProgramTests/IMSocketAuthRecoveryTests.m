//  IMSocketAuthRecoveryTests.m
//  握手 401 → 先续期再判被踢（IMSocketManager+AuthRecovery，与 Android `IMSocketUnauthorizedTest` 同表）。
//
//  2026-10-08 实测：服务端换签名密钥重启，本端拿 10 分钟缓存里的旧 token 重连撞 401，被直接送回登录页——
//  续期其实能成功。错法是**把用户踢出去**，所以钉「第一次 401 不发被踢通知、转去重连」。
//
//  用 `IMSocketManager.sharedManager`（未连接）；`openSocket` 临时换成桩：计数 + 像真的一样 ++ 连接代次
//  （真开会去换 token、发网络请求）。

#import <XCTest/XCTest.h>
#import <objc/runtime.h>

#import "IMSocketManager.h"
#import "IMSocketManager+Private.h"
#import "IMSocketManager+AuthRecovery.h"
#import "IMHTTPService.h"

static NSInteger gOpenSocketCalls = 0;

@interface IMSocketManager (AuthRecoveryTestHooks)
- (void)handleDisconnect:(nullable NSError *)error authRejected:(BOOL)authRejected;
- (void)im_test_countingOpenSocket;
@end

@implementation IMSocketManager (AuthRecoveryTestHooks)
- (void)im_test_countingOpenSocket {
    gOpenSocketCalls += 1;
    NSUInteger gen = [[self valueForKey:@"_connectionGeneration"] unsignedIntegerValue];
    [self setValue:@(gen + 1) forKey:@"_connectionGeneration"];
}
@end

@interface IMSocketAuthRecoveryTests : XCTestCase
@end

@implementation IMSocketAuthRecoveryTests {
    IMSocketManager *_mgr;
    Method _open, _stub;
    NSInteger _revokes;
    id _observer;
    NSString *_savedRefresh;
}

- (void)setUp {
    [self settleHostApp];
    _mgr = IMSocketManager.sharedManager;
    _open = class_getInstanceMethod(IMSocketManager.class, @selector(openSocket));
    _stub = class_getInstanceMethod(IMSocketManager.class, @selector(im_test_countingOpenSocket));
    method_exchangeImplementations(_open, _stub);
    gOpenSocketCalls = 0;
    _revokes = 0;
    _savedRefresh = IMHTTPService.sharedService.refreshToken;
    IMHTTPService.sharedService.refreshToken = @"test-refresh-credential";
    __weak typeof(self) weakSelf = self;
    _observer = [NSNotificationCenter.defaultCenter addObserverForName:IMSocketDidRevokeSessionNotification object:nil
                                                                 queue:nil usingBlock:^(NSNotification *n) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self) { self->_revokes += 1; }
    }];
    [self onQueue:^{
        [self->_mgr setValue:@NO forKey:@"_manualClose"];
        [self->_mgr setValue:@0 forKey:@"_refreshRetryGeneration"];
    }];
    [self simulateConnect]; // 一条正常 connect 开出来的连接
}

- (void)tearDown {
    [self settleHostApp]; // 先让宿主收尾（见 settleHostApp），再还原桩与凭据
    method_exchangeImplementations(_open, _stub);
    [NSNotificationCenter.defaultCenter removeObserver:_observer];
    IMHTTPService.sharedService.refreshToken = _savedRefresh;
    [self onQueue:^{
        [self->_mgr setValue:@NO forKey:@"_manualClose"];
        [self->_mgr setValue:@0 forKey:@"_refreshRetryGeneration"];
        self->_mgr.state = IMSocketStateDisconnected;
    }];
}

/// 被踢通知会让测试宿主 App 的 SceneDelegate 异步登出（清续期凭据、断 socket）。不等它跑完，
/// 它会落进下一条用例、把那边刚设好的续期凭据清掉——单跑全绿、合跑串号。
- (void)settleHostApp {
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
}

- (void)onQueue:(void (^)(void))block { dispatch_sync([_mgr valueForKey:@"_queue"], block); }

- (NSUInteger)generation { return [[_mgr valueForKey:@"_connectionGeneration"] unsignedIntegerValue]; }

/// connect / 退避重连 / 唤醒都经 openSocket 开新代次——与续期无关的一次新连接。
- (void)simulateConnect {
    [self onQueue:^{ [self->_mgr im_test_countingOpenSocket]; }];
    gOpenSocketCalls = 0;
}

/// 模拟当前这条连接「握手中 → 401」。handleDisconnect 对已断开且无 task 的会直接跳过，所以先摆成 Connecting。
- (void)reject401 {
    [self onQueue:^{
        self->_mgr.state = IMSocketStateConnecting;
        [self->_mgr handleDisconnect:nil authRejected:YES];
    }];
    // 被踢通知是 dispatch_async 到主队列发的：排空一轮再断言
    XCTestExpectation *e = [self expectationWithDescription:@"drain main"];
    dispatch_async(dispatch_get_main_queue(), ^{ [e fulfill]; });
    [self waitForExpectations:@[e] timeout:2];
}

- (void)testDecisionTable {
    XCTAssertEqual(IMSocketUnauthorizedActionFor(YES, 3, 0), IMSocketUnauthorizedActionRefresh, @"第一次 401：先续期");
    XCTAssertEqual(IMSocketUnauthorizedActionFor(YES, 4, 4), IMSocketUnauthorizedActionRevoked, @"续期后开的那条还 401：按被踢");
    XCTAssertEqual(IMSocketUnauthorizedActionFor(YES, 7, 4), IMSocketUnauthorizedActionRefresh, @"别的连接撞 401 照样能续");
    XCTAssertEqual(IMSocketUnauthorizedActionFor(NO, 3, 0), IMSocketUnauthorizedActionRevoked, @"没有续期凭据：续不了，按被踢");
}

- (void)testFirst401RefreshesInsteadOfKicking {
    [self reject401];
    XCTAssertEqual(_revokes, 0, @"token 只是失效（过期 / 服务端换密钥）不能把人踢回登录页");
    XCTAssertEqual(gOpenSocketCalls, 1, @"应立即重连（openSocket 内会 miss 缓存去续期）");
    XCTAssertFalse([[_mgr valueForKey:@"_manualClose"] boolValue], @"还要继续自动重连");
}

- (void)testSecond401OnRefreshedConnectionKicks {
    [self reject401];
    [self reject401];
    XCTAssertEqual(_revokes, 1, @"续期换来的新 token 还 401 = sid 真被吊销");
    XCTAssertEqual(gOpenSocketCalls, 1, @"不再续第二次（防死循环）");
    XCTAssertTrue([[_mgr valueForKey:@"_manualClose"] boolValue], @"被踢后停自动重连");
}

/// /code-review 2026-10-08：「续过一次」不能粘在后来的连接上——续上后新连接断网 / 退出再登录，
/// 之后新开的连接第一次 401 还得能续，不能直接当被踢。
- (void)testLaterConnectionCanRefreshAgain {
    [self reject401];
    [self simulateConnect]; // 退避重连 / 重新登录开出的新连接
    [self reject401];
    XCTAssertEqual(_revokes, 0);
    XCTAssertEqual(gOpenSocketCalls, 1);
}

/// /code-review 2026-10-08：没有续期凭据时照常重连，会退回空密码 POST /login——生产环境无限重试、
/// 开发环境（-dev-login）把吊销的设备「复活」。
- (void)testNoRefreshCredentialKicksImmediately {
    IMHTTPService.sharedService.refreshToken = nil;
    [self reject401];
    XCTAssertEqual(_revokes, 1);
    XCTAssertEqual(gOpenSocketCalls, 0);
}

/// /code-review 2026-10-08：续期窗口里 currentToken 不能被清空（推送上报、下载设置、媒体发送都直接读它）。
- (void)testExpireCachedTokenKeepsCurrentToken {
    IMHTTPService *http = IMHTTPService.sharedService;
    id savedToken = [http valueForKey:@"currentToken"];
    id savedAt = [http valueForKey:@"tokenFetchedAt"];
    [http setValue:@"cached-token" forKey:@"currentToken"];
    [http setValue:@(CFAbsoluteTimeGetCurrent()) forKey:@"tokenFetchedAt"];
    [http expireCachedToken];
    XCTAssertEqualObjects(http.currentToken, @"cached-token");
    XCTAssertEqual([[http valueForKey:@"tokenFetchedAt"] doubleValue], 0, @"缓存必须过期，下次换票才会去续期");
    [http setValue:savedToken forKey:@"currentToken"];
    [http setValue:savedAt forKey:@"tokenFetchedAt"];
}

@end
