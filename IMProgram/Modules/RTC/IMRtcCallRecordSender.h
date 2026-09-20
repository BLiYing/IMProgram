//  IMRtcCallRecordSender.h
//  通话记录消息的发送（设计 CALL_RECORD_DESIGN §2）：收到 SDK 的 callSummary → **只有主叫**发一条 content_type=call。
//  · client_msg_id = "call-"+call_id：主叫两台设备都收到结束事件、断线重发都只落一条（服务端按它幂等，无需新代码）。
//  · 被叫 / 表外角色永不发（否则一通电话两条）。发送失败**不影响通话**，只写 IM.RTC 日志，不弹提示、不自动补发。
//  · 被叫拉黑了主叫 → 服务端回 200102：吞掉（不暴露拉黑），并把本地那一行摘掉（不留红❗）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMRtcCallRecordSender : NSObject

/// 纯函数（可单测）：由 callSummary 事件负载算出「要不要发、发到哪、发什么」。
/// 返回 nil = 不发（被叫 / 缺 call_id / 1v1 缺对端 / 群缺群号）；否则含 clientMsgID / convID / toUser / content / isGroup。
+ (nullable NSDictionary<NSString *, id> *)planForSummaryPayload:(NSDictionary<NSString *, id> *)payload
                                                         selfUID:(NSString *)selfUID;

/// 处理一条 callSummary 事件（主线程）。
+ (void)handleSummaryPayload:(NSDictionary<NSString *, id> *)payload selfUID:(NSString *)selfUID;

@end

NS_ASSUME_NONNULL_END
