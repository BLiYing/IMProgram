#import "IMRtcInviteProvider.h"
#import "IMLocalization.h"
#import "IMGroupInfo.h"
#import "IMHTTPService.h"
#import "IMLog.h"
#import "IMRemarkStore.h"
#import "IMMediaUtil.h"

static const NSInteger kPageSize = 50;

@implementation IMRtcInviteProvider

- (void)inviteCandidatesFor:(IMInviteContext *)context query:(NSString *)query cursor:(nullable NSString *)cursor
                        completion:(void (^)(NSArray<IMInviteCandidate *> *, NSString *_Nullable, NSError *_Nullable))completion {
    NSString *groupID = context.chatGroupID;
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (groupID.length == 0 || token.length == 0) {
        IMLogWarnWithTag(IMLogTagRTC, @"rtc_invite_candidates_empty group=%@ token=%d", groupID.length ? groupID : @"-", (int)token.length);
        completion(@[], nil, nil); // 必须回调：Kit 10 秒超时会判失败
        return;
    }
    NSString *q = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSSet<NSString *> *inCall = [NSSet setWithArray:context.participantUIDs];
    NSString *host = IMHTTPService.sharedService.host;
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService groupMembersPageWithToken:token convID:groupID cursor:cursor.length ? cursor : nil
                                                     limit:kPageSize query:q.length ? q : nil
                                                completion:^(NSArray<IMGroupMember *> *members, NSString *next, BOOL hasMore, NSError *error) {
        if (error) {
            IMLogWarnWithTag(IMLogTagRTC, @"rtc_invite_candidates_failed group=%@ err=%@", groupID, error.localizedDescription);
            completion(@[], nil, error);
            return;
        }
        NSMutableArray<IMInviteCandidate *> *out = [NSMutableArray array];
        for (IMGroupMember *m in members) {
            if (m.userID.length == 0 || [m.userID isEqualToString:ws.selfUID]) { continue; }
            NSString *name = [IMRemarkStore.sharedStore remarkForUser:m.userID];
            if (name.length == 0) { name = m.groupNickname; }
            if (name.length == 0) { name = m.nickname; }
            if (name.length == 0 && m.username.length) { name = [@"@" stringByAppendingString:m.username]; }
            NSString *full = m.avatarURL.length ? IMMediaFullURL(m.avatarURL, host) : nil;
            BOOL busy = [inCall containsObject:m.userID];
            [out addObject:[[IMInviteCandidate alloc] initWithUid:m.userID name:name ?: @"" avatarURL:full.length ? [NSURL URLWithString:full] : nil
                                                         subtitle:nil selectable:!busy unselectableReason:busy ? IMLocalized(@"rtc.invite.in_call") : nil]];
        }
        IMLogWithTag(IMLogTagRTC, @"rtc_invite_candidates group=%@ q=%@ got=%lu shown=%lu more=%d", groupID, q.length ? q : @"-",
                     (unsigned long)members.count, (unsigned long)out.count, hasMore);
        completion(out, (hasMore && members.count > 0) ? next : nil, nil);
    }];
}

@end
