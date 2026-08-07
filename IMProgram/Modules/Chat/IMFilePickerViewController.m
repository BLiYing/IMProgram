//  IMFilePickerViewController.m

#import "IMFilePickerViewController.h"
#import "IMMediaUtil.h"
#import "IMTheme.h"
#import "IMMainTabBarController.h" // kIMLiquidBarHeight
#import "IMProgram-Swift.h"        // IMLiquidNavigationBar（自持沉浸式标题栏）

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface IMFilePickerViewController () <UITableViewDataSource, UITableViewDelegate, IMLiquidNavigationBarDelegate>
@end

@implementation IMFilePickerViewController {
    NSMutableArray<NSDictionary *> *_recent;
    dispatch_block_t _onFromPhotos;
    dispatch_block_t _onFromFiles;
    void (^_onPickRecent)(NSString *, NSString *, int64_t);
    IMSentFilePageLoader _loadPage;
    BOOL _loading;
    BOOL _hasMore;
    UITableView *_tableView;
}

+ (UIDocumentPickerViewController *)systemDocumentPicker {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    picker.allowsMultipleSelection = NO;
    picker.shouldShowFileExtensions = YES;
    // File Provider 的 DOCRemote… 页面和返回栈由系统维护。全屏且由稳定的文件面板直接呈现，
    // 避免先 dismiss 面板再跨 modal 重建 picker。
    picker.modalPresentationStyle = UIModalPresentationFullScreen;
    return picker;
}

- (instancetype)initWithRecentFiles:(NSArray<NSDictionary *> *)recentFiles
                        onFromPhotos:(dispatch_block_t)onFromPhotos
                         onFromFiles:(dispatch_block_t)onFromFiles
                        onPickRecent:(void (^)(NSString *, NSString *, int64_t))onPickRecent
                            loadPage:(IMSentFilePageLoader)loadPage {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _recent = [recentFiles mutableCopy] ?: [NSMutableArray array];
        _onFromPhotos = [onFromPhotos copy];
        _onFromFiles = [onFromFiles copy];
        _onPickRecent = [onPickRecent copy];
        _loadPage = [loadPage copy];
        _hasMore = YES;
        if (@available(iOS 15.0, *)) {
            self.modalPresentationStyle = UIModalPresentationPageSheet;
            self.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                                                         UISheetPresentationControllerDetent.largeDetent];
            self.sheetPresentationController.prefersGrabberVisible = YES;
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"文件";
    self.view.backgroundColor = IMTheme.pageBackground;
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [self.view addSubview:_tableView];
    [self installLiquidNavigationBar];
    [self loadNextPage:NO];
}

/// 自持沉浸式标题栏（方案 A）：本卡片以模态 sheet 呈现、不经导航容器注入，故照详情/设置页做法
/// 自己挂一条 IMLiquidNavigationBar——撑 56pt 安全区给内容让位，栏用 hostExtraTopInset 还原 sheet
/// 顶部真实位置。左上角关闭改用统一 Liquid Glass 圆钮（xmark），尺寸/材质与全局返回按钮一致。
- (void)installLiquidNavigationBar {
    UIEdgeInsets insets = self.additionalSafeAreaInsets;
    insets.top = kIMLiquidBarHeight;
    self.additionalSafeAreaInsets = insets;

    IMLiquidNavigationBar *bar = [[IMLiquidNavigationBar alloc] initWithTitle:self.title subtitle:@"" actionTitle:nil];
    bar.delegate = self;
    bar.hostExtraTopInset = kIMLiquidBarHeight;
    bar.leftImage = [UIImage systemImageNamed:@"xmark"
                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17
                                                                                              weight:UIImageSymbolWeightSemibold]];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    ]];
}

#pragma mark - IMLiquidNavigationBarDelegate

// 关闭：左侧 xmark（leftImage 非空 → 组件走 DidTapLeft）。DidTapBack 兜底同样关闭。
- (void)liquidNavigationBarDidTapLeft:(IMLiquidNavigationBar *)bar { [self closeTapped]; }
- (void)liquidNavigationBarDidTapBack:(IMLiquidNavigationBar *)bar { [self closeTapped]; }
- (void)liquidNavigationBarDidTapAction:(IMLiquidNavigationBar *)bar { /* 无右侧操作 */ }

- (void)loadNextPage:(BOOL)nextPage {
    if (_loading || !_loadPage || (nextPage && !_hasMore)) { return; }
    _loading = YES;
    __weak typeof(self) ws = self;
    _loadPage(nextPage, ^(NSArray<NSDictionary *> *files, BOOL hasMore, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        self->_loading = NO;
        if (error) {
            self->_hasMore = NO; // 离线时静默保留 SQLite 缓存，避免滚动反复请求
            return;
        }
        self->_hasMore = hasMore;
        if (!nextPage) { [self->_recent removeAllObjects]; }
        NSMutableSet<NSString *> *known = [NSMutableSet set];
        for (NSDictionary *item in self->_recent) {
            NSString *serverID = [item[@"server_msg_id"] isKindOfClass:NSString.class] ? item[@"server_msg_id"] : @"";
            if (serverID.length > 0) { [known addObject:serverID]; }
        }
        for (NSDictionary *item in files ?: @[]) {
            NSString *serverID = [item[@"server_msg_id"] isKindOfClass:NSString.class] ? item[@"server_msg_id"] : @"";
            if (serverID.length == 0 || [known containsObject:serverID]) { continue; }
            [known addObject:serverID];
            [self->_recent addObject:item];
        }
        [self->_tableView reloadData];
    });
}

- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)dismissThen:(dispatch_block_t)then {
    [self dismissViewControllerAnimated:YES completion:^{ if (then) { then(); } }];
}

// section 0 = 入口两项；section 1 = 最近发送的文件
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return _recent.count > 0 ? 2 : 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 2 : (NSInteger)_recent.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 1 ? @"最近发送的文件" : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) { cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"]; }
    cell.imageView.tintColor = self.view.tintColor;
    cell.detailTextLabel.text = nil;
    if (ip.section == 0) {
        if (ip.row == 0) {
            cell.textLabel.text = @"从相册中选择";
            cell.imageView.image = [UIImage systemImageNamed:@"photo.on.rectangle"];
        } else {
            cell.textLabel.text = @"从文件中选择";
            cell.imageView.image = [UIImage systemImageNamed:@"folder"];
        }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        NSDictionary *f = _recent[(NSUInteger)ip.row];
        cell.textLabel.text = [f[@"name"] isKindOfClass:NSString.class] ? f[@"name"] : @"文件";
        cell.textLabel.numberOfLines = 1;
        // 文件名尾部是扩展名，长名字中间截断更可读（与详情页文件列表一致，保留后缀可见）。
        cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        cell.imageView.image = IMFileTypeIconForName(cell.textLabel.text, 34);
        NSString *size = IMFormatFileSize([f[@"size"] longLongValue]);
        NSString *dateTime = IMFormatFileDateTime([f[@"timestamp"] longLongValue]);
        if (size.length > 0 && dateTime.length > 0) {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", size, dateTime];
        } else {
            cell.detailTextLabel.text = size.length > 0 ? size : dateTime;
        }
        cell.detailTextLabel.textColor = IMTheme.textSecondary;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) {
        // 两个入口都先关闭本面板，再由聊天页承载后续选择器——
        // 系统文件浏览器直接盖在聊天页上，点叉叉/选完都直接回聊天页，不回落本面板。
        [self dismissThen:(ip.row == 0 ? _onFromPhotos : _onFromFiles)];
        return;
    }
    NSDictionary *f = _recent[(NSUInteger)ip.row];
    NSString *url = [f[@"url"] isKindOfClass:NSString.class] ? f[@"url"] : @"";
    NSString *name = [f[@"name"] isKindOfClass:NSString.class] ? f[@"name"] : @"";
    int64_t size = [f[@"size"] longLongValue];
    void (^cb)(NSString *, NSString *, int64_t) = _onPickRecent;
    [self dismissViewControllerAnimated:YES completion:^{ if (cb && url.length) { cb(url, name, size); } }];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1 && indexPath.row >= (NSInteger)_recent.count - 5) {
        [self loadNextPage:YES];
    }
}

@end
