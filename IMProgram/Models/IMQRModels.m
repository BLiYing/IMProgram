//  IMQRModels.m

#import "IMQRModels.h"

#pragma mark - 脏数据安全的取值助手（与 IMGroupInfo 同范式）

static NSString *IMQRString(NSDictionary *dict, NSString *key) {
    id v = dict[key];
    return [v isKindOfClass:[NSString class]] ? v : @"";
}
static NSInteger IMQRInt(NSDictionary *dict, NSString *key) {
    id v = dict[key];
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : 0;
}
static int64_t IMQRInt64(NSDictionary *dict, NSString *key) {
    id v = dict[key];
    return [v respondsToSelector:@selector(longLongValue)] ? [v longLongValue] : 0;
}
static BOOL IMQRBool(NSDictionary *dict, NSString *key) {
    id v = dict[key];
    return [v respondsToSelector:@selector(boolValue)] && [v isKindOfClass:[NSNumber class]] ? [v boolValue] : NO;
}

@implementation IMQRUserCard
+ (instancetype)fromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) { return nil; }
    IMQRUserCard *c = [IMQRUserCard new];
    c.userID = IMQRString(dict, @"user_id");
    c.nickname = IMQRString(dict, @"nickname");
    c.avatarURL = IMQRString(dict, @"avatar_url");
    c.relation = IMQRString(dict, @"relation");
    return c;
}
@end

@implementation IMQRGroupCard
+ (instancetype)fromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) { return nil; }
    IMQRGroupCard *c = [IMQRGroupCard new];
    c.groupID = IMQRString(dict, @"group_id");
    c.name = IMQRString(dict, @"name");
    c.avatarURL = IMQRString(dict, @"avatar_url");
    c.memberCount = IMQRInt(dict, @"member_count");
    c.inviterNickname = IMQRString(dict, @"inviter_nickname");
    c.joined = IMQRBool(dict, @"joined");
    c.joinable = IMQRBool(dict, @"joinable");
    c.reason = IMQRString(dict, @"reason");
    return c;
}
@end

@implementation IMQRResolved
+ (instancetype)fromDictionary:(NSDictionary *)dict {
    IMQRResolved *r = [IMQRResolved new];
    r.kind = IMQRKindUnknown;
    if (![dict isKindOfClass:[NSDictionary class]]) { return r; }
    NSString *kind = IMQRString(dict, @"kind");
    NSDictionary *data = [dict[@"data"] isKindOfClass:[NSDictionary class]] ? dict[@"data"] : nil;
    if ([kind isEqualToString:@"user"]) {
        r.kind = IMQRKindUser;
        r.user = [IMQRUserCard fromDictionary:data];
    } else if ([kind isEqualToString:@"group"]) {
        r.kind = IMQRKindGroup;
        r.group = [IMQRGroupCard fromDictionary:data];
    } else {
        r.kind = IMQRKindUnknown;
        r.unknownText = data ? IMQRString(data, @"text") : @"";
    }
    return r;
}
@end

@implementation IMJoinRequest
+ (instancetype)fromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) { return nil; }
    NSString *uid = IMQRString(dict, @"user_id");
    if (uid.length == 0) { return nil; }
    IMJoinRequest *r = [IMJoinRequest new];
    r.userID = uid;
    r.nickname = IMQRString(dict, @"nickname");
    r.avatarURL = IMQRString(dict, @"avatar_url");
    r.hello = IMQRString(dict, @"hello");
    r.status = IMQRString(dict, @"status");
    r.createdAt = IMQRInt64(dict, @"created_at");
    return r;
}
+ (NSArray<IMJoinRequest *> *)fromArray:(NSArray *)arr {
    if (![arr isKindOfClass:[NSArray class]]) { return @[]; }
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:arr.count];
    for (id item in arr) {
        IMJoinRequest *r = [IMJoinRequest fromDictionary:item];
        if (r) { [out addObject:r]; }
    }
    return out;
}
@end

#pragma mark - 纯映射

IMQRUserAction IMQRUserActionForRelation(NSString *relation) {
    if ([relation isEqualToString:@"self"]) { return IMQRUserActionSelf; }
    if ([relation isEqualToString:@"friend"]) { return IMQRUserActionMessage; }
    if ([relation isEqualToString:@"blocked"]) { return IMQRUserActionBlocked; }
    return IMQRUserActionAdd;
}

NSString *IMQRUserActionLabel(IMQRUserAction action) {
    switch (action) {
        case IMQRUserActionMessage: return @"发消息";
        case IMQRUserActionSelf:    return @"查看我的资料";
        case IMQRUserActionBlocked: return @"查看资料";
        case IMQRUserActionAdd:
        default:                    return @"添加到通讯录";
    }
}

IMQRGroupAction IMQRGroupActionForCard(IMQRGroupCard *card) {
    if (!card) { return IMQRGroupActionDisabled; }
    if (card.joined) { return IMQRGroupActionEnter; }
    if (!card.joinable) { return IMQRGroupActionDisabled; }
    if ([card.reason isEqualToString:@"approval"]) { return IMQRGroupActionApply; }
    return IMQRGroupActionJoin;
}

NSString *IMQRGroupActionLabel(IMQRGroupAction action) {
    switch (action) {
        case IMQRGroupActionEnter:    return @"进入群聊";
        case IMQRGroupActionApply:    return @"申请加入";
        case IMQRGroupActionDisabled: return @"无法加入";
        case IMQRGroupActionJoin:
        default:                      return @"加入群聊";
    }
}

NSString *IMQRGroupActionNote(IMQRGroupCard *card) {
    if (!card) { return nil; }
    if (card.joined) { return nil; }
    if (!card.joinable) {
        if ([card.reason isEqualToString:@"full"]) { return @"群成员已达上限，暂时无法加入"; }
        if ([card.reason isEqualToString:@"banned"]) { return @"你已被移出该群，暂时或永久不可加入"; }
        return nil;
    }
    if ([card.reason isEqualToString:@"approval"]) { return @"该群需管理员审批"; }
    return nil;
}

NSString *IMQRUnknownDomain(NSString *text) {
    NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![t hasPrefix:@"http://"] && ![t hasPrefix:@"https://"]) { return nil; }
    NSURL *url = [NSURL URLWithString:t];
    return url.host.length > 0 ? url.host : nil;
}
