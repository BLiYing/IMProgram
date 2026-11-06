//  IMAboutLinks.h
//  「关于我们」四个链接（隐私政策 / 服务条款 / 技术支持 / 在线客服）的后台配置：拉取 + 解析。
//  契约：GET /api/v1/about-links（IMServer internal/aboutlinks）。取值语义——
//    · 绝对 http(s) URL：原样打开，**不追加 ?lang=**；
//    · 以 "/" 开头：本服务托管页，用 IMAppInfo 拼 host + 路径 + ?lang=；
//    · 空串：只可能是在线客服，表示后台关闭了入口（隐藏该行）。
//  拉不到（离线 / 老服务端 404 / 非法响应）：法务三项退回内置路径，在线客服隐藏，且不弹错误。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const IMAboutLinkFieldPrivacy;         ///< privacy_url
FOUNDATION_EXPORT NSString *const IMAboutLinkFieldTerms;           ///< terms_url
FOUNDATION_EXPORT NSString *const IMAboutLinkFieldSupport;         ///< support_url
FOUNDATION_EXPORT NSString *const IMAboutLinkFieldCustomerService; ///< customer_service_url

/// 客服页内跳转决策。
typedef NS_ENUM(NSInteger, IMAboutNavDecision) {
    IMAboutNavDecisionAllow,    ///< 页内加载（http/https 且有主机，或 about:blank）
    IMAboutNavDecisionExternal, ///< 交给系统 openURL（tel:/mailto:/sms: 等）
    IMAboutNavDecisionBlock,    ///< 拦掉（javascript:/file:/data:/blob: 等，或空 URL）
};

/// UA 标记前缀，与 Android AboutLinks.BEACON_UA_MARKER 一致。
FOUNDATION_EXPORT NSString *const IMBeaconUAMarker; ///< @"BeaconApp/"

@interface IMAboutLinks : NSObject

/// 在系统默认 UA 末尾追加 " BeaconApp/<version> (iOS)"；已带标记不重复追加；version 为空/空白 → "0.0.0"；base 为空 → 只返回标记串。
+ (NSString *)beaconUserAgentWithBase:(nullable NSString *)base version:(nullable NSString *)version;

/// 客服页里一次导航该怎么走（见 IMAboutNavDecision）。
+ (IMAboutNavDecision)navigationDecisionForURL:(nullable NSURL *)url;

+ (instancetype)shared;

/// 最近一次成功拉到的链接（字段名 → 值）及其对应的服务器；host 不同则视为无缓存。
- (nullable NSDictionary<NSString *, NSString *> *)cachedLinksForScheme:(nullable NSString *)scheme host:(nullable NSString *)host;

/// 异步拉取并写缓存；token 为空则匿名拉（此时服务端不返回客服地址）。completion 在主线程，ok=NO 表示失败（缓存不动）。
- (void)refreshWithScheme:(nullable NSString *)scheme
                     host:(nullable NSString *)host
                    token:(nullable NSString *)token
                  timeout:(NSTimeInterval)timeout
               completion:(nullable void (^)(BOOL ok))completion;

/// 解析信封响应体 → 四字段字典；code≠0 / 非 JSON / data 缺失 → nil。缺的字段不补，非字符串值丢弃。
+ (nullable NSDictionary<NSString *, NSString *> *)linksFromResponseData:(nullable NSData *)data;

/// 一个配置值 → 最终可打开的 URL；非 http(s)（如 javascript:）、无主机、空值 → nil。
+ (nullable NSURL *)URLForConfigValue:(nullable NSString *)value
                                 host:(nullable NSString *)host
                               scheme:(nullable NSString *)scheme
                             language:(NSString *)language;

/// 某字段的最终 URL（含回退）：links 为 nil 或缺该字段时，法务三项用内置路径、在线客服为 nil。
+ (nullable NSURL *)URLForField:(NSString *)field
                          links:(nullable NSDictionary<NSString *, NSString *> *)links
                           host:(nullable NSString *)host
                         scheme:(nullable NSString *)scheme
                       language:(NSString *)language;

@end

NS_ASSUME_NONNULL_END
