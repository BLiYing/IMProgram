//  IMTimeUtil.h
//  时间相关纯逻辑自由函数（无 UIKit 依赖）——网络/模型/UI 各层通用。
//  IMTheme 是 UI 设计令牌头（import UIKit），时间工具放那会逼非 UI 层依赖主题头（CODING_STYLE §7③）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 当前时刻的毫秒时间戳（协议/SQLite 全用毫秒；此前 (int64_t)(...*1000) 在十余处各写一遍）。
FOUNDATION_EXPORT int64_t IMNowMillis(void);

NS_ASSUME_NONNULL_END
