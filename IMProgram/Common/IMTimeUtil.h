//  IMTimeUtil.h
//  时间相关纯逻辑自由函数（无 UIKit 依赖）——网络/模型/UI 各层通用。
//  IMTheme 是 UI 设计令牌头（import UIKit），时间工具放那会逼非 UI 层依赖主题头（CODING_STYLE §7③）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 当前时刻的毫秒时间戳（协议/SQLite 全用毫秒；此前 (int64_t)(...*1000) 在十余处各写一遍）。
FOUNDATION_EXPORT int64_t IMNowMillis(void);

/// 语音时长毫秒 → "m:ss"（0/负值 → "0:00"；与后端 hub_voice.go formatVoiceDuration 同口径）。
/// 曾在气泡/收藏行/录音 HUD/锁定条/详情行五处各写一遍 %ld:%02ld（2026-08-26 收口）。
FOUNDATION_EXPORT NSString *IMFormatVoiceDuration(int64_t millis);

/// RFC3339 字符串（sys_args["at"]，如 "2026-09-22T10:00:00Z"）→ 本地时间 "yyyy-MM-dd HH:mm"；
/// 解析失败/空串返回空串。系统通知单聊（P3 i18n，new_device_login/password_changed/device_kicked）
/// 模板代入前必须先转成人读格式，不能把 RFC3339 原样喂进 IMLocalizedFormat。
FOUNDATION_EXPORT NSString *IMFormatRFC3339LocalDateTime(NSString *_Nullable rfc3339);

NS_ASSUME_NONNULL_END
