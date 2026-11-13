//  IMHTTPService+Export.m

#import "IMHTTPService+Export.h"
#import "IMHTTPService+Private.h"
#import "IMLocalization.h"
#import "IMHTTPService+Phone.h"

@implementation IMHTTPService (Export)

/// 整包解信封（runEnvelopeRequest）；业务错误额外把 retry_after_sec（data 内或顶层）挂到 IMErrorRetryAfterSecKey。
/// 业务码用 messageFrom: 走友好文案映射（200002 / 200010 / 200011 已收录）。
- (void)runExportRequest:(nullable NSMutableURLRequest *)req
                completion:(void (^)(id _Nullable data, NSError *_Nullable error))completion {
    [self runEnvelopeRequest:req decorateError:^NSError *(NSError *err, NSDictionary *body) {
        id data = body[@"data"];
        id retry = [data isKindOfClass:NSDictionary.class] ? data[@"retry_after_sec"] : nil;
        retry = retry ?: body[@"retry_after_sec"];
        if (![retry isKindOfClass:NSNumber.class]) { return err; }
        NSMutableDictionary *info = [err.userInfo mutableCopy] ?: [NSMutableDictionary dictionary];
        info[IMErrorRetryAfterSecKey] = retry;
        return [NSError errorWithDomain:err.domain code:err.code userInfo:info];
    } completion:completion];
}

- (void)startExportWithToken:(NSString *)token proof:(IMIdentityProof *)proof includeMedia:(BOOL)includeMedia
                     formats:(NSArray<NSString *> *)formats
                  completion:(void (^)(IMExportJob *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/exports" method:@"POST" token:token
                                                     body:IMBodyWithProof(@{ @"include_media": @(includeMedia), @"formats": formats ?: @[] }, proof)];
    [self runExportRequest:req completion:^(id data, NSError *error) {
        if (error) { completion(nil, error); return; }
        IMExportJob *job = [IMExportJob jobFromJSON:data];
        // 成功码但回包不是任务对象：当失败处理（页面无从进入进行中态）。
        completion(job, job ? nil : [self errorWithMessage:IMLocalized(@"common.action_failed")]);
    }];
}

- (void)fetchLatestExportWithToken:(NSString *)token completion:(void (^)(IMExportJob *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/exports/latest" method:@"GET" token:token body:nil];
    [self runExportRequest:req completion:^(id data, NSError *error) {
        if (error) { completion(nil, error); return; }
        if (!data || data == NSNull.null) { completion(nil, nil); return; } // 从没导出过
        IMExportJob *job = [IMExportJob jobFromJSON:data];
        completion(job, job ? nil : [self errorWithMessage:IMLocalized(@"common.action_failed")]);
    }];
}

- (void)cancelExport:(NSString *)jobID token:(NSString *)token completion:(void (^)(NSError *))completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/users/me/exports/%@/cancel", [self pathEscape:jobID ?: @""]];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"POST" token:token body:@{}];
    [self runExportRequest:req completion:^(id data, NSError *error) { completion(error); }];
}

- (void)exportDownloadURLForJob:(NSString *)jobID token:(NSString *)token
                     completion:(void (^)(NSString *, NSError *))completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/users/me/exports/%@/download_url", [self pathEscape:jobID ?: @""]];
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"POST" token:token body:@{}];
    [self runExportRequest:req completion:^(id data, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSString *url = [data isKindOfClass:NSDictionary.class] && [data[@"url"] isKindOfClass:NSString.class] ? data[@"url"] : nil;
        completion(url.length > 0 ? url : nil, url.length > 0 ? nil : [self errorWithMessage:IMLocalized(@"export.download_failed")]);
    }];
}

@end
