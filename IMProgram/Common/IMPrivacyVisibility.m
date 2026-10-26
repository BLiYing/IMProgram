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
    return kind == IMPrivacyVisibilityKindLastSeen ? @"last_seen_visibility" : @"avatar_visibility";
}

NSString *IMPrivacyVisibilityDefault(IMPrivacyVisibilityKind kind) {
    return kind == IMPrivacyVisibilityKindLastSeen ? IMPrivacyVisibilityContacts : IMPrivacyVisibilityEveryone;
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
    return kind == IMPrivacyVisibilityKindLastSeen ? @"ps.row.last_seen" : @"ps.row.avatar";
}

NSString *IMPrivacyVisibilityFooterKey(IMPrivacyVisibilityKind kind) {
    return kind == IMPrivacyVisibilityKindLastSeen ? @"ps.visibility.last_seen.footer" : @"ps.visibility.avatar.footer";
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
    return s;
}

- (NSString *)visibilityForKind:(IMPrivacyVisibilityKind)kind {
    return kind == IMPrivacyVisibilityKindLastSeen ? self.lastSeenVisibility : self.avatarVisibility;
}

- (void)setVisibility:(NSString *)level forKind:(IMPrivacyVisibilityKind)kind {
    if (kind == IMPrivacyVisibilityKindLastSeen) { self.lastSeenVisibility = level; } else { self.avatarVisibility = level; }
}

@end
