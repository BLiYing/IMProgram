//  IMMediaPreviewViewController.m

#import "IMMediaPreviewViewController.h"
#import "IMMediaPicker.h"
#import "IMMediaPickLogic.h"
#import "IMMediaPickSession.h"
#import "IMMediaPickerBars.h"
#import "IMLocalization.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"

static const CGFloat kMaxZoom = 4;
static NSString * const kPageCellID = @"page";

#pragma mark - 单页（可缩放）

@interface IMMediaPreviewPageCell : UICollectionViewCell <UIScrollViewDelegate>
@property (nonatomic, copy, nullable) NSString *assetID;
@property (nonatomic, assign) int32_t requestID;
@property (nonatomic, strong, readonly) UIImageView *imageView;
@property (nonatomic, strong, readonly) UILabel *videoNote;
- (void)resetZoom;
@end

@implementation IMMediaPreviewPageCell {
    UIScrollView *_scroll;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.backgroundColor = UIColor.blackColor;
        _scroll = [[UIScrollView alloc] initWithFrame:self.contentView.bounds];
        _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _scroll.delegate = self;
        _scroll.minimumZoomScale = 1;
        _scroll.maximumZoomScale = kMaxZoom;
        _scroll.showsHorizontalScrollIndicator = NO;
        _scroll.showsVerticalScrollIndicator = NO;
        _scroll.alwaysBounceHorizontal = NO; // 1 倍时单指横滑交给外层翻页
        [self.contentView addSubview:_scroll];
        _imageView = [[UIImageView alloc] initWithFrame:_scroll.bounds];
        _imageView.contentMode = UIViewContentModeScaleAspectFit;
        _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_scroll addSubview:_imageView];
        UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapped:)];
        dbl.numberOfTapsRequired = 2;
        [_scroll addGestureRecognizer:dbl];

        _videoNote = [UILabel new];
        _videoNote.font = [UIFont systemFontOfSize:13];
        _videoNote.textColor = UIColor.whiteColor;
        _videoNote.textAlignment = NSTextAlignmentCenter;
        _videoNote.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.6];
        _videoNote.layer.cornerRadius = 14;
        _videoNote.clipsToBounds = YES;
        _videoNote.hidden = YES;
        [self.contentView addSubview:_videoNote];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize fit = [_videoNote sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    CGFloat w = fit.width + 24, h = fit.height + 12; // 内边距 横 12 竖 6
    CGRect b = self.contentView.bounds;
    _videoNote.frame = CGRectMake((CGRectGetWidth(b) - w) / 2, CGRectGetHeight(b) - 120 - h, w, h); // 距底 120
}

- (void)resetZoom { [_scroll setZoomScale:1 animated:NO]; }

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return _imageView; }

- (void)doubleTapped:(UITapGestureRecognizer *)g {
    if (_scroll.zoomScale > 1) { [_scroll setZoomScale:1 animated:YES]; return; }
    CGPoint p = [g locationInView:_imageView];
    CGFloat z = 2;
    CGSize size = CGSizeMake(CGRectGetWidth(_scroll.bounds) / z, CGRectGetHeight(_scroll.bounds) / z);
    [_scroll zoomToRect:CGRectMake(p.x - size.width / 2, p.y - size.height / 2, size.width, size.height) animated:YES];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.assetID = nil;
    _imageView.image = nil;
    _videoNote.hidden = YES;
    [self resetZoom];
}
@end

#pragma mark - 预览页

@interface IMMediaPreviewViewController () <UICollectionViewDataSource, UICollectionViewDelegate>
@end

@implementation IMMediaPreviewViewController {
    IMMediaPickSession *_session;
    NSInteger _count;
    NSInteger _startIndex;
    PHAsset *(^_provider)(NSInteger);
    UICollectionView *_pager;
    UILabel *_pageLabel;
    UILabel *_selectCircle;
    IMMediaPickerBottomBar *_bottomBar;
    NSInteger _current;
    BOOL _didScrollToStart;
}

- (instancetype)initWithSession:(IMMediaPickSession *)session count:(NSInteger)count startIndex:(NSInteger)startIndex
                   assetAtIndex:(PHAsset *(^)(NSInteger))provider {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _session = session;
        _count = count;
        _startIndex = MAX(0, MIN(startIndex, count - 1));
        _current = _startIndex;
        _provider = [provider copy];
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.minimumLineSpacing = 0;
    layout.minimumInteritemSpacing = 0;
    _pager = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    _pager.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _pager.backgroundColor = UIColor.blackColor;
    _pager.pagingEnabled = YES;
    _pager.showsHorizontalScrollIndicator = NO;
    _pager.dataSource = self;
    _pager.delegate = self;
    [_pager registerClass:IMMediaPreviewPageCell.class forCellWithReuseIdentifier:kPageCellID];
    [self.view addSubview:_pager];
    [self buildTopBar];
    [self buildBottomBar];
    [self refreshState];
}

- (void)buildTopBar {
    UIButton *back = [UIButton buttonWithType:UIButtonTypeSystem];
    [back setTitle:IMLocalized(@"common.back") forState:UIControlStateNormal];
    back.titleLabel.font = [UIFont systemFontOfSize:17];
    back.tintColor = IMTheme.accent;
    back.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    [back addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    _pageLabel = [UILabel new];
    _pageLabel.font = [UIFont systemFontOfSize:15];
    _pageLabel.textColor = UIColor.whiteColor;
    _pageLabel.textAlignment = NSTextAlignmentCenter;
    _selectCircle = [UILabel new];
    _selectCircle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _selectCircle.textColor = UIColor.whiteColor;
    _selectCircle.textAlignment = NSTextAlignmentCenter;
    _selectCircle.layer.cornerRadius = 13;
    _selectCircle.clipsToBounds = YES;
    _selectCircle.userInteractionEnabled = YES;
    [_selectCircle addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(circleTapped)]];

    UIView *rightWrap = [UIView new];
    _selectCircle.translatesAutoresizingMaskIntoConstraints = NO;
    [rightWrap addSubview:_selectCircle];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[back, _pageLabel, rightWrap]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    back.translatesAutoresizingMaskIntoConstraints = NO;
    rightWrap.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [row.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [row.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [back.widthAnchor constraintEqualToConstant:64],
        [rightWrap.widthAnchor constraintEqualToConstant:64],
        [rightWrap.heightAnchor constraintEqualToConstant:26],
        [_selectCircle.trailingAnchor constraintEqualToAnchor:rightWrap.trailingAnchor],
        [_selectCircle.centerYAnchor constraintEqualToAnchor:rightWrap.centerYAnchor],
        [_selectCircle.widthAnchor constraintEqualToConstant:26],
        [_selectCircle.heightAnchor constraintEqualToConstant:26],
    ]];
}

- (void)buildBottomBar {
    __weak typeof(self) ws = self;
    _bottomBar = [[IMMediaPickerBottomBar alloc] initWithDarkStyle:YES];
    _bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
    _bottomBar.onOriginalToggle = ^{
        __strong typeof(ws) self_ = ws;
        if (!self_) { return; }
        self_->_session.sendOriginal = !self_->_session.sendOriginal;
        [self_ selectionDidChange];
    };
    _bottomBar.onSend = ^{ if (ws.onSend) { ws.onSend(); } };
    [self.view addSubview:_bottomBar];
    [NSLayoutConstraint activateConstraints:@[
        [_bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_bottomBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)_pager.collectionViewLayout;
    if (!CGSizeEqualToSize(layout.itemSize, _pager.bounds.size) && !CGSizeEqualToSize(_pager.bounds.size, CGSizeZero)) {
        layout.itemSize = _pager.bounds.size;
        [layout invalidateLayout];
        [_pager layoutIfNeeded]; // 先让 contentSize 按新 itemSize 算出来，下面跳到第 N 页才不会落在旧的（50×50 格）内容区里
    }
    if (!_didScrollToStart && _pager.bounds.size.width > 0) {
        _didScrollToStart = YES;
        [_pager setContentOffset:CGPointMake(_startIndex * _pager.bounds.size.width, 0) animated:NO];
    }
}

#pragma mark 状态

- (nullable PHAsset *)currentAsset { return (_current >= 0 && _current < _count) ? _provider(_current) : nil; }

- (void)refreshState {
    _pageLabel.text = [NSString stringWithFormat:@"%ld/%ld", (long)_current + 1, (long)_count];
    PHAsset *asset = [self currentAsset];
    NSInteger n = asset ? [_session numberOfAsset:asset] : 0;
    _selectCircle.text = n > 0 ? [NSString stringWithFormat:@"%ld", (long)n] : nil;
    _selectCircle.backgroundColor = n > 0 ? IMTheme.accent : [UIColor.whiteColor colorWithAlphaComponent:0.4];
    [_bottomBar updateWithSelectedCount:(NSInteger)_session.selectedIDs.count
                             originalOn:_session.sendOriginal
                             totalBytes:_session.totalBytes
                            showsBanner:NO];
}

- (void)selectionDidChange {
    [self refreshState];
    if (self.onSelectionChanged) { self.onSelectionChanged(); }
}

- (void)closeTapped { if (self.onClose) { self.onClose(); } }

- (void)circleTapped {
    PHAsset *asset = [self currentAsset];
    if (!asset) { return; }
    BOOL selected = [_session numberOfAsset:asset] > 0;
    if (!selected && (NSInteger)_session.selectedIDs.count >= kIMMediaPickLimit) {
        [self im_showToast:IMLocalizedFormat(@"media.picker.limit", (long)kIMMediaPickLimit)];
        return;
    }
    if (!selected && ![_session isSelectableAsset:asset]) {
        // 与宫格页同一条提示：不可选的唯一原因是超上限（见 isSelectableWithSizeBytes:）。
        [self im_showToast:IMLocalizedFormat(@"media.picker.too_large", [IMMediaPickLogic sizeLabelForBytes:kIMMaxVideoBytes])];
        return;
    }
    [_session toggleAsset:asset];
    [self selectionDidChange];
}

#pragma mark UICollectionView

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section { return _count; }

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    IMMediaPreviewPageCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kPageCellID forIndexPath:indexPath];
    PHAsset *asset = _provider(indexPath.item);
    if (cell.requestID != PHInvalidImageRequestID) { [PHImageManager.defaultManager cancelImageRequest:cell.requestID]; }
    cell.assetID = asset.localIdentifier;
    BOOL isVideo = asset.mediaType == PHAssetMediaTypeVideo;
    cell.videoNote.hidden = !isVideo;
    if (isVideo) {
        cell.videoNote.text = IMLocalizedFormat(@"media.picker.video_preview_note",
                                                [IMMediaPickLogic durationLabelForSeconds:asset.duration]);
        [cell setNeedsLayout];
    }
    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize bounds = collectionView.bounds.size;
    // 屏幕尺寸的 2 倍：够双指放大看清，又不把几千万像素的原图整张解进内存。
    CGSize target = CGSizeMake(bounds.width * scale * 2, bounds.height * scale * 2);
    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
    opt.networkAccessAllowed = YES; // 用户主动在看这一张，iCloud 原件允许下载
    __weak IMMediaPreviewPageCell *weakCell = cell;
    NSString *assetID = asset.localIdentifier;
    cell.requestID = [PHImageManager.defaultManager requestImageForAsset:asset targetSize:target
        contentMode:PHImageContentModeAspectFit options:opt resultHandler:^(UIImage *image, NSDictionary *info) {
        if (image && [weakCell.assetID isEqualToString:assetID]) { weakCell.imageView.image = image; }
    }];
    return cell;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView != _pager) { return; }
    CGFloat w = CGRectGetWidth(_pager.bounds);
    if (w <= 0) { return; }
    _current = MAX(0, MIN(_count - 1, (NSInteger)llround(_pager.contentOffset.x / w)));
    [self refreshState];
}

@end
