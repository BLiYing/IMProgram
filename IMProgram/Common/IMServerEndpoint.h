//  IMServerEndpoint.h
//  全 App **唯一**的「服务器地址协议」权威：HTTP / WebSocket / 媒体补全 / 日志上报四路共用。
//
//  为什么要有这个类（2026-09-03）：此前 scheme 以 `@"http://%@%@"` 字面量散在 5 处
//  （IMHTTPService / IMSocketManager / IMMediaUtil / IMChatRecordViewController / IMRemoteLogSink），
//  于是「换 https」是一次跨 5 个文件的改代码 + 发版，而不是改一处配置。收口之后：
//    · 用户在登录页填 `https://host:port` 即整端切换，客户端一行不用改；
//    · 「哪些主机是我自家服务器」有了唯一判据 —— 媒体/头像的外站 URL 白名单就挂在这里
//      （见 IMMediaUtil 的 IMMediaFullURL，防发送方可控 URL 被零点击自动拉取）。
//
//  **协议选择不来自服务端**：客户端得先选协议才能连上服务端，才谈得上读配置；若通过明文信道
//  去问「我该不该用 https」，中间人回一句「不该」就把 TLS 抵消了（经典降级攻击）。故 scheme
//  只由使用者在登录页配置、本地持久化，**永不从网络下发**。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const IMServerSchemeHTTP;   ///< @"http"
FOUNDATION_EXPORT NSString *const IMServerSchemeHTTPS;  ///< @"https"

@interface IMServerEndpoint : NSObject

+ (instancetype)shared;

/// 当前协议：`IMServerSchemeHTTP`（默认）或 `IMServerSchemeHTTPS`。
/// 赋非法值会被忽略并保持原值（宁可维持可用状态，也不要拼出畸形 URL）。
///
/// **atomic 是必需的，不是保险**：本类是进程级单例，`scheme` 在**多个队列**上被读——
/// `IMSocketManager.openSocketWithToken:` 在其私有串行队列上读（建 ws URL），
/// `IMMediaFullURL` 会在媒体下载 / 图片加载回调里被调到——而写它的是主线程（登录页、
/// SceneDelegate 冷启动恢复）。`nonatomic` 的并发读写没有任何同步，读方可能拿到正在被替换、
/// 已 release 的 NSString，表现为随机 EXC_BAD_ACCESS。
/// 注意：本属性两个存取器都是**手写并加锁**的（见 .m）——只写 atomic 关键字不够，
/// 自定义 setter 会绕过编译器合成的原子写。
@property (atomic, copy) NSString *scheme;

/// scheme == https。UI 提示与「已走过 https 就不再降级」之类的判断用。
@property (nonatomic, readonly) BOOL isSecure;

/// 解析用户输入的服务器地址。接受三种写法，返回拆好的 scheme 与 `host:port`：
///   `192.168.1.12:8080` → (http, 192.168.1.12:8080)   ——无协议前缀时按 http（保持既有默认）
///   `https://im.example.com` → (https, im.example.com)
///   `http://im.example.com:8080/` → (http, im.example.com:8080)  ——尾斜杠去掉
/// 拒绝：空串、只有协议头、带路径（`host/api`）、带 userinfo（`user@host`，易被用来伪装主机）、
/// 含空白、非 http(s) 协议。返回 NO 时不写出参。
+ (BOOL)parseInput:(nullable NSString *)input
            scheme:(NSString *_Nullable *_Nullable)outScheme
              host:(NSString *_Nullable *_Nullable)outHost;

/// `<scheme>://<host><path>`。host 为空或结果非法 → nil。
- (nullable NSURL *)httpURLForHost:(nullable NSString *)host path:(NSString *)path;

/// `ws://` 或 `wss://`（跟随 scheme）。query 已编码，不含 `?`；为空则不拼。
- (nullable NSURL *)webSocketURLForHost:(nullable NSString *)host
                                   path:(NSString *)path
                                  query:(nullable NSString *)query;

/// 相对路径（`/uploads/x.jpg`）→ 绝对地址串。host 为空时按空串拼（与历史行为一致，交由下游判空）。
- (NSString *)absoluteURLStringForHost:(nullable NSString *)host relativePath:(NSString *)path;

/// 绝对 URL 的主机是否**就是** `host` 所指的这台服务器（主机名不分大小写，端口须一致）。
/// 判据故意从严：拿不准就当外站。用于媒体/头像的外站 URL 拦截。
- (BOOL)isOwnHost:(nullable NSString *)host forAbsoluteURL:(nullable NSString *)urlString;

@end

NS_ASSUME_NONNULL_END
