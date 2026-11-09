//  IMPublicConfig.m

#import "IMPublicConfig.h"
#import "IMLog.h"
#import "IMServerEndpoint.h"

static NSString * const kIMPublicConfigPath = @"/api/v1/public-config";
static const NSTimeInterval kIMPublicConfigTimeout = 5;

@interface IMPublicConfig ()
/// 每发一次请求 +1；回调时不等于当前值 = 已被更新的请求或 cancel 取代，丢弃。只在主线程读写。
@property (nonatomic, assign) NSUInteger generation;
/// 在途请求：被新请求取代或 cancel 时一并取消，连点页签不会堆积请求。只在主线程读写。
@property (nonatomic, strong, nullable) NSURLSessionDataTask *task;
@end

@implementation IMPublicConfig

+ (BOOL)registerEnabledFromResponseData:(NSData *)data {
    if (data.length == 0) { return YES; }
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![root isKindOfClass:NSDictionary.class]) { return YES; }
    // code 可能是 null / 字符串：NSNull 没有 integerValue，直接发消息会崩。
    id code = root[@"code"];
    if (![code isKindOfClass:NSNumber.class] || [code integerValue] != 0) { return YES; }
    NSDictionary *d = root[@"data"];
    if (![d isKindOfClass:NSDictionary.class]) { return YES; }
    id enabled = d[@"register_enabled"];
    if (![enabled isKindOfClass:NSNumber.class]) { return YES; }
    return [enabled boolValue];
}

- (void)fetchRegisterEnabledWithScheme:(NSString *)scheme
                                  host:(NSString *)host
                            completion:(void (^)(BOOL))completion {
    [self cancel];
    NSUInteger gen = self.generation;
    __weak typeof(self) weakSelf = self;
    void (^finish)(BOOL) = ^(BOOL enabled) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || self.generation != gen) { return; } // 旧请求的迟到响应
            completion(enabled);
        });
    };
    NSString *s = scheme.length > 0 ? scheme : IMServerSchemeHTTP;
    NSURL *url = host.length > 0
        ? [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@%@", s, host, kIMPublicConfigPath]] : nil;
    if (!url) { finish(YES); return; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = kIMPublicConfigTimeout;
    self.task = [NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        if (error.code == NSURLErrorCancelled && [error.domain isEqualToString:NSURLErrorDomain]) { return; } // 被取代 / cancel，非故障
        if (error) {
            // 离线 / 连不上：按开放处理，真正提交时服务端仍会回 200007。
            IMLogWarnWithTag(IMLogTagHTTP, @"public_config_fetch_failed host=%@ err=%@", host, error.localizedDescription ?: @"-");
            finish(YES);
            return;
        }
        BOOL enabled = [IMPublicConfig registerEnabledFromResponseData:data];
        IMLogHTTP(@"public_config host=%@ status=%ld register_enabled=%d", host,
                  (long)([resp isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)resp).statusCode : 0), enabled);
        finish(enabled);
    }];
    [self.task resume];
}

- (void)cancel {
    self.generation++;
    [self.task cancel];
    self.task = nil;
}

@end
