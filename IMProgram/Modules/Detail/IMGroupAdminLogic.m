//  IMGroupAdminLogic.m

#import "IMGroupAdminLogic.h"
#import "IMGroupInfo.h"
#import "IMUserCard.h"
#import "IMLocalization.h"

const NSUInteger IMGroupAdminMaxBatch = 5;

@implementation IMGroupAdminLogic

+ (nullable IMGroupMember *)ownerFromMembers:(NSArray<IMGroupMember *> *)members {
    for (IMGroupMember *m in members) {
        if (m.role == IMGroupRoleOwner) { return m; }
    }
    return nil;
}

+ (NSArray<IMGroupMember *> *)adminsFromMembers:(NSArray<IMGroupMember *> *)members {
    NSMutableArray<IMGroupMember *> *admins = [NSMutableArray array];
    for (IMGroupMember *m in members) {
        if (m.role == IMGroupRoleAdmin) { [admins addObject:m]; }
    }
    [admins sortUsingComparator:^NSComparisonResult(IMGroupMember *a, IMGroupMember *b) {
        if (a.joinedAt == b.joinedAt) { return [a.userID compare:b.userID]; } // 同毫秒时稳定排序
        return a.joinedAt < b.joinedAt ? NSOrderedAscending : NSOrderedDescending;
    }];
    return admins;
}

+ (NSString *)adminCountTextForMembers:(NSArray<IMGroupMember *> *)members {
    NSUInteger n = [self adminsFromMembers:members].count;
    return n == 0 ? IMLocalized(@"settings.info.not_set") : IMLocalizedFormat(@"common.people_count", (long)n);
}

+ (NSArray<IMGroupMember *> *)adminCandidatesFromMembers:(NSArray<IMGroupMember *> *)members
                                                myUserID:(NSString *)myUserID {
    NSMutableArray<IMGroupMember *> *out = [NSMutableArray array];
    for (IMGroupMember *m in members) {
        if (m.role != IMGroupRoleMember) { continue; }               // 群主 + 现有管理员
        if (myUserID.length > 0 && [m.userID isEqualToString:myUserID]) { continue; } // 我自己
        [out addObject:m];
    }
    return out;
}

+ (NSSet<NSString *> *)adminExclusionsFromMembers:(NSArray<IMGroupMember *> *)members
                                         myUserID:(NSString *)myUserID {
    NSMutableSet<NSString *> *out = [NSMutableSet set];
    if (myUserID.length > 0) { [out addObject:myUserID]; }
    for (IMGroupMember *m in members) {
        if (m.userID.length == 0) { continue; }
        if (m.role == IMGroupRoleOwner || m.role == IMGroupRoleAdmin) { [out addObject:m.userID]; }
    }
    return out;
}

+ (NSArray<IMGroupMember *> *)transferCandidatesFromMembers:(NSArray<IMGroupMember *> *)members
                                                   myUserID:(NSString *)myUserID {
    NSMutableArray<IMGroupMember *> *out = [NSMutableArray array];
    for (IMGroupMember *m in members) {
        if (myUserID.length > 0 && [m.userID isEqualToString:myUserID]) { continue; }
        [out addObject:m];
    }
    return out;
}

+ (NSArray<IMUserCard *> *)pickerCardsFromMembers:(NSArray<IMGroupMember *> *)members {
    NSMutableArray<IMUserCard *> *cards = [NSMutableArray array];
    for (IMGroupMember *m in members) {
        IMUserCard *c = [IMUserCard new];
        c.userID = m.userID;
        c.nickname = m.displayName; // 群内公开名（群昵称优先）；备注由 IMUserCard.displayName 就地叠加
        c.username = m.username ?: @"";
        c.avatarURL = m.avatarURL ?: @"";
        [cards addObject:c];
    }
    return cards;
}

+ (NSArray<NSString *> *)clampBatchSelection:(NSArray<NSString *> *)selectedIDs {
    if (selectedIDs.count <= IMGroupAdminMaxBatch) { return selectedIDs ?: @[]; }
    return [selectedIDs subarrayWithRange:NSMakeRange(0, IMGroupAdminMaxBatch)];
}

+ (NSString *)toastForError:(NSError *)error {
    switch (error.code) {
        case 300201: return IMLocalized(@"group.event.dissolved");
        case 300203: return IMLocalized(@"group.manage.removed_toast");
        case 300204: return IMLocalized(@"group.admin.error.owner_only");
        case 100001: return IMLocalized(@"group.admin.error.stale_retry"); // 三种语义共用一个码，见头文件说明
        default: break;
    }
    return error.localizedDescription.length > 0 ? error.localizedDescription : IMLocalized(@"common.action_failed");
}

+ (NSString *)batchToastWithSucceeded:(NSUInteger)succeeded
                               failed:(NSUInteger)failed
                           firstError:(NSString *)firstError {
    if (failed == 0) { return IMLocalizedFormat(@"group.admin_list.batch_added", (long)succeeded); }
    if (succeeded == 0) { return firstError.length > 0 ? firstError : IMLocalized(@"group.admin_list.add_failed"); }
    return IMLocalizedFormat(@"group.admin_list.batch_partial",
            (long)succeeded, (long)failed, firstError.length > 0 ? firstError : IMLocalized(@"common.action_failed"));
}

@end
