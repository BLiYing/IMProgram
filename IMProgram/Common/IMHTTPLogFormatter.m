//  IMHTTPLogFormatter.m

#import "IMHTTPLogFormatter.h"

static NSUInteger const kIMHTTPLogMaxCharacters = 16 * 1024;

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
            @"phone", @"phonenumber", @"mobile", @"telephone"
        ]];
    });
    NSString *normalized = [[key lowercaseString]
                            stringByReplacingOccurrencesOfString:@"_" withString:@""];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"-" withString:@""];
    return [keys containsObject:normalized];
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

id IMHTTPSanitizedJSONObject(id object, BOOL includeBusinessContent) {
    if ([object isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            NSString *stringKey = [key isKindOfClass:NSString.class] ? key : [key description];
            if (IMHTTPKeyIsAlwaysSensitive(stringKey) ||
                (!includeBusinessContent && IMHTTPKeyContainsBusinessContent(stringKey))) {
                result[stringKey] = @"***";
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
        return IMHTTPDataURIMetadata(object) ?: object;
    }
    if ([object isKindOfClass:NSNumber.class] ||
        object == NSNull.null) {
        return object;
    }
    return [object description] ?: @"";
}

static NSString *IMHTTPTruncatedString(NSString *value) {
    if (value.length <= kIMHTTPLogMaxCharacters) { return value; }
    NSUInteger omitted = value.length - kIMHTTPLogMaxCharacters;
    return [[value substringToIndex:kIMHTTPLogMaxCharacters]
            stringByAppendingFormat:@"…<truncated %lu chars>", (unsigned long)omitted];
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
    return text ? IMHTTPTruncatedString(text) :
        [NSString stringWithFormat:@"<binary %lu bytes>", (unsigned long)data.length];
}
