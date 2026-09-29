//  IMConversationPreview.m

#import "IMConversationPreview.h"
#import "IMContactCard.h"
#import "IMCallRecord.h"
#import "IMLocalization.h"

NSString *IMConversationMediaPreview(NSString *contentType, NSString *caption, NSString *content,
                                      int64_t durationMs, BOOL mine, BOOL isGroup, BOOL *missedCall) {
    if (missedCall) { *missedCall = NO; }
    if (contentType.length == 0) { return nil; }

    // 图文/视频文/文件文带 caption 时列表预览显 caption，否则回退占位（Telegram 图说模型）。
    if (caption.length > 0 &&
        ([contentType isEqualToString:@"image"] || [contentType isEqualToString:@"video"] || [contentType isEqualToString:@"file"])) {
        return caption;
    }
    if ([contentType isEqualToString:IMContentTypeContact]) {
        // 个人名片：`[个人名片] 小明`——需要 content（快照里的昵称）。
        return IMContactCardPreview(content);
    }
    if ([contentType isEqualToString:IMContentTypeCall]) {
        // 通话记录：`[语音通话] 未接来电`（按「我」的视角），只有被叫「未接来电」算 missedCall。
        IMCallRecordDisplay *cd = IMCallRecordRender(content, mine, isGroup, nil);
        if (missedCall) { *missedCall = cd.tone == IMCallRecordToneMissed; }
        return cd.preview;
    }
    if ([contentType isEqualToString:@"voice"]) {
        // voice：`[语音] m:ss`，与聊天页 IMVoiceBubbleCell 同一格式。
        int64_t sec = MAX((int64_t)0, durationMs / 1000);
        return IMLocalizedFormat(@"preview.voice_duration", [NSString stringWithFormat:@"%lld:%02lld", sec / 60, sec % 60]);
    }

    static NSDictionary<NSString *, NSString *> *mediaNameKeys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        mediaNameKeys = @{ @"image": @"preview.image", @"video": @"preview.video", @"file": @"preview.file",
                           @"chat_record": @"preview.chat_record",
                           @"location": @"preview.location" };
    });
    NSString *nameKey = mediaNameKeys[contentType];
    return nameKey ? IMLocalized(nameKey) : nil;
}
