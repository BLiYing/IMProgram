#import <XCTest/XCTest.h>

#import "IMSocketManager.h"

/// 外部唤醒信号（网络恢复 / 回到前台）该做什么。判据只有两个输入、三个输出，但**三条"不该做"
/// 全是踩过或想得到的坑**，所以单独钉住：
///  · 主动断开后还重连 = 把"退出登录"和"被踢下线"自动撤销（后者曾经就是靠 token 缓存静默重登伪自愈的）；
///  · 连接中再连一次 = 掐掉正在握手的那条，反而更慢；
///  · 已连接却重连 = 白白断一次好连接。
@interface IMSocketWakeActionTests : XCTestCase
@end

@implementation IMSocketWakeActionTests

- (void)testDisconnectedReconnects {
    XCTAssertEqual(IMSocketWakeActionFor(IMSocketStateDisconnected, NO), IMSocketWakeActionReconnect,
                   @"断开态是这个功能的主场：跳过退避立即重连");
}

- (void)testConnectedOnlyProbes {
    XCTAssertEqual(IMSocketWakeActionFor(IMSocketStateConnected, NO), IMSocketWakeActionProbe,
                   @"连接尚在只探活；后台挂起后连接可能已死，但要由 ping 写失败去发现，而不是先自断");
}

- (void)testConnectingDoesNothing {
    XCTAssertEqual(IMSocketWakeActionFor(IMSocketStateConnecting, NO), IMSocketWakeActionNone,
                   @"正在握手就别打断它");
}

- (void)testManualCloseAlwaysWins {
    // 退出登录 / 被踢下线（401）都会置 manualClose；此时任何唤醒信号都不得把连接拉回来。
    XCTAssertEqual(IMSocketWakeActionFor(IMSocketStateDisconnected, YES), IMSocketWakeActionNone);
    XCTAssertEqual(IMSocketWakeActionFor(IMSocketStateConnecting, YES), IMSocketWakeActionNone);
    XCTAssertEqual(IMSocketWakeActionFor(IMSocketStateConnected, YES), IMSocketWakeActionNone);
}

@end
