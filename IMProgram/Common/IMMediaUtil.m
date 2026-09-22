//  IMMediaUtil.m

#import "IMMediaUtil.h"
#import "IMContactCard.h"
#import "IMCallRecord.h"
#import "IMMessageModel.h"
#import "IMServerEndpoint.h"
#import "IMLocalization.h"
#import "IMTimeUtil.h" // IMFormatVoiceDuration：引用快照 voice 类复用同一 mm:ss 格式化，不重写
#import <math.h>

/// 是否是 http(s) 绝对 URL。旧实现用 `hasPrefix:@"http"`，把 `httpfoo:` 之类也算进去了。
static BOOL IMIsAbsoluteHTTPURL(NSString *s) {
    return [s hasPrefix:@"http://"] || [s hasPrefix:@"https://"];
}

NSString *IMMediaFullURL(NSString *content, NSString *host) {
    if (content.length == 0) { return @""; }
    if ([content hasPrefix:@"data:"]) { return content; } // 内联缩略图，不走网络
    if (IMIsAbsoluteHTTPURL(content)) {
        // 外站直接丢弃（返回空串，各调用点原本就按"没有图"降级到首字母圈/占位图）。理由见 .h。
        if (![IMServerEndpoint.shared isOwnHost:host forAbsoluteURL:content]) { return @""; }
        // 是自家的，但协议可能与当前配置不符（历史数据里的 http:// 绝对地址）——按当前 scheme 重拼，
        // 免得整端切到 https 之后混进明文请求被 ATS 拦掉、表现为"部分图片不显示"。
        NSURLComponents *c = [NSURLComponents componentsWithString:content];
        NSString *path = c.percentEncodedPath ?: @"";
        if (c.percentEncodedQuery.length > 0) { path = [path stringByAppendingFormat:@"?%@", c.percentEncodedQuery]; }
        return [IMServerEndpoint.shared absoluteURLStringForHost:host relativePath:path];
    }
    return [IMServerEndpoint.shared absoluteURLStringForHost:host relativePath:content];
}

NSString *IMLinkPreviewImageURL(NSString *content, NSString *host) {
    if (content.length == 0) { return @""; }
    if ([content hasPrefix:@"data:"] || IMIsAbsoluteHTTPURL(content)) { return content; }
    return [IMServerEndpoint.shared absoluteURLStringForHost:host relativePath:content];
}

NSString *IMReplySnippet(IMMessageModel *m) {
    // 图说 caption「有字显字」（Telegram 模型）：图文/视频文/文件文带 caption 时引用条显 caption 文字。
    if (m.caption.length > 0 &&
        ([m.contentType isEqualToString:@"image"] || [m.contentType isEqualToString:@"video"] || [m.contentType isEqualToString:@"file"])) {
        return m.caption.length > 60 ? [[m.caption substringToIndex:60] stringByAppendingString:@"…"] : m.caption;
    }
    if ([m.contentType isEqualToString:@"image"]) { return IMLocalized(@"preview.image"); }
    if ([m.contentType isEqualToString:@"video"]) { return IMLocalized(@"preview.video"); }
    if ([m.contentType isEqualToString:@"file"]) {
        NSString *fn = m.fileName.length > 0 ? m.fileName : IMMediaFileName(m.content);
        return fn.length > 0 ? IMLocalizedFormat(@"quote.snapshot.file_named", fn) : IMLocalized(@"preview.file");
    }
    if ([m.contentType isEqualToString:@"chat_record"]) { return IMChatRecordSnippet(m.content); } // [聊天记录] 标题
    if ([m.contentType isEqualToString:IMContentTypeContact]) { return IMContactCardPreview(m.content); } // [个人名片] 昵称
    if ([m.contentType isEqualToString:IMContentTypeCall]) { return IMCallRecordNeutralPreview(); }      // 通话记录不可被引用；已随 App 语言
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
    return title.length > 0 ? IMLocalizedFormat(@"quote.snapshot.chat_record_titled", title) : IMLocalized(@"preview.chat_record");
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
    if ([ct isEqualToString:@"image"]) { return IMLocalized(@"preview.image"); }
    if ([ct isEqualToString:@"video"]) { return IMLocalized(@"preview.video"); }
    if ([ct isEqualToString:@"file"]) {
        NSString *fn = [it[@"fn"] isKindOfClass:NSString.class] ? it[@"fn"] : IMMediaFileName(c);
        return fn.length > 0 ? IMLocalizedFormat(@"quote.snapshot.file_named", fn) : IMLocalized(@"preview.file");
    }
    if ([ct isEqualToString:IMContentTypeContact]) { return IMContactCardPreview(c); }
    if ([ct isEqualToString:IMContentTypeCall]) { return IMCallRecordNeutralPreview(); }
    // 语音条目：显 [语音] m:ss（无 d 的老记录只显 [语音]），别把 URL 铺进套娃卡片的两行预览里。
    if ([ct isEqualToString:@"voice"] || [ct isEqualToString:@"audio"]) {
        int64_t ms = [it[@"d"] respondsToSelector:@selector(longLongValue)] ? [it[@"d"] longLongValue] : 0;
        if (ms <= 0) { return IMLocalized(@"preview.voice"); }
        return IMLocalizedFormat(@"preview.voice_duration", IMFormatVoiceDuration(ms));
    }
    if ([ct isEqualToString:@"chat_record"]) {
        // 嵌套合并转发：只取子标题（maxLines=0，不再展开子条目），显「[聊天记录] 子标题」。
        // 子 JSON 非法时标题回落 IMSummarizeRecord 的本地化默认标题，此时不叠加以免重复
        // （与 IMSummarizeRecord 的默认标题同一口径，见 record.chat_history）。
        NSString *t = nil; IMSummarizeRecord(c, &t, NULL, 0);
        return (t.length > 0 && ![t isEqualToString:IMLocalized(@"record.chat_history")])
            ? IMLocalizedFormat(@"quote.snapshot.chat_record_titled", t) : IMLocalized(@"preview.chat_record");
    }
    return c;
}

NSString *IMRecordSenderKey(NSDictionary *it) {
    if (![it isKindOfClass:NSDictionary.class]) { return @"n:"; }
    NSString *u = [it[@"u"] isKindOfClass:NSString.class] ? it[@"u"] : @"";
    if (u.length > 0) { return [@"u:" stringByAppendingString:u]; }
    NSString *n = [it[@"n"] isKindOfClass:NSString.class] ? it[@"n"] : @"";
    return [@"n:" stringByAppendingString:n];
}

NSDictionary<NSString *, NSString *> *IMRecordSenderKeysForUIDs(NSArray<NSString *> *uids) {
    NSMutableDictionary<NSString *, NSString *> *keys = [NSMutableDictionary dictionary];
    for (id raw in (uids ?: @[])) {
        if (![raw isKindOfClass:NSString.class]) { continue; }
        NSString *uid = (NSString *)raw;
        if (uid.length == 0 || keys[uid]) { continue; }
        keys[uid] = [NSString stringWithFormat:@"s%lu", (unsigned long)(keys.count + 1)];
    }
    return keys;
}

void IMSummarizeRecord(NSString *json, NSString **outTitle, NSArray<NSString *> **outLines, NSInteger maxLines) {
    NSString *title = IMLocalized(@"record.chat_history"); // 缺 t 字段的老快照兜底标题，跟随 App 语言
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

/// 2026-09-22 P3 修复：此前这里全是硬编码中文字面量，不看 App 当前语言——英文界面下引用条一直显
/// 中文，是真实 bug（不是新引入的问题，见 P3 客户端消费守则 §2）。改为按 IMLocalized 取当前语言。
/// `[chat_record]`/存量 JSON 救援分支仍调用 IMChatRecordSnippet（标题前缀硬编码中文）、`[call]`/
/// `[contact]` 未改走 IMCallRecordNeutralPreview/IMContactCardPreview（同样硬编码中文）——这两个
/// 是更大范围的共用函数（还服务会话列表/合并转发卡片等本批未涉及的界面），不在本批改动范围内，
/// 已在交付报告里注明为已知残留限制。
NSString *IMLocalizeReplySnippet(NSString *snap) {
    if (snap.length == 0) { return @""; }
    if ([snap isEqualToString:@"[image]"]) { return IMLocalized(@"preview.image"); }
    if ([snap isEqualToString:@"[video]"]) { return IMLocalized(@"preview.video"); }
    if ([snap isEqualToString:@"[file]"])  { return IMLocalized(@"preview.file"); }
    NSString *fn = IMReplySnippetFileName(snap); // wire 形 `[file] x` 与本端存量本地化形 `[文件] x` 都能取出文件名
    if (fn.length > 0) { return IMLocalizedFormat(@"quote.snapshot.file_named", fn); } // 带名文件；本地化输入幂等重组（换成当前语言）
    if ([snap isEqualToString:@"[chat_record]"]) { return IMLocalized(@"quote.snapshot.chat_record"); } // 旧服务端 token（无标题）兜底
    if ([snap isEqualToString:@"[contact]"]) { return IMLocalized(@"quote.snapshot.contact"); }         // 同上：老服务端下发的裸 token
    if ([snap isEqualToString:@"[call]"]) { return IMLocalized(@"quote.snapshot.call"); }               // 通话记录同上
    if (IMLooksLikeChatRecordJSON(snap)) { return IMChatRecordSnippet(snap); } // 存量 JSON 截段救援（残留硬编码中文，见上注释）
    return snap; // 纯文本 / 已本地化的存量输入：幂等原样
}

/// 语言无关的快照类别判定（供 IMRenderReplySnapshot 挑图标用）：同时识别 wire token（`[image]` 等）
/// 与本端存量本地化形（`[图片]` 等），不依赖 IMLocalizeReplySnippet 的输出语言——旧版
/// IMMediaGlyphForSnippet（IMBubbleCell.m）曾直接拿本地化后的中文字符串做字符串比较，一旦引用条
/// 文案改成跟随语言（本批修复），英文界面下这个比较就再也不会命中，图标会静默消失，
/// 是本批顺手一并修的另一处（原函数依赖 IMLocalizeReplySnippet 永远输出中文这一"巧合"才成立）。
static NSString *IMReplySnippetGlyphKind(NSString *raw) {
    if ([raw isEqualToString:@"[image]"] || [raw isEqualToString:@"[图片]"]) { return @"image"; }
    if ([raw isEqualToString:@"[video]"] || [raw isEqualToString:@"[视频]"]) { return @"video"; }
    if ([raw isEqualToString:@"[file]"]  || [raw isEqualToString:@"[文件]"]) { return @"file"; }
    if (IMReplySnippetFileName(raw).length > 0) { return @"file"; }
    if ([raw isEqualToString:@"[chat_record]"] || [raw hasPrefix:@"[聊天记录]"] || IMLooksLikeChatRecordJSON(raw)) { return @"chat_record"; }
    return @"";
}

/// 旧 wire-token 路径的渲染（reply_snapshot_kind 为空时用）：文案 + 图标/文件类判定一起算好，
/// 供 IMRenderReplySnapshot 的"kind 为空"与"kind==other 且非 image/video"两处共用，避免复制一份。
static void IMRenderLegacyReplySnippet(NSString *raw,
                                        NSString **outText, NSString **outGlyph,
                                        BOOL *outIsFile, NSString **outFileName) {
    NSString *text = IMLocalizeReplySnippet(raw);
    NSString *tag = IMReplySnippetGlyphKind(raw);
    NSString *glyph = nil; BOOL isFile = NO; NSString *fileName = nil;
    if ([tag isEqualToString:@"image"]) { glyph = @"photo.fill"; }
    else if ([tag isEqualToString:@"video"]) { glyph = @"video.fill"; }
    else if ([tag isEqualToString:@"file"]) { isFile = YES; fileName = IMReplySnippetFileName(raw); }
    else if ([tag isEqualToString:@"chat_record"]) { glyph = @"text.bubble.fill"; }
    if (outText) { *outText = text; }
    if (outGlyph) { *outGlyph = glyph; }
    if (outIsFile) { *outIsFile = isFile; }
    if (outFileName) { *outFileName = fileName; }
}

void IMRenderReplySnapshot(IMMessageModel *message,
                            NSString **outText, NSString **outGlyphSymbolName,
                            BOOL *outIsFileKind, NSString **outFileName) {
    NSString *text = @""; NSString *glyph = nil; BOOL isFile = NO; NSString *fileName = nil;
    if (message.replyToConvSeq > 0) {
        NSString *rawFallback = message.replySnapshot.length > 0 ? message.replySnapshot : IMLocalized(@"chat.quote.original_fallback");
        NSString *kind = message.replySnapshotKind;
        NSDictionary<NSString *, NSString *> *args = message.replySnapshotArgs ?: @{};
        if ([kind isEqualToString:@"recalled"]) {
            text = IMLocalized(@"quote.snapshot.recalled");
        } else if ([kind isEqualToString:@"chat_record"]) {
            NSString *title = args[@"title"];
            text = title.length > 0 ? IMLocalizedFormat(@"quote.snapshot.chat_record_titled", title) : IMLocalized(@"quote.snapshot.chat_record");
            glyph = @"text.bubble.fill";
        } else if ([kind isEqualToString:@"file"]) {
            NSString *name = args[@"name"];
            text = name.length > 0 ? IMLocalizedFormat(@"quote.snapshot.file_named", name) : IMLocalized(@"preview.file");
            isFile = YES;
            fileName = name;
        } else if ([kind isEqualToString:@"voice"]) {
            int64_t ms = [args[@"duration_ms"] longLongValue];
            text = IMLocalizedFormat(@"preview.voice_duration", IMFormatVoiceDuration(ms));
        } else if ([kind isEqualToString:@"contact"]) {
            NSString *name = args[@"name"];
            text = name.length > 0 ? IMLocalizedFormat(@"quote.snapshot.contact_named", name) : IMLocalized(@"quote.snapshot.contact");
        } else if ([kind isEqualToString:@"call"]) {
            text = IMLocalized(@"quote.snapshot.call");
        } else if ([kind isEqualToString:@"other"]) {
            NSString *ct = args[@"content_type"];
            if ([ct isEqualToString:@"image"]) { text = IMLocalized(@"preview.image"); glyph = @"photo.fill"; }
            else if ([ct isEqualToString:@"video"]) { text = IMLocalized(@"preview.video"); glyph = @"video.fill"; }
            else { IMRenderLegacyReplySnippet(rawFallback, &text, &glyph, &isFile, &fileName); } // 罕见兜底
        } else {
            // kind 为空（纯文本引用/老消息）或不认识的取值 → 回退旧 wire-token 路径
            IMRenderLegacyReplySnippet(rawFallback, &text, &glyph, &isFile, &fileName);
        }
    }
    if (outText) { *outText = text; }
    if (outGlyphSymbolName) { *outGlyphSymbolName = glyph; }
    if (outIsFileKind) { *outIsFileKind = isFile; }
    if (outFileName) { *outFileName = fileName; }
}
