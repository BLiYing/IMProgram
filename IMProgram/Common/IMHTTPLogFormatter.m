//  IMHTTPLogFormatter.m

#import "IMHTTPLogFormatter.h"
#import "IMEmailLogin.h"

static NSUInteger const kIMHTTPLogMaxCharacters = 16 * 1024;
/// 单个字符串值的截断上限。整体 16 KB 是"一条日志最多多长"，这个是"一个字段值最多多长"。
/// 二者缺一不可：只有整体上限时，一个超大字段（如 2 万字的 content）会把它之后序列化出来的
/// 所有字段——包括密码脱敏后的 `"***"` 证据、以及其它有用字段——整段挤出 16 KB 之外，
/// 日志在排查时反而残缺。逐值截断保证每个 key 都留下，只把过长的那个值截短。
static NSUInteger const kIMHTTPLogMaxValueCharacters = 4 * 1024;

NSString *IMHTTPNewRequestID(void) {
    return NSUUID.UUID.UUIDString;
}

static BOOL IMHTTPKeyIsAlwaysSensitive(NSString *key) {
    static NSSet<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [NSSet setWithArray:@[
            @"password", @"passwd", @"passcode", @"secret", @"clientsecret",
            @"token", @"accesstoken", @"refreshtoken", @"idtoken", @"jwt",
            @"authorization", @"cookie", @"setcookie",
            @"phone", @"phonenumber", @"mobile", @"telephone",
            // 两步验证（PROTOCOL §7.1）：登录票据、二维码 URI（内含密钥）、一次性恢复码列表
            @"ticket", @"otpauthuri", @"recoverycodes"
        ]];
    });
    NSString *normalized = [[key lowercaseString]
                            stringByReplacingOccurrencesOfString:@"_" withString:@""];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"-" withString:@""];
    return [keys containsObject:normalized];
}

/// 两步验证的 `code`（动态码 / 恢复码）是**字符串**；信封里的业务码 `code` 是数字，必须原样保留，否则日志没法排障。
static BOOL IMHTTPIsVerificationCode(NSString *key, id value) {
    return [key.lowercaseString isEqualToString:@"code"] && [value isKindOfClass:NSString.class];
}

/// 邮箱登录（PROTOCOL §7.2）：`email` 字段，以及登录名里填的邮箱（`username` 含 @）→ 脱敏成 a***@domain，日志不落完整邮箱。
static BOOL IMHTTPIsEmailValue(NSString *key, id value) {
    if (![value isKindOfClass:NSString.class]) { return NO; }
    NSString *k = key.lowercaseString;
    return [k isEqualToString:@"email"] || ([k isEqualToString:@"username"] && [(NSString *)value containsString:@"@"]);
}

static BOOL IMHTTPKeyContainsBusinessContent(NSString *key) {
    static NSSet<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [NSSet setWithArray:@[
            @"content", @"text", @"note", @"reason", @"resolution", @"translation",
            @"description", @"remark"
        ]];
    });
    return [keys containsObject:key.lowercaseString];
}

/// 把字符串截到 limit 字符，超出部分记成 `…<truncated N chars>`。逐值截断与整体兜底共用一份。
static NSString *IMHTTPTruncatedToLimit(NSString *value, NSUInteger limit) {
    if (value.length <= limit) { return value; }
    NSUInteger omitted = value.length - limit;
    return [[value substringToIndex:limit]
            stringByAppendingFormat:@"…<truncated %lu chars>", (unsigned long)omitted];
}

static NSString *IMHTTPDataURIMetadata(NSString *value) {
    if (![value.lowercaseString hasPrefix:@"data:"]) { return nil; }
    NSRange comma = [value rangeOfString:@","];
    if (comma.location == NSNotFound) { return nil; }
    NSString *descriptor = [value substringWithRange:NSMakeRange(5, comma.location - 5)];
    NSString *mediaType = [[descriptor componentsSeparatedByString:@";"] firstObject];
    if (mediaType.length == 0) { mediaType = @"unknown"; }
    return [NSString stringWithFormat:@"<data-uri type=%@ chars=%lu>",
            mediaType, (unsigned long)value.length];
}

/// 导出下载链接 `/api/v1/exports/download?t=<一次性令牌>`：令牌即凭据，日志里遮成 `t=***`。
/// 只认 `/exports/download` 路径，其它 `?t=` 不动。
static NSString *IMHTTPMaskedDownloadToken(NSString *value) {
    if ([value rangeOfString:@"/exports/download"].location == NSNotFound) { return value; }
    static NSRegularExpression *re;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"(/exports/download\\?(?:[^\"\\s#]*&)?t=)[^&\"\\s#]*"
                                                       options:0 error:NULL];
    });
    return [re stringByReplacingMatchesInString:value options:0 range:NSMakeRange(0, value.length)
                                   withTemplate:@"$1***"];
}

id IMHTTPSanitizedJSONObject(id object, BOOL includeBusinessContent) {
    if ([object isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            NSString *stringKey = [key isKindOfClass:NSString.class] ? key : [key description];
            if (IMHTTPKeyIsAlwaysSensitive(stringKey) || IMHTTPIsVerificationCode(stringKey, value) ||
                (!includeBusinessContent && IMHTTPKeyContainsBusinessContent(stringKey))) {
                result[stringKey] = @"***";
            } else if (IMHTTPIsEmailValue(stringKey, value)) {
                result[stringKey] = IMEmailMasked(value);
            } else {
                result[stringKey] = IMHTTPSanitizedJSONObject(value, includeBusinessContent);
            }
        }];
        return result;
    }
    if ([object isKindOfClass:NSArray.class]) {
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:[(NSArray *)object count]];
        for (id value in (NSArray *)object) {
            [result addObject:IMHTTPSanitizedJSONObject(value, includeBusinessContent)];
        }
        return result;
    }
    if ([object isKindOfClass:NSString.class]) {
        NSString *meta = IMHTTPDataURIMetadata(object);
        if (meta) { return meta; }
        // 逐值截断：单个字段值过长时就地截短，避免它把同层其它字段挤出整体上限。
        return IMHTTPTruncatedToLimit(IMHTTPMaskedDownloadToken(object), kIMHTTPLogMaxValueCharacters);
    }
    if ([object isKindOfClass:NSNumber.class] ||
        object == NSNull.null) {
        return object;
    }
    return [object description] ?: @"";
}

/// 整体上限兜底：逐值截断后，字段数极多时序列化结果仍可能超 16 KB，这里最后再夹一刀。
static NSString *IMHTTPTruncatedString(NSString *value) {
    return IMHTTPTruncatedToLimit(value, kIMHTTPLogMaxCharacters);
}

NSString *IMHTTPLogBody(NSData *data, NSString *contentType, BOOL includeBusinessContent) {
    if (data.length == 0) { return @"<empty>"; }
    NSString *lowerType = contentType.lowercaseString ?: @"";
    if ([lowerType containsString:@"multipart/form-data"]) {
        return [NSString stringWithFormat:@"<multipart %lu bytes>", (unsigned long)data.length];
    }

    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (object) {
        id sanitized = IMHTTPSanitizedJSONObject(object, includeBusinessContent);
        NSData *json = [NSJSONSerialization dataWithJSONObject:sanitized options:0 error:NULL];
        NSString *text = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
        return IMHTTPTruncatedString(text ?: @"<invalid-json>");
    }

    if (!includeBusinessContent) {
        return [NSString stringWithFormat:@"<non-json redacted %lu bytes>", (unsigned long)data.length];
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return text ? IMHTTPTruncatedString(IMHTTPMaskedDownloadToken(text)) :
        [NSString stringWithFormat:@"<binary %lu bytes>", (unsigned long)data.length];
}

NSString *IMHTTPPollResponseSummary(NSData *data) {
    if (data.length == 0) { return @"<empty>"; }
    NSUInteger bytes = data.length;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    NSDictionary *root = [object isKindOfClass:NSDictionary.class] ? (NSDictionary *)object : nil;
    NSDictionary *payload = [root[@"data"] isKindOfClass:NSDictionary.class] ? root[@"data"] : nil;
    // 只取 data 下的数组条数（conversations / items）；轮询快照高度重复，条数足够定位异常。
    for (NSString *key in @[@"conversations", @"items"]) {
        id value = payload[key];
        if ([value isKindOfClass:NSArray.class]) {
            return [NSString stringWithFormat:@"<poll %@=%lu bytes=%lu>",
                    key, (unsigned long)[(NSArray *)value count], (unsigned long)bytes];
        }
    }
    return [NSString stringWithFormat:@"<poll bytes=%lu>", (unsigned long)bytes]; // 非预期结构：只记字节
}
