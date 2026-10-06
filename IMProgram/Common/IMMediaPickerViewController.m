//  IMMediaPickerViewController.m

#import "IMMediaPickerViewController.h"
#import <PhotosUI/PhotosUI.h>
#import "IMMediaPicker.h"
#import "IMMediaPickLogic.h"
#import "IMMediaPickSession.h"
#import "IMMediaPickerBars.h"
#import "IMMediaPickerBucketSheet.h"
#import "IMMediaPickerCell.h"
#import "IMMediaPickerPhotos.h"
#import "IMMediaPreviewViewController.h"
#import "IMLocalization.h"
#import "IMLog.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"

static const CGFloat kGridGap = 2;           // Android GAP = 2dp
static NSString * const kCellID = @"tile";
static const NSTimeInterval kLibraryReloadDebounce = 0.3;

typedef NS_ENUM(NSInteger, IMMediaPickerEmptyMode) {
    IMMediaPickerEmptyNone,
    IMMediaPickerEmptyDenied,     ///< 拒绝 / 受限：说明 + 去设置
    IMMediaPickerEmptyNoAssets,   ///< 授权了但相册里没有照片
    IMMediaPickerEmptyLimited,    ///< 有限访问且授权集合为空：说明 + 管理授权的照片
};

@interface IMMediaPickerViewController () <UICollectionViewDataSource, UICollectionViewDelegate,
                                           UICollectionViewDataSourcePrefetching, PHPhotoLibraryChangeObserver>
@end

@implementation IMMediaPickerViewController {
    IMMediaPickSession *_session;
    IMMediaPickerTopBar *_topBar;
    IMMediaPickerBottomBar *_bottomBar;
    UICollectionView *_collection;
    UICollectionViewFlowLayout *_layout;
    UIView *_content;                    // 顶栏与底栏之间：宫格 / 空状态 / 相册面板的容器
    UIStackView *_emptyView;
    UILabel *_emptyLabel;
    UIButton *_emptyButton;
    IMMediaPickerBucketSheet *_sheet;

    NSArray<IMMediaPickBucket *> *_buckets;
    NSString *_bucketID;
    PHFetchResult<PHAsset *> *_assets;
    PHAuthorizationStatus _status;
    CGSize _thumbSize;                   // 像素
    BOOL _requestingAccess;
    BOOL _observing;
    BOOL _reloadPending;
    BOOL _finished;                      // 已回调过 onFinish：发送钮连点 / 取消与发送并发不得回调两次（会把整批媒体发两遍）
    NSUInteger _bucketsGeneration;       // 相册列表重载代次：后台加载乱序返回时，只认最新一次
    dispatch_queue_t _sizeQueue;
}

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        _session = [IMMediaPickSession new];
        _buckets = @[];
        _bucketID = kIMMediaPickAllBucketID;
        _status = PHAuthorizationStatusNotDetermined;
        _sizeQueue = dispatch_queue_create("im.media.picker.size", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    if (_observing) { [PHPhotoLibrary.sharedPhotoLibrary unregisterChangeObserver:self]; }
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [IMMediaPickerPhotos.cachingManager stopCachingImagesForAllAssets];
}

#pragma mark - 视图

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = IMTheme.pageBackground;
    [self buildBars];
    [self buildGrid];
    [self buildEmptyView];
    [self refreshChrome];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appDidBecomeActive)
                                               name:UIApplicationDidBecomeActiveNotification object:nil];
    [self reloadAccess];
}

- (void)buildBars {
    __weak typeof(self) ws = self;
    _topBar = [IMMediaPickerTopBar new];
    _topBar.translatesAutoresizingMaskIntoConstraints = NO;
    _topBar.onCancel = ^{ [ws finishWithAssets:@[]]; };
    _topBar.onTitleTap = ^{ [ws toggleSheet]; };
    [self.view addSubview:_topBar];

    _bottomBar = [[IMMediaPickerBottomBar alloc] initWithDarkStyle:NO];
    _bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
    _bottomBar.onPreview = ^{ [ws openSelectedPreview]; };
    _bottomBar.onOriginalToggle = ^{ [ws toggleOriginal]; };
    _bottomBar.onSend = ^{ [ws send]; };
    _bottomBar.onManageAccess = ^{ [ws manageLimitedAccess]; };
    [self.view addSubview:_bottomBar];

    _content = [UIView new];
    _content.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view insertSubview:_content atIndex:0];
    [NSLayoutConstraint activateConstraints:@[
        [_topBar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_topBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_topBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_bottomBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_content.topAnchor constraintEqualToAnchor:_topBar.bottomAnchor],
        [_content.bottomAnchor constraintEqualToAnchor:_bottomBar.topAnchor],
        [_content.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_content.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)buildGrid {
    _layout = [UICollectionViewFlowLayout new];
    _layout.minimumInteritemSpacing = kGridGap;
    _layout.minimumLineSpacing = kGridGap;
    _layout.sectionInset = UIEdgeInsetsMake(kGridGap, kGridGap, kGridGap, kGridGap);
    _collection = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:_layout];
    _collection.backgroundColor = IMTheme.pageBackground;
    _collection.dataSource = self;
    _collection.delegate = self;
    _collection.prefetchDataSource = self;
    _collection.alwaysBounceVertical = YES;
    [_collection registerClass:IMMediaPickerCell.class forCellWithReuseIdentifier:kCellID];
    _collection.translatesAutoresizingMaskIntoConstraints = NO;
    [_content addSubview:_collection];
    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                        action:@selector(longPressed:)];
    [_collection addGestureRecognizer:press];
    [self pinToContent:_collection];
}

- (void)buildEmptyView {
    _emptyLabel = [UILabel new];
    _emptyLabel.font = [UIFont systemFontOfSize:15];
    _emptyLabel.textColor = IMTheme.textSecondary;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.numberOfLines = 0;
    _emptyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _emptyButton.titleLabel.font = [UIFont systemFontOfSize:15];
    _emptyButton.tintColor = IMTheme.accent;
    [_emptyButton addTarget:self action:@selector(emptyButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    _emptyView = [[UIStackView alloc] initWithArrangedSubviews:@[_emptyLabel, _emptyButton]];
    _emptyView.axis = UILayoutConstraintAxisVertical;
    _emptyView.alignment = UIStackViewAlignmentCenter;
    _emptyView.spacing = 12;
    _emptyView.hidden = YES;
    _emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    [_content addSubview:_emptyView];
    [NSLayoutConstraint activateConstraints:@[
        [_emptyView.centerYAnchor constraintEqualToAnchor:_content.centerYAnchor],
        [_emptyView.leadingAnchor constraintEqualToAnchor:_content.leadingAnchor constant:16],
        [_emptyView.trailingAnchor constraintEqualToAnchor:_content.trailingAnchor constant:-16],
    ]];
}

- (void)pinToContent:(UIView *)v {
    [NSLayoutConstraint activateConstraints:@[
        [v.topAnchor constraintEqualToAnchor:_content.topAnchor],
        [v.bottomAnchor constraintEqualToAnchor:_content.bottomAnchor],
        [v.leadingAnchor constraintEqualToAnchor:_content.leadingAnchor],
        [v.trailingAnchor constraintEqualToAnchor:_content.trailingAnchor],
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(_collection.bounds);
    if (width <= 0) { return; }
    NSInteger cols = [IMMediaPickLogic columnCountForWidth:width];
    CGFloat side = floor((width - kGridGap * (cols + 1)) / cols);
    if (side != _layout.itemSize.width) {
        _layout.itemSize = CGSizeMake(side, side);
        CGFloat scale = UIScreen.mainScreen.scale;
        _thumbSize = CGSizeMake(side * scale, side * scale);
        [_layout invalidateLayout];
    }
}

#pragma mark - 权限三态

- (void)appDidBecomeActive {
    // 从「设置」回来：状态变了就重走一遍，用户不必再点一次。
    if ([IMMediaPickerPhotos authorizationStatus] != _status) { [self reloadAccess]; }
}

- (void)reloadAccess {
    PHAuthorizationStatus status = [IMMediaPickerPhotos authorizationStatus];
    _status = status;
    if (status == PHAuthorizationStatusNotDetermined) {
        if (_requestingAccess) { return; }
        _requestingAccess = YES;
        [self showEmptyMode:IMMediaPickerEmptyNone]; // 授权前页面空白，不闪现空状态文案
        __weak typeof(self) ws = self;
        [IMMediaPickerPhotos requestAuthorization:^(PHAuthorizationStatus granted) {
            __strong typeof(ws) self_ = ws;
            if (!self_) { return; }
            self_->_requestingAccess = NO;
            [self_ reloadAccess];
        }];
        return;
    }
    BOOL canBrowse = status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited;
    if (!canBrowse) {
        // 拒绝 / 受限：同一页面的空状态，没有任何降级退路（拍摄与文件入口仍在 ➕ 面板）。
        _bucketsGeneration++; // 在途的相册加载作废，别在被拒空状态之上又把宫格盖回来
        _buckets = @[];
        _assets = nil;
        [_collection reloadData];
        [self showEmptyMode:IMMediaPickerEmptyDenied];
        [self refreshChrome];
        return;
    }
    if (!_observing) {
        [PHPhotoLibrary.sharedPhotoLibrary registerChangeObserver:self];
        _observing = YES;
    }
    [self reloadBuckets];
}

- (void)reloadBuckets {
    NSString *all = IMLocalized(@"media.picker.all");
    NSString *unnamed = IMLocalized(@"media.picker.unnamed");
    __weak typeof(self) ws = self;
    NSUInteger generation = ++_bucketsGeneration;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<IMMediaPickBucket *> *buckets = [IMMediaPickerPhotos loadBucketsWithAllTitle:all unnamedTitle:unnamed];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) self_ = ws;
            if (!self_ || generation != self_->_bucketsGeneration) { return; } // 更新的一次已发起，丢弃过期结果
            [self_ applyBuckets:buckets];
        });
    });
}

- (void)applyBuckets:(NSArray<IMMediaPickBucket *> *)buckets {
    _buckets = buckets;
    // 选中的照片可能刚在系统相册里被删 / 在「管理」里被取消授权：不剔掉的话底栏数字、上限计数与实际发送数对不上。
    [_session pruneUnavailableSelection];
    IMMediaPickBucket *current = [self bucketWithID:_bucketID] ?: buckets.firstObject;
    _bucketID = current.bucketID ?: kIMMediaPickAllBucketID;
    _assets = current.assets;
    [IMMediaPickerPhotos.cachingManager stopCachingImagesForAllAssets];
    [_collection reloadData]; // 不重置滚动位置：相册内容变化（拍了新照片 / 「管理」改选）时用户不该被甩回顶部
    if (_assets.count == 0) {
        [self showEmptyMode:(_status == PHAuthorizationStatusLimited ? IMMediaPickerEmptyLimited : IMMediaPickerEmptyNoAssets)];
    } else {
        [self showEmptyMode:IMMediaPickerEmptyNone];
    }
    [self refreshChrome];
}

- (nullable IMMediaPickBucket *)bucketWithID:(NSString *)bucketID {
    for (IMMediaPickBucket *b in _buckets) { if ([b.bucketID isEqualToString:bucketID]) { return b; } }
    return nil;
}

- (void)showEmptyMode:(IMMediaPickerEmptyMode)mode {
    _emptyView.hidden = mode == IMMediaPickerEmptyNone;
    _collection.hidden = mode != IMMediaPickerEmptyNone;
    _emptyButton.tag = mode;
    switch (mode) {
        case IMMediaPickerEmptyDenied:
            _emptyLabel.text = IMLocalized(@"media.picker.denied");
            [_emptyButton setTitle:IMLocalized(@"media.picker.go_settings") forState:UIControlStateNormal];
            _emptyButton.hidden = NO;
            break;
        case IMMediaPickerEmptyLimited:
            _emptyLabel.text = IMLocalized(@"media.picker.empty_partial");
            [_emptyButton setTitle:IMLocalized(@"media.picker.manage_access") forState:UIControlStateNormal];
            _emptyButton.hidden = NO;
            break;
        case IMMediaPickerEmptyNoAssets:
            _emptyLabel.text = IMLocalized(@"media.picker.empty");
            _emptyButton.hidden = YES;
            break;
        case IMMediaPickerEmptyNone:
            break;
    }
}

- (void)emptyButtonTapped {
    if (_emptyButton.tag == IMMediaPickerEmptyDenied) {
        NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
        if (url) { [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil]; }
    } else {
        [self manageLimitedAccess];
    }
}

- (void)manageLimitedAccess {
    [PHPhotoLibrary.sharedPhotoLibrary presentLimitedLibraryPickerFromViewController:self];
}

#pragma mark PHPhotoLibraryChangeObserver

- (void)photoLibraryDidChange:(PHChange *)changeInstance {
    // 在任意线程回调：合并抖动后回主线程重取（「管理授权的照片」改选后也走这条）。
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_reloadPending) { return; }
        self->_reloadPending = YES;
        __weak typeof(self) ws = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kLibraryReloadDebounce * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(ws) self_ = ws;
            if (!self_) { return; }
            self_->_reloadPending = NO;
            [self_ reloadAccess];
        });
    });
}

#pragma mark - 顶栏 / 底栏 / 相册面板

- (void)refreshChrome {
    IMMediaPickBucket *current = [self bucketWithID:_bucketID];
    NSString *title = current.title ?: IMLocalized(@"media.picker.all");
    [_topBar setTitle:title canSwitch:_buckets.count > 1 expanded:_sheet.superview != nil];
    [_bottomBar updateWithSelectedCount:(NSInteger)_session.selectedIDs.count
                             originalOn:_session.sendOriginal
                             totalBytes:_session.totalBytes
                            showsBanner:_status == PHAuthorizationStatusLimited];
}

- (void)toggleSheet {
    if (_sheet.superview) { [self hideSheet]; return; }
    if (_buckets.count < 2) { return; }
    __weak typeof(self) ws = self;
    _sheet = [[IMMediaPickerBucketSheet alloc] initWithFrame:CGRectZero];
    _sheet.translatesAutoresizingMaskIntoConstraints = NO;
    [_sheet setBuckets:_buckets];
    _sheet.onDismiss = ^{ [ws hideSheet]; };
    _sheet.onPick = ^(NSString *bucketID) { [ws selectBucket:bucketID]; };
    [_content addSubview:_sheet];
    [self pinToContent:_sheet];
    [self refreshChrome];
}

- (void)hideSheet {
    [_sheet removeFromSuperview];
    _sheet = nil;
    [self refreshChrome];
}

- (void)selectBucket:(NSString *)bucketID {
    [self hideSheet];
    IMMediaPickBucket *b = [self bucketWithID:bucketID];
    if (!b) { return; }
    _bucketID = bucketID;
    _assets = b.assets;
    [IMMediaPickerPhotos.cachingManager stopCachingImagesForAllAssets];
    [_collection reloadData];
    [_collection setContentOffset:CGPointZero animated:NO];
    [self refreshChrome];
}

#pragma mark - 选择

- (void)toggleOriginal {
    _session.sendOriginal = !_session.sendOriginal;
    [self refreshChrome];
}

- (void)toggleAsset:(PHAsset *)asset {
    if (![_session isSelectableAsset:asset]) {
        long long size = [_session sizeBytesOfAsset:asset];
        [self im_showToast:[IMMediaPickLogic isTooLargeWithSizeBytes:size]
            ? IMLocalizedFormat(@"media.picker.too_large", [IMMediaPickLogic sizeLabelForBytes:kIMMaxVideoBytes])
            : IMLocalized(@"media.picker.unreadable")];
        return;
    }
    if (![_session toggleAsset:asset]) {
        [self im_showToast:IMLocalizedFormat(@"media.picker.limit", (long)kIMMediaPickLimit)];
        return;
    }
    [self refreshSelectionUI];
}

/// 选中变化后：可见格重画（取消中间一张后后面的编号要顺延）+ 底栏。
- (void)refreshSelectionUI {
    for (IMMediaPickerCell *cell in _collection.visibleCells) {
        NSIndexPath *ip = [_collection indexPathForCell:cell];
        if (ip && ip.item < (NSInteger)_assets.count) { [self configureCell:cell asset:_assets[ip.item]]; }
    }
    [self refreshChrome];
}

- (void)send {
    NSArray<PHAsset *> *assets = _session.orderedAssets;
    [self finishWithAssets:assets];
}

- (void)finishWithAssets:(NSArray<PHAsset *> *)assets {
    if (_finished) { return; }
    _finished = YES;
    if (self.onFinish) { self.onFinish(assets, _session.sendOriginal); }
}

#pragma mark - 预览

- (void)longPressed:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) { return; }
    NSIndexPath *ip = [_collection indexPathForItemAtPoint:[g locationInView:_collection]];
    if (!ip || ip.item >= (NSInteger)_assets.count) { return; }
    PHFetchResult<PHAsset *> *assets = _assets;
    [self presentPreviewWithCount:(NSInteger)assets.count start:ip.item assetAtIndex:^PHAsset *(NSInteger i) { return assets[i]; }];
}

- (void)openSelectedPreview {
    NSArray<PHAsset *> *chosen = _session.orderedAssets;
    if (chosen.count == 0) { return; }
    [self presentPreviewWithCount:(NSInteger)chosen.count start:0 assetAtIndex:^PHAsset *(NSInteger i) { return chosen[i]; }];
}

- (void)presentPreviewWithCount:(NSInteger)count start:(NSInteger)start
                   assetAtIndex:(PHAsset *(^)(NSInteger index))provider {
    IMMediaPreviewViewController *preview = [[IMMediaPreviewViewController alloc] initWithSession:_session
                                                                                            count:count
                                                                                       startIndex:start
                                                                                     assetAtIndex:provider];
    __weak typeof(self) ws = self;
    __weak IMMediaPreviewViewController *weakPreview = preview;
    preview.onSelectionChanged = ^{ [ws refreshSelectionUI]; };
    preview.onClose = ^{ [weakPreview dismissViewControllerAnimated:YES completion:nil]; };
    preview.onSend = ^{
        [weakPreview dismissViewControllerAnimated:NO completion:nil];
        [ws send];
    };
    [self presentViewController:preview animated:YES completion:nil];
}

#pragma mark - UICollectionView

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)_assets.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    IMMediaPickerCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kCellID forIndexPath:indexPath];
    PHAsset *asset = _assets[indexPath.item];
    if (cell.imageRequestID != PHInvalidImageRequestID) {
        [IMMediaPickerPhotos.cachingManager cancelImageRequest:cell.imageRequestID];
    }
    cell.assetID = asset.localIdentifier;
    [self configureCell:cell asset:asset];
    __weak IMMediaPickerCell *weakCell = cell;
    NSString *assetID = asset.localIdentifier;
    cell.imageRequestID = [IMMediaPickerPhotos.cachingManager requestImageForAsset:asset targetSize:_thumbSize
        contentMode:PHImageContentModeAspectFill options:IMMediaPickerPhotos.thumbnailOptions
        resultHandler:^(UIImage *image, NSDictionary *info) {
        // image 为空 = 请求被取消 / 失败：别把已有的低清图擦掉
        if (image && [weakCell.assetID isEqualToString:assetID]) { [weakCell setThumbnail:image]; }
    }];
    [self loadSizeIfNeededForAsset:asset];
    return cell;
}

- (void)configureCell:(IMMediaPickerCell *)cell asset:(PHAsset *)asset {
    BOOL isVideo = asset.mediaType == PHAssetMediaTypeVideo;
    [cell configureWithNumber:[_session numberOfAsset:asset]
                videoDuration:(isVideo ? asset.duration : -1)
                       dimmed:[_session isDimmedAsset:asset]];
}

/// 视频体积在格子出现时后台补读（用于 >2GB 置灰）；图片不需要（不可能超限）。
- (void)loadSizeIfNeededForAsset:(PHAsset *)asset {
    if (asset.mediaType != PHAssetMediaTypeVideo || [IMMediaPickerPhotos cachedSizeBytesOfAsset:asset]) { return; }
    __weak typeof(self) ws = self;
    dispatch_async(_sizeQueue, ^{
        [IMMediaPickerPhotos sizeBytesOfAsset:asset];
        dispatch_async(dispatch_get_main_queue(), ^{ [ws refreshDimmedForAsset:asset]; });
    });
}

- (void)refreshDimmedForAsset:(PHAsset *)asset {
    for (IMMediaPickerCell *cell in _collection.visibleCells) {
        if ([cell.assetID isEqualToString:asset.localIdentifier]) { [self configureCell:cell asset:asset]; }
    }
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:NO];
    [self toggleAsset:_assets[indexPath.item]];
}

- (void)collectionView:(UICollectionView *)collectionView prefetchItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths {
    [IMMediaPickerPhotos.cachingManager startCachingImagesForAssets:[self assetsAtIndexPaths:indexPaths]
        targetSize:_thumbSize contentMode:PHImageContentModeAspectFill options:IMMediaPickerPhotos.thumbnailOptions];
}

- (void)collectionView:(UICollectionView *)collectionView cancelPrefetchingForItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths {
    [IMMediaPickerPhotos.cachingManager stopCachingImagesForAssets:[self assetsAtIndexPaths:indexPaths]
        targetSize:_thumbSize contentMode:PHImageContentModeAspectFill options:IMMediaPickerPhotos.thumbnailOptions];
}

- (NSArray<PHAsset *> *)assetsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths {
    NSMutableArray<PHAsset *> *out = [NSMutableArray arrayWithCapacity:indexPaths.count];
    for (NSIndexPath *ip in indexPaths) {
        if (ip.item < (NSInteger)_assets.count) { [out addObject:_assets[ip.item]]; }
    }
    return out;
}

@end
