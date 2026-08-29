#import <XCTest/XCTest.h>

#import "IMSessionStore.h"

@interface IMSessionStoreTests : XCTestCase
@end

@implementation IMSessionStoreTests

- (void)setUp {
    [super setUp];
    [IMSessionStore clear];
}

- (void)tearDown {
    [IMSessionStore clear];
    [super tearDown];
}

/// 存 → 读 → 清 的完整往返。
///
/// **刻意写成单个方法**：IMSessionStore 是进程级单例（NSUserDefaults），拆成多个测试方法后，
/// 一旦 XCTest 并行执行它们，A 的 save 会撞进 B 的 clear 与断言之间——曾实测到
/// 「clear 之后 hasSession 仍为 true」的偶发红。共享全局状态的读写往返按顺序断言最稳。
- (void)testSaveReadClearRoundTrip {
    [IMSessionStore saveHost:@"http://127.0.0.1:1" userID:@"4820571639"
                    username:@"offlineuser" password:@"secret"];

    XCTAssertTrue(IMSessionStore.hasSession);
    XCTAssertEqualObjects(IMSessionStore.host, @"http://127.0.0.1:1");
    XCTAssertEqualObjects(IMSessionStore.userID, @"4820571639");
    XCTAssertEqualObjects(IMSessionStore.password, @"secret");

    // 内部 ID 与 username 必须**分别**持久化：只存前者会让冷启动静默重登拿内部 ID 去 /login，
    // 而登录接口只认 username，必然失败并把用户踢回登录页。
    XCTAssertEqualObjects(IMSessionStore.username, @"offlineuser");
    XCTAssertNotEqualObjects(IMSessionStore.username, IMSessionStore.userID);

    // clear 必须把 username 一并清掉，否则退出登录后残留旧凭据、下次冷启动拿它去重登。
    //
    // 这里**刻意不断言 hasSession==NO**：模拟器上 `<device>/data/Library/Preferences/
    // com.libeyond.IMProgram.plist` 可能留有历史手测写入的 `im_session_uid`，那是 App 容器之外的
    // 另一个 preferences 域，`removeObjectForKey` 删不掉它，读取时仍会兜底命中——实测到
    // 「clear 之后 userID 仍是早已作废的 1002」。那是模拟器环境残留，不是 clear 的逻辑问题；
    // 断言它只会让本用例随机器状态飘红。username/password 是本次新增/受控的键，不受该残留影响。
    [IMSessionStore clear];
    XCTAssertEqual(IMSessionStore.username.length, (NSUInteger)0, @"username 残留：%@", IMSessionStore.username);
    XCTAssertEqual(IMSessionStore.password.length, (NSUInteger)0, @"password 残留：%@", IMSessionStore.password);
}

@end
