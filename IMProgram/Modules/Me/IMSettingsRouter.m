//  IMSettingsRouter.m

#import "IMSettingsRouter.h"
#import "IMFavoritesViewController.h"
#import "IMCallHistoryViewController.h"
#import "IMDeviceListViewController.h"
#import "IMNotificationSettingsViewController.h"
#import "IMNotificationTypeViewController.h"
#import "IMNotificationSoundViewController.h"
#import "IMPrivacySecurityViewController.h"
#import "IMBlockedListViewController.h"
#import "IMChangePasswordViewController.h"
#import "IMDataStorageViewController.h"
#import "IMAutoDownloadNetworkViewController.h"
#import "IMAutoDownloadCategoryViewController.h"
#import "IMAppearanceViewController.h"
#import "IMPowerSavingViewController.h"
#import "IMLanguageViewController.h"

typedef UIViewController *(^IMPageBuilder)(NSString *host, NSString *userID);

@implementation IMSettingsRouter

/// 页面 id → 建页 block。id 约定：一级 = 「我」页行 id；二级起 = 「父/子」。
+ (NSDictionary<NSString *, IMPageBuilder> *)builders {
    static NSDictionary<NSString *, IMPageBuilder> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary<NSString *, IMPageBuilder> *t = [NSMutableDictionary dictionary];
        t[@"saved"] = ^UIViewController *(NSString *h, NSString *u) { return [IMFavoritesViewController new]; };
        t[@"recentCalls"] = ^UIViewController *(NSString *h, NSString *u) { return [[IMCallHistoryViewController alloc] initWithHost:h userID:u]; };
        t[@"devices"] = ^UIViewController *(NSString *h, NSString *u) { return [[IMDeviceListViewController alloc] initWithHost:h userID:u]; };
        t[@"notifications"] = ^UIViewController *(NSString *h, NSString *u) { return [[IMNotificationSettingsViewController alloc] initWithHost:h userID:u]; };
        t[@"notifications/private"] = ^UIViewController *(NSString *h, NSString *u) { return [[IMNotificationTypeViewController alloc] initWithHost:h userID:u isGroup:NO]; };
        t[@"notifications/group"] = ^UIViewController *(NSString *h, NSString *u) { return [[IMNotificationTypeViewController alloc] initWithHost:h userID:u isGroup:YES]; };
        t[@"notifications/private/sound"] = ^UIViewController *(NSString *h, NSString *u) { return [[IMNotificationSoundViewController alloc] initForGroup:NO]; };
        t[@"notifications/group/sound"] = ^UIViewController *(NSString *h, NSString *u) { return [[IMNotificationSoundViewController alloc] initForGroup:YES]; };
        t[@"privacy"] = ^UIViewController *(NSString *h, NSString *u) { return [[IMPrivacySecurityViewController alloc] initWithHost:h userID:u]; };
        t[@"privacy/blocked"] = ^UIViewController *(NSString *h, NSString *u) { return [[IMBlockedListViewController alloc] initWithHost:h userID:u]; };
        t[@"privacy/changePassword"] = ^UIViewController *(NSString *h, NSString *u) { return [[IMChangePasswordViewController alloc] initWithHost:h userID:u]; };
        t[@"storage"] = ^UIViewController *(NSString *h, NSString *u) { return [IMDataStorageViewController new]; };
        t[@"appearance"] = ^UIViewController *(NSString *h, NSString *u) { return [IMAppearanceViewController new]; };
        t[@"powerSaving"] = ^UIViewController *(NSString *h, NSString *u) { return [IMPowerSavingViewController new]; };
        t[@"language"] = ^UIViewController *(NSString *h, NSString *u) { return [IMLanguageViewController new]; };
        NSDictionary<NSString *, NSNumber *> *nets = @{ @"cellular": @(IMDownloadNetworkCellular), @"wifi": @(IMDownloadNetworkWifi) };
        NSDictionary<NSString *, NSNumber *> *cats = @{ @"image": @(IMDownloadCategoryImage), @"video": @(IMDownloadCategoryVideo),
                                                        @"file": @(IMDownloadCategoryFile) };
        for (NSString *net in nets) {
            IMDownloadNetworkKind netKind = (IMDownloadNetworkKind)nets[net].integerValue;
            t[[@"storage/" stringByAppendingString:net]] = ^UIViewController *(NSString *h, NSString *u) {
                return [[IMAutoDownloadNetworkViewController alloc] initWithNetwork:netKind];
            };
            for (NSString *cat in cats) {
                IMDownloadCategoryKind catKind = (IMDownloadCategoryKind)cats[cat].integerValue;
                t[[NSString stringWithFormat:@"storage/%@/%@", net, cat]] = ^UIViewController *(NSString *h, NSString *u) {
                    return [[IMAutoDownloadCategoryViewController alloc] initWithNetwork:netKind category:catKind];
                };
            }
        }
        table = t;
    });
    return table;
}

+ (BOOL)canBuildPageID:(NSString *)pageID { return [self builders][pageID] != nil; }

+ (NSArray<UIViewController *> *)viewControllersForRoute:(NSArray<NSString *> *)route host:(NSString *)host userID:(NSString *)userID {
    if (route.count == 0) { return nil; }
    NSMutableArray<UIViewController *> *out = [NSMutableArray array];
    for (NSString *pageID in route) {
        IMPageBuilder build = [self builders][pageID];
        if (!build) { return nil; }
        UIViewController *vc = build(host, userID);
        if (!vc) { return nil; }
        [out addObject:vc];
    }
    return out;
}

@end
