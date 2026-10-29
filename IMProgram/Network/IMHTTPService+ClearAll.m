//  IMHTTPService+ClearAll.m

#import "IMHTTPService+ClearAll.h"
#import "IMHTTPService+Private.h"
#import "IMLocalization.h"

@implementation IMHTTPService (ClearAll)

- (void)clearAllConversationsWithToken:(NSString *)token
                            completion:(void (^)(IMClearAllResult *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/conversations/clear" method:@"POST" token:token body:nil];
    if (!req) {
        [self callOnMain:^{ completion(nil, [self errorWithMessage:IMLocalized(@"net.error.invalid_server")]); }];
        return;
    }
    [self runDataRequest:req fallback:IMLocalized(@"common.action_failed") completion:^(NSDictionary *data, NSError *error) {
        if (error) { completion(nil, error); return; }
        IMClearAllResult *result = IMClearAllParseResponse(data);
        // 成功码但回包不是对象：当失败处理（本机变更只在明确成功后发生）。
        completion(result, result ? nil : [self errorWithMessage:IMLocalized(@"common.action_failed")]);
    }];
}

@end
