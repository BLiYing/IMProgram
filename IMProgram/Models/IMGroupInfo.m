//  IMGroupInfo.m

#import "IMGroupInfo.h"

IMGroupRole IMGroupRoleFromString(NSString *s) {
    if ([s isEqualToString:@"owner"]) { return IMGroupRoleOwner; }
    if ([s isEqualToString:@"admin"]) { return IMGroupRoleAdmin; }
    return IMGroupRoleMember;
}

/// 脏数据安全取字符串。
static NSString *IMGroupString(NSDictionary *dict, NSString *key) {
    id v = dict[key];
    return [v isKindOfClass:[NSString class]] ? v : @"";
}

/// 脏数据安全取整数。
static int64_t IMGroupInt64(NSDictionary *dict, NSString *key) {
    id v = dict[key];
    return [v respondsToSelector:@selector(longLongValue)] ? [v longLongValue] : 0;
}

/// 脏数据安全取布尔（接受 true/false 与 0/1）。
static BOOL IMGroupBool(NSDictionary *dict, NSString *key) {
    id v = dict[key];
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : NO;
}

@interface IMGroupMember ()
/// 单个成员解析（脏数据安全；无 user_id 返回 nil）。
+ (nullable instancetype)memberFromDictionary:(NSDictionary *)dict;
@end

@implementation IMGroupMember

- (NSString *)displayName {
    if (self.groupNickname.length > 0) { return self.groupNickname; } // 群昵称优先（G1）
    return self.nickname.length > 0 ? self.nickname : self.userID;
}

+ (nullable instancetype)memberFromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) { return nil; }
    IMGroupMember *m = [IMGroupMember new];
    m.userID = IMGroupString(dict, @"user_id");
    if (m.userID.length == 0) { return nil; }
    m.nickname = IMGroupString(dict, @"nickname");
    NSString *gn = IMGroupString(dict, @"group_nickname");
    m.groupNickname = gn.length > 0 ? gn : nil;
    m.avatarURL = IMGroupString(dict, @"avatar_url");
    m.role = IMGroupRoleFromString(IMGroupString(dict, @"role"));
    m.joinedAt = IMGroupInt64(dict, @"joined_at");
    m.muteUntil = IMGroupInt64(dict, @"mute_until");
    return m;
}

@end

@implementation IMGroupInfo

- (BOOL)canManage {
    return self.myRole == IMGroupRoleOwner || self.myRole == IMGroupRoleAdmin;
}

+ (nullable instancetype)groupFromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) { return nil; }
    IMGroupInfo *g = [IMGroupInfo new];
    g.convID = IMGroupString(dict, @"conv_id");
    if (g.convID.length == 0) { return nil; }
    g.name = IMGroupString(dict, @"name");
    g.owner = IMGroupString(dict, @"owner");
    g.avatarURL = IMGroupString(dict, @"avatar_url");
    g.createdAt = IMGroupInt64(dict, @"created_at");
    g.myRole = IMGroupRoleFromString(IMGroupString(dict, @"my_role"));
    g.intro = IMGroupString(dict, @"intro");
    g.announcement = IMGroupString(dict, @"announcement");
    NSString *annBy = IMGroupString(dict, @"announcement_by");
    g.announcementBy = annBy.length > 0 ? annBy : nil;
    g.announcementAt = IMGroupInt64(dict, @"announcement_at");
    g.memberCount = (NSInteger)IMGroupInt64(dict, @"member_count");
    NSString *myNick = IMGroupString(dict, @"my_nickname");
    g.myNickname = myNick.length > 0 ? myNick : nil;
    g.muteUntil = IMGroupInt64(dict, @"mute_until");
    g.joinApproval = IMGroupBool(dict, @"join_approval");
    g.permInvite = IMGroupBool(dict, @"perm_invite");
    g.permEditInfo = IMGroupBool(dict, @"perm_edit_info");
    g.permPin = IMGroupBool(dict, @"perm_pin");
    g.historyVisible = IMGroupBool(dict, @"history_visible");
    g.myMuteUntil = IMGroupInt64(dict, @"my_mute_until");
    NSArray *rawMembers = [dict[@"members"] isKindOfClass:[NSArray class]] ? dict[@"members"] : @[];
    NSMutableArray<IMGroupMember *> *members = [NSMutableArray arrayWithCapacity:rawMembers.count];
    for (id item in rawMembers) {
        IMGroupMember *m = [IMGroupMember memberFromDictionary:item];
        if (m) { [members addObject:m]; }
    }
    g.members = members;
    return g;
}

+ (NSArray<IMGroupInfo *> *)groupsFromArray:(NSArray *)array {
    if (![array isKindOfClass:[NSArray class]]) { return @[]; }
    NSMutableArray<IMGroupInfo *> *out = [NSMutableArray arrayWithCapacity:array.count];
    for (id item in array) {
        IMGroupInfo *g = [self groupFromDictionary:item];
        if (g) { [out addObject:g]; }
    }
    return out;
}

- (nullable NSString *)nicknameOfMember:(NSString *)userID {
    if (userID.length == 0) { return nil; }
    for (IMGroupMember *m in self.members) {
        if ([m.userID isEqualToString:userID]) {
            // 群昵称优先（G1），回退全局昵称；都无返回 nil 让调用方回退 uid。
            if (m.groupNickname.length > 0) { return m.groupNickname; }
            return m.nickname.length > 0 ? m.nickname : nil;
        }
    }
    return nil;
}

- (nullable NSString *)avatarURLOfMember:(NSString *)userID {
    if (userID.length == 0) { return nil; }
    for (IMGroupMember *m in self.members) {
        if ([m.userID isEqualToString:userID]) {
            return m.avatarURL.length > 0 ? m.avatarURL : nil;
        }
    }
    return nil;
}

@end
