//  IMMediaUtil.m

#import "IMMediaUtil.h"

NSString *IMMediaFullURL(NSString *content, NSString *host) {
    if (content.length == 0) { return @""; }
    if ([content hasPrefix:@"http"] || [content hasPrefix:@"data:"]) { return content; }
    return [NSString stringWithFormat:@"http://%@%@", host ?: @"", content];
}

NSString *IMMediaFileName(NSString *content) {
    if (content.length == 0) { return @""; }
    NSString *last = content.lastPathComponent ?: content;
    NSString *decoded = [last stringByRemovingPercentEncoding] ?: last;
    NSRange r = [decoded rangeOfString:@"__"];
    if (r.location != NSNotFound && r.location + 2 < decoded.length) {
        return [decoded substringFromIndex:r.location + 2];
    }
    return decoded; // 老文件（无 __）回退整段名
}

BOOL IMMediaLooksLikeURL(NSString *s) {
    if (!([s hasPrefix:@"http://"] || [s hasPrefix:@"https://"])) { return NO; }
    if ([s rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) { return NO; }
    return [NSURL URLWithString:s] != nil;
}
