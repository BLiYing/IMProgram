//  IMRtcConfig.h
//  im-rtc 接入配置。值来自 bundle 里的 `IMRtcConfig.local.plist`（**已被 .gitignore 忽略，不要提交**）。
//  模板见同目录 `IMRtcConfig.example.plist`。
//
//  接入票不再由本端签发，改由 IMServer 的 POST /api/v1/rtc/token 代为向 im-rtc-server 换票
//  （见 IMRtcCall.m 的 signTokenWithCompletion:）——本端既不需要也不该知道 SDKAppID / SDKSecretKey。
//  对端：im-android `rtc/RtcConfig.kt`、im-web `src/rtc/rtcConfig.ts`。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMRtcConfig : NSObject

/// 信令地址，`ws://` 或 `wss://`。真机别填 127.0.0.1（那指的是手机自己）。
@property (nonatomic, copy, readonly) NSString *wsURL;

/// 从 bundle 读；文件不存在返回空配置（`missingKeys` 会列出全部）。
+ (instancetype)load;
- (instancetype)initWithDictionary:(nullable NSDictionary *)dict NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// 缺哪几项（配置名，给人看的）。空 = 可用。
@property (nonatomic, copy, readonly) NSArray<NSString *> *missingKeys;
@property (nonatomic, readonly) BOOL isUsable;

/// 宿主 id 送进 im-rtc 前的字段校验（协议 §2.5：非空、无空白、≤64 字节）。不合规返回原因，合规返回 nil。
+ (nullable NSString *)problemForID:(nullable NSString *)identifier kind:(NSString *)kind;

@end

NS_ASSUME_NONNULL_END
