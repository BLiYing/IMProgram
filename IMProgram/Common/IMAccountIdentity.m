//  IMAccountIdentity.m

#import "IMAccountIdentity.h"

NSString * const IMSystemUserID = @"777000";

NSString *IMDisplayName(NSString *nickname, NSString *username) {
    NSString *nick = [nickname stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (nick.length > 0) { return nick; }
    if (username.length > 0) { return [@"@" stringByAppendingString:username]; }
    return @"未命名用户";
}
