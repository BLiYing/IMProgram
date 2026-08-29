//  IMContactCard.m

#import "IMContactCard.h"

NSString * const IMContentTypeContact = @"contact";

@implementation IMContactCard
@end

/// 取字典里的字符串并 trim；非字符串/空白返回 nil（统一"空白即无"的归一化）。
static NSString *_Nullable trimmedString(NSDictionary *d, NSString *key) {
    id v = d[key];
    if (![v isKindOfClass:NSString.class]) { return nil; }
    NSString *s = [(NSString *)v stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return s.length > 0 ? s : nil;
}

IMContactCard *IMContactCardParse(NSString *content) {
    if (![content isKindOfClass:NSString.class] || content.length == 0) { return nil; }
    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    if (data.length == 0) { return nil; }
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![obj isKindOfClass:NSDictionary.class]) { return nil; }  // 数组/标量/非法 JSON 一并挡在这
    NSDictionary *d = obj;
    NSString *uid = trimmedString(d, @"u");
    if (uid.length == 0) { return nil; }                          // 缺 u = 点不动的死卡，视同脏数据
    IMContactCard *c = [IMContactCard new];
    c.userID = uid;
    c.username = trimmedString(d, @"un");   // 老消息无此字段 → nil → 副标题留空
    c.nickname = trimmedString(d, @"n");
    c.avatarURL = trimmedString(d, @"a");
    return c;
}

NSString *IMContactCardBuild(NSString *userID, NSString *username, NSString *nickname, NSString *avatarURL) {
    NSString *uid = [(userID ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (uid.length == 0) { return nil; }
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithObject:uid forKey:@"u"];
    NSString *un = [(username ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (un.length > 0) { d[@"un"] = un; }
    NSString *n = [(nickname ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (n.length > 0) { d[@"n"] = n; }
    NSString *a = [(avatarURL ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (a.length > 0) { d[@"a"] = a; }
    NSData *json = [NSJSONSerialization dataWithJSONObject:d options:0 error:NULL];
    if (json.length == 0) { return nil; }
    return [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
}

NSString *IMContactCardPreview(NSString *content) {
    IMContactCard *c = IMContactCardParse(content);
    if (!c) { return @"[个人名片]"; }
    // 末级**不落 userID**：这条预览会出现在会话列表/引用条上，露出 10 位随机数字比不带名字更糟
    // （与服务端 contactReplySnapshot 同口径，见 docs/design/ACCOUNT_IDENTITY_REDESIGN.md §7.5）。
    if (c.nickname.length > 0) { return [@"[个人名片] " stringByAppendingString:c.nickname]; }
    if (c.username.length > 0) { return [@"[个人名片] @" stringByAppendingString:c.username]; }
    return @"[个人名片]";
}
