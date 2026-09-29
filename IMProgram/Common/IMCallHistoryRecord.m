//  IMCallHistoryRecord.m

#import "IMCallHistoryRecord.h"
#import "IMTheme.h"

@implementation IMCallHistoryRecord
- (instancetype)init {
    if ((self = [super init])) {
        _callID = @""; _roomID = @""; _caller = @""; _reason = @""; _memberUIDs = @[];
    }
    return self;
}
@end

@implementation IMCallHistorySection
@end

BOOL IMCallHistoryRecordIsMissed(IMCallHistoryRecord *record, NSString *selfUID) {
    if (record == nil || selfUID.length == 0) { return NO; }
    return ![record.caller isEqualToString:selfUID] && record.durationSec == 0;
}

NSString *IMCallHistoryRecordPeerUID(IMCallHistoryRecord *record, NSString *selfUID) {
    if (record == nil) { return nil; }
    if (record.caller.length > 0 && ![record.caller isEqualToString:selfUID]) { return record.caller; }
    for (NSString *uid in record.memberUIDs) {
        if (uid.length > 0 && ![uid isEqualToString:selfUID]) { return uid; }
    }
    return nil;
}

NSInteger IMCallHistoryGroupPeerCount(NSArray<NSString *> *memberUIDs, NSString *callerUID) {
    NSInteger base = MAX((NSInteger)memberUIDs.count, 1);
    BOOL callerInMembers = callerUID.length > 0 && [memberUIDs containsObject:callerUID];
    return base + (callerInMembers ? 0 : 1);
}

NSArray<IMCallHistoryRecord *> *IMCallHistoryApplyFilter(NSArray<IMCallHistoryRecord *> *records,
                                                          IMCallHistoryFilter filter, NSString *selfUID) {
    if (filter == IMCallHistoryFilterAll) { return records ?: @[]; }
    NSMutableArray<IMCallHistoryRecord *> *out = [NSMutableArray array];
    for (IMCallHistoryRecord *r in records) {
        if (IMCallHistoryRecordIsMissed(r, selfUID)) { [out addObject:r]; }
    }
    return out;
}

NSArray<IMCallHistorySection *> *IMCallHistoryGroupByDate(NSArray<IMCallHistoryRecord *> *sortedDescRecords) {
    NSMutableArray<IMCallHistorySection *> *sections = [NSMutableArray array];
    IMCallHistorySection *current = nil;
    int64_t currentAnchorMs = 0;
    NSMutableArray<IMCallHistoryRecord *> *bucket = nil;
    for (IMCallHistoryRecord *r in sortedDescRecords) {
        BOOL sameDay = current != nil && [IMTheme isMillis:r.startedAtMs sameDayAsMillis:currentAnchorMs];
        if (!sameDay) {
            if (current) { current.records = [bucket copy]; }
            current = [IMCallHistorySection new];
            current.title = [IMTheme dayHeaderStringFromMillis:r.startedAtMs];
            bucket = [NSMutableArray array];
            currentAnchorMs = r.startedAtMs;
            [sections addObject:current];
        }
        [bucket addObject:r];
    }
    if (current) { current.records = [bucket copy]; }
    return sections;
}
