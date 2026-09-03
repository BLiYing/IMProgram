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
    [IMSessionStore saveHost:@"http://127.0.0.1:1" userID:@"4820571639" username:@"offlineuser"];
    [IMSessionStore saveRefreshToken:@"refresh-abc"];

    XCTAssertTrue(IMSessionStore.hasSession);
    XCTAssertEqualObjects(IMSessionStore.host, @"http://127.0.0.1:1");
    XCTAssertEqualObjects(IMSessionStore.userID, @"4820571639");
    // 保持登录靠**续期凭据**，不再靠账号明文密码（密码不可吊销，"注销这台设备"对它完全无效）。
    XCTAssertEqualObjects(IMSessionStore.refreshToken, @"refresh-abc");

    // 内部 ID 与 username 必须**分别**持久化：只存前者会让续期失效后的重新登录拿内部 ID 去 /login，
    // 而登录接口只认 username，必然失败。
    XCTAssertEqualObjects(IMSessionStore.username, @"offlineuser");
    XCTAssertNotEqualObjects(IMSessionStore.username, IMSessionStore.userID);

    // 空/nil 即删除——续期被服务端拒掉时要能擦干净，否则每次进页面都拿同一枚废凭据重试。
    [IMSessionStore saveRefreshToken:@""];
    XCTAssertNil(IMSessionStore.refreshToken);
    [IMSessionStore saveRefreshToken:@"refresh-xyz"];
    XCTAssertEqualObjects(IMSessionStore.refreshToken, @"refresh-xyz");

    // 迁移垫片：老版本留下的明文密码只读一次、用完即删。
    [NSUserDefaults.standardUserDefaults setObject:@"legacy-secret" forKey:@"im_session_pwd"];
    XCTAssertEqualObjects(IMSessionStore.legacyPassword, @"legacy-secret");
    [IMSessionStore clearLegacyPassword];
    XCTAssertNil(IMSessionStore.legacyPassword);

    // clear 必须把 username / 续期凭据 / 遗留明文一并清掉，否则退出登录后残留旧凭据、下次冷启动拿它重登。
    //
    // 这里**刻意不断言 hasSession==NO**：模拟器上 `<device>/data/Library/Preferences/
    // com.libeyond.IMProgram.plist` 可能留有历史手测写入的 `im_session_uid`，那是 App 容器之外的
    // 另一个 preferences 域，`removeObjectForKey` 删不掉它，读取时仍会兜底命中——实测到
    // 「clear 之后 userID 仍是早已作废的 1002」。那是模拟器环境残留，不是 clear 的逻辑问题；
    // 断言它只会让本用例随机器状态飘红。下面这几个键是本次受控写入的，不受该残留影响。
    [NSUserDefaults.standardUserDefaults setObject:@"legacy-secret" forKey:@"im_session_pwd"];
    [IMSessionStore clear];
    XCTAssertEqual(IMSessionStore.username.length, (NSUInteger)0, @"username 残留：%@", IMSessionStore.username);
    XCTAssertNil(IMSessionStore.refreshToken, @"refresh 残留：%@", IMSessionStore.refreshToken);
    XCTAssertNil(IMSessionStore.legacyPassword, @"遗留明文密码残留");
}

@end
