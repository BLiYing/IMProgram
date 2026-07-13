//  IMChatDetailTabs.m

#import "IMChatDetailTabs.h"
#import "IMMessageModel.h"
#import "IMMediaUtil.h"

@implementation IMChatDetailTab
@end

@implementation IMChatDetailTabs

+ (BOOL)message:(IMMessageModel *)m matchesKind:(IMDetailTabKind)kind {
    if (!m) { return NO; }
    if (m.recalledAt > 0) { return NO; }        // 撤回墓碑不计入任何类别
    if (m.content.length == 0) { return NO; }   // 空内容（占位/异常）不计
    NSString *ct = m.contentType ?: @"text";
    switch (kind) {
        case IMDetailTabKindMedia:
            return [ct isEqualToString:@"image"] || [ct isEqualToString:@"video"];
        case IMDetailTabKindFiles:
            return [ct isEqualToString:@"file"];
        case IMDetailTabKindVoice:
            return [ct isEqualToString:@"audio"];
        case IMDetailTabKindLinks:
            // 独立 link 类型，或普通文本但形如 URL（仿 Telegram 的「链接」聚合）。
            if ([ct isEqualToString:@"link"]) { return YES; }
            return [ct isEqualToString:@"text"] && IMMediaLooksLikeURL(m.content);
        case IMDetailTabKindMembers:
            return NO; // 成员非消息类型
    }
    return NO;
}

+ (NSString *)titleForKind:(IMDetailTabKind)kind {
    switch (kind) {
        case IMDetailTabKindMembers: return @"成员";
        case IMDetailTabKindMedia:   return @"媒体";
        case IMDetailTabKindFiles:   return @"文件";
        case IMDetailTabKindVoice:   return @"语音";
        case IMDetailTabKindLinks:   return @"链接";
    }
    return @"";
}

+ (IMChatDetailTab *)tabWithKind:(IMDetailTabKind)kind {
    IMChatDetailTab *t = [IMChatDetailTab new];
    t.kind = kind;
    t.title = [self titleForKind:kind];
    return t;
}

+ (NSArray<IMChatDetailTab *> *)tabsForMessages:(NSArray<IMMessageModel *> *)messages isGroup:(BOOL)isGroup {
    NSMutableArray<IMChatDetailTab *> *tabs = [NSMutableArray array];
    if (isGroup) { [tabs addObject:[self tabWithKind:IMDetailTabKindMembers]]; } // 成员恒第一

    // 单次遍历统计各内容类别是否存在。
    BOOL hasMedia = NO, hasFiles = NO, hasVoice = NO, hasLinks = NO;
    for (IMMessageModel *m in messages) {
        if (!hasMedia && [self message:m matchesKind:IMDetailTabKindMedia]) { hasMedia = YES; }
        if (!hasFiles && [self message:m matchesKind:IMDetailTabKindFiles]) { hasFiles = YES; }
        if (!hasVoice && [self message:m matchesKind:IMDetailTabKindVoice]) { hasVoice = YES; }
        if (!hasLinks && [self message:m matchesKind:IMDetailTabKindLinks]) { hasLinks = YES; }
        if (hasMedia && hasFiles && hasVoice && hasLinks) { break; } // 全齐即可提前收
    }
    if (hasMedia) { [tabs addObject:[self tabWithKind:IMDetailTabKindMedia]]; }
    if (hasFiles) { [tabs addObject:[self tabWithKind:IMDetailTabKindFiles]]; }
    if (hasVoice) { [tabs addObject:[self tabWithKind:IMDetailTabKindVoice]]; }
    if (hasLinks) { [tabs addObject:[self tabWithKind:IMDetailTabKindLinks]]; }
    return tabs;
}

@end
