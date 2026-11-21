//  IMHTTPService+Directory.m

#import "IMHTTPService+Directory.h"
#import "IMHTTPService+Private.h"
#import "IMLocalization.h"

@implementation IMHTTPService (Directory)

/// 拼请求 + 跑：保留业务码（400101 等按码出文案，400120 带回 data）。
- (void)directoryPath:(NSString *)path method:(NSString *)method body:(nullable id)body token:(NSString *)token
           completion:(IMDirectoryCompletion)completion {
    [self runDataRequest:[self authedRequestForPath:path method:method token:token body:body]
                fallback:IMLocalized(@"common.action_failed") completion:completion];
}

- (void)directoryMeWithToken:(NSString *)token completion:(IMDirectoryCompletion)completion {
    [self directoryPath:@"/api/v1/directory/me" method:@"GET" body:nil token:token completion:completion];
}

- (void)redeemInviteCodeWithToken:(NSString *)token code:(NSString *)code completion:(IMDirectoryCompletion)completion {
    [self directoryPath:@"/api/v1/directory/redeem" method:@"POST" body:@{ @"code": code ?: @"" } token:token completion:completion];
}

- (void)directoryUnitsWithToken:(NSString *)token completion:(IMDirectoryCompletion)completion {
    [self directoryPath:@"/api/v1/directory/units" method:@"GET" body:nil token:token completion:completion];
}

- (void)directoryDeptWithToken:(NSString *)token unitID:(NSString *)unitID deptID:(NSString *)deptID
                        cursor:(NSString *)cursor completion:(IMDirectoryCompletion)completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/directory/units/%@/depts/%@",
                      [self pathEscape:unitID], [self pathEscape:(deptID.length > 0 ? deptID : @"root")]];
    if (cursor.length > 0) { path = [path stringByAppendingFormat:@"?cursor=%@", IMQueryValueEscape(cursor)]; }
    [self directoryPath:path method:@"GET" body:nil token:token completion:completion];
}

- (void)directorySearchWithToken:(NSString *)token query:(NSString *)query completion:(IMDirectoryCompletion)completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/directory/search?q=%@", IMQueryValueEscape(query)];
    [self directoryPath:path method:@"GET" body:nil token:token completion:completion];
}

- (void)directoryNoticeAckWithToken:(NSString *)token completion:(IMDirectoryCompletion)completion {
    [self directoryPath:@"/api/v1/directory/notice-ack" method:@"POST" body:@{} token:token completion:completion];
}

@end
