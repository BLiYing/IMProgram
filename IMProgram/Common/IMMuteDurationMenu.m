//  IMMuteDurationMenu.m

#import "IMMuteDurationMenu.h"
#import "IMLocalization.h"
#import "IMTimeUtil.h"

int64_t IMMuteUntilForDurationOption(IMMuteDurationOption option, int64_t nowMs) {
    switch (option) {
        case IMMuteDurationOneHour:    return nowMs + 1LL * 60 * 60 * 1000;
        case IMMuteDurationEightHours: return nowMs + 8LL * 60 * 60 * 1000;
        case IMMuteDurationOneDay:     return nowMs + 24LL * 60 * 60 * 1000;
        case IMMuteDurationSevenDays:  return nowMs + 7LL * 24 * 60 * 60 * 1000;
        case IMMuteDurationForever:    return 0;
    }
    return 0;
}

@implementation IMMuteDurationMenu

+ (void)presentFromViewController:(UIViewController *)host
                        sourceView:(UIView *)sourceView
                        sourceRect:(CGRect)sourceRect
                  conversationName:(NSString *)conversationName
                   showUnmuteFirst:(BOOL)showUnmuteFirst
                        completion:(void (^)(BOOL unmuted, int64_t muteUntil))completion {
    if (!host) { return; }
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:IMLocalizedFormat(@"notif.mute.sheet_title", conversationName ?: @"")
                          message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    if (showUnmuteFirst) {
        [sheet addAction:[UIAlertAction actionWithTitle:IMLocalized(@"conv.menu.unmute")
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction *a) {
            if (completion) { completion(YES, 0); }
        }]];
    }
    void (^add)(NSString *, IMMuteDurationOption) = ^(NSString *title, IMMuteDurationOption option) {
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *a) {
            if (completion) { completion(NO, IMMuteUntilForDurationOption(option, IMNowMillis())); }
        }]];
    };
    add(IMLocalized(@"mute.1h"), IMMuteDurationOneHour);
    add(IMLocalized(@"mute.8h"), IMMuteDurationEightHours);
    add(IMLocalized(@"mute.1d"), IMMuteDurationOneDay);
    add(IMLocalized(@"mute.7d"), IMMuteDurationSevenDays);
    add(IMLocalized(@"common.permanent"), IMMuteDurationForever);
    [sheet addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel")
                                               style:UIAlertActionStyleCancel handler:nil]];
    UIView *anchor = sourceView ?: host.view;
    sheet.popoverPresentationController.sourceView = anchor;
    sheet.popoverPresentationController.sourceRect = CGRectIsEmpty(sourceRect)
        ? CGRectMake(CGRectGetMidX(host.view.bounds), CGRectGetMaxY(host.view.bounds) - 60, 1, 1)
        : sourceRect;
    [host presentViewController:sheet animated:YES completion:nil];
}

@end
