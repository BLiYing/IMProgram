//  IMSocketAuthRecoveryTests.m
//  握手 401 → 先续期再判被踢（IMSocketManager+AuthRecovery，与 Android `IMSocketUnauthorizedTest` 同表）。
//
//  2026-10-08 实测：服务端换签名密钥重启，本端拿 10 分钟缓存里的旧 token 重连撞 401，被直接送回登录页——
//  续期其实能成功。错法是**把用户踢出去**，所以钉「第一次 401 不发被踢通知、转去重连」。
//
//  用 `IMSocketManager.sharedManager`（未连接）；`openSocket` 临时换成计数桩——真开会去换 token、发网络请求。

#import <XCTest/XCTest.h>
#import <objc/runtime.h>

#import "IMSocketManager.h"
#import "IMSocketManager+Private.h"
#import "IMSocketManager+AuthRecovery.h"

static NSInteger gOpenSocketCalls = 0;

@interface IMSocketManager (AuthRecoveryTestHooks)
- (void)handleDisconnect:(nullable NSError *)error authRejected:(BOOL)authRejected;
- (void)im_test_countingOpenSocket;
@end

@implementation IMSocketManager (AuthRecoveryTestHooks)
- (void)im_test_countingOpenSocket { gOpenSocketCalls += 1; }
@end

@interface IMSocketAuthRecoveryTests : XCTestCase
@end

@implementation IMSocketAuthRecoveryTests {
    IMSocketManager *_mgr;
    Method _open, _stub;
    NSInteger _revokes;
    id _observer;
}

- (void)setUp {
    _mgr = IMSocketManager.sharedManager;
    _open = class_getInstanceMethod(IMSocketManager.class, @selector(openSocket));
    _stub = class_getInstanceMethod(IMSocketManager.class, @selector(im_test_countingOpenSocket));
    method_exchangeImplementations(_open, _stub);
    gOpenSocketCalls = 0;
    _revokes = 0;
    __weak typeof(self) weakSelf = self;
    _observer = [NSNotificationCenter.defaultCenter addObserverForName:IMSocketDidRevokeSessionNotification object:nil
                                                                 queue:nil usingBlock:^(NSNotification *n) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self) { self->_revokes += 1; }
    }];
    [self onQueue:^{
        [self->_mgr setValue:@NO forKey:@"_manualClose"];
        [self->_mgr setValue:@NO forKey:@"_retriedAfterRefresh"];
    }];
}

- (void)tearDown {
    method_exchangeImplementations(_open, _stub);
    [NSNotificationCenter.defaultCenter removeObserver:_observer];
    [self onQueue:^{
        [self->_mgr setValue:@NO forKey:@"_manualClose"];
        [self->_mgr setValue:@NO forKey:@"_retriedAfterRefresh"];
        self->_mgr.state = IMSocketStateDisconnected;
    }];
}

- (void)onQueue:(void (^)(void))block { dispatch_sync([_mgr valueForKey:@"_queue"], block); }

/// 模拟一次「握手中 → 401」。handleDisconnect 对已断开且无 task 的会直接跳过，所以先摆成 Connecting。
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
    XCTAssertEqual(IMSocketUnauthorizedActionFor(NO), IMSocketUnauthorizedActionRefresh, @"第一次 401：先续期");
    XCTAssertEqual(IMSocketUnauthorizedActionFor(YES), IMSocketUnauthorizedActionRevoked, @"续期后的新 token 还 401：按被踢");
}

- (void)testFirst401RefreshesInsteadOfKicking {
    [self reject401];
    XCTAssertEqual(_revokes, 0, @"token 只是失效（过期 / 服务端换密钥）不能把人踢回登录页");
    XCTAssertEqual(gOpenSocketCalls, 1, @"应立即重连（openSocket 内会 miss 缓存去续期）");
    XCTAssertFalse([[_mgr valueForKey:@"_manualClose"] boolValue], @"还要继续自动重连");
}

- (void)testSecond401AfterRefreshKicks {
    [self reject401];
    [self reject401];
    XCTAssertEqual(_revokes, 1, @"续期换来的新 token 还 401 = sid 真被吊销");
    XCTAssertEqual(gOpenSocketCalls, 1, @"不再续第二次（防死循环）");
    XCTAssertTrue([[_mgr valueForKey:@"_manualClose"] boolValue], @"被踢后停自动重连");
}

- (void)testConnectingSuccessfullyResetsRetryBudget {
    [self reject401];
    [self onQueue:^{ [self->_mgr setValue:@NO forKey:@"_retriedAfterRefresh"]; }]; // didOpen 做的事
    [self reject401];
    XCTAssertEqual(_revokes, 0, @"连上过之后再遇到 401，还能再续一次");
    XCTAssertEqual(gOpenSocketCalls, 2);
}

@end
