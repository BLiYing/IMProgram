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
#import "IMSocketManager.h" // IMSocketDidRemoveMessageNotification：长按删除后就地移除该格
#import "IMSocketManager+BatchDelete.h" // IMRemovedMessageSeqs
#import "IMLocalization.h"
#import "IMMediaServerTimeline.h"
#import "IMMediaUtil.h"
#import "UIViewController+IMToast.h"

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
+ (instancetype)itemWithURL:(NSString *)url isVideo:(BOOL)isVideo timestamp:(int64_t)timestamp
                      thumb:(NSString *)thumb durationMillis:(int64_t)durationMillis {
    IMMediaItem *it = [self itemWithURL:url isVideo:isVideo timestamp:timestamp thumb:thumb];
    it.durationMillis = durationMillis;
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
    UILabel *_emptyLabel;                   // 空态提示（初始为空 / 删到空时显示）
    IMMediaDownloadCoordinator *_downloads;
    NSString *_host, *_myUserID, *_title;
    BOOL _isGroup;
    NSArray<IMMenuAction *> *(^_contextActionsProvider)(IMMessageModel *);
    NSArray<IMPopoverCardItem *> *(^_moreActionsProvider)(IMMessageModel *);
    BOOL _loadFailed;                       // 服务端续拉失败过（首屏失败时空态要说网络问题，不说「无媒体」）
    IMMediaServerTimeline *_timeline;       // 服务端续拉模式才有；有它时 _items/_messages 都由它派生（新→旧）
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

#pragma mark - 服务端续拉模式

- (void)attachServerTimeline:(IMMediaServerTimeline *)timeline {
    _timeline = timeline;
    [self rebuildFromTimeline];
}

/// 由时间线（升序）重派生展示项：新→旧。续拉只会在**末尾**追加，已有格的下标不动。
- (void)rebuildFromTimeline {
    NSArray<IMMessageModel *> *asc = _timeline.messages;
    NSMutableArray<IMMessageModel *> *msgs = [NSMutableArray arrayWithCapacity:asc.count];
    NSMutableArray<IMMediaItem *> *items = [NSMutableArray arrayWithCapacity:asc.count];
    for (IMMessageModel *m in [asc reverseObjectEnumerator]) {
        [msgs addObject:m];
        [items addObject:[IMMediaItem itemWithURL:IMMediaFullURL(m.content, _host)
                                          isVideo:[m.contentType isEqualToString:@"video"]
                                        timestamp:m.timestamp thumb:m.thumb]];
    }
    _messages = msgs; _items = items;
    // 空态只在「确实没有」时显示：还能续拉不是空；首屏加载失败也不能写成「无媒体」（说的是网络问题）
    _emptyLabel.hidden = _items.count > 0 || _timeline.hasMore;
    if (_timeline && _items.count == 0 && _loadFailed) {
        _emptyLabel.text = IMLocalized(@"media.viewer.offline_partial_notice");
        _emptyLabel.hidden = NO;
    }
    [_collection reloadData];
}

/// 往更旧的续拉一页；失败 = 离线降级，停在已有的那段并说一句（不说「没有更多了」）。
- (void)loadMoreFromServer {
    if (!_timeline || _timeline.loading || !_timeline.hasMore) { return; }
    __weak typeof(self) ws = self;
    [_timeline loadOlder:^(NSInteger added, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) { [self im_showToast:IMLocalized(@"media.viewer.offline_partial_notice")]; self->_loadFailed = YES; }
        [self rebuildFromTimeline];
    }];
}

- (void)collectionView:(UICollectionView *)cv willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)ip {
    if (_timeline && _timeline.hasMore && ip.item + 12 >= (NSInteger)_items.count) { [self loadMoreFromServer]; }
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
    self.title = IMLocalized(@"gallery.title");
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

    _emptyLabel = [UILabel new];
    _emptyLabel.text = IMLocalized(@"gallery.empty");
    _emptyLabel.textColor = UIColor.secondaryLabelColor;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.frame = self.view.bounds;
    _emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _emptyLabel.hidden = _items.count > 0;
    [self.view addSubview:_emptyLabel];

    if (_timeline) { [self loadMoreFromServer]; } // 服务端模式首屏：展示项还是空的，先要最新一页
    // 长按菜单删除（为所有人/仅自己）落地后就地移除该格——本页持快照，不监听就会残留已删消息。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMessageRemoved:)
                                               name:IMSocketDidRemoveMessageNotification object:nil];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

/// 某条消息被物理移除（为所有人删除 / 仅为我删除）→ 按 convID+convSeq 从快照删格并刷新；删到空显空态。
- (void)onMessageRemoved:(NSNotification *)note {
    NSString *convID = note.userInfo[kIMConvIDKey];
    // 批量删除只来一次通知，带全部 seq（IMRemovedMessageSeqs）；单条就是一元集合。
    NSSet<NSNumber *> *gone = [NSSet setWithArray:IMRemovedMessageSeqs(note.userInfo)];
    if (convID.length == 0 || gone.count == 0) { return; }
    // 观察者按 object:nil 注册（任何会话的删除都会进来），绝大多数命不中本页快照——
    // 先只读扫一遍，无命中直接返回，别为不相干的通知白付两次全量 mutableCopy。
    BOOL hit = NO;
    for (IMMessageModel *m in _messages) {
        if ([gone containsObject:@(m.convSeq)] && (m.convID.length == 0 || [m.convID isEqualToString:convID])) { hit = YES; break; }
    }
    if (!hit) { return; }
    NSMutableArray<IMMediaItem *> *items = [_items mutableCopy];
    NSMutableArray<IMMessageModel *> *msgs = [_messages mutableCopy];
    BOOL changed = NO;
    for (NSInteger i = (NSInteger)msgs.count - 1; i >= 0; i--) {
        IMMessageModel *m = msgs[(NSUInteger)i];
        // 本页快照全部来自同一会话：convID 缺失（个别本地模型未回填）时按 seq 匹配即可，不至跨会话误删。
        if ([gone containsObject:@(m.convSeq)] && (m.convID.length == 0 || [m.convID isEqualToString:convID])) {
            [msgs removeObjectAtIndex:(NSUInteger)i];
            if (i < (NSInteger)items.count) { [items removeObjectAtIndex:(NSUInteger)i]; }
            changed = YES;
        }
    }
    if (!changed) { return; }
    if (_timeline) { [_timeline removeMessagesWithConvSeqs:gone]; } // 否则下次由时间线重派生时已删的图会复活
    _items = items;
    _messages = msgs;
    [_collection reloadData];
    _emptyLabel.hidden = _items.count > 0 || _timeline.hasMore; // 服务端模式删光已加载的、后面还有更旧的：不是空
    if (_items.count == 0 && _timeline.hasMore) { [self loadMoreFromServer]; }
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
    NSArray<IMPopoverCardItem *> *(^moreProvider)(IMMessageModel *) = _moreActionsProvider;
    __weak typeof(self) wself = self;
    IMMediaPagerViewController *pager =
        [IMMediaPagerViewController pagerWithCount:_items.count startIndex:(NSUInteger)ip.item
                                      pageProvider:^IMMediaViewerViewController *(NSUInteger index) {
            // 按**调用时**的展示项取（服务端续拉会让它变长）
            __strong typeof(wself) sself = wself;
            NSArray<IMMediaItem *> *items = sself ? sself->_items : @[];
            NSArray<IMMessageModel *> *msgs = sself ? sself->_messages : @[];
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
    if (_timeline) {
        pager.olderAtEnd = YES; // 媒体库新→旧：更旧的在末尾，追加不挪下标
        pager.countProvider = ^NSUInteger{ __strong typeof(wself) s = wself; return s ? s->_items.count : 0; }; // 网格自己也会续拉：以真实长度为准
        pager.hasOlder = ^BOOL{ return [wself isTimelineHasMore]; };
        pager.olderLoader = ^(void (^done)(NSInteger)) {
            __strong typeof(wself) s = wself;
            if (!s || !s->_timeline) { done(0); return; }
            [s->_timeline loadOlder:^(NSInteger added, NSError *error) {
                if (error) { [[UIViewController im_topVisibleViewController] im_showToast:IMLocalized(@"media.viewer.offline_partial_notice")]; } // 查看器盖在上面：toast 要打在可见页上
                [wself rebuildFromTimeline];
                done(added);
            }];
        };
    }
    [self presentViewController:pager animated:YES completion:nil];
}

- (BOOL)isTimelineHasMore { return _timeline.hasMore; }

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
            ? [IMMenuAction actionWithId:@"cancel" title:IMLocalized(@"file.menu.cancel_download") image:@"xmark.circle"
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
