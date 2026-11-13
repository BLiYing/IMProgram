//  IMHTTPService+Account.m

#import "IMHTTPService+Account.h"
#import "IMHTTPService+Private.h"
#import "IMLocalization.h"
#import "IMHTTPService+Phone.h"

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

- (void)deleteAccountWithToken:(NSString *)token proof:(IMIdentityProof *)proof
                    completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/account/delete" method:@"POST" token:token
                                                     body:@{ @"proof": [proof JSONObject] }];
    [self runEnvelopeRequest:req completion:^(id data, NSError *error) { completion(error); }];
}

- (void)restoreAccountWithUsername:(NSString *)username password:(NSString *)password
                        completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self postRequestToPath:@"/api/v1/account/restore"
                                                  body:@{ @"username": username ?: @"", @"password": password ?: @"" }];
    [self runEnvelopeRequest:req completion:^(id data, NSError *error) { completion(error); }];
}

@end
