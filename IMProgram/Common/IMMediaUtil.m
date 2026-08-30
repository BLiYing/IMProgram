//  IMMediaUtil.m

#import "IMMediaUtil.h"
#import "IMContactCard.h"
#import "IMMessageModel.h"
#import <math.h>

NSString *IMMediaFullURL(NSString *content, NSString *host) {
    if (content.length == 0) { return @""; }
    if ([content hasPrefix:@"http"] || [content hasPrefix:@"data:"]) { return content; }
    return [NSString stringWithFormat:@"http://%@%@", host ?: @"", content];
}

NSString *IMReplySnippet(IMMessageModel *m) {
    // 图说 caption「有字显字」（Telegram 模型）：图文/视频文/文件文带 caption 时引用条显 caption 文字。
    if (m.caption.length > 0 &&
        ([m.contentType isEqualToString:@"image"] || [m.contentType isEqualToString:@"video"] || [m.contentType isEqualToString:@"file"])) {
        return m.caption.length > 60 ? [[m.caption substringToIndex:60] stringByAppendingString:@"…"] : m.caption;
    }
    if ([m.contentType isEqualToString:@"image"]) { return @"[图片]"; }
    if ([m.contentType isEqualToString:@"video"]) { return @"[视频]"; }
    if ([m.contentType isEqualToString:@"file"]) {
        NSString *fn = m.fileName.length > 0 ? m.fileName : IMMediaFileName(m.content);
        return fn.length > 0 ? [@"[文件] " stringByAppendingString:fn] : @"[文件]";
    }
    if ([m.contentType isEqualToString:@"chat_record"]) { return IMChatRecordSnippet(m.content); } // [聊天记录] 标题
    if ([m.contentType isEqualToString:IMContentTypeContact]) { return IMContactCardPreview(m.content); } // [个人名片] 昵称
    NSString *c = m.content ?: @"";
    return c.length > 60 ? [[c substringToIndex:60] stringByAppendingString:@"…"] : c;
}

BOOL IMLooksLikeChatRecordJSON(NSString *s) {
    return [s hasPrefix:@"{"] && ([s containsString:@"\"items\""] || [s containsString:@"\"t\":"]);
}

NSString *IMChatRecordSnippet(NSString *recordJSON) {
    NSString *title = nil;
    NSData *d = [recordJSON dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *dict = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    if ([dict isKindOfClass:NSDictionary.class] && [dict[@"t"] isKindOfClass:NSString.class]) {
        title = dict[@"t"];
    } else if (recordJSON.length > 0) {
        // 存量脏快照：旧引用把整段 JSON 截 60 字入库，反序列化必失败 → 正则抠 "t":"…" 标题。
        NSRange key = [recordJSON rangeOfString:@"\"t\":\""];
        if (key.location != NSNotFound) {
            NSUInteger start = NSMaxRange(key);
            NSRange close = [recordJSON rangeOfString:@"\"" options:0
                                                range:NSMakeRange(start, recordJSON.length - start)];
            if (close.location != NSNotFound && close.location > start) {
                title = [recordJSON substringWithRange:NSMakeRange(start, close.location - start)];
            }
        }
    }
    return title.length > 0 ? [NSString stringWithFormat:@"[聊天记录] %@", title] : @"[聊天记录]";
}

NSString *IMRecordItemPreview(NSDictionary *it) {
    if (![it isKindOfClass:NSDictionary.class]) { return @""; }
    NSString *ct = [it[@"ct"] isKindOfClass:NSString.class] ? it[@"ct"] : @"text";
    NSString *c  = [it[@"c"]  isKindOfClass:NSString.class] ? it[@"c"]  : @"";
    // 图说条目「有字显字」：媒体/文件带 cap（caption）时优先显文字，否则回退 [图片]/[视频]/[文件名]。
    NSString *cap = [it[@"cap"] isKindOfClass:NSString.class] ? it[@"cap"] : nil;
    if (cap.length > 0 && ([ct isEqualToString:@"image"] || [ct isEqualToString:@"video"] || [ct isEqualToString:@"file"])) {
        return cap.length > 60 ? [[cap substringToIndex:60] stringByAppendingString:@"…"] : cap;
    }
    if ([ct isEqualToString:@"image"]) { return @"[图片]"; }
    if ([ct isEqualToString:@"video"]) { return @"[视频]"; }
    if ([ct isEqualToString:@"file"]) {
        NSString *fn = [it[@"fn"] isKindOfClass:NSString.class] ? it[@"fn"] : IMMediaFileName(c);
        return fn.length > 0 ? [@"[文件] " stringByAppendingString:fn] : @"[文件]";
    }
    if ([ct isEqualToString:IMContentTypeContact]) { return IMContactCardPreview(c); }
    // 语音条目：显 [语音] m:ss（无 d 的老记录只显 [语音]），别把 URL 铺进套娃卡片的两行预览里。
    if ([ct isEqualToString:@"voice"] || [ct isEqualToString:@"audio"]) {
        int64_t ms = [it[@"d"] respondsToSelector:@selector(longLongValue)] ? [it[@"d"] longLongValue] : 0;
        if (ms <= 0) { return @"[语音]"; }
        long long sec = ms / 1000;
        return [NSString stringWithFormat:@"[语音] %lld:%02lld", sec / 60, sec % 60];
    }
    if ([ct isEqualToString:@"chat_record"]) {
        // 嵌套合并转发：只取子标题（maxLines=0，不再展开子条目），显「[聊天记录] 子标题」。
        // 子 JSON 非法时标题回落「聊天记录」，此时不叠加以免「[聊天记录] 聊天记录」（与 Web 一致）。
        NSString *t = nil; IMSummarizeRecord(c, &t, NULL, 0);
        return (t.length > 0 && ![t isEqualToString:@"聊天记录"])
            ? [@"[聊天记录] " stringByAppendingString:t] : @"[聊天记录]";
    }
    return c;
}

void IMSummarizeRecord(NSString *json, NSString **outTitle, NSArray<NSString *> **outLines, NSInteger maxLines) {
    NSString *title = @"聊天记录";
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSData *d = [json dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *dict = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    if ([dict isKindOfClass:NSDictionary.class]) {
        if ([dict[@"t"] isKindOfClass:NSString.class]) { title = dict[@"t"]; }
        NSArray *items = [dict[@"items"] isKindOfClass:NSArray.class] ? dict[@"items"] : @[];
        for (NSDictionary *it in items) {
            if (maxLines <= 0 || (NSInteger)lines.count >= maxLines) { break; }
            if (![it isKindOfClass:NSDictionary.class]) { continue; }
            NSString *n = [it[@"n"] isKindOfClass:NSString.class] ? it[@"n"] : @"";
            [lines addObject:[NSString stringWithFormat:@"%@: %@", n, IMRecordItemPreview(it)]];
        }
    }
    if (outTitle) { *outTitle = title; }
    if (outLines) { *outLines = lines; }
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

NSString *IMFormatFileSize(int64_t bytes) {
    if (bytes < 0) { return @""; }
    if (bytes == 0) { return @"0 KB"; }
    double value = 0;
    NSString *unit = nil;
    if (bytes >= 1024LL * 1024LL * 1024LL) {
        value = (double)bytes / (1024.0 * 1024.0 * 1024.0);
        unit = @"GB";
    } else if (bytes >= 1024LL * 1024LL) {
        value = (double)bytes / (1024.0 * 1024.0);
        unit = @"MB";
    } else {
        value = (double)bytes / 1024.0;
        unit = @"KB";
    }
    value = MAX(0.1, value);
    NSString *number = fabs(value - round(value)) < 0.05
        ? [NSString stringWithFormat:@"%.0f", value]
        : [NSString stringWithFormat:@"%.1f", value];
    return [NSString stringWithFormat:@"%@ %@", number, unit];
}

NSString *IMFormatFileDateTime(int64_t timestampMillis) {
    if (timestampMillis <= 0) { return @""; }
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)timestampMillis / 1000.0];
    return [formatter stringFromDate:date] ?: @"";
}

BOOL IMMediaLooksLikeURL(NSString *s) {
    if (!([s hasPrefix:@"http://"] || [s hasPrefix:@"https://"])) { return NO; }
    if ([s rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) { return NO; }
    return [NSURL URLWithString:s] != nil;
}

/// 文本内 http(s) URL 的正则（与 Web src/messageContent.ts 的 URL_REGEX 同款）：
/// - 只识别显式 http(s)，不猜裸域（避 example.com 误识 + 后端 SSRF 面）
/// - 中部只允许 URL 合法字符（RFC 3986 unreserved+reserved+pct-encoded 的 ASCII 子集），
///   遇非 URL 字符（空白/中文汉字/中文标点/<>"' 等）自然作为边界；末尾再回吐句末标点 .,;:!?)]}"'。
/// 修 bug：老正则用反向排除 `[^\s<>()"'【...]`，中文汉字都通过 → "分身乏术，https://foo.com，好文"
/// 被吸成整段（中文都在中部集合内），preview API 拿到含中文的 URL 直接 404。
static NSRegularExpression *IMURLRegexShared(void) {
    static NSRegularExpression *r; static dispatch_once_t once;
    dispatch_once(&once, ^{
        r = [NSRegularExpression regularExpressionWithPattern:@"https?://[-A-Za-z0-9._~:/?#\\[\\]@!$&'()*+,;=%]+[-A-Za-z0-9_~/#\\[\\]@!$&'*+=%]"
                                                      options:0 error:NULL];
    });
    return r;
}

NSString *IMFirstURLInText(NSString *text) {
    if (text.length == 0) { return nil; }
    NSTextCheckingResult *m = [IMURLRegexShared() firstMatchInString:text options:0
                                                                range:NSMakeRange(0, text.length)];
    return m ? [text substringWithRange:m.range] : nil;
}

NSArray<NSValue *> *IMURLRangesInText(NSString *text) {
    if (text.length == 0) { return @[]; }
    NSMutableArray<NSValue *> *out = [NSMutableArray new];
    [IMURLRegexShared() enumerateMatchesInString:text options:0 range:NSMakeRange(0, text.length)
                                      usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
        if (m) { [out addObject:[NSValue valueWithRange:m.range]]; }
    }];
    return out;
}

static BOOL IMExtensionIn(NSString *ext, NSArray<NSString *> *extensions) {
    return [extensions containsObject:ext];
}

NSString *IMFileTypeIdentifierForName(NSString *name) {
    NSString *fileName = IMMediaFileName(name ?: @"");
    fileName = [fileName componentsSeparatedByCharactersInSet:
                [NSCharacterSet characterSetWithCharactersInString:@"?#"]].firstObject ?: fileName;
    NSString *ext = fileName.pathExtension.lowercaseString ?: @"";
    if ([ext isEqualToString:@"pdf"]) { return @"pdf"; }
    if (IMExtensionIn(ext, @[@"doc", @"docx", @"docm", @"dot", @"dotx", @"odt"])) { return @"word"; }
    if (IMExtensionIn(ext, @[@"xls", @"xlsx", @"xlsm", @"xlsb", @"xlt", @"xltx", @"ods"])) { return @"excel"; }
    if (IMExtensionIn(ext, @[@"ppt", @"pptx", @"pptm", @"pps", @"ppsx", @"odp"])) { return @"powerpoint"; }
    if (IMExtensionIn(ext, @[@"csv", @"tsv"])) { return @"csv"; }
    if ([ext isEqualToString:@"pages"]) { return @"pages"; }
    if ([ext isEqualToString:@"numbers"]) { return @"numbers"; }
    if ([ext isEqualToString:@"key"]) { return @"keynote"; }
    if (IMExtensionIn(ext, @[@"txt", @"rtf", @"rtfd", @"log"])) { return @"text"; }
    if (IMExtensionIn(ext, @[@"md", @"markdown"])) { return @"markdown"; }
    if (IMExtensionIn(ext, @[@"xml", @"xsd", @"xsl", @"xslt", @"plist"])) { return @"xml"; }
    if (IMExtensionIn(ext, @[@"json", @"geojson"])) { return @"json"; }
    if (IMExtensionIn(ext, @[@"jpg", @"jpeg", @"png", @"gif", @"webp", @"heic", @"heif", @"bmp",
                              @"tif", @"tiff", @"svg", @"ico", @"raw", @"dng", @"psd"])) { return @"image"; }
    if (IMExtensionIn(ext, @[@"mp4", @"mov", @"m4v", @"avi", @"mkv", @"webm", @"wmv", @"flv",
                              @"mpg", @"mpeg", @"3gp"])) { return @"video"; }
    if (IMExtensionIn(ext, @[@"mp3", @"m4a", @"aac", @"wav", @"flac", @"ogg", @"opus", @"wma",
                              @"aiff", @"caf"])) { return @"audio"; }
    if (IMExtensionIn(ext, @[@"zip", @"rar", @"7z", @"tar", @"gz", @"bz2", @"xz", @"tgz"])) { return @"archive"; }
    if (IMExtensionIn(ext, @[@"html", @"htm", @"css", @"scss", @"less", @"js", @"jsx", @"ts", @"tsx",
                              @"swift", @"m", @"mm", @"h", @"c", @"cc", @"cpp", @"cxx", @"java", @"kt",
                              @"kts", @"py", @"go", @"rs", @"rb", @"php", @"sh", @"zsh", @"yaml", @"yml",
                              @"toml", @"ini"])) { return @"code"; }
    if (IMExtensionIn(ext, @[@"db", @"sqlite", @"sqlite3", @"sql", @"mdb", @"accdb"])) { return @"database"; }
    if (IMExtensionIn(ext, @[@"ttf", @"otf", @"woff", @"woff2", @"eot"])) { return @"font"; }
    if (IMExtensionIn(ext, @[@"epub", @"mobi", @"azw", @"azw3", @"fb2"])) { return @"ebook"; }
    if (IMExtensionIn(ext, @[@"dmg", @"pkg", @"exe", @"msi", @"apk", @"ipa", @"appimage", @"deb", @"rpm"])) { return @"package"; }
    return @"unknown";
}

UIImage *IMFileTypeIconForName(NSString *name, CGFloat pointSize) {
    NSString *kind = IMFileTypeIdentifierForName(name);
    CGFloat size = MAX(1, pointSize);
    NSString *cacheKey = [NSString stringWithFormat:@"%@-%.1f-%.1f", kind, size, UIScreen.mainScreen.scale];
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ cache = [NSCache new]; });
    UIImage *cached = [cache objectForKey:cacheKey];
    if (cached) { return cached; }

    UIImage *source = [UIImage imageNamed:[@"FileType_" stringByAppendingString:kind]];
    if (!source && ![kind isEqualToString:@"unknown"]) {
        source = [UIImage imageNamed:@"FileType_unknown"];
    }
    if (!source) { return [UIImage systemImageNamed:@"questionmark.square.fill"] ?: [UIImage new]; }
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = NO;
    format.scale = UIScreen.mainScreen.scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size) format:format];
    UIImage *result = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGFloat ratio = source.size.width > 0 && source.size.height > 0 ? source.size.width / source.size.height : 1;
        CGSize drawSize = ratio > 1 ? CGSizeMake(size, size / ratio) : CGSizeMake(size * ratio, size);
        CGRect rect = CGRectMake((size - drawSize.width) / 2, (size - drawSize.height) / 2,
                                 drawSize.width, drawSize.height);
        [source drawInRect:rect];
    }];
    result = [result imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [cache setObject:result forKey:cacheKey];
    return result;
}

NSString *IMReplySnippetFileName(NSString *snap) {
    if ([snap hasPrefix:@"[file] "])  { return [snap substringFromIndex:7]; } // wire 形（服务端冻结）
    if ([snap hasPrefix:@"[文件] "]) { return [snap substringFromIndex:5]; } // 本端存量：本地化形入库
    return nil;
}

NSString *IMLocalizeReplySnippet(NSString *snap) {
    if (snap.length == 0) { return @""; }
    if ([snap isEqualToString:@"[image]"]) { return @"[图片]"; }
    if ([snap isEqualToString:@"[video]"]) { return @"[视频]"; }
    if ([snap isEqualToString:@"[file]"])  { return @"[文件]"; }
    NSString *fn = IMReplySnippetFileName(snap);
    if (fn.length > 0) { return [@"[文件] " stringByAppendingString:fn]; } // 带名文件；本地化输入幂等重组
    if ([snap isEqualToString:@"[chat_record]"]) { return @"[聊天记录]"; } // 旧服务端 token（无标题）兜底
    if ([snap isEqualToString:@"[contact]"]) { return @"[个人名片]"; }      // 同上：老服务端下发的裸 token
    if (IMLooksLikeChatRecordJSON(snap)) { return IMChatRecordSnippet(snap); } // 存量 JSON 截段救援
    return snap;
}
