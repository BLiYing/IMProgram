//  IMSettingsSearchRegistry.m

#import "IMSettingsSearchRegistry.h"
#import "IMScopedSearch.h"
#import "IMLocalization.h"

NSString *const IMSettingsSearchPathSeparator = @" › ";

@implementation IMSettingsSearchEntry

+ (instancetype)entryWithID:(NSString *)entryID title:(NSString *)title path:(NSArray<NSString *> *)path
                systemImage:(NSString *)image iconBg:(UIColor *)bg route:(NSArray<NSString *> *)route {
    IMSettingsSearchEntry *e = [IMSettingsSearchEntry new];
    e.entryID = entryID; e.title = title; e.path = path; e.systemImage = image; e.iconBg = bg; e.route = route;
    e.aliases = @[];
    return e;
}

- (NSString *)subtitle {
    if (self.path.count <= 1) { return IMLocalized(@"ios.tab.me"); }
    return [self.path componentsJoinedByString:IMSettingsSearchPathSeparator];
}

/// 匹配用的拼接串：整条路径（已含自身标题）+ 标题。
- (NSString *)searchHaystack {
    return [[self.path arrayByAddingObject:self.title ?: @""] componentsJoinedByString:IMSettingsSearchPathSeparator];
}

@end

@implementation IMSettingsSearchRegistry

/// 登记 helper：path 末项即自身标题，前缀为祖先页标题；route 与 path 逐级对应。
static IMSettingsSearchEntry *IMEntry(NSString *entryID, NSArray<NSString *> *path, NSString *symbol, UIColor *bg,
                                      NSArray<NSString *> *route) {
    return [IMSettingsSearchEntry entryWithID:entryID title:path.lastObject path:path systemImage:symbol iconBg:bg route:route];
}

+ (NSArray<IMSettingsSearchEntry *> *)allEntries {
    NSString *notif = IMLocalized(@"ios.settings.row.notifications");
    NSString *notifPrivate = IMLocalized(@"notif.type.private_title");
    NSString *notifGroup = IMLocalized(@"notif.type.group_title");
    NSString *sound = IMLocalized(@"notif.sound.title");
    NSString *privacy = IMLocalized(@"settings.row.privacy");
    NSString *storage = IMLocalized(@"ios.settings.row.data_storage");
    NSString *cellular = IMLocalized(@"download.network.cellular");
    NSString *wifi = IMLocalized(@"download.network.wifi");
    UIColor *red = UIColor.systemRedColor, *blue = UIColor.systemBlueColor, *green = UIColor.systemGreenColor;

    NSMutableArray<IMSettingsSearchEntry *> *out = [NSMutableArray arrayWithArray:@[
        // —— 「我」页一级（非破坏性、非「开发中」；「聊天文件夹」开发中、「退出登录」破坏性，均不登记）——
        IMEntry(@"saved", @[IMLocalized(@"common.saved_messages")], @"bookmark.fill", blue, @[@"saved"]),
        IMEntry(@"recentCalls", @[IMLocalized(@"ios.settings.row.recent_calls")], @"phone.fill", green, @[@"recentCalls"]),
        IMEntry(@"devices", @[IMLocalized(@"settings.row.devices")], @"laptopcomputer", UIColor.systemOrangeColor, @[@"devices"]),
        IMEntry(@"shareMyCard", @[IMLocalized(@"settings.info.share_card")], @"person.crop.square", UIColor.systemTealColor, @[@"shareMyCard"]),
        IMEntry(@"notifications", @[notif], @"bell.badge.fill", red, @[@"notifications"]),
        IMEntry(@"privacy", @[privacy], @"lock.fill", UIColor.systemGrayColor, @[@"privacy"]),
        IMEntry(@"storage", @[storage], @"externaldrive.fill", green, @[@"storage"]),
        IMEntry(@"appearance", @[IMLocalized(@"ios.settings.row.appearance")], @"circle.lefthalf.filled", blue, @[@"appearance"]),
        IMEntry(@"powerSaving", @[IMLocalized(@"ios.settings.row.power_saving")], @"bolt.fill", UIColor.systemYellowColor, @[@"powerSaving"]),
        IMEntry(@"language", @[IMLocalized(@"settings.language.title")], @"globe", UIColor.systemPurpleColor, @[@"language"]),
        // —— 通知：私聊 / 群聊通知页、各自的提示音页 ——
        IMEntry(@"notifications.private", @[notif, notifPrivate], @"person.fill", blue, @[@"notifications", @"notifications/private"]),
        IMEntry(@"notifications.group", @[notif, notifGroup], @"person.2.fill", green, @[@"notifications", @"notifications/group"]),
        IMEntry(@"notifications.private.sound", @[notif, notifPrivate, sound], @"speaker.wave.2.fill", red,
                @[@"notifications", @"notifications/private", @"notifications/private/sound"]),
        IMEntry(@"notifications.group.sound", @[notif, notifGroup, sound], @"speaker.wave.2.fill", red,
                @[@"notifications", @"notifications/group", @"notifications/group/sound"]),
        // —— 隐私与安全：已屏蔽的用户 / 修改密码（账号保护等占位行不登记）——
        IMEntry(@"privacy.blocked", @[privacy, IMLocalized(@"blocked.title")], @"nosign", red, @[@"privacy", @"privacy/blocked"]),
        IMEntry(@"privacy.changePassword", @[privacy, IMLocalized(@"settings.change_password")], @"key.fill", blue,
                @[@"privacy", @"privacy/changePassword"]),
        // —— 数据和存储：自动下载（移动数据 / Wi-Fi）及各媒体类别 ——
        IMEntry(@"storage.cellular", @[storage, cellular], @"antenna.radiowaves.left.and.right", green, @[@"storage", @"storage/cellular"]),
        IMEntry(@"storage.wifi", @[storage, wifi], @"wifi", blue, @[@"storage", @"storage/wifi"]),
    ]];
    NSArray<NSArray *> *categories = @[ @[@"image", IMLocalized(@"common.image"), @"photo.fill"],
                                        @[@"video", IMLocalized(@"common.video"), @"video.fill"],
                                        @[@"file", IMLocalized(@"common.file"), @"doc.fill"] ];
    for (NSArray *net in @[ @[@"cellular", cellular], @[@"wifi", wifi] ]) {
        for (NSArray *cat in categories) {
            NSString *netPage = [@"storage/" stringByAppendingString:net[0]];
            [out addObject:IMEntry([NSString stringWithFormat:@"storage.%@.%@", net[0], cat[0]],
                                   @[storage, net[1], cat[1]], cat[2], green,
                                   @[@"storage", netPage, [NSString stringWithFormat:@"%@/%@", netPage, cat[0]]])];
        }
    }
    for (IMSettingsSearchEntry *e in out) {
        // 通知「提示音」页：中文用户习惯搜「声音」，英文页标题已是 Sound，别名只补中文口径
        if ([e.entryID hasSuffix:@".sound"]) { e.aliases = @[@"声音"]; }
    }
    return out;
}

+ (NSArray<IMSettingsSearchEntry *> *)filterEntries:(NSArray<IMSettingsSearchEntry *> *)entries keyword:(NSString *)keyword {
    if (IMScopedSearchNormalize(keyword).length == 0) { return @[]; }
    NSMutableArray<IMSettingsSearchEntry *> *titleHits = [NSMutableArray array];
    NSMutableArray<IMSettingsSearchEntry *> *pathHits = [NSMutableArray array];
    for (IMSettingsSearchEntry *e in entries) {
        if (IMScopedSearchMatches(keyword, [@[e.title ?: @""] arrayByAddingObjectsFromArray:e.aliases ?: @[]])) { [titleHits addObject:e]; }
        else if (IMScopedSearchMatches(keyword, @[[e searchHaystack]])) { [pathHits addObject:e]; }
    }
    return [titleHits arrayByAddingObjectsFromArray:pathHits];
}

@end
