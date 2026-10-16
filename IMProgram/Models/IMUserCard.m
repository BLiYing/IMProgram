//  IMUserCard.m

#import "IMUserCard.h"
#import "IMLocalization.h"

#import "IMRemarkStore.h"

IMFriendStatus IMFriendStatusFromString(NSString *s) {
    if ([s isEqualToString:@"requested"]) { return IMFriendStatusRequested; }
    if ([s isEqualToString:@"pending"])   { return IMFriendStatusPending; }
    if ([s isEqualToString:@"accepted"])  { return IMFriendStatusAccepted; }
    if ([s isEqualToString:@"blocked"])   { return IMFriendStatusBlocked; }
    return IMFriendStatusNone;
}

@implementation IMUserCard

+ (NSArray<IMUserCard *> *)cardsFromArray:(NSArray *)array {
    if (![array isKindOfClass:[NSArray class]]) { return @[]; }
    NSMutableArray<IMUserCard *> *out = [NSMutableArray arrayWithCapacity:array.count];
    for (id item in array) {
        if (![item isKindOfClass:[NSDictionary class]]) { continue; }
        [out addObject:[self cardFromDictionary:item]];
    }
    return out;
}

/// 权威端点（GET /users/{id}、/users/batch、/friends）的收尾：这些响应对每个用户都如实带 / 不带 `deleted`，
/// 所以此处按 `deleted` 的真实值登记**或撤销**（账号在冷静期内被恢复后，下一次拉到的名片不再带它）。
+ (void)reconcileDeletedFlags:(NSArray<IMUserCard *> *)cards {
    for (IMUserCard *c in cards) { [IMRemarkStore.sharedStore setUser:c.userID deleted:c.deleted]; }
}

+ (instancetype)cardFromDictionary:(NSDictionary *)dict {
    IMUserCard *c = [IMUserCard new];
    c.userID = [self stringForKey:@"user_id" in:dict];
    c.username = [self stringForKey:@"username" in:dict];
    c.nickname = [self stringForKey:@"nickname" in:dict];
    c.remark = [self stringForKey:@"remark" in:dict]; // 好友列表 / 资料卡带；找人结果无此键 → 空串
    c.avatarURL = [self stringForKey:@"avatar_url" in:dict];
    c.phone = [self stringForKey:@"phone" in:dict];
    c.status = IMFriendStatusFromString([self stringForKey:@"status" in:dict]);
    c.blocked = [dict[@"blocked"] respondsToSelector:@selector(boolValue)] ? [dict[@"blocked"] boolValue] : NO;
    c.updatedAt = [dict[@"updated_at"] respondsToSelector:@selector(longLongValue)] ? [dict[@"updated_at"] longLongValue] : 0;
    c.deleted = [dict[@"deleted"] respondsToSelector:@selector(boolValue)] ? [dict[@"deleted"] boolValue] : NO;
    if (c.deleted) { [IMRemarkStore.sharedStore setUser:c.userID deleted:YES]; } // 只登记；撤销见 +reconcileDeletedFlags:（并非每个端点都带 deleted，缺席不等于未注销）
    c.hello = [self stringForKey:@"hello" in:dict]; // 仅好友申请行带；其余为空串
    // 在线态快照：找人/好友列表不带这些键，解析出的是空态（level=Unknown，副标题为空串）。
    c.presence = [IMPresence presenceFromProfileDictionary:dict];

    NSMutableArray<NSString *> *tags = [NSMutableArray array];
    if ([dict[@"tags"] isKindOfClass:[NSArray class]]) {
        for (id t in dict[@"tags"]) {
            if ([t isKindOfClass:[NSString class]] && [(NSString *)t length] > 0) { [tags addObject:t]; }
        }
    }
    c.tags = tags;
    return c;
}

- (NSString *)displayName {
    if (self.deleted || [IMRemarkStore.sharedStore isDeletedUser:self.userID]) { return IMLocalized(@"delete_account.deleted_user"); }
    // 备注取 IMRemarkStore 的实时值而非本对象的 remark 快照：列表里的卡片常比"刚改完的备注"旧
    // 一拍，读快照会闪回旧名；store 没见过该 uid（如陌生人搜索结果）时回退昵称。
    // self.remark 的职责是把服务端值**喂进** store（见 IMRemarkStore.ingestFriends:）。
    NSString *nick = [self.nickname stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // 昵称为空时不再回退到 userID（那是 10 位内部数字 ID）；退到 @username，两者都空才给占位。
    NSString *fallback = nick.length > 0 ? nick
                       : (self.username.length > 0 ? [@"@" stringByAppendingString:self.username] : IMLocalized(@"common.unnamed_user"));
    return [IMRemarkStore.sharedStore displayNameForUser:self.userID fallback:fallback];
}

+ (NSString *)stringForKey:(NSString *)key in:(NSDictionary *)dict {
    id v = dict[key];
    return [v isKindOfClass:[NSString class]] ? v : @"";
}

@end
