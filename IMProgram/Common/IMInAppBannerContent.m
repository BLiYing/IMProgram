//  IMInAppBannerContent.m

#import "IMInAppBannerContent.h"
#import "IMConversationPreview.h"
#import "IMLocalization.h"

@implementation IMInAppBannerContent
@end

IMInAppBannerContent *IMInAppBannerContentBuild(NSString *title, BOOL isGroup, NSString *avatarURL, NSString *avatarSeed,
                                                 BOOL previewEnabled, NSString *contentType, NSString *caption,
                                                 NSString *content, int64_t durationMs, NSString *senderDisplayName) {
    IMInAppBannerContent *out = [IMInAppBannerContent new];
    out.title = title.length > 0 ? title : @"";
    out.avatarURL = avatarURL;
    out.avatarSeed = avatarSeed.length > 0 ? avatarSeed : @"";
    out.avatarDisplayName = out.title;

    if (!previewEnabled) {
        out.body = IMLocalized(@"notif.preview.hidden");
        return out;
    }

    // mine 恒 NO：横幅只会为别人发来的消息触发（调用点见 IMSocketManager+Alerts.m 的 eligible 判据）。
    NSString *summary = IMConversationMediaPreview(contentType, caption, content, durationMs, NO, isGroup, NULL);
    if (summary.length == 0) {
        summary = content.length > 0 ? content : IMLocalized(@"conv.list.no_message");
    }
    if (isGroup && senderDisplayName.length > 0) {
        out.body = [NSString stringWithFormat:@"%@: %@", senderDisplayName, summary];
    } else {
        out.body = summary;
    }
    return out;
}
