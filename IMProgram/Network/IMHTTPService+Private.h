//  IMHTTPService+Private.h
//  IMHTTPService 的**共享内部接口**：把请求构造与响应解包暴露给同类的分文件 category
//  （CODING_STYLE §7 ②：一组内聚方法 → 分文件 category），套路与 IMSocketManager+Private.h 一致。
//
//  拆分的直接原因是体量红线（IMHTTPService.m 已逼近 1500 行），但选择**沿"整会话查询"这条线**切：
//  会话内检索 / 日历聚合是离线积压方案里新长出来的一族接口（OFFLINE_BACKLOG_DESIGN §4.9），
//  与登录、上传、好友等既有接口没有共享状态，天然独立。

#import "IMHTTPService.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMHTTPService (Private)

/// 构造带 Bearer 的请求；body 非空时序列化为 JSON 并补 Content-Type。服务器地址非法时返回 nil。
- (nullable NSMutableURLRequest *)authedRequestForPath:(NSString *)path
                                                method:(NSString *)method
                                                 token:(NSString *)token
                                                  body:(nullable NSDictionary *)body;

/// 发请求并解包 `{code,message,data}`：code != 0 时用 fallback 造错误；回调已在主线程。
- (void)runDataRequest:(nullable NSMutableURLRequest *)request
              fallback:(NSString *)fallback
            completion:(void (^)(NSDictionary *_Nullable data, NSError *_Nullable error))completion;

/// URL 路径段转义（conv_id 里有下划线与字母数字，但别假设，统一走它）。
- (NSString *)pathEscape:(NSString *)raw;

/// 主线程回调（内部网络回调在会话队列上）。
- (void)callOnMain:(dispatch_block_t)block;

/// 造一个带文案的 NSError（domain/code 与既有一致）。
- (NSError *)errorWithMessage:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
