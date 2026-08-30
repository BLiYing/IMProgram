//  IMGroupAdminLogic.m

#import "IMGroupAdminLogic.h"
#import "IMGroupInfo.h"
#import "IMUserCard.h"

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
    return n == 0 ? @"未设置" : [NSString stringWithFormat:@"%lu 人", (unsigned long)n];
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
        case 300201: return @"该群已被解散";
        case 300203: return @"你已不在该群";
        case 300204: return @"只有群主可以进行此操作";
        case 100001: return @"操作失败，请刷新后重试"; // 三种语义共用一个码，见头文件说明
        default: break;
    }
    return error.localizedDescription.length > 0 ? error.localizedDescription : @"操作失败";
}

+ (NSString *)batchToastWithSucceeded:(NSUInteger)succeeded
                               failed:(NSUInteger)failed
                           firstError:(NSString *)firstError {
    if (failed == 0) { return [NSString stringWithFormat:@"已添加 %lu 位管理员", (unsigned long)succeeded]; }
    if (succeeded == 0) { return firstError.length > 0 ? firstError : @"添加失败"; }
    return [NSString stringWithFormat:@"%lu 位已添加，%lu 位失败：%@",
            (unsigned long)succeeded, (unsigned long)failed, firstError.length > 0 ? firstError : @"操作失败"];
}

@end
