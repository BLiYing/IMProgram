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

/// `watch` 订阅集的记忆：连接级易失态（PROTOCOL §5.5），重连后必须重发，故 `IMSocketManager`
/// 记住最后一次集合。这里只钉「记住 + 归一化」这一半；**重连时真的重发**要靠手测/日志
/// （`watch 重发 N 个（连接级易失态）`），单测起不了 WebSocket。
- (void)testWatchSetIsRemembered {
    IMSocketManager *m = IMSocketManager.sharedManager; // 单例：用例末尾复位，别把关注集留给别的用例

    [m watchUsers:@[@"1001", @"1002"]];
    XCTAssertEqualObjects(m.watchedUserIDs, (@[@"1001", @"1002"]), @"记住最后一次全集，供重连重发");

    [m watchUsers:@[@"2001"]];
    XCTAssertEqualObjects(m.watchedUserIDs, @[@"2001"], @"全量替换语义：后一次覆盖前一次，不做并集");

    [m watchUsers:@[]];
    XCTAssertEqualObjects(m.watchedUserIDs, @[], @"空集=取消全部关注");

    [m watchUsers:nil];
    XCTAssertEqualObjects(m.watchedUserIDs, @[], @"nil 归一化成空集，读取方不必判空");
    // 已是空集，等于已复位；显式再写一次以表明意图（将来在上面追加断言时别忘了这一步）。
    [m watchUsers:@[]];
}

@end
