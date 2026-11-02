//  IMDataStorageViewController.m

#import "IMSessionTeardown.h"
#import "IMDataStorageViewController.h"
#import "IMAutoDownloadNetworkViewController.h"
#import "IMDownloadSettingsUI.h"
#import "IMDownloadSettingsStore.h"
#import "IMMediaUtil.h" // IMFormatFileSize
#import "IMImageLoader.h"
#import "IMViewedMediaStore.h"
#import "IMLog.h"
#import "IMLocalization.h"
#import "IMSettingsIcon.h"

@interface IMDataStorageViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation IMDataStorageViewController {
    int64_t _cacheBytes;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"ios.settings.row.data_storage");
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reloadTable)
                                               name:IMDownloadSettingsDidChangeNotification object:nil];
    [[IMDownloadSettingsStore shared] refresh]; // 打开即拉最新（多端同步）
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
    [self recomputeCacheSize];
}

- (void)reloadTable { [self.tableView reloadData]; }

#pragma mark - 缓存大小

- (nullable NSURL *)cachesRoot {
    return [NSFileManager.defaultManager URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask
                                       appropriateForURL:nil create:NO error:NULL];
}

/// 本 VC **自己删**的目录：下载文件 + 视频原件。图片缓存 `im_image_cache` 归 IMImageLoader 所有，
/// 只经它 `clearCache`（同时清内存 + 重置记账），不在这里直删——直删会与其 `_diskQueue` 抢同一目录。
- (NSArray<NSURL *> *)ownedCacheDirs { return IMSessionTeardown.ownedMediaCacheDirectories; } // 与注销账号清缓存共用同一份目录清单

/// 计**用量**的全部目录（含图片缓存）。少算一个就会「显示 0 B 却清出几百 MB」。
- (NSArray<NSURL *> *)sizeDirs {
    NSURL *caches = [self cachesRoot];
    if (!caches) { return @[]; }
    return [[self ownedCacheDirs] arrayByAddingObject:[caches URLByAppendingPathComponent:@"im_image_cache" isDirectory:YES]];
}

- (void)recomputeCacheSize {
    NSArray<NSURL *> *dirs = [self sizeDirs];
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        int64_t total = 0;
        for (NSURL *dir in dirs) {
            NSDirectoryEnumerator *en = [NSFileManager.defaultManager enumeratorAtURL:dir includingPropertiesForKeys:@[NSURLFileSizeKey]
                                                                              options:0 errorHandler:nil];
            for (NSURL *f in en) {
                NSNumber *size = nil;
                [f getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
                total += size.longLongValue;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            self->_cacheBytes = total;
            [self.tableView reloadData];
        });
    });
}

/// 只删本机文件，云端保留可重下——卡片会自动退回"未下载"态（草图 §08-03）。
- (void)clearCache {
    // 破坏性且不可撤销（本机文件全删、所有卡片退回"未下载"）→ 必须留痕，
    // 否则"我的图片怎么全没了/怎么又重下了一遍"无从追溯。
    IMLogWithTag(IMLogTagMedia, @"media_cache_cleared bytes=%lld", _cacheBytes);
    for (NSURL *dir in [self ownedCacheDirs]) { [NSFileManager.defaultManager removeItemAtURL:dir error:NULL]; }
    // 图片缓存交给 owner：连**内存**一起清（否则 hasCachedImageForURL 仍回 YES、图片退不回"未下载"）+ 重置记账。
    [[IMImageLoader shared] clearCache];
    // 「看过」登记一并清：回到没看过，门控按策略重判（与 Web `clearMediaCache` 同）
    [IMViewedMediaStore.shared clearCurrentUser];
    _cacheBytes = 0;
    [self.tableView reloadData];
}

#pragma mark - Table（对齐草图 §05：①存储用量 ②自动下载媒体文件[移动/Wi-Fi/重置]）

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : 3; // 0: 存储用量；1: 使用移动数据/Wi-Fi/重置
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 1 ? IMLocalized(@"autodl.master_switch") : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) { return IMLocalized(@"storage.footer.cache_hint"); }
    return IMLocalized(@"storage.footer.reset_hint");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // 存储用量：橙色图标块 + 右侧用量 + ›（草图 §05 第一行）。
    if (indexPath.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        cell.textLabel.text = IMLocalized(@"storage.row.usage");
        cell.detailTextLabel.text = _cacheBytes > 0 ? IMFormatFileSize(_cacheBytes) : @"0 KB";
        cell.imageView.image = IMSettingsIconImage(@"chart.pie.fill", UIColor.systemOrangeColor);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    IMDownloadSettings *s = [IMDownloadSettingsStore shared].settings;
    // 使用移动数据 / 使用 Wi-Fi：左图标块 + 标题 + 副标题（阈值汇总）+ ›（草图 §05 中段两行）。
    if (indexPath.row < 2) {
        IMDownloadNetworkKind net = indexPath.row == 0 ? IMDownloadNetworkCellular : IMDownloadNetworkWifi;
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        cell.textLabel.text = IMDownloadNetworkTitle(net);
        cell.detailTextLabel.text = IMNetworkSummary(IMPolicyForNetwork(s, net));
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.imageView.image = (net == IMDownloadNetworkCellular)
            ? IMSettingsIconImage(@"antenna.radiowaves.left.and.right", UIColor.systemGreenColor)
            : IMSettingsIconImage(@"wifi", UIColor.systemBlueColor);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    // 重置自动下载设置：蓝色动作行。用透明占位图占住行首图标位 → 标题与上方带图标行左对齐（草图 §05 蓝字行）。
    // 已是出厂默认（含刚点过重置）→ 无可重置：置灰 + 不可点。用户改动后自动恢复可点。
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    BOOL atDefault = [self settingsAtDefault];
    cell.textLabel.text = IMLocalized(@"storage.row.reset");
    cell.textLabel.textColor = atDefault ? UIColor.tertiaryLabelColor : cell.tintColor;
    cell.userInteractionEnabled = !atDefault;
    cell.imageView.image = IMSettingsIconSpacer();
    return cell;
}

/// 当前策略是否等于出厂默认（决定「重置」行是否可点）。
- (BOOL)settingsAtDefault {
    return [[IMDownloadSettingsStore shared].settings isEquivalentTo:[IMDownloadSettings defaultSettings]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) { [self confirmClearCache]; return; }
    if (indexPath.row < 2) {
        IMDownloadNetworkKind net = indexPath.row == 0 ? IMDownloadNetworkCellular : IMDownloadNetworkWifi;
        [self.navigationController pushViewController:[[IMAutoDownloadNetworkViewController alloc] initWithNetwork:net] animated:YES];
        return;
    }
    if ([self settingsAtDefault]) { return; } // 已是默认：无可重置（行也已置灰）
    [self confirmReset];
}

- (void)confirmClearCache {
    NSString *msg = _cacheBytes > 0 ? IMLocalizedFormat(@"storage.clear_confirm.message_with_size", IMFormatFileSize(_cacheBytes))
                                    : IMLocalized(@"storage.clear_confirm.message_empty");
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:IMLocalized(@"storage.clear_confirm.title") message:msg preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    if (_cacheBytes > 0) {
        __weak typeof(self) ws = self;
        [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.clear") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { [ws clearCache]; }]];
    }
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)confirmReset {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:IMLocalized(@"storage.row.reset")
        message:IMLocalized(@"storage.reset_confirm.message") preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.reset") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [[IMDownloadSettingsStore shared] resetToDefaults];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

@end
