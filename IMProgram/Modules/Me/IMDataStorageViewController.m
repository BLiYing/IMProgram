//  IMDataStorageViewController.m

#import "IMDataStorageViewController.h"
#import "IMAutoDownloadNetworkViewController.h"
#import "IMDownloadSettingsUI.h"
#import "IMDownloadSettingsStore.h"
#import "IMMediaDownloader.h"
#import "IMMediaUtil.h" // IMFormatFileSize
#import "IMImageLoader.h"
#import "IMLog.h"

@implementation IMDataStorageViewController {
    int64_t _cacheBytes;
}

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"数据和存储";
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

/// 本机媒体缓存的**全部**落地目录。少算一个就会出现「显示 0 B 却清出几百 MB」/「清了还在」：
///   - `IMDownloads`         下载的文件（IMMediaDownloader）
///   - `im_original_videos`  视频原件（整段预取 + 查看器「查看原视频」+ 自己发的视频收编）
///   - `im_image_cache`      图片磁盘缓存（IMImageLoader，冷启动免重下）
- (NSArray<NSURL *> *)cacheDirs {
    NSURL *caches = [NSFileManager.defaultManager URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask
                                               appropriateForURL:nil create:NO error:NULL];
    if (!caches) { return @[]; }
    return @[[caches URLByAppendingPathComponent:@"IMDownloads" isDirectory:YES],
             [caches URLByAppendingPathComponent:@"im_original_videos" isDirectory:YES],
             [caches URLByAppendingPathComponent:@"im_image_cache" isDirectory:YES]];
}

- (void)recomputeCacheSize {
    NSArray<NSURL *> *dirs = [self cacheDirs];
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
    IMLogWithTag(IMLogTagMedia, @"media_cache_cleared bytes=%lld dirs=%lu",
                 _cacheBytes, (unsigned long)[self cacheDirs].count);
    for (NSURL *dir in [self cacheDirs]) { [NSFileManager.defaultManager removeItemAtURL:dir error:NULL]; }
    [[IMImageLoader shared] clearCache]; // 连**内存**缓存一起清，否则图片卡片退不回"未下载"（且记账值会漂）
    _cacheBytes = 0;
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : 3; // 0: 存储用量；1: 使用移动数据/Wi-Fi/重置
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 1 ? @"自动下载媒体文件" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? @"下载的文件缓存在本机；清除后云端仍保留，需要时可重新下载。" : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        cell.textLabel.text = @"存储用量";
        cell.detailTextLabel.text = _cacheBytes > 0 ? IMFormatFileSize(_cacheBytes) : @"0 KB";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    IMDownloadSettings *s = [IMDownloadSettingsStore shared].settings;
    if (indexPath.row < 2) {
        IMDownloadNetworkKind net = indexPath.row == 0 ? IMDownloadNetworkCellular : IMDownloadNetworkWifi;
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        cell.textLabel.text = IMDownloadNetworkTitle(net);
        cell.detailTextLabel.text = IMNetworkSummary(IMPolicyForNetwork(s, net));
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = @"重置自动下载设置";
    cell.textLabel.textColor = cell.tintColor; // 蓝色动作行
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) { [self confirmClearCache]; return; }
    if (indexPath.row < 2) {
        IMDownloadNetworkKind net = indexPath.row == 0 ? IMDownloadNetworkCellular : IMDownloadNetworkWifi;
        [self.navigationController pushViewController:[[IMAutoDownloadNetworkViewController alloc] initWithNetwork:net] animated:YES];
        return;
    }
    [self confirmReset];
}

- (void)confirmClearCache {
    NSString *msg = _cacheBytes > 0 ? [NSString stringWithFormat:@"将删除本机缓存的 %@ 下载文件，云端保留可重新下载。", IMFormatFileSize(_cacheBytes)]
                                    : @"暂无可清除的缓存。";
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"清除缓存" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (_cacheBytes > 0) {
        __weak typeof(self) ws = self;
        [ac addAction:[UIAlertAction actionWithTitle:@"清除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { [ws clearCache]; }]];
    }
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)confirmReset {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"重置自动下载设置"
        message:@"恢复为出厂默认（移动数据中档、Wi-Fi 高档）。" preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"重置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [[IMDownloadSettingsStore shared] resetToDefaults];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

@end
