//  IMMuteDurationMenu.m

#import "IMMuteDurationMenu.h"
#import "IMLocalization.h"
#import "IMTimeUtil.h"
#import "IMActionListSheet.h"

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
    // 自绘底部弹层（IMActionListSheet，对齐 Android ActionSheet）：不用系统 ActionSheet——
    // 它在 iOS 26 / iOS 18 外观不同。sourceView/sourceRect 是 iPad popover 锚点，自绘弹层不需要，保留签名不动调用方。
    NSMutableArray<IMActionListItem *> *items = [NSMutableArray array];
    if (showUnmuteFirst) {
        [items addObject:[IMActionListItem itemWithTitle:IMLocalized(@"conv.menu.unmute") destructive:YES handler:^{
            if (completion) { completion(YES, 0); }
        }]];
    }
    void (^add)(NSString *, IMMuteDurationOption) = ^(NSString *title, IMMuteDurationOption option) {
        [items addObject:[IMActionListItem itemWithTitle:title destructive:NO handler:^{
            if (completion) { completion(NO, IMMuteUntilForDurationOption(option, IMNowMillis())); }
        }]];
    };
    add(IMLocalized(@"mute.1h"), IMMuteDurationOneHour);
    add(IMLocalized(@"mute.8h"), IMMuteDurationEightHours);
    add(IMLocalized(@"mute.1d"), IMMuteDurationOneDay);
    add(IMLocalized(@"mute.7d"), IMMuteDurationSevenDays);
    add(IMLocalized(@"common.permanent"), IMMuteDurationForever);
    [IMActionListSheet presentFrom:host
                             title:IMLocalizedFormat(@"notif.mute.sheet_title", conversationName ?: @"")
                             items:items];
}

@end
