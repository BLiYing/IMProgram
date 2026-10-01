//  IMPushSender.m

#import "IMPushSender.h"

NSString *const IMAppGroupID = @"group.com.libeyond.IMProgram";

static NSString *const kIMSharedSchemeKey = @"im_push_server_scheme";
static NSString *const kIMSharedHostKey = @"im_push_server_host";

void IMPushSharedSaveServer(NSString *scheme, NSString *host) {
    if (scheme.length == 0 || host.length == 0) { return; }
    NSUserDefaults *shared = [[NSUserDefaults alloc] initWithSuiteName:IMAppGroupID];
    [shared setObject:scheme forKey:kIMSharedSchemeKey];
    [shared setObject:host forKey:kIMSharedHostKey];
}

NSURL *IMPushAvatarURL(NSString *path, NSString *scheme, NSString *host) {
    if (path.length == 0 || host.length == 0) { return nil; }
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) { return nil; }
    if (![path hasPrefix:@"/avatars/"] || [path containsString:@".."]) { return nil; }
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@%@", scheme, host, path]];
    // 主机里混进了 `/`、`@` 之类的字符时拼出来的 URL 会指向别处：拼完再核一遍主机。
    if (url == nil || url.host.length == 0 || ![host hasPrefix:url.host]) { return nil; }
    return url;
}

NSURL *IMPushSharedAvatarURL(NSString *path) {
    NSUserDefaults *shared = [[NSUserDefaults alloc] initWithSuiteName:IMAppGroupID];
    return IMPushAvatarURL(path, [shared stringForKey:kIMSharedSchemeKey], [shared stringForKey:kIMSharedHostKey]);
}

static NSString *IMPushString(NSDictionary *d, NSString *key) {
    id v = d[key];
    return [v isKindOfClass:NSString.class] && [(NSString *)v length] > 0 ? v : nil;
}

@interface IMPushSender ()
@property (nonatomic, copy, readwrite) NSString *convID;
@property (nonatomic, copy, readwrite) NSString *senderID;
@property (nonatomic, copy, readwrite) NSString *senderName;
@property (nonatomic, copy, readwrite, nullable) NSString *avatarPath;
@property (nonatomic, copy, readwrite, nullable) NSString *groupAvatarPath;
@property (nonatomic, copy, readwrite, nullable) NSString *bareBody;
@property (nonatomic, readwrite) BOOL isGroup;
@end

@implementation IMPushSender

+ (instancetype)senderFromUserInfo:(NSDictionary *)userInfo {
    if (![userInfo isKindOfClass:NSDictionary.class]) { return nil; }
    NSString *conv = IMPushString(userInfo, @"conv_id");
    NSString *sid = IMPushString(userInfo, @"sender_id");
    if (conv == nil || sid == nil) { return nil; }
    IMPushSender *s = [IMPushSender new];
    s.convID = conv;
    s.senderID = sid;
    s.senderName = IMPushString(userInfo, @"sender_name") ?: sid;
    s.avatarPath = IMPushString(userInfo, @"sender_avatar");
    s.groupAvatarPath = IMPushString(userInfo, @"group_avatar");
    s.isGroup = ![conv hasPrefix:@"u_"];
    s.bareBody = s.isGroup ? IMPushString(userInfo, @"bare_body") : nil;
    return s;
}

@end
