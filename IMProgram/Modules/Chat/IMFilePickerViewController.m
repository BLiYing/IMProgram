//  IMFilePickerViewController.m

#import "IMFilePickerViewController.h"
#import "IMLog.h"
#import "IMMediaUtil.h"
#import "IMTheme.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface IMFilePickerViewController () <UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate>
@end

@implementation IMFilePickerViewController {
    NSMutableArray<NSDictionary *> *_recent;
    dispatch_block_t _onFromPhotos;
    void (^_onPickDocument)(NSURL *);
    void (^_onPickRecent)(NSString *, NSString *, int64_t);
    IMSentFilePageLoader _loadPage;
    BOOL _loading;
    BOOL _hasMore;
    BOOL _documentPickerPresented;
    UITableView *_tableView;
    NSURL *_pickedDocumentURL;
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
                      onPickDocument:(void (^)(NSURL *))onPickDocument
                        onPickRecent:(void (^)(NSString *, NSString *, int64_t))onPickRecent
                            loadPage:(IMSentFilePageLoader)loadPage {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _recent = [recentFiles mutableCopy] ?: [NSMutableArray array];
        _onFromPhotos = [onFromPhotos copy];
        _onPickDocument = [onPickDocument copy];
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
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeTapped)];
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [self.view addSubview:_tableView];
    [self loadNextPage:NO];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // UIDocumentPicker 自己负责关闭 File Provider 页面；等文件面板重新可见后再关闭面板，
    // 避免应用与系统同时 dismiss 导致 Files 的返回栈被截断。
    if (!_documentPickerPresented || self.presentedViewController) { return; }
    _documentPickerPresented = NO;
    NSURL *url = _pickedDocumentURL;
    if (!url) {
        IMLogUI(@"系统文件浏览器已关闭，返回文件面板");
        return;
    }
    _pickedDocumentURL = nil;
    void (^callback)(NSURL *) = _onPickDocument;
    [self dismissViewControllerAnimated:YES completion:^{
        if (callback) { callback(url); }
    }];
}

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

- (void)presentSystemDocumentPicker {
    if (_documentPickerPresented || self.presentedViewController) {
        IMLogUI(@"忽略重复的系统文件浏览器呈现请求");
        return;
    }
    UIDocumentPickerViewController *picker = [IMFilePickerViewController systemDocumentPicker];
    picker.delegate = self;
    _documentPickerPresented = YES;
    IMLogUI(@"打开系统文件浏览器：picker=%p，contentType=%@", picker, UTTypeItem.identifier);
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) { return; }
    IMLogUI(@"系统文件浏览器完成选择：picker=%p，count=%lu", controller, (unsigned long)urls.count);
    _pickedDocumentURL = [url copy];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    IMLogUI(@"系统文件浏览器取消选择：picker=%p", controller);
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
        if (ip.row == 0) {
            [self dismissThen:_onFromPhotos];
        } else {
            [self presentSystemDocumentPicker];
        }
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
