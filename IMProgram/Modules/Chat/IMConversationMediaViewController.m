//  IMConversationMediaViewController.m

#import "IMConversationMediaViewController.h"
#import "IMMediaViewerViewController.h"
#import "IMMediaPagerViewController.h"
#import "IMMediaTileCell.h"                 // 与资料 tab 共用的门控格子
#import "IMMediaDownloadCoordinator.h"      // 门控/进度/取消（自建，与聊天页共享同一份下载态）
#import "IMDownloadProgress.h"
#import "IMMessageModel.h"
#import "IMMenuAction.h"
#import "IMPopoverCard.h"

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

#pragma mark - 媒体库

@interface IMConversationMediaViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@end

@implementation IMConversationMediaViewController {
    NSArray<IMMediaItem *> *_items;
    NSArray<IMMessageModel *> *_messages;   // 与 _items 逐位对齐
    UICollectionView *_collection;
    IMMediaDownloadCoordinator *_downloads;
    NSString *_host, *_myUserID, *_title;
    BOOL _isGroup;
    NSArray<IMMenuAction *> *(^_contextActionsProvider)(IMMessageModel *);
    NSArray<IMPopoverCardItem *> *(^_moreActionsProvider)(IMMessageModel *);
}

+ (instancetype)galleryWithItems:(NSArray<IMMediaItem *> *)items
                        messages:(NSArray<IMMessageModel *> *)messages
                            host:(NSString *)host
                        myUserID:(NSString *)myUserID
                         isGroup:(BOOL)isGroup
                           title:(NSString *)title
          contextActionsProvider:(NSArray<IMMenuAction *> *(^)(IMMessageModel *))contextActionsProvider
             moreActionsProvider:(NSArray<IMPopoverCardItem *> *(^)(IMMessageModel *))moreActionsProvider {
    IMConversationMediaViewController *vc = [IMConversationMediaViewController new];
    // 新到旧展示（媒体库惯例）：items 与 messages 逐位对齐，需成对同序重排。
    NSUInteger n = MIN(items.count, messages.count);
    NSMutableArray<NSNumber *> *order = [NSMutableArray arrayWithCapacity:n];
    for (NSUInteger i = 0; i < n; i++) { [order addObject:@(i)]; }
    [order sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        int64_t ta = items[a.unsignedIntegerValue].timestamp, tb = items[b.unsignedIntegerValue].timestamp;
        if (ta == tb) { return NSOrderedSame; }
        return ta > tb ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSMutableArray<IMMediaItem *> *si = [NSMutableArray arrayWithCapacity:n];
    NSMutableArray<IMMessageModel *> *sm = [NSMutableArray arrayWithCapacity:n];
    for (NSNumber *idx in order) { [si addObject:items[idx.unsignedIntegerValue]]; [sm addObject:messages[idx.unsignedIntegerValue]]; }
    vc->_items = si;
    vc->_messages = sm;
    vc->_host = [host copy]; vc->_myUserID = [myUserID copy]; vc->_isGroup = isGroup; vc->_title = [title copy];
    vc->_contextActionsProvider = [contextActionsProvider copy];
    vc->_moreActionsProvider = [moreActionsProvider copy];
    return vc;
}

/// 自建下载协调器（与资料页一致）：autoPrefetch 关，只反映状态、下载一律由用户点；与聊天页共享同一份下载态（key=content）。
- (IMMediaDownloadCoordinator *)downloads {
    if (!_downloads) {
        _downloads = [[IMMediaDownloadCoordinator alloc] initWithHost:(_host ?: @"") myUserID:(_myUserID ?: @"") isGroup:_isGroup];
        _downloads.autoPrefetchEnabled = NO;
        __weak typeof(self) ws = self;
        _downloads.onProgress = ^(IMMessageModel *m, IMDownloadProgress *state) { [ws updateTileForMessage:m state:state]; };
        _downloads.onStateChanged = ^(IMMessageModel *m) { [ws reloadTileForMessage:m]; };
    }
    return _downloads;
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
    [_collection registerClass:IMMediaTileCell.class forCellWithReuseIdentifier:@"media"];
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

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 抢回仍在跑的下载回调（同资料页/聊天页）：从查看器返回或后台切回时进度不冻结。
    if (_downloads && _messages.count) { [_downloads reattachActiveTasksForMessages:_messages]; }
}

- (nullable IMMessageModel *)messageAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_messages.count) { return nil; }
    return _messages[index];
}

#pragma mark - 下载态就地刷新（同资料页）

- (void)updateTileForMessage:(IMMessageModel *)m state:(IMDownloadProgress *)state {
    NSUInteger i = [_messages indexOfObjectIdenticalTo:m];
    if (i == NSNotFound) { return; }
    IMMediaTileCell *c = (IMMediaTileCell *)[_collection cellForItemAtIndexPath:[NSIndexPath indexPathForItem:(NSInteger)i inSection:0]];
    if ([c isKindOfClass:IMMediaTileCell.class]) { [c updateDownload:state]; }
}

- (void)reloadTileForMessage:(IMMessageModel *)m {
    NSUInteger i = [_messages indexOfObjectIdenticalTo:m];
    if (i == NSNotFound) { return; }
    [_collection reloadItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:(NSInteger)i inSection:0]]];
}

#pragma mark - CollectionView

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section { return _items.count; }

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    IMMediaTileCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"media" forIndexPath:ip];
    IMMessageModel *m = [self messageAtIndex:ip.item];
    IMDownloadProgress *dp = m ? [self.downloads stateForMessage:m] : nil;
    [cell configureWithItem:_items[ip.item] download:dp thumb:m.thumb];
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)ip {
    CGFloat cols = 3, spacing = 2;
    CGFloat w = floor((cv.bounds.size.width - (cols - 1) * spacing) / cols);
    return CGSizeMake(w, w);
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    IMMessageModel *m = [self messageAtIndex:ip.item];
    // 门控格（未就绪）：点击=就地下载，不打开（下载优先，与资料 tab 一致）。
    IMDownloadProgress *dp = m ? [self.downloads stateForMessage:m] : nil;
    if (dp && dp.phase != IMDownloadPhaseDone) { if (m) { [self.downloads handleTapForMessage:m]; } return; }

    // 就绪：进分页查看器，翻页范围=整个媒体库，不显「媒体库」按钮（onOpenGallery=nil，避免死循环）。
    NSArray<IMMediaItem *> *items = _items;
    NSArray<IMMessageModel *> *msgs = _messages;
    NSArray<IMPopoverCardItem *> *(^moreProvider)(IMMessageModel *) = _moreActionsProvider;
    IMMediaPagerViewController *pager =
        [IMMediaPagerViewController pagerWithCount:items.count startIndex:(NSUInteger)ip.item
                                      pageProvider:^IMMediaViewerViewController *(NSUInteger index) {
            if (index >= items.count) { return nil; }
            IMMediaItem *it = items[index];
            IMMediaViewerViewController *v = [IMMediaViewerViewController viewerWithURL:it.url isVideo:it.isVideo
                                                                       preloadedImage:nil onOpenGallery:nil];
            v.thumbDataURI = it.thumb;
            IMMessageModel *mm = index < msgs.count ? msgs[index] : nil;
            if (mm && moreProvider) { v.moreActions = moreProvider(mm); }
            return v;
        }];
    pager.conversationTitle = _title;
    [self presentViewController:pager animated:YES completion:nil];
}

/// 逐格长按菜单（与资料 tab 一致）：本页自带「取消下载」（用自建协调器），其余（转发/定位/删除）由聊天页提供。
- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)cv
    contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)ip point:(CGPoint)point {
    IMMessageModel *m = [self messageAtIndex:ip.item];
    if (!m || m.convSeq <= 0) { return nil; }
    __weak typeof(self) ws = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *sug) {
        __strong typeof(ws) self = ws;
        if (!self) { return nil; }
        NSMutableArray<IMMenuAction *> *acts = [NSMutableArray array];
        NSArray<IMMenuAction *> *provided = self->_contextActionsProvider ? self->_contextActionsProvider(m) : nil;
        // 顺序对齐资料 tab：转发 / 定位 / [取消下载·仅进行中] / 删除。取消下载优先插在「删除」前；
        // 未找到 delete（provider 约定变更兜底）则追加到末尾，保证进行中态永远有取消入口、不被静默吞掉。
        IMDownloadProgress *dp = [self.downloads stateForMessage:m];
        BOOL downloading = dp.phase == IMDownloadPhaseDownloading || dp.phase == IMDownloadPhasePaused;
        IMMenuAction *cancel = downloading
            ? [IMMenuAction actionWithId:@"cancel" title:@"取消下载" image:@"xmark.circle"
                                 handler:^{ [ws.downloads cancelDownloadForMessage:m]; }]
            : nil;
        BOOL cancelInserted = NO;
        for (IMMenuAction *a in provided) {
            if (cancel && !cancelInserted && [a.actionId isEqualToString:@"delete"]) {
                [acts addObject:cancel]; cancelInserted = YES;
            }
            [acts addObject:a];
        }
        if (cancel && !cancelInserted) { [acts addObject:cancel]; }
        return [IMMenuAction menuWithActions:acts];
    }];
}

@end
