//  IMMediaUtil.h
//  媒体/链接相关的小工具（聊天页、收藏页、聊天记录详情等共用，避免重复实现）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 相对 URL（/uploads/xxx）补 host 成绝对地址；已是 http/data: 的原样返回；空→空串。
FOUNDATION_EXPORT NSString *IMMediaFullURL(NSString *_Nullable content, NSString *_Nullable host);

/// 从文件消息 URL 取原始显示文件名：存储名格式 <随机>__<原名>.<ext>，取 "__" 之后并百分号解码。
FOUNDATION_EXPORT NSString *IMMediaFileName(NSString *_Nullable content);

/// 整条内容是否就是一个 http(s) 链接（无空白）→ 用于 URL 消息渲染判定。
FOUNDATION_EXPORT BOOL IMMediaLooksLikeURL(NSString *_Nullable s);

NS_ASSUME_NONNULL_END
