//  IMHTTPService+RTC.h
//  im-rtc（音视频通话）接入票：由 IMServer 代为向 im-rtc-server 换票，本端不需要也不该知道
//  任何签名密钥。单独一个 category 是因为这条路径只有 IMRtcCall.m 一个调用方，与登录/上传/
//  好友等既有接口没有共享状态（CODING_STYLE §7 ②：一组内聚方法 → 分文件 category）。

#import "IMHTTPService.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMHTTPService (RTC)

/// 取一枚 im-rtc 接入票（须已登录 IM，`token` 传当前会话的 Bearer token）→ `data.{token,expires_at_ms,expires_in_sec}`。
/// 未配置 / 换票失败等业务错误经 `error` 返回（业务码见 IMServer errcode `600001`/`600002`），
/// 调用方按"通话入口不可用"静默降级，不向用户展示错误细节。
- (void)rtcTokenWithToken:(NSString *)token
                completion:(void (^)(NSDictionary *_Nullable data, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
