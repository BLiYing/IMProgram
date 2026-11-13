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
    return [IMLoginConfig configFromResponseData:data].registerEnabled;
}

- (void)fetchRegisterEnabledWithScheme:(NSString *)scheme
                                  host:(NSString *)host
                            completion:(void (^)(BOOL))completion {
    [self fetchConfigWithScheme:scheme host:host completion:^(IMLoginConfig *config, BOOL failed) {
        completion(config.registerEnabled);
    }];
}

- (void)fetchConfigWithScheme:(NSString *)scheme host:(NSString *)host
                   completion:(void (^)(IMLoginConfig *, BOOL))completion {
    [self cancel];
    NSUInteger gen = self.generation;
    __weak typeof(self) weakSelf = self;
    void (^finish)(IMLoginConfig *, BOOL) = ^(IMLoginConfig *config, BOOL failed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || self.generation != gen) { return; } // 旧请求的迟到响应
            completion(config, failed);
        });
    };
    NSString *s = scheme.length > 0 ? scheme : IMServerSchemeHTTP;
    NSURL *url = host.length > 0
        ? [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@%@", s, host, kIMPublicConfigPath]] : nil;
    if (!url) { finish(IMLoginConfig.fallbackConfig, YES); return; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = kIMPublicConfigTimeout;
    self.task = [NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        if (error.code == NSURLErrorCancelled && [error.domain isEqualToString:NSURLErrorDomain]) { return; } // 被取代 / cancel，非故障
        if (error) {
            // 离线 / 连不上：按开放、短信不可用处理，真正提交时服务端仍会回 200007。
            IMLogWarnWithTag(IMLogTagHTTP, @"public_config_fetch_failed host=%@ err=%@", host, error.localizedDescription ?: @"-");
            finish(IMLoginConfig.fallbackConfig, YES);
            return;
        }
        IMLoginConfig *config = [IMLoginConfig configFromResponseData:data];
        IMLogHTTP(@"public_config host=%@ status=%ld register_enabled=%d sms=%d regions=%lu", host,
                  (long)([resp isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)resp).statusCode : 0),
                  config.registerEnabled, config.smsAvailable, (unsigned long)config.smsRegions.count);
        finish(config, NO);
    }];
    [self.task resume];
}

- (void)cancel {
    self.generation++;
    [self.task cancel];
    self.task = nil;
}

@end
