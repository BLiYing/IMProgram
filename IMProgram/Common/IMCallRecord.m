//  IMCallRecord.m

#import "IMCallRecord.h"
#import "IMLocalization.h"

NSString * const IMContentTypeCall = @"call";

static const NSInteger kIMCallRecordMaxDuration = 86400 * 3; // 与服务端截断一致

@implementation IMCallRecord
@end

@implementation IMCallRecordDisplay
@end

static NSString *_Nullable trimmedString(NSDictionary *d, NSString *key) {
    id v = d[key];
    if (![v isKindOfClass:NSString.class]) { return nil; }
    NSString *s = [(NSString *)v stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return s.length > 0 ? s : nil;
}

IMCallRecord *IMCallRecordParse(NSString *content) {
    if (![content isKindOfClass:NSString.class] || content.length == 0) { return nil; }
    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    id obj = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![obj isKindOfClass:NSDictionary.class]) { return nil; }
    NSDictionary *d = obj;
    NSString *cid = trimmedString(d, @"cid");
    NSString *m = trimmedString(d, @"m");
    BOOL isAudio = [m isEqualToString:@"audio"], isVideo = [m isEqualToString:@"video"];
    if (cid.length == 0 || (!isAudio && !isVideo)) { return nil; } // 缺 cid / m 非法 = 回拨不了的死记录
    IMCallRecord *r = [IMCallRecord new];
    r.callID = cid;
    r.video = isVideo;
    r.reason = trimmedString(d, @"r") ?: @"";
    NSInteger sec = [d[@"d"] isKindOfClass:NSNumber.class] ? [d[@"d"] integerValue] : 0;
    r.durationSec = MIN(MAX(sec, 0), kIMCallRecordMaxDuration);
    r.group = [d[@"g"] respondsToSelector:@selector(integerValue)] && [d[@"g"] integerValue] == 1;
    return r;
}

NSString *IMCallRecordBuild(NSString *callID, BOOL video, NSString *reason, NSInteger durationSec, BOOL group) {
    NSString *cid = [(callID ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (cid.length == 0) { return nil; }
    NSMutableDictionary *d = [@{ @"cid": cid, @"m": video ? @"video" : @"audio",
                                 @"r": reason ?: @"", @"d": @(MAX(durationSec, 0)) } mutableCopy];
    if (group) { d[@"g"] = @1; }
    NSData *json = [NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingSortedKeys error:NULL];
    return json.length > 0 ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
}

NSString *IMCallRecordFormatDuration(NSInteger sec) {
    sec = MAX(sec, 0);
    if (sec >= 3600) { return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)(sec / 3600), (long)(sec % 3600 / 60), (long)(sec % 60)]; }
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)(sec / 60), (long)(sec % 60)];
}

/// 单聊正文；missed 同时输出。
static NSString *singleText(IMCallRecord *r, BOOL viewerIsSender, BOOL *missed) {
    *missed = NO;
    if (r.durationSec > 0) { return IMLocalizedFormat(@"call.record.duration", IMCallRecordFormatDuration(r.durationSec)); }
    NSString *k = r.reason;
    // 主叫看 / 被叫看；只有被叫侧且 cancel/no_answer/busy/offline 才红（自己 reject 不红）。
    // 表里放文案**键**（不在 dispatch_once 里取文案，否则切语言后不会变）。
    static NSDictionary<NSString *, NSArray<NSString *> *> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{ @"cancel":    @[@"call.record.cancelled", @"call.record.missed"],
                   @"reject":    @[@"call.record.declined_by_peer", @"call.record.declined"],
                   @"no_answer": @[@"call.record.peer_no_answer", @"call.record.missed"],
                   @"busy":      @[@"call.record.peer_busy", @"call.record.missed"],
                   @"offline":   @[@"call.record.peer_offline", @"call.record.missed"] };
    });
    NSArray<NSString *> *row = table[k];
    if (!row) { return IMLocalized(@"call.record.not_connected"); }   // network / room_closed / kicked / error / 表外 reason
    *missed = !viewerIsSender && ![k isEqualToString:@"reject"];
    return IMLocalized(row[viewerIsSender ? 0 : 1]);
}

/// 群系统条正文 + 会话列表预览尾巴。
static NSString *groupText(IMCallRecord *r, BOOL viewerIsSender, NSString *senderName, NSString **tail) {
    NSString *who = viewerIsSender ? IMLocalized(@"call.record.who_self")
                                   : (senderName.length > 0 ? senderName : IMLocalized(@"call.record.who_peer"));
    NSString *kind = IMLocalized(r.video ? @"call.record.kind_video" : @"call.record.kind_voice");
    if (r.durationSec > 0) {
        NSString *t = IMCallRecordFormatDuration(r.durationSec);
        *tail = IMLocalizedFormat(@"call.record.tail_duration", t);
        return IMLocalizedFormat(@"call.record.group_duration", who, kind, t);
    }
    if ([r.reason isEqualToString:@"no_answer"]) {
        *tail = IMLocalized(@"call.record.tail_no_answer");
        return IMLocalizedFormat(@"call.record.group_no_answer", who, kind);
    }
    if ([r.reason isEqualToString:@"cancel"]) {
        *tail = IMLocalized(@"call.record.cancelled");
        return IMLocalizedFormat(@"call.record.group_cancelled", who, kind);
    }
    *tail = IMLocalized(@"call.record.tail_ended");
    return IMLocalized(@"call.record.group_ended");
}

IMCallRecordDisplay *IMCallRecordRender(NSString *content, BOOL viewerIsSender, BOOL isGroup, NSString *senderName) {
    IMCallRecordDisplay *out = [IMCallRecordDisplay new];
    IMCallRecord *r = IMCallRecordParse(content);
    if (!r) {
        out.supported = NO; out.text = IMCallRecordUnsupportedText; out.tappable = NO;
        out.preview = IMCallRecordNeutralPreview();
        return out;
    }
    out.supported = YES; out.video = r.video;
    if (isGroup) {
        NSString *tail = @"";
        out.text = groupText(r, viewerIsSender, senderName, &tail);
        out.tone = IMCallRecordToneNormal; out.tappable = NO;
        out.preview = IMLocalizedFormat(r.video ? @"call.record.preview_group_video" : @"call.record.preview_group_voice", tail);
        return out;
    }
    BOOL missed = NO;
    out.text = singleText(r, viewerIsSender, &missed);
    out.tone = missed ? IMCallRecordToneMissed : IMCallRecordToneNormal;
    out.tappable = YES;
    out.preview = IMLocalizedFormat(r.video ? @"call.record.preview_video" : @"call.record.preview_voice", out.text);
    return out;
}

NSString *IMCallRecordPreview(NSString *content, BOOL viewerIsSender, BOOL isGroup) {
    return IMCallRecordRender(content, viewerIsSender, isGroup, nil).preview;
}

NSString *IMCallRecordNeutralPreview(void) { return IMLocalized(@"quote.snapshot.call"); }
