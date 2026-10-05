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
///
/// 【重复构造点】tap 路径里各父 VC 自己 push 时也在构造同一批页面，两处必须保持一致（类与构造参数）：
///   IMSettingsViewController            saved / recentCalls / devices / notifications / privacy / storage / appearance / powerSaving / language
///   IMNotificationSettingsViewController notifications/private|group      → IMNotificationTypeViewController(isGroup)
///   IMNotificationTypeViewController     notifications/{private|group}/sound → IMNotificationSoundViewController(initForGroup:)
///   IMPrivacySecurityViewController     privacy/blocked / privacy/changePassword
///   IMDataStorageViewController         storage/{cellular|wifi}           → IMAutoDownloadNetworkViewController(network)
///   IMAutoDownloadNetworkViewController storage/{net}/{image|video|file}  → IMAutoDownloadCategoryViewController(network, category)
/// 没有抽成「父 VC 暴露工厂」：这些构造都是一行 init，抽工厂要改 6 个 VC 的 ~17 处 push 点且各自参数来源不同，收益小于风险；
/// 改用本表集中 + `IMSettingsRouterTests` 钉住 id→页面类型。新增/改动任一页面的构造时，同步改这里与该测试。
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

/// 纯动作行（不 push 页面）。目前只有「分享我的名片」。
+ (BOOL)isActionRoute:(NSArray<NSString *> *)route {
    return route.count == 1 && [route.firstObject isEqualToString:@"shareMyCard"];
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
