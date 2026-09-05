//  IMGroupNameDefault.m
//  见头文件：与 Web `src/groupName.ts` 逐字同规则。

#import "IMGroupNameDefault.h"

const NSUInteger IMMaxGroupNameLength = 30;

/// 逐个 UTF-16 单元扫描、把代理对算作 1——即 Go 的 rune 数。
/// 不用 `ByComposedCharacterSequences`：那按**字形簇**计数（一家四口 emoji 算 1 个），
/// 与服务端的 `len([]rune)` 对不上，会放过一个服务端要拒的群名。
NSUInteger IMGroupNameRuneLength(NSString *s) {
    NSUInteger n = 0;
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (CFStringIsSurrogateHighCharacter(c) && i + 1 < s.length
            && CFStringIsSurrogateLowCharacter([s characterAtIndex:i + 1])) {
            i++;
        }
        n++;
    }
    return n;
}

NSString *IMGroupNameTruncateToRunes(NSString *s, NSUInteger n) {
    if (s.length == 0 || n == 0) { return n == 0 ? @"" : (s ?: @""); }
    NSUInteger runes = 0;
    for (NSUInteger i = 0; i < s.length; i++) {
        if (runes == n) { return [s substringToIndex:i]; }
        unichar c = [s characterAtIndex:i];
        if (CFStringIsSurrogateHighCharacter(c) && i + 1 < s.length
            && CFStringIsSurrogateLowCharacter([s characterAtIndex:i + 1])) {
            i++;
        }
        runes++;
    }
    return s;
}

NSString *IMPublicUserName(NSString *nickname, NSString *username, NSString *userID) {
    NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSString *nick = [(nickname ?: @"") stringByTrimmingCharactersInSet:ws];
    if (nick.length > 0) { return nick; }
    NSString *uname = [(username ?: @"") stringByTrimmingCharactersInSet:ws];
    if (uname.length > 0) { return [@"@" stringByAppendingString:uname]; }
    return [(userID ?: @"") stringByTrimmingCharactersInSet:ws];
}

NSString *IMDefaultGroupName(NSArray<NSString *> *names, NSUInteger maxLen) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for (NSString *raw in names) {
        NSString *name = [(raw ?: @"") stringByTrimmingCharactersInSet:ws];
        if (name.length == 0) { continue; }
        NSString *candidate = [[parts arrayByAddingObject:name] componentsJoinedByString:@"、"];
        if (IMGroupNameRuneLength(candidate) <= maxLen) {
            [parts addObject:name];
            continue;
        }
        // 放不下这一个就到此为止；一个都没放下（首名本身超长）时硬截首名。
        if (parts.count == 0) { return IMGroupNameTruncateToRunes(name, maxLen); }
        break;
    }
    return [parts componentsJoinedByString:@"、"];
}
