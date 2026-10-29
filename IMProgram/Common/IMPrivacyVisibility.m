//  IMPrivacyVisibility.m

#import "IMPrivacyVisibility.h"
#import "IMAutoDelete.h"
#import "IMLocalization.h"

NSString *const IMPrivacyVisibilityEveryone = @"everyone";
NSString *const IMPrivacyVisibilityContacts = @"contacts";
NSString *const IMPrivacyVisibilityNobody = @"nobody";

NSArray<NSString *> *IMPrivacyVisibilityLevels(void) {
    return @[IMPrivacyVisibilityEveryone, IMPrivacyVisibilityContacts, IMPrivacyVisibilityNobody];
}

NSString *IMPrivacyVisibilityJSONKey(IMPrivacyVisibilityKind kind) {
    switch (kind) {
        case IMPrivacyVisibilityKindLastSeen: return @"last_seen_visibility";
        case IMPrivacyVisibilityKindAvatar:   return @"avatar_visibility";
        case IMPrivacyVisibilityKindBio:      return @"bio_visibility";
        case IMPrivacyVisibilityKindPhone:    return @"phone_visibility";
        case IMPrivacyVisibilityKindCount:    break;
    }
    NSCAssert(NO, @"未知的隐私项目 %ld", (long)kind);
    return @"";
}

NSString *IMPrivacyVisibilityDefault(IMPrivacyVisibilityKind kind) {
    switch (kind) {
        case IMPrivacyVisibilityKindLastSeen: return IMPrivacyVisibilityContacts;
        case IMPrivacyVisibilityKindPhone:    return IMPrivacyVisibilityNobody;
        default:                              return IMPrivacyVisibilityEveryone;
    }
}

NSString *IMPrivacyVisibilityParse(IMPrivacyVisibilityKind kind, id raw) {
    if ([raw isKindOfClass:NSString.class] && [IMPrivacyVisibilityLevels() containsObject:raw]) { return raw; }
    return IMPrivacyVisibilityDefault(kind);
}

NSString *IMPrivacyVisibilityTitle(NSString *level) {
    if ([level isEqualToString:IMPrivacyVisibilityContacts]) { return IMLocalized(@"ps.visibility.contacts"); }
    if ([level isEqualToString:IMPrivacyVisibilityNobody]) { return IMLocalized(@"ps.visibility.nobody"); }
    return IMLocalized(@"ps.visibility.everyone");
}

NSString *IMPrivacyVisibilityRowTitleKey(IMPrivacyVisibilityKind kind) {
    switch (kind) {
        case IMPrivacyVisibilityKindLastSeen: return @"ps.row.last_seen";
        case IMPrivacyVisibilityKindAvatar:   return @"ps.row.avatar";
        case IMPrivacyVisibilityKindBio:      return @"ps.row.bio";
        case IMPrivacyVisibilityKindPhone:    return @"ps.row.phone_number";
        case IMPrivacyVisibilityKindCount:    break;
    }
    NSCAssert(NO, @"未知的隐私项目 %ld", (long)kind);
    return @"";
}

NSString *IMPrivacyVisibilityFooterKey(IMPrivacyVisibilityKind kind) {
    switch (kind) {
        case IMPrivacyVisibilityKindLastSeen: return @"ps.visibility.last_seen.footer";
        case IMPrivacyVisibilityKindAvatar:   return @"ps.visibility.avatar.footer";
        case IMPrivacyVisibilityKindBio:      return @"ps.visibility.bio.footer";
        case IMPrivacyVisibilityKindPhone:    return @"ps.visibility.phone.footer";
        case IMPrivacyVisibilityKindCount:    break;
    }
    NSCAssert(NO, @"未知的隐私项目 %ld", (long)kind);
    return @"";
}

NSDictionary *IMPrivacyVisibilityPutBody(IMPrivacyVisibilityKind kind, NSString *level) {
    return @{ IMPrivacyVisibilityJSONKey(kind): level };
}

@implementation IMPrivacySettings

+ (instancetype)settingsFromJSON:(NSDictionary *)data {
    NSDictionary *d = [data isKindOfClass:NSDictionary.class] ? data : @{};
    IMPrivacySettings *s = [IMPrivacySettings new];
    s.autoDeleteDefaultSec = IMAutoDeleteSecFromJSON(d[@"auto_delete_default_sec"]);
    s.lastSeenVisibility = IMPrivacyVisibilityParse(IMPrivacyVisibilityKindLastSeen, d[@"last_seen_visibility"]);
    s.avatarVisibility = IMPrivacyVisibilityParse(IMPrivacyVisibilityKindAvatar, d[@"avatar_visibility"]);
    s.bioVisibility = IMPrivacyVisibilityParse(IMPrivacyVisibilityKindBio, d[@"bio_visibility"]);
    s.phoneVisibility = IMPrivacyVisibilityParse(IMPrivacyVisibilityKindPhone, d[@"phone_visibility"]);
    return s;
}

- (NSString *)visibilityForKind:(IMPrivacyVisibilityKind)kind {
    switch (kind) {
        case IMPrivacyVisibilityKindLastSeen: return self.lastSeenVisibility;
        case IMPrivacyVisibilityKindAvatar:   return self.avatarVisibility;
        case IMPrivacyVisibilityKindBio:      return self.bioVisibility;
        case IMPrivacyVisibilityKindPhone:    return self.phoneVisibility;
        case IMPrivacyVisibilityKindCount:    break;
    }
    NSAssert(NO, @"未知的隐私项目 %ld", (long)kind);
    return IMPrivacyVisibilityDefault(IMPrivacyVisibilityKindAvatar);
}

- (void)setVisibility:(NSString *)level forKind:(IMPrivacyVisibilityKind)kind {
    switch (kind) {
        case IMPrivacyVisibilityKindLastSeen: self.lastSeenVisibility = level; break;
        case IMPrivacyVisibilityKindAvatar:   self.avatarVisibility = level; break;
        case IMPrivacyVisibilityKindBio:      self.bioVisibility = level; break;
        case IMPrivacyVisibilityKindPhone:    self.phoneVisibility = level; break;
        case IMPrivacyVisibilityKindCount:    NSAssert(NO, @"未知的隐私项目 %ld", (long)kind); break;
    }
}

@end
