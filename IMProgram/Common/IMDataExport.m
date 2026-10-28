//  IMDataExport.m

#import "IMDataExport.h"
#import "IMHTTPService+Account.h"
#import "IMServerEndpoint.h"
#import "IMLocalization.h"

NSInteger const IMErrCodeExportBusy = 200010;
NSInteger const IMErrCodeExportCooldown = 200011;
NSString * const IMErrorRetryAfterSecKey = @"im_retry_after_sec";

static NSInteger IMExportInt(id raw) {
    return [raw isKindOfClass:NSNumber.class] ? [raw integerValue] : 0;
}

@implementation IMExportJob

+ (instancetype)jobFromJSON:(id)json {
    if (![json isKindOfClass:NSDictionary.class]) { return nil; }
    NSDictionary *d = json;
    id rawID = d[@"id"];
    NSString *jobID = [rawID isKindOfClass:NSString.class] ? rawID : ([rawID isKindOfClass:NSNumber.class] ? [rawID stringValue] : @"");
    if (jobID.length == 0) { return nil; }
    NSDictionary *progress = [d[@"progress"] isKindOfClass:NSDictionary.class] ? d[@"progress"] : @{};
    NSDictionary *result = [d[@"result"] isKindOfClass:NSDictionary.class] ? d[@"result"] : @{};
    IMExportJob *job = [IMExportJob new];
    job->_jobID = [jobID copy];
    job->_status = IMExportStatusFromString(d[@"status"]);
    job->_doneConvs = MAX(0, IMExportInt(progress[@"done_convs"]));
    job->_totalConvs = MAX(0, IMExportInt(progress[@"total_convs"]));
    job->_sizeBytes = [result[@"size_bytes"] isKindOfClass:NSNumber.class] ? MAX(0, [result[@"size_bytes"] longLongValue]) : 0;
    job->_convCount = MAX(0, IMExportInt(result[@"conv_count"]));
    job->_msgCount = MAX(0, IMExportInt(result[@"msg_count"]));
    job->_finishedAt = IMParseDeleteAt(d[@"finished_at"]);
    job->_expiresAt = IMParseDeleteAt(d[@"expires_at"]);
    return job;
}

@end

IMExportStatus IMExportStatusFromString(id raw) {
    if (![raw isKindOfClass:NSString.class]) { return IMExportStatusUnknown; }
    static NSDictionary<NSString *, NSNumber *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{ @"queued": @(IMExportStatusQueued), @"running": @(IMExportStatusRunning), @"done": @(IMExportStatusDone),
                 @"failed": @(IMExportStatusFailed), @"canceled": @(IMExportStatusCanceled), @"expired": @(IMExportStatusExpired) };
    });
    return (IMExportStatus)[map[raw] integerValue];
}

IMExportViewState IMExportViewStateForJob(IMExportJob *job, NSDate *now) {
    switch (job.status) {
        case IMExportStatusQueued:
        case IMExportStatusRunning:
            return IMExportViewStateRunning;
        case IMExportStatusDone:
            if (job.expiresAt && [job.expiresAt compare:now] != NSOrderedDescending) { return IMExportViewStateConfig; }
            return IMExportViewStateDone;
        case IMExportStatusFailed:
            return IMExportViewStateFailed;
        default:
            return IMExportViewStateConfig;
    }
}

IMExportViewState IMExportResolveViewState(IMExportJob *job, NSString *ackFailedID, NSDate *cooldownUntil, NSDate *now) {
    IMExportViewState st = IMExportViewStateForJob(job, now);
    if (st == IMExportViewStateFailed && ackFailedID.length > 0 && [ackFailedID isEqualToString:job.jobID]) {
        st = IMExportViewStateConfig;
    }
    if (st == IMExportViewStateConfig && IMExportCooldownUntil(job, cooldownUntil, now)) {
        return IMExportViewStateCooldown;
    }
    return st;
}

NSTimeInterval const IMExportCooldownSec = 24 * 3600;

NSDate *IMExportCooldownUntil(IMExportJob *job, NSDate *localUntil, NSDate *now) {
    NSDate *until = (localUntil && [localUntil compare:now] == NSOrderedDescending) ? localUntil : nil;
    BOOL succeeded = job.status == IMExportStatusDone || job.status == IMExportStatusExpired;
    if (succeeded && job.finishedAt) {
        NSDate *derived = [job.finishedAt dateByAddingTimeInterval:IMExportCooldownSec];
        if ([derived compare:now] == NSOrderedDescending && (!until || [derived compare:until] == NSOrderedDescending)) { until = derived; }
    }
    return until;
}

BOOL IMExportCanStart(NSString *password, BOOL html, BOOL json, BOOL busy, BOOL cooling) {
    return password.length > 0 && (html || json) && !busy && !cooling;
}

NSInteger IMExportCooldownHours(NSTimeInterval remainingSec) {
    return MAX(1, (NSInteger)ceil(remainingSec / 3600.0));
}

float IMExportProgressFraction(NSInteger done, NSInteger total) {
    if (total <= 0) { return 0; }
    return (float)MIN(1.0, MAX(0.0, (double)done / (double)total));
}

NSURL *IMExportDownloadURL(NSString *raw, NSString *host) {
    NSString *s = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (s.length == 0) { return nil; }
    NSString *lower = s.lowercaseString;
    if ([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"]) {
        return [IMServerEndpoint.shared isOwnHost:host forAbsoluteURL:s] ? [NSURL URLWithString:s] : nil;
    }
    if (![s hasPrefix:@"/"] || host.length == 0) { return nil; }
    return [IMServerEndpoint.shared httpURLForHost:host path:s];
}

BOOL IMExportDownloadFailureIsGone(NSInteger httpStatus) {
    return httpStatus == 401 || httpStatus == 403 || httpStatus == 404 || httpStatus == 410;
}

BOOL IMExportShouldApplyLatest(NSUInteger fetchEpoch, NSUInteger currentEpoch) {
    return fetchEpoch == currentEpoch;
}

NSString *IMExportSummaryText(IMExportJob *job) {
    NSString *size = [NSByteCountFormatter stringFromByteCount:job.sizeBytes countStyle:NSByteCountFormatterCountStyleFile];
    return IMLocalizedFormat(@"export.done.summary", size, (long)job.convCount, (long)job.msgCount);
}

NSString *IMExportExpiresText(IMExportJob *job) {
    if (!job.expiresAt) { return nil; }
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = IMLocalization.shared.locale;
    f.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"MMMdHHmm" options:0 locale:f.locale];
    return IMLocalizedFormat(@"export.done.expires", [f stringFromDate:job.expiresAt]);
}

NSString *IMExportFileName(IMExportJob *job, NSDate *now) {
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"yyyyMMdd";
    return [NSString stringWithFormat:@"im-export-%@.zip", [f stringFromDate:job.finishedAt ?: now]];
}
