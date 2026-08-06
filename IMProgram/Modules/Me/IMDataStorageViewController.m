//  IMDataStorageViewController.m

#import "IMDataStorageViewController.h"
#import "IMAutoDownloadNetworkViewController.h"
#import "IMDownloadSettingsUI.h"
#import "IMDownloadSettingsStore.h"
#import "IMMediaUtil.h" // IMFormatFileSize
#import "IMImageLoader.h"
#import "IMLog.h"

static const CGFloat kIMSettingsIconSide = 29;

/// iOS 设置风格的彩色圆角图标块（白色 SF Symbol + 品牌底色）渲染成 UIImage，供 cell.imageView 放在**左侧**，
/// 对齐草图 §05 每行左侧图标。渲染成图而非用 accessoryView，才能落在 iOS 原生的行首图标位。
/// **按 symbol 记忆化**：全页图标固定，避免每次 cellForRow / reloadData 重复光栅化。
static UIImage *IMSettingsIconImage(NSString *symbol, UIColor *bg) {
    static NSMutableDictionary<NSString *, UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
    UIImage *cached = cache[symbol];
    if (cached) { return cached; }
    CGFloat side = kIMSettingsIconSide;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        UIBezierPath *tile = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:7];
        [bg setFill];
        [tile fill];
        UIImage *glyph = [[UIImage systemImageNamed:symbol
                                  withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]]
                          imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        CGSize g = glyph.size;
        [glyph drawInRect:CGRectMake((side - g.width) / 2, (side - g.height) / 2, g.width, g.height)];
    }];
    cache[symbol] = img;
    return img;
}

/// 与图标块同尺寸的**透明占位图**：给无图标的行（如「重置」）占住行首图标位，标题与上方带图标的行左对齐（草图 §05）。
static UIImage *IMSettingsIconSpacer(void) {
    static UIImage *spacer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(kIMSettingsIconSide, kIMSettingsIconSide)];
        spacer = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {}]; // 全透明
    });
    return spacer;
}

@interface IMDataStorageViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation IMDataStorageViewController {
    int64_t _cacheBytes;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"数据和存储";
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
- (NSArray<NSURL *> *)ownedCacheDirs {
    NSURL *caches = [self cachesRoot];
    if (!caches) { return @[]; }
    return @[[caches URLByAppendingPathComponent:@"IMDownloads" isDirectory:YES],
             [caches URLByAppendingPathComponent:@"im_original_videos" isDirectory:YES]];
}

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
    _cacheBytes = 0;
    [self.tableView reloadData];
}

#pragma mark - Table（对齐草图 §05：①存储用量 ②自动下载媒体文件[移动/Wi-Fi/重置]）

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : 3; // 0: 存储用量；1: 使用移动数据/Wi-Fi/重置
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 1 ? @"自动下载媒体文件" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) { return @"下载的文件缓存在本机；清除后云端仍保留，需要时可重新下载。"; }
    return @"“重置”会把两个网络都恢复为出厂默认（移动数据中档、Wi-Fi 高档）。语音消息占用小，始终自动下载。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // 存储用量：橙色图标块 + 右侧用量 + ›（草图 §05 第一行）。
    if (indexPath.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        cell.textLabel.text = @"存储用量";
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
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = @"重置自动下载设置";
    cell.textLabel.textColor = cell.tintColor;
    cell.imageView.image = IMSettingsIconSpacer();
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
