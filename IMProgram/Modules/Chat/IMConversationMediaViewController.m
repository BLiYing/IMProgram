//  IMConversationMediaViewController.m

#import "IMConversationMediaViewController.h"
#import "IMMediaViewerViewController.h"
#import "IMMediaPagerViewController.h"
#import "IMMediaPlaceholder.h" // 统一门控占位取图（真帧>thumb磨砂>灰底）
#import "IMMediaExpiryRegistry.h" // 失效登记：媒体库宫格据此显 ⊘（自身只读本地、不联网探测）
#import "IMImageLoader.h"          // 铁律 A：本机已缓存则不显失效
#import "IMOriginalVideoCache.h"

@implementation IMMediaItem
+ (instancetype)itemWithURL:(NSString *)url isVideo:(BOOL)isVideo timestamp:(int64_t)timestamp {
    return [self itemWithURL:url isVideo:isVideo timestamp:timestamp thumb:nil];
}
+ (instancetype)itemWithURL:(NSString *)url isVideo:(BOOL)isVideo timestamp:(int64_t)timestamp
                      thumb:(NSString *)thumb {
    IMMediaItem *it = [IMMediaItem new];
    it.url = url; it.isVideo = isVideo; it.timestamp = timestamp; it.thumb = thumb;
    return it;
}
@end

#pragma mark - 缩略图 Cell

@interface IMMediaGridCell : UICollectionViewCell
- (void)configureWithItem:(IMMediaItem *)item;
@end

@implementation IMMediaGridCell {
    UIImageView *_thumb;
    UIImageView *_playBadge;
    UIImageView *_expiredBadge; // 中心 ⊘（失效）
    NSString    *_url;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _thumb = [UIImageView new];
        _thumb.contentMode = UIViewContentModeScaleAspectFill;
        _thumb.clipsToBounds = YES;
        _thumb.backgroundColor = UIColor.tertiarySystemFillColor;
        _thumb.frame = self.contentView.bounds;
        _thumb.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.contentView addSubview:_thumb];

        _playBadge = [[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:@"play.circle.fill"
                    withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightRegular]]];
        _playBadge.tintColor = UIColor.whiteColor;
        _playBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _playBadge.hidden = YES;
        [self.contentView addSubview:_playBadge];
        _expiredBadge = [[UIImageView alloc] initWithImage:[IMMediaPlaceholder expiredGlyphImage]];
        _expiredBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _expiredBadge.hidden = YES;
        [self.contentView addSubview:_expiredBadge];
        [NSLayoutConstraint activateConstraints:@[
            [_playBadge.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_playBadge.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_expiredBadge.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_expiredBadge.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
    }
    return self;
}
- (void)configureWithItem:(IMMediaItem *)item {
    _url = item.url;
    _thumb.image = nil;
    // 已知失效：显 ⊘ + dim thumb、去播放键（本 VC 只读本地不联网，故不在此探测，仅据登记表展示）。
    // 铁律 A：本机有原件（图片缓存 / 视频原件缓存）→ 照显真图，不叠失效（否则把能看的原件 dim+⊘，code-review #5）。
    BOOL hasLocal = item.isVideo ? [IMOriginalVideoCache hasCacheForFullURL:item.url]
                                 : [[IMImageLoader shared] hasCachedImageForURL:item.url];
    BOOL expired = !hasLocal && [IMMediaExpiryRegistry.shared isExpiredURL:item.url];
    _expiredBadge.hidden = !expired;
    _thumb.alpha = expired ? 0.5 : 1.0;
    _playBadge.hidden = expired || !item.isVideo;
    __weak typeof(self) ws = self;
    NSString *want = item.url;
    // 门控一致（M4-7）：媒体库同样走「真帧(仅已下载)>thumb 磨砂>灰底」，关自动下载时不为缩略图联网拉原件。
    [IMMediaPlaceholder previewForURL:item.url isVideo:item.isVideo thumb:item.thumb completion:^(UIImage *image) {
        __strong typeof(ws) self = ws;
        if (self && image && [self->_url isEqualToString:want]) { self->_thumb.image = image; }
    }];
}
- (void)prepareForReuse { [super prepareForReuse]; _thumb.image = nil; _thumb.alpha = 1.0; _expiredBadge.hidden = YES; }
@end

#pragma mark - 媒体库

@interface IMConversationMediaViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@end

@implementation IMConversationMediaViewController {
    NSArray<IMMediaItem *> *_items;
    UICollectionView *_collection;
}

+ (instancetype)galleryWithItems:(NSArray<IMMediaItem *> *)items {
    IMConversationMediaViewController *vc = [IMConversationMediaViewController new];
    // 新到旧展示（媒体库惯例）。
    vc->_items = [items sortedArrayUsingComparator:^NSComparisonResult(IMMediaItem *a, IMMediaItem *b) {
        if (a.timestamp == b.timestamp) { return NSOrderedSame; }
        return a.timestamp > b.timestamp ? NSOrderedAscending : NSOrderedDescending;
    }];
    return vc;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"图片与视频";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumInteritemSpacing = 2;
    layout.minimumLineSpacing = 2;
    _collection = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    _collection.backgroundColor = UIColor.systemBackgroundColor;
    _collection.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _collection.dataSource = self;
    _collection.delegate = self;
    [_collection registerClass:IMMediaGridCell.class forCellWithReuseIdentifier:@"media"];
    [self.view addSubview:_collection];

    if (_items.count == 0) {
        UILabel *empty = [UILabel new];
        empty.text = @"暂无图片或视频";
        empty.textColor = UIColor.secondaryLabelColor;
        empty.textAlignment = NSTextAlignmentCenter;
        empty.frame = self.view.bounds;
        empty.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:empty];
    }

    // 别处（气泡/查看器）刚探到某 URL 失效 → 刷新宫格显 ⊘（本 VC 自身不联网探测）。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onExpiryChanged)
                                               name:IMMediaExpiryDidChangeNotification object:nil];
}

- (void)onExpiryChanged { [_collection reloadData]; }

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return _items.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    IMMediaGridCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"media" forIndexPath:ip];
    [cell configureWithItem:_items[ip.item]];
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)ip {
    CGFloat cols = 3, spacing = 2;
    CGFloat w = floor((cv.bounds.size.width - (cols - 1) * spacing) / cols);
    return CGSizeMake(w, w);
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    // 任务3：媒体库内也支持左右翻页（网格已是完整时间线）。媒体库内不再显示「媒体库」按钮
    // （onOpenGallery=nil），此处无消息上下文故不带「更多」动作。捕获局部 items 避免强引用 self。
    NSArray<IMMediaItem *> *items = _items;
    IMMediaPagerViewController *pager =
        [IMMediaPagerViewController pagerWithCount:items.count startIndex:(NSUInteger)ip.item
                                      pageProvider:^IMMediaViewerViewController *(NSUInteger index) {
            if (index >= items.count) { return nil; }
            IMMediaItem *it = items[index];
            return [IMMediaViewerViewController viewerWithURL:it.url isVideo:it.isVideo
                                              preloadedImage:nil onOpenGallery:nil];
        }];
    [self presentViewController:pager animated:YES completion:nil];
}

@end
