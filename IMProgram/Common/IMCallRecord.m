//  IMCallRecord.m

#import "IMCallRecord.h"

NSString * const IMContentTypeCall = @"call";
NSString * const IMCallRecordUnsupportedText = @"[音视频通话] 请升级新版查看";

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
    if (r.durationSec > 0) { return [@"通话时长 " stringByAppendingString:IMCallRecordFormatDuration(r.durationSec)]; }
    NSString *k = r.reason;
    // 主叫看 / 被叫看；只有被叫侧且 cancel/no_answer/busy/offline 才红（自己 reject 不红）。
    static NSDictionary<NSString *, NSArray<NSString *> *> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{ @"cancel":    @[@"已取消", @"未接来电"],
                   @"reject":    @[@"对方已拒绝", @"已拒绝"],
                   @"no_answer": @[@"对方无应答", @"未接来电"],
                   @"busy":      @[@"对方忙线", @"未接来电"],
                   @"offline":   @[@"对方不在线", @"未接来电"] };
    });
    NSArray<NSString *> *row = table[k];
    if (!row) { return @"通话未接通"; }   // network / room_closed / kicked / error / 表外 reason
    *missed = !viewerIsSender && ![k isEqualToString:@"reject"];
    return row[viewerIsSender ? 0 : 1];
}

/// 群系统条正文 + 会话列表预览尾巴。
static NSString *groupText(IMCallRecord *r, BOOL viewerIsSender, NSString *senderName, NSString **tail) {
    NSString *who = viewerIsSender ? @"你" : (senderName.length > 0 ? senderName : @"对方");
    NSString *kind = r.video ? @"视频" : @"语音";
    if (r.durationSec > 0) {
        NSString *t = IMCallRecordFormatDuration(r.durationSec);
        *tail = [@"时长 " stringByAppendingString:t];
        return [NSString stringWithFormat:@"%@发起的群%@通话，时长 %@", who, kind, t];
    }
    if ([r.reason isEqualToString:@"no_answer"]) {
        *tail = @"无人接听";
        return [NSString stringWithFormat:@"%@发起的群%@通话，无人接听", who, kind];
    }
    if ([r.reason isEqualToString:@"cancel"]) {
        *tail = @"已取消";
        return [NSString stringWithFormat:@"%@取消了群%@通话", who, kind];
    }
    *tail = @"已结束";
    return @"群通话已结束";
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
        out.preview = [NSString stringWithFormat:@"[群%@通话] %@", r.video ? @"视频" : @"语音", tail];
        return out;
    }
    BOOL missed = NO;
    out.text = singleText(r, viewerIsSender, &missed);
    out.tone = missed ? IMCallRecordToneMissed : IMCallRecordToneNormal;
    out.tappable = YES;
    out.preview = [NSString stringWithFormat:@"[%@通话] %@", r.video ? @"视频" : @"语音", out.text];
    return out;
}

NSString *IMCallRecordPreview(NSString *content, BOOL viewerIsSender, BOOL isGroup) {
    return IMCallRecordRender(content, viewerIsSender, isGroup, nil).preview;
}

NSString *IMCallRecordNeutralPreview(void) { return @"[音视频通话]"; }
