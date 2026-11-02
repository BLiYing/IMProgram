//  IMAppInfo.h
//  「关于我们」用的纯函数：版本串、可复制的版本信息、法务页链接拼接。无 UI、可单测。
//  设计：IMServer/docs/design/ABOUT_LEGAL_DESIGN.md

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 后端托管的三个静态页路径（与 IMServer `internal/legal` 的 `Paths` 一致）。
FOUNDATION_EXPORT NSString *const IMLegalPathPrivacy; ///< /legal/privacy
FOUNDATION_EXPORT NSString *const IMLegalPathTerms;   ///< /legal/terms
FOUNDATION_EXPORT NSString *const IMLegalPathSupport; ///< /support

@interface IMAppInfo : NSObject

/// 「1.0.0 (12)」：营销版本 + 构建号；任一缺失时退化为另一个，两者都缺为「-」。
+ (NSString *)versionStringWithShortVersion:(nullable NSString *)shortVersion build:(nullable NSString *)build;
/// 读当前 App 的 Info.plist。
+ (NSString *)versionString;
/// 点「版本」行复制的整串，带平台名便于贴给客服：「iOS 1.0.0 (12)」。
+ (NSString *)versionClipboardString;
/// 法务页完整链接：服务器地址 + 路径 + `?lang=<zh-Hans|en>`（用 App 内语言偏好，不是系统语言）。host 为空或路径不在白名单返回 nil。
/// 用 `IMServerEndpoint.shared` 的当前 scheme（已登录 / 已在登录页提交过地址时才确定）。
+ (nullable NSURL *)legalURLForPath:(NSString *)path host:(nullable NSString *)host language:(NSString *)language;
/// 同上，但 scheme 由调用方显式给出——登录页「同意」链接在用户尚未提交地址时用，避免为了拼个预览链接去改全局单例。
+ (nullable NSURL *)legalURLForPath:(NSString *)path host:(nullable NSString *)host scheme:(NSString *)scheme language:(NSString *)language;

@end

NS_ASSUME_NONNULL_END
