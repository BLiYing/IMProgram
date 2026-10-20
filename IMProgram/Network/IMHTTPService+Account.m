//  IMHTTPService+Account.m

#import "IMHTTPService+Account.h"
#import "IMHTTPService+Private.h"
#import "IMLocalization.h"

NSInteger const IMErrCodeAccountPendingDeletion = 200005;
NSInteger const IMErrCodeNoPermission = 100103;
NSString * const IMErrorDeleteAtKey = @"im_delete_at";
NSString * const IMErrorOwnedGroupsKey = @"im_owned_groups";

NSDate *IMParseDeleteAt(id raw) {
    if ([raw isKindOfClass:NSNumber.class]) {
        double v = [raw doubleValue];
        if (v <= 0) { return nil; }
        return [NSDate dateWithTimeIntervalSince1970:v > 1e11 ? v / 1000.0 : v];
    }
    if ([raw isKindOfClass:NSString.class] && [raw length] > 0) {
        NSISO8601DateFormatter *f = [NSISO8601DateFormatter new];
        NSDate *d = [f dateFromString:raw];
        if (d) { return d; }
        f.formatOptions |= NSISO8601DateFormatWithFractionalSeconds;
        d = [f dateFromString:raw];
        if (d) { return d; }
        double v = [raw doubleValue];
        return v > 0 ? IMParseDeleteAt(@(v)) : nil;
    }
    return nil;
}

NSString *IMDeleteAtDisplayString(NSDate *date) {
    if (!date) { return @"-"; }
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = IMLocalization.shared.locale;
    f.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"MMMd" options:0 locale:f.locale];
    return [f stringFromDate:date];
}

NSArray<NSDictionary<NSString *, NSString *> *> *IMParseOwnedGroups(id raw) {
    if (![raw isKindOfClass:NSArray.class]) { return @[]; }
    NSMutableArray *out = [NSMutableArray array];
    for (id item in (NSArray *)raw) {
        NSString *gid = @"", *name = @"";
        if ([item isKindOfClass:NSString.class]) {
            name = item;
        } else if ([item isKindOfClass:NSDictionary.class]) {
            for (NSString *k in @[@"id", @"group_id", @"conv_id", @"topic_id"]) {
                if ([item[k] isKindOfClass:NSString.class] && [item[k] length] > 0) { gid = item[k]; break; }
            }
            name = [item[@"name"] isKindOfClass:NSString.class] ? item[@"name"] : @"";
        }
        if (name.length == 0 && gid.length == 0) { continue; }
        [out addObject:@{ @"id": gid, @"name": name }];
    }
    return out;
}

NSError *IMErrorByAttachingAccountInfo(NSError *error, NSDictionary *body) {
    NSDictionary *data = [body[@"data"] isKindOfClass:NSDictionary.class] ? body[@"data"] : nil;
    if (!error || !data) { return error; }
    NSMutableDictionary *info = [error.userInfo mutableCopy] ?: [NSMutableDictionary dictionary];
    NSDate *at = IMParseDeleteAt(data[@"delete_at"]);
    if (at) { info[IMErrorDeleteAtKey] = at; }
    NSArray *groups = IMParseOwnedGroups(data[@"owned_groups"]);
    if (groups.count > 0) { info[IMErrorOwnedGroupsKey] = groups; }
    return [NSError errorWithDomain:error.domain code:error.code userInfo:info];
}

@implementation IMHTTPService (Account)

/// 发请求，业务码非 0 时保留码并附 owned_groups / delete_at。
- (void)runAccountRequest:(nullable NSURLRequest *)req
                 fallback:(NSString *)fallback
               completion:(void (^)(NSError *_Nullable))completion {
    if (!req) {
        [self callOnMain:^{ completion([self errorWithMessage:IMLocalized(@"net.error.invalid_server")]); }];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        NSError *result = error;
        // 信封缺 code（网关/代理回了别的 JSON）不能当成功：注销成功会触发本机清库 + 登出，必须有明确的 code=0。
        BOOL hasCode = [body[@"code"] isKindOfClass:NSNumber.class] || [body[@"code"] isKindOfClass:NSString.class];
        NSInteger code = hasCode ? [body[@"code"] integerValue] : -1;
        if (!error && code != 0) {
            result = IMErrorByAttachingAccountInfo(
                [self errorWithCode:code message:[self messageFrom:body fallback:fallback]], body);
        }
        [self callOnMain:^{ completion(result); }];
    }];
}

- (void)deleteAccountWithToken:(NSString *)token password:(NSString *)password
                    completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/account/delete" method:@"POST" token:token
                                                     body:@{ @"password": password ?: @"" }];
    [self runAccountRequest:req fallback:IMLocalized(@"common.action_failed") completion:completion];
}

- (void)restoreAccountWithUsername:(NSString *)username password:(NSString *)password
                        completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self postRequestToPath:@"/api/v1/account/restore"
                                                  body:@{ @"username": username ?: @"", @"password": password ?: @"" }];
    [self runAccountRequest:req fallback:IMLocalized(@"common.action_failed") completion:completion];
}

@end
