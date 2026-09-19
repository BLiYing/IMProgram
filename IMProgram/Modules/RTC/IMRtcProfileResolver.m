#import "IMRtcProfileResolver.h"
#import "IMGroupInfo.h"
#import "IMHTTPService.h"
#import "IMImageLoader.h"
#import "IMLog.h"
#import "IMMediaUtil.h"
#import "IMRemarkStore.h"
#import "IMUserCard.h"
#import "IMUserProfileCache.h"

@implementation IMRtcProfileResolver {
    IMGroupInfo *_group;
    /// 已经触发过加载的地址：同一张图不重复发起。主线程读写。
    NSMutableSet<NSString *> *_askedAvatars;
    /// 上一次给 Kit 的答案，只在变化时记日志（避免整屏重画时刷屏）。
    NSMutableDictionary<NSString *, NSString *> *_lastAnswer;
}

- (instancetype)init {
    if ((self = [super init])) {
        _groupID = @"";
        _askedAvatars = [NSMutableSet set];
        _lastAnswer = [NSMutableDictionary dictionary];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(profilesResolved:)
                                                   name:IMUserProfileCacheDidResolveNotification object:nil];
    }
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)putGroup:(IMGroupInfo *)group { _group = group; }

#pragma mark - IMProfileResolving

- (nullable NSString *)displayNameForUID:(NSString *)uid {
    NSString *name = [self resolveNameForUID:uid];
    [self logAnswerForUID:uid name:name avatar:nil];
    return name;
}

- (nullable UIImage *)avatarImageForUID:(NSString *)uid {
    NSString *url = [self avatarURLForUID:uid];
    if (url.length == 0) { return nil; }
    UIImage *cached = [IMImageLoader.shared cachedImageForURL:url];
    if (cached) { return cached; }
    if (![_askedAvatars containsObject:url]) {
        [_askedAvatars addObject:url];
        __weak typeof(self) ws = self;
        [IMImageLoader.shared loadImageURL:url completion:^(UIImage *_Nullable image) {
            if (!image) { IMLogWarnWithTag(IMLogTagRTC, @"rtc_avatar_failed uid=%@ url=%@", uid, url); return; }
            [ws.kit reloadProfiles:@[uid]]; // 主线程；Kit 整屏重画，下一次来问就命中内存缓存
        }];
    }
    return nil;
}

#pragma mark - IM 已有数据

/// 备注 > 群昵称 > 昵称 > @句柄。取不到返回 nil（Kit 退回 uid），并让 IMUserProfileCache 排队兜底取一次。
- (nullable NSString *)resolveNameForUID:(NSString *)uid {
    NSString *remark = [IMRemarkStore.sharedStore remarkForUser:uid];
    if (remark.length) { return remark; }
    IMGroupMember *member = [self memberForUID:uid];
    if (member.groupNickname.length) { return member.groupNickname; }
    if (member.nickname.length) { return member.nickname; }
    // 没命中会排队去拉，拉完发 IMUserProfileCacheDidResolveNotification（见 profilesResolved:）。
    IMUserCard *card = [IMUserProfileCache.sharedCache cardForUserID:uid];
    if (card.nickname.length) { return card.nickname; }
    if (member.username.length) { return [@"@" stringByAppendingString:member.username]; }
    if (card.username.length) { return [@"@" stringByAppendingString:card.username]; }
    return nil;
}

- (nullable NSString *)avatarURLForUID:(NSString *)uid {
    NSString *raw = [self memberForUID:uid].avatarURL;
    if (raw.length == 0) { raw = [IMUserProfileCache.sharedCache peekCardForUserID:uid].avatarURL; }
    if (raw.length == 0) { return nil; }
    NSString *full = IMMediaFullURL(raw, IMHTTPService.sharedService.host);
    return full.length ? full : nil;
}

- (nullable IMGroupMember *)memberForUID:(NSString *)uid {
    if (self.groupID.length == 0 || ![_group.convID isEqualToString:self.groupID]) { return nil; }
    for (IMGroupMember *m in _group.members) {
        if ([m.userID isEqualToString:uid]) { return m; }
    }
    return nil;
}

#pragma mark - 兜底取回

- (void)profilesResolved:(NSNotification *)note {
    NSArray<NSString *> *uids = note.userInfo[@"user_ids"];
    if (uids.count == 0) { return; }
    [self.kit reloadProfiles:uids];
}

/// 只在答案变化时记一条：把「没问」和「答错」分开，联调靠它定位。
- (void)logAnswerForUID:(NSString *)uid name:(nullable NSString *)name avatar:(nullable NSString *)avatar {
    NSString *key = [NSString stringWithFormat:@"%@|%@", name ?: @"-", self.groupID];
    if ([_lastAnswer[uid] isEqualToString:key]) { return; }
    _lastAnswer[uid] = key;
    IMLogWithTag(IMLogTagRTC, @"rtc_profile_resolve uid=%@ name=%@ group=%@", uid, name ?: @"-", self.groupID.length ? self.groupID : @"-");
}

@end
