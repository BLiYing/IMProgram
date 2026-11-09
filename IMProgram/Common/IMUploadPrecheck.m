//  IMUploadPrecheck.m

#import "IMUploadPrecheck.h"

#import "IMLocalization.h"
#import "IMLog.h"
#import "IMServerConfigStore.h"

static const long long kIMUploadGiB = 1024LL * 1024 * 1024;
static const long long kIMUploadMiB = 1024LL * 1024;

/// 小写扩展名（不带点），口径同服务端 Go `filepath.Ext`：取最后一段路径里最后一个点之后的部分。
/// 不用 NSString.pathExtension：它把 ".exe" / ".sh" 这类点开头的名字当成「无扩展名」，而服务端判为 .exe → 500002。
static NSString *IMUploadExtension(NSString *fileName) {
    NSString *base = fileName.lastPathComponent;
    NSRange dot = [base rangeOfString:@"." options:NSBackwardsSearch];
    if (dot.location == NSNotFound || NSMaxRange(dot) >= base.length) { return @""; }
    return [base substringFromIndex:NSMaxRange(dot)].lowercaseString;
}

IMUploadPrecheckResult IMUploadPrecheckEvaluate(NSString *fileName, long long byteCount, BOOL isVoice, BOOL enabled,
                                                long long maxFileBytes, NSArray<NSString *> *blockedExtensions) {
    if (!enabled) { return IMUploadPrecheckDisabled; }
    if (isVoice) { return IMUploadPrecheckOK; } // 语音只受总开关约束
    NSString *ext = IMUploadExtension(fileName);
    if (ext.length > 0 && blockedExtensions.count > 0) {
        NSString *dotted = [@"." stringByAppendingString:ext];
        for (NSString *blocked in blockedExtensions) {
            if ([blocked.lowercaseString isEqualToString:dotted]) { return IMUploadPrecheckBlockedType; }
        }
    }
    long long limit = maxFileBytes > 0 ? maxFileBytes : IMServerConfigDefaultUploadMaxFileBytes;
    if (byteCount > limit) { return IMUploadPrecheckTooLarge; }
    return IMUploadPrecheckOK;
}

NSString *IMUploadLimitLabel(long long bytes) {
    if (bytes >= kIMUploadGiB && bytes % kIMUploadGiB == 0) {
        return [NSString stringWithFormat:@"%lld GB", bytes / kIMUploadGiB];
    }
    bytes = MAX(0LL, bytes);
    if (bytes % kIMUploadMiB == 0) { return [NSString stringWithFormat:@"%lld MB", bytes / kIMUploadMiB]; }
    return [NSString stringWithFormat:@"%.1f MB", (double)bytes / kIMUploadMiB]; // 同服务端：非整 MiB 保留一位小数
}

/// 判定结果 → 文案（Message 与 WithStore 共用，免得同一组值判两遍）。
static NSString *IMUploadPrecheckMessageForResult(IMUploadPrecheckResult r, long long maxFileBytes) {
    switch (r) {
        case IMUploadPrecheckOK: return nil;
        case IMUploadPrecheckDisabled: return IMLocalized(@"err.500003");
        case IMUploadPrecheckBlockedType: return IMLocalized(@"upload.precheck.blocked_type");
        case IMUploadPrecheckTooLarge: {
            long long limit = maxFileBytes > 0 ? maxFileBytes : IMServerConfigDefaultUploadMaxFileBytes;
            return IMLocalizedFormat(@"upload.precheck.too_large", IMUploadLimitLabel(limit));
        }
    }
    return nil;
}

NSString *IMUploadPrecheckMessage(NSString *fileName, long long byteCount, BOOL isVoice, BOOL enabled,
                                  long long maxFileBytes, NSArray<NSString *> *blockedExtensions) {
    IMUploadPrecheckResult r = IMUploadPrecheckEvaluate(fileName, byteCount, isVoice, enabled, maxFileBytes, blockedExtensions);
    return IMUploadPrecheckMessageForResult(r, maxFileBytes);
}

NSString *IMUploadPrecheckCurrent(NSString *fileName, long long byteCount, BOOL isVoice) {
    return IMUploadPrecheckWithStore(IMServerConfigStore.shared, fileName, byteCount, isVoice);
}

NSString *IMUploadPrecheckWithStore(IMServerConfigStore *s, NSString *fileName, long long byteCount, BOOL isVoice) {
    // 先取一份快照再判：判定与出文案必须用同一组值（分开读的话中途配置刷新会出现「判为拦截、文案却为 nil」）。
    BOOL enabled = s.uploadEnabled;
    long long maxBytes = s.uploadMaxFileBytes;
    NSArray<NSString *> *blocked = s.uploadBlockedExtensions;
    IMUploadPrecheckResult r = IMUploadPrecheckEvaluate(fileName, byteCount, isVoice, enabled, maxBytes, blocked);
    if (r == IMUploadPrecheckOK) { return nil; }
    static NSString * const reasons[] = { @"ok", @"disabled", @"blocked_type", @"too_large" };
    IMLogWarnWithTag(IMLogTagMedia, @"upload_precheck_rejected reason=%@ ext=%@ bytes=%lld voice=%d max_bytes=%lld",
                     reasons[r], IMUploadExtension(fileName), byteCount, isVoice, maxBytes);
    // 本地拦下的请求根本到不了服务端：缓存若已过期（管理员关了又开 / 调大上限 / 解禁扩展名），不刷新的话
    // 要等下次重连 / 回前台才自愈。拦一次就顺手重拉（refresh 自带在途合并与几秒内去重），下一次尝试用新值。
    [s refresh];
    return IMUploadPrecheckMessageForResult(r, maxBytes);
}

NSString *IMUploadServerRejectionMessage(NSInteger code, NSString *serverText, NSString *fileName,
                                        long long maxFileBytes, NSArray<NSString *> *blockedExtensions) {
    switch (code) {
        case 500003: return IMUploadPrecheckMessageForResult(IMUploadPrecheckDisabled, maxFileBytes);
        case 500001: return IMUploadPrecheckMessageForResult(IMUploadPrecheckTooLarge, maxFileBytes);
        case 500002: {
            // 500002 也用于「本就不支持的格式」：只有扩展名确在禁用表里才换成「管理员禁止」文案。
            IMUploadPrecheckResult r = IMUploadPrecheckEvaluate(fileName, 0, NO, YES, maxFileBytes, blockedExtensions);
            if (r == IMUploadPrecheckBlockedType) { return IMUploadPrecheckMessageForResult(r, maxFileBytes); }
            return serverText.length > 0 ? serverText : nil;
        }
    }
    return serverText.length > 0 ? serverText : nil;
}

NSString *IMUploadServerRejectionMessageCurrent(NSInteger code, NSString *serverText, NSString *fileName) {
    IMServerConfigStore *s = IMServerConfigStore.shared;
    NSString *text = IMUploadServerRejectionMessage(code, serverText, fileName, s.uploadMaxFileBytes, s.uploadBlockedExtensions);
    [s refresh]; // 服务端与本地缓存判得不一样 = 缓存多半过期：重拉，下一次预检用新值
    return text;
}

BOOL IMUploadIsPolicyRejectionCode(NSInteger code) {
    return code == 500001 || code == 500002 || code == 500003;
}
