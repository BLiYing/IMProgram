//  IMMediaUtil.m

#import "IMMediaUtil.h"
#import <math.h>

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
