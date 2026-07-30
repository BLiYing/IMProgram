//  IMHTTPLogFormatter.h
//  HTTP 日志脱敏与限长，纯函数便于 XCTest 覆盖。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 每次 HTTP 请求的客户端关联 ID；同时发送为 X-Request-ID。
FOUNDATION_EXPORT NSString *IMHTTPNewRequestID(void);

/// 递归脱敏 JSON。密码/token/手机号始终隐藏，Data URI 只保留元数据；
/// includeBusinessContent=NO 时正文类字段也隐藏。
FOUNDATION_EXPORT id IMHTTPSanitizedJSONObject(id object, BOOL includeBusinessContent);

/// 把 HTTP body 格式化成安全日志文本。multipart 只记录字节数，JSON 会递归脱敏并截断。
FOUNDATION_EXPORT NSString *IMHTTPLogBody(NSData * _Nullable data,
                                          NSString * _Nullable contentType,
                                          BOOL includeBusinessContent);

NS_ASSUME_NONNULL_END
