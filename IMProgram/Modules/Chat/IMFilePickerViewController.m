//  IMFilePickerViewController.m

#import "IMFilePickerViewController.h"
#import "IMMediaUtil.h"

@interface IMFilePickerViewController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation IMFilePickerViewController {
    NSMutableArray<NSDictionary *> *_recent;
    dispatch_block_t _onFromPhotos;
    dispatch_block_t _onFromFiles;
    void (^_onPickRecent)(NSString *, NSString *);
    IMSentFilePageLoader _loadPage;
    BOOL _loading;
    BOOL _hasMore;
    UITableView *_tableView;
}

- (instancetype)initWithRecentFiles:(NSArray<NSDictionary *> *)recentFiles
                        onFromPhotos:(dispatch_block_t)onFromPhotos
                         onFromFiles:(dispatch_block_t)onFromFiles
                        onPickRecent:(void (^)(NSString *, NSString *))onPickRecent
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
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeTapped)];
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"c"];
    [self.view addSubview:_tableView];
    [self loadNextPage:NO];
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

// section 0 = 入口两项；section 1 = 最近发送的文件
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return _recent.count > 0 ? 2 : 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 2 : (NSInteger)_recent.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 1 ? @"最近发送的文件" : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"c" forIndexPath:ip];
    cell.imageView.tintColor = self.view.tintColor;
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
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) {
        [self dismissThen:(ip.row == 0 ? _onFromPhotos : _onFromFiles)];
        return;
    }
    NSDictionary *f = _recent[(NSUInteger)ip.row];
    NSString *url = [f[@"url"] isKindOfClass:NSString.class] ? f[@"url"] : @"";
    NSString *name = [f[@"name"] isKindOfClass:NSString.class] ? f[@"name"] : @"";
    void (^cb)(NSString *, NSString *) = _onPickRecent;
    [self dismissViewControllerAnimated:YES completion:^{ if (cb && url.length) { cb(url, name); } }];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1 && indexPath.row >= (NSInteger)_recent.count - 5) {
        [self loadNextPage:YES];
    }
}

@end
