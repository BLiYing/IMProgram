//  IMSysEventFormatter.m

#import "IMSysEventFormatter.h"
#import "IMLocalization.h"
#import "IMMessageModel.h"  // IMSysSegment
#import "IMTimeUtil.h"      // IMFormatRFC3339LocalDateTime

/// 群系统消息事件表（权威定义见 docs/PROTOCOL.md §6.6 / internal/store/types.go SysEvent*）：
/// event → [文案键, 人名槽位个数, 额外 sys_args 键(NSNull=无)]。
/// **人名槽位在 vararg 顺序里恒排在额外参数之前**（已用 docs/i18n/strings.json 的 args 声明顺序核对
/// 过全部 16 个事件，无一例外）——这不是本文件的假设，是当前文案表的既成事实；新增事件若打破这个
/// 前提，下面 IMSegmentsForSysEvent 的哨兵切分对该事件仍然按"位置"定位，不受影响，只是这张表要补行。
static NSDictionary<NSString *, NSArray *> *IMSysEventTable(void) {
    static NSDictionary *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = @{
            @"group_create":       @[@"sys.group.create",             @1, @"name"],
            @"member_invite":      @[@"sys.group.member_invite",      @1, @"names"], // names 由客户端自己拼（§1.3）
            @"member_join":        @[@"sys.group.member_join",        @1, NSNull.null],
            @"member_leave":       @[@"sys.group.member_leave",       @1, NSNull.null],
            @"member_remove":      @[@"sys.group.member_remove",      @2, NSNull.null],
            @"member_remove_ban":  @[@"sys.group.member_remove_ban",  @2, NSNull.null],
            @"role_admin_set":     @[@"sys.group.role_admin_set",     @1, NSNull.null],
            @"role_admin_revoked": @[@"sys.group.role_admin_revoked", @1, NSNull.null],
            @"owner_transfer":     @[@"sys.group.owner_transfer",     @1, NSNull.null],
            @"group_rename":       @[@"sys.group.rename",             @0, @"name"],
            @"group_avatar":       @[@"sys.group.avatar",             @1, NSNull.null],
            @"announcement":       @[@"sys.group.announcement",       @1, NSNull.null],
            @"mute_all_on":        @[@"sys.group.mute_all_on",        @0, NSNull.null],
            @"mute_all_off":       @[@"sys.group.mute_all_off",       @0, NSNull.null],
            @"mute_member":        @[@"sys.group.mute_member",        @2, NSNull.null],
            @"unmute_member":      @[@"sys.group.unmute_member",      @2, NSNull.null],
        };
    });
    return t;
}

/// 按当前 App 语言拼接一组人名（§1.3）：zh-Hans 用「、」，其余（en）用「, 」。
/// 不做 "A, B and C" 的语法优化——`, ` 简单拼接是本批既定取舍，不是遗漏。
static NSString *IMJoinLocalizedNames(NSArray<NSString *> *names) {
    if (names.count == 0) { return @""; }
    NSString *sep = [IMLocalization.shared.language isEqualToString:IMLanguagePrefZhHans] ? @"、" : @", ";
    return [names componentsJoinedByString:sep];
}

NSArray<IMSysSegment *> *IMSegmentsForSysEvent(NSString *event,
                                                NSDictionary<NSString *, NSString *> *sysArgs,
                                                NSArray<IMSysSegment *> *sysSegments,
                                                NSString *(^displayNameForUID)(NSString *, NSString *)) {
    if (event.length == 0) { return nil; }
    NSArray *spec = IMSysEventTable()[event];
    if (!spec) { return nil; } // 未识别事件（老消息/未来新增）→ 回退老路径
    NSString *key = spec[0];
    NSInteger nameSlotCount = [spec[1] integerValue];
    NSString *extraArgKey = (spec[2] == (id)NSNull.null) ? nil : spec[2];
    sysArgs = sysArgs ?: @{};

    NSMutableArray<IMSysSegment *> *uidSegs = [NSMutableArray array];
    for (IMSysSegment *seg in sysSegments) {
        if (seg.uid.length > 0) { [uidSegs addObject:seg]; }
    }
    if ((NSInteger)uidSegs.count < nameSlotCount) { return nil; } // 数据不齐（理论不该发生）→ 防御性回退

    // 每次调用独立随机的哨兵串（Unicode 私用/互文注解字符，正常文案绝不会出现），杜绝恶意群名/
    // 设备名等用户可控文本恰好撞上哨兵、把切分位置搅乱的边角风险。
    uint32_t nonce = arc4random();
    NSMutableArray<NSString *> *sentinels = [NSMutableArray arrayWithCapacity:(NSUInteger)nameSlotCount];
    NSMutableArray<NSString *> *varargs = [NSMutableArray array];
    for (NSInteger i = 0; i < nameSlotCount; i++) {
        NSString *s = [NSString stringWithFormat:@"\U0010FFF9%08x%ld\U0010FFFA", nonce, (long)i];
        [sentinels addObject:s];
        [varargs addObject:s];
    }
    if (extraArgKey) {
        NSString *val;
        if ([event isEqualToString:@"member_invite"]) {
            // §1.3：actor 之外其余带 uid 的段是被邀请者，提前本地解析显示名再按语言拼接。
            NSMutableArray<NSString *> *invitees = [NSMutableArray array];
            for (NSUInteger i = (NSUInteger)nameSlotCount; i < uidSegs.count; i++) {
                IMSysSegment *seg = uidSegs[i];
                NSString *name = displayNameForUID ? displayNameForUID(seg.uid, seg.text) : seg.text;
                if (name.length > 0) { [invitees addObject:name]; }
            }
            val = IMJoinLocalizedNames(invitees);
        } else {
            val = sysArgs[extraArgKey] ?: @"";
        }
        [varargs addObject:val];
    }

    NSString *formatted = IMLocalizedFormatArgs(key, varargs);

    // 按哨兵在结果串里的**实际位置**排序切分（不是按传入顺序）：天然兼容语言间的词序差异。
    NSMutableArray<NSValue *> *ranges = [NSMutableArray arrayWithCapacity:sentinels.count];
    for (NSString *s in sentinels) {
        NSRange r = [formatted rangeOfString:s];
        if (r.location == NSNotFound) { return nil; } // 译文漏了占位符（CI 应已拦截）→ 防御性整句回退
        [ranges addObject:[NSValue valueWithRange:r]];
    }
    NSMutableArray<NSNumber *> *order = [NSMutableArray arrayWithCapacity:ranges.count];
    for (NSUInteger i = 0; i < ranges.count; i++) { [order addObject:@(i)]; }
    [order sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        NSUInteger la = ((NSValue *)ranges[a.unsignedIntegerValue]).rangeValue.location;
        NSUInteger lb = ((NSValue *)ranges[b.unsignedIntegerValue]).rangeValue.location;
        return la < lb ? NSOrderedAscending : (la > lb ? NSOrderedDescending : NSOrderedSame);
    }];

    NSMutableArray<IMSysSegment *> *out = [NSMutableArray array];
    NSUInteger cursor = 0;
    for (NSNumber *n in order) {
        NSUInteger idx = n.unsignedIntegerValue;
        NSRange r = ((NSValue *)ranges[idx]).rangeValue;
        if (r.location > cursor) {
            NSString *text = [formatted substringWithRange:NSMakeRange(cursor, r.location - cursor)];
            if (text.length > 0) {
                IMSysSegment *fixed = [IMSysSegment new];
                fixed.text = text;
                [out addObject:fixed];
            }
        }
        IMSysSegment *nameSeg = [IMSysSegment new];
        nameSeg.uid = uidSegs[idx].uid;
        nameSeg.text = uidSegs[idx].text; // 服务端字面：本地显示名解析交给调用方 displayNameForUID（渲染时现做）
        [out addObject:nameSeg];
        cursor = NSMaxRange(r);
    }
    if (cursor < formatted.length) {
        NSString *tail = [formatted substringFromIndex:cursor];
        if (tail.length > 0) {
            IMSysSegment *fixed = [IMSysSegment new];
            fixed.text = tail;
            [out addObject:fixed];
        }
    }
    return out.count > 0 ? out : nil;
}

NSString *IMTextForNoticeSysEvent(NSString *event, NSDictionary<NSString *, NSString *> *sysArgs) {
    if (event.length == 0) { return nil; }
    sysArgs = sysArgs ?: @{};
    NSMutableArray<NSString *> *lines = [NSMutableArray array];

    if ([event isEqualToString:@"new_device_login"]) {
        NSString *at = IMFormatRFC3339LocalDateTime(sysArgs[@"at"]);
        BOOL unusual = [sysArgs[@"unusual"] isEqualToString:@"1"];
        NSString *province = sysArgs[@"province"];
        if (unusual && province.length > 0) {
            [lines addObject:IMLocalizedFormatArgs(@"sys.notice.new_device.headline_unusual", @[at, province])];
        } else {
            [lines addObject:IMLocalizedFormatArgs(@"sys.notice.new_device.headline_normal", @[at])];
        }
        NSString *device = sysArgs[@"device"].length > 0 ? sysArgs[@"device"] : IMLocalized(@"device.platform.unknown");
        NSString *platform = sysArgs[@"platform"];
        if (platform.length > 0) {
            [lines addObject:IMLocalizedFormatArgs(@"sys.notice.new_device.device_platform_line", @[device, platform])];
        } else {
            [lines addObject:IMLocalizedFormatArgs(@"sys.notice.new_device.device_line", @[device])];
        }
        if (sysArgs[@"ip"].length > 0) {
            [lines addObject:IMLocalizedFormatArgs(@"sys.notice.new_device.ip_line", @[sysArgs[@"ip"]])];
        }
        if (unusual && sysArgs[@"familiars"].length > 0) {
            NSMutableArray<NSString *> *trimmed = [NSMutableArray array];
            for (NSString *p in [sysArgs[@"familiars"] componentsSeparatedByString:@","]) {
                NSString *t = [p stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                if (t.length > 0) { [trimmed addObject:t]; }
            }
            if (trimmed.count > 0) {
                [lines addObject:IMLocalizedFormatArgs(@"sys.notice.new_device.familiars_line", @[IMJoinLocalizedNames(trimmed)])];
            }
        }
        [lines addObject:IMLocalized(@"sys.notice.new_device.footer")];
    } else if ([event isEqualToString:@"password_changed"]) {
        NSString *at = IMFormatRFC3339LocalDateTime(sysArgs[@"at"]);
        [lines addObject:IMLocalizedFormatArgs(@"sys.notice.password_changed.headline", @[at])];
        if (sysArgs[@"device"].length > 0) {
            [lines addObject:IMLocalizedFormatArgs(@"sys.notice.password_changed.device_line", @[sysArgs[@"device"]])];
        }
        [lines addObject:IMLocalized(@"sys.notice.password_changed.footer")];
    } else if ([event isEqualToString:@"device_kicked"]) {
        NSString *device = sysArgs[@"target_device"].length > 0 ? sysArgs[@"target_device"] : IMLocalized(@"common.unknown_device_kicked");
        [lines addObject:IMLocalizedFormatArgs(@"sys.notice.device_kicked.headline", @[device])];
        NSString *at = IMFormatRFC3339LocalDateTime(sysArgs[@"at"]);
        if (sysArgs[@"actor_device"].length > 0) {
            [lines addObject:IMLocalizedFormatArgs(@"sys.notice.device_kicked.by_line", @[sysArgs[@"actor_device"], at])];
        } else {
            [lines addObject:IMLocalizedFormatArgs(@"sys.notice.device_kicked.time_line", @[at])];
        }
        [lines addObject:IMLocalized(@"sys.notice.device_kicked.footer")];
    } else {
        return nil; // 未识别事件 → 回退 content
    }
    return [lines componentsJoinedByString:@"\n"];
}
