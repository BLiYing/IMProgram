//  IMHTTPService+Workbench.m

#import "IMHTTPService+Workbench.h"
#import "IMHTTPService+Private.h"
#import "IMLocalization.h"

@implementation IMHTTPService (Workbench)

- (void)workbenchPath:(NSString *)path method:(NSString *)method body:(nullable id)body token:(NSString *)token
           completion:(IMWorkbenchCompletion)completion {
    [self runDataRequest:[self authedRequestForPath:path method:method token:token body:body]
                fallback:IMLocalized(@"common.action_failed") completion:completion];
}

- (void)workbenchHomeWithToken:(NSString *)token unitID:(NSString *)unitID completion:(IMWorkbenchCompletion)completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/workbench?unit_id=%@", IMQueryValueEscape(unitID)];
    [self workbenchPath:path method:@"GET" body:nil token:token completion:completion];
}

- (void)workbenchStoreWithToken:(NSString *)token unitID:(NSString *)unitID completion:(IMWorkbenchCompletion)completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/workbench/store?unit_id=%@", IMQueryValueEscape(unitID)];
    [self workbenchPath:path method:@"GET" body:nil token:token completion:completion];
}

- (void)workbenchSetAppWithToken:(NSString *)token unitID:(NSString *)unitID appID:(NSString *)appID
                            add:(BOOL)add completion:(IMWorkbenchCompletion)completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/workbench/apps/%@/%@", [self pathEscape:appID], add ? @"add" : @"remove"];
    [self workbenchPath:path method:@"POST" body:@{ @"unit_id": unitID ?: @"" } token:token completion:completion];
}

- (void)workbenchOpenAppWithToken:(NSString *)token unitID:(NSString *)unitID appID:(NSString *)appID
                       completion:(IMWorkbenchCompletion)completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/workbench/apps/%@/open", [self pathEscape:appID]];
    [self workbenchPath:path method:@"POST" body:@{ @"unit_id": unitID ?: @"" } token:token completion:completion];
}

@end
