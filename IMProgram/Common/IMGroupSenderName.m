//  IMGroupSenderName.m

#import "IMGroupSenderName.h"
#import "IMMessageModel.h"

NSString *IMGroupSenderPublicName(NSString *memberNickname, NSString *latestSnapshot, NSString *ownSnapshot) {
    if (memberNickname.length > 0) { return memberNickname; }
    if (latestSnapshot.length > 0) { return latestSnapshot; }
    if (ownSnapshot.length > 0) { return ownSnapshot; }
    return nil;
}

NSString *IMLatestSenderNickname(NSArray<IMMessageModel *> *messages, NSString *sender) {
    if (sender.length == 0) { return nil; }
    for (IMMessageModel *m in messages.reverseObjectEnumerator) {
        if ([m.from isEqualToString:sender] && m.fromNickname.length > 0) { return m.fromNickname; }
    }
    return nil;
}

BOOL IMGroupMemberNicknameStale(NSString *memberNickname, NSString *inboundNickname) {
    return memberNickname.length > 0 && inboundNickname.length > 0 && ![memberNickname isEqualToString:inboundNickname];
}
