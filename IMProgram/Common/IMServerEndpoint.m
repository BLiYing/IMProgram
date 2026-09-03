//  IMServerEndpoint.m

#import "IMServerEndpoint.h"

NSString *const IMServerSchemeHTTP  = @"http";
NSString *const IMServerSchemeHTTPS = @"https";

/// 把 `host:port` 拆成主机名与端口。借 NSURLComponents 做解析而不是自己找冒号——
/// IPv6 字面量（`[::1]:8080`）里冒号成堆，手写切分必错。
static BOOL IMSplitHostPort(NSString *hostPort, NSString **outHost, NSNumber **outPort) {
    if (hostPort.length == 0) { return NO; }
    NSURLComponents *c = [NSURLComponents componentsWithString:
                          [NSString stringWithFormat:@"http://%@", hostPort]];
    if (c.host.length == 0) { return NO; }
    if (outHost) { *outHost = c.host.lowercaseString; }
    if (outPort) { *outPort = c.port; }
    return YES;
}

@implementation IMServerEndpoint

// getter 与 setter 都手写了 → 编译器不再合成 ivar，必须显式 @synthesize。
@synthesize scheme = _scheme;

+ (instancetype)shared {
    static IMServerEndpoint *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [IMServerEndpoint new]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) { _scheme = IMServerSchemeHTTP; }
    return self;
}

// scheme 的存取器**都手写并加锁**。只在 .h 写 atomic 是不够的：自定义 setter 会让编译器
// 只合成 getter，写路径便绕过了原子性——那比 nonatomic 更糟，因为看起来是安全的。
// 用 @synchronized 而不是引入新的锁类型，与本仓既有做法一致（IMHTTPService 的在途登录状态同款）。
- (NSString *)scheme {
    @synchronized (self) { return _scheme; }
}

- (void)setScheme:(NSString *)scheme {
    NSString *s = scheme.lowercaseString;
    // 非法值忽略：拼出 `null://host` 之后全端静默连不上，比维持旧值难查得多。
    if (![s isEqualToString:IMServerSchemeHTTP] && ![s isEqualToString:IMServerSchemeHTTPS]) { return; }
    @synchronized (self) { _scheme = [s copy]; }
}

- (BOOL)isSecure {
    return [self.scheme isEqualToString:IMServerSchemeHTTPS];
}

+ (BOOL)parseInput:(NSString *)input
            scheme:(NSString *_Nullable *_Nullable)outScheme
              host:(NSString *_Nullable *_Nullable)outHost {
    NSString *text = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length == 0) { return NO; }

    NSString *scheme = IMServerSchemeHTTP; // 无协议前缀 → http，保持改造前的默认行为
    NSString *rest = text;
    NSRange sep = [text rangeOfString:@"://"];
    if (sep.location != NSNotFound) {
        NSString *prefix = [text substringToIndex:sep.location].lowercaseString;
        if (![prefix isEqualToString:IMServerSchemeHTTP] && ![prefix isEqualToString:IMServerSchemeHTTPS]) {
            return NO; // ws:// / 乱写的协议一律拒，别猜用户意图
        }
        scheme = prefix;
        rest = [text substringFromIndex:sep.location + sep.length];
    }

    while ([rest hasSuffix:@"/"]) { rest = [rest substringToIndex:rest.length - 1]; } // 容忍尾斜杠
    if (rest.length == 0) { return NO; }
    // 路径前缀不支持（全端各处都按 `host + 绝对路径` 拼，允许路径会拼出 /base/api/v1/... 之类的错地址）；
    // userinfo 拒收：`http://real.server@evil.example` 看起来像连自家、实际连 evil。
    if ([rest containsString:@"/"] || [rest containsString:@"@"] || [rest containsString:@"?"]) { return NO; }
    if ([rest rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) { return NO; }
    if (!IMSplitHostPort(rest, NULL, NULL)) { return NO; }

    if (outScheme) { *outScheme = scheme; }
    if (outHost) { *outHost = rest.lowercaseString; }
    return YES;
}

- (NSURL *)httpURLForHost:(NSString *)host path:(NSString *)path {
    if (host.length == 0) { return nil; }
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@%@", self.scheme, host, path ?: @""]];
}

- (NSURL *)webSocketURLForHost:(NSString *)host path:(NSString *)path query:(NSString *)query {
    if (host.length == 0) { return nil; }
    // ws ↔ http、wss ↔ https 一一对应：TLS 与否必须两条通道一致，否则「网页 https 了、长连接还明文」。
    NSString *wsScheme = self.isSecure ? @"wss" : @"ws";
    NSMutableString *s = [NSMutableString stringWithFormat:@"%@://%@%@", wsScheme, host, path ?: @""];
    if (query.length > 0) { [s appendFormat:@"?%@", query]; }
    return [NSURL URLWithString:s];
}

- (NSString *)absoluteURLStringForHost:(NSString *)host relativePath:(NSString *)path {
    return [NSString stringWithFormat:@"%@://%@%@", self.scheme, host ?: @"", path ?: @""];
}

- (BOOL)isOwnHost:(NSString *)host forAbsoluteURL:(NSString *)urlString {
    NSString *ownHost = nil, *urlHost = nil;
    NSNumber *ownPort = nil, *urlPort = nil;
    if (!IMSplitHostPort(host, &ownHost, &ownPort)) { return NO; }

    NSURLComponents *c = [NSURLComponents componentsWithString:urlString ?: @""];
    NSString *s = c.scheme.lowercaseString;
    if (![s isEqualToString:IMServerSchemeHTTP] && ![s isEqualToString:IMServerSchemeHTTPS]) { return NO; }
    urlHost = c.host.lowercaseString;
    urlPort = c.port;
    if (urlHost.length == 0 || ![urlHost isEqualToString:ownHost]) { return NO; }
    // 端口从严比对：显式 `:443` 与省略端口视为不同。服务端下发的是相对路径，此路径只在
    // 「对端塞了个绝对 URL」时才走到，从严不会误伤自家链接，放松则等于给绕过留门。
    if (ownPort == nil && urlPort == nil) { return YES; }
    return [ownPort isEqualToNumber:(urlPort ?: @(-1))];
}

@end
