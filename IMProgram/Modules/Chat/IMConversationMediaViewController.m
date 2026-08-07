//  IMConversationMediaViewController.m

#import "IMConversationMediaViewController.h"
#import "IMMediaViewerViewController.h"
#import "IMMediaPlaceholder.h" // 统一门控占位取图（真帧>thumb磨砂>灰底）

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
        [NSLayoutConstraint activateConstraints:@[
            [_playBadge.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_playBadge.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
    }
    return self;
}
- (void)configureWithItem:(IMMediaItem *)item {
    _url = item.url;
    _thumb.image = nil;
    _playBadge.hidden = !item.isVideo;
    __weak typeof(self) ws = self;
    NSString *want = item.url;
    // 门控一致（M4-7）：媒体库同样走「真帧(仅已下载)>thumb 磨砂>灰底」，关自动下载时不为缩略图联网拉原件。
    [IMMediaPlaceholder previewForURL:item.url isVideo:item.isVideo thumb:item.thumb completion:^(UIImage *image) {
        __strong typeof(ws) self = ws;
        if (self && image && [self->_url isEqualToString:want]) { self->_thumb.image = image; }
    }];
}
- (void)prepareForReuse { [super prepareForReuse]; _thumb.image = nil; }
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
}

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
    IMMediaItem *it = _items[ip.item];
    // 复用聊天中的查看逻辑；媒体库内不再显示「媒体库」按钮（onOpenGallery=nil）。
    IMMediaViewerViewController *viewer = [IMMediaViewerViewController viewerWithURL:it.url
                                                                            isVideo:it.isVideo
                                                                     preloadedImage:nil
                                                                      onOpenGallery:nil];
    [self presentViewController:viewer animated:YES completion:nil];
}

@end
