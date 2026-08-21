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

/// 高频轮询接口（会话列表 /conversations、隐藏消息 /messages/hidden）的响应摘要：
/// 只留 data 下数组的条数与字节数，**不记整份 body**。这两个接口约每 16s 一轮、内容高度重复，
/// 整份 body 会把 dev 汇聚日志撑到几百 MB 而排查价值极低；条数足以发现"会话数突变/隐藏漏同步"类异常。
/// 其余接口仍走 IMHTTPLogBody 完整记录（favorites/messages/groups/sync 等排查靠它们，不受影响）。
FOUNDATION_EXPORT NSString *IMHTTPPollResponseSummary(NSData * _Nullable data);

NS_ASSUME_NONNULL_END
