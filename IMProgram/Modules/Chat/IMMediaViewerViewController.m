//  IMMediaViewerViewController.m

#import "IMMediaViewerViewController.h"
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMOriginalVideoCache.h"
#import "IMMediaExpiryRegistry.h" // 被动展示 404 失效登记 + 复验
#import "IMMediaPlaceholder.h"    // 失效占位覆盖层
#import "UIViewController+IMToast.h"
#import "IMGlass.h" // 标准 Liquid Glass 按钮配置（iOS26 glass()/旧系统 gray() 降级）
#import "IMLog.h"
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>

@interface IMMediaViewerViewController () <UIScrollViewDelegate, NSURLSessionDownloadDelegate>
@end

@implementation IMMediaViewerViewController {
    NSString        *_url;
    BOOL             _isVideo;
    UIImage         *_preloaded;
    dispatch_block_t _onOpenGallery;

    // 图片
    UIScrollView *_scroll;
    UIImageView  *_imageView;
    UIImage      *_fullImage;      // 下载用（优先原图字节）
    UIView       *_expiredOverlay; // 失效占位覆盖层（被动展示 404）

    // 视频
    AVPlayer         *_player;
    AVPlayerLayer    *_playerLayer;
    UIView           *_videoContainer;
    UIImageView      *_poster;     // 首帧封面（未开播前显示）
    UIButton         *_playButton; // 居中大播放按钮
    UISlider         *_scrubber;
    UILabel          *_timeLabel;
    UIButton         *_speedButton;
    UIButton         *_originalChip;
    BOOL              _originalChipVisible;   // chip「本应可见」（沉浸态恢复用；下载完/本地原件后置 NO）
    BOOL              _downloadingOriginal;  // 原视频下载中（chip 显示百分比，#1）
    BOOL              _usingLocalOriginal;   // 打开时已命中本地原件缓存 → 本地播放，不显「查看原视频」chip
    NSURLSession     *_originalSession;      // delegate 模式才有进度回调
    id                _timeObserver;
    AVPlayerItem     *_observedItem;      // 正在观察 status 的 item（换 item 时要迁移，dealloc 时要摘）
    UILabel          *_unplayableLabel;   // 解不了码时的降级说明（避免只剩黑屏）
    BOOL              _started;    // 是否已首次播放
    BOOL              _scrubbing;
    NSArray<NSNumber *> *_speeds;
    NSUInteger        _speedIdx;

    // 通用控件
    UIButton *_closeButton;
    UIButton *_downloadButton;
    UIButton *_galleryButton;
    UIButton *_moreButton;   // 「更多」锚点（IMPopoverCard 从它旁边展开）
    BOOL      _saving;

    UIActivityIndicatorView *_loadingSpinner; // 路线 A：磨砂占位上叠加载菊花，全量到达/失败即停
}

+ (instancetype)viewerWithURL:(NSString *)fullURL
                      isVideo:(BOOL)isVideo
               preloadedImage:(UIImage *)preloadedImage
                onOpenGallery:(dispatch_block_t)onOpenGallery {
    IMMediaViewerViewController *vc = [IMMediaViewerViewController new];
    vc->_url = [fullURL copy];
    vc->_isVideo = isVideo;
    vc->_preloaded = preloadedImage;
    vc->_onOpenGallery = [onOpenGallery copy];
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    return vc;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    _speeds = @[@1.0, @1.5, @2.0];
    if (_isVideo) { [self setupVideo]; } else { [self setupImage]; }
    [self setupCommonControls];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _scroll.frame = self.view.bounds;
    _imageView.frame = _scroll.bounds;
    _videoContainer.frame = self.view.bounds;
    _playerLayer.frame = _videoContainer.bounds;
    _poster.frame = _videoContainer.bounds;
}

#pragma mark - 图片

- (void)setupImage {
    _scroll = [UIScrollView new];
    _scroll.delegate = self;
    _scroll.minimumZoomScale = 1.0;
    _scroll.maximumZoomScale = 3.0;
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.showsHorizontalScrollIndicator = NO;
    [self.view addSubview:_scroll];

    _imageView = [UIImageView new];
    _imageView.contentMode = UIViewContentModeScaleAspectFit;
    _imageView.userInteractionEnabled = YES;
    _imageView.image = _preloaded;
    _fullImage = _preloaded;
    [_scroll addSubview:_imageView];

    // 路线 A：无预载图（多为门控/未下载项）→ 先显内嵌 thumb 磨砂占位 + 菊花，全量到达后替换，避免黑屏闪。
    if (!_preloaded) { [self showThumbPlaceholder]; }

    // 无壳（翻页容器托管）：单击转给容器切 chrome；独立打开：单击关闭查看器（原行为）。
    UITapGestureRecognizer *single = [[UITapGestureRecognizer alloc] initWithTarget:self
        action:(_chromeless ? @selector(handleContentSingleTap) : @selector(dismissSelf))];
    UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapZoom:)];
    dbl.numberOfTapsRequired = 2;
    [single requireGestureRecognizerToFail:dbl];
    [_imageView addGestureRecognizer:single];
    [_imageView addGestureRecognizer:dbl];

    // 已知失效**且本机无缓存**：直接画失效占位、不回源。本机已缓存则照显真图（铁律 A），交给下方 loadImageURL 同步命中。
    if (![[IMImageLoader shared] hasCachedImageForURL:_url] && [IMMediaExpiryRegistry.shared isExpiredURL:_url]) {
        [self hideLoadingSpinner];
        [self showExpiredOverlayForVideo:NO]; return;
    }
    // 拉取（可能更清晰的）原图，兼作下载源。
    __weak typeof(self) ws = self;
    NSString *want = _url;
    [[IMImageLoader shared] loadImageURL:_url completion:^(UIImage *image) {
        __strong typeof(ws) self = ws;
        if (!self || ![self->_url isEqualToString:want]) { return; }
        if (image) { self->_imageView.image = image; self->_fullImage = image; [self hideLoadingSpinner]; return; }
        [self hideLoadingSpinner];
        // 无 preload 兜底且加载失败 → 复验 404，命中画失效占位（非空屏）。
        if (self->_preloaded) { return; } // 有本地预览就不判失效（缓存过的照显，铁律 A）
        [IMMediaExpiryRegistry.shared verifyExpiredForURL:want completion:^(BOOL expired) {
            __strong typeof(ws) self2 = ws;
            if (self2 && expired && [self2->_url isEqualToString:want]) { [self2 showExpiredOverlayForVideo:NO]; }
        }];
    }];
}

/// 路线 A 加载占位：内嵌 thumb 磨砂图铺满（居中 aspectFit）+ 居中菊花。全量/封面到达或失败时由 hideLoadingSpinner 收起菊花。
- (void)showThumbPlaceholder {
    if (_thumbDataURI.length > 0) {
        UIImageView *target = _isVideo ? _poster : _imageView;
        UIImage *cached = [IMMediaPlaceholder cachedFrostedForThumb:_thumbDataURI];
        if (cached) {
            if (!target.image) { target.image = cached; }
        } else {
            __weak typeof(self) ws = self;
            [IMMediaPlaceholder frostedForThumb:_thumbDataURI completion:^(UIImage *blurred) {
                __strong typeof(ws) self = ws;
                // 全量图/真封面已到（_fullImage / _started）则不覆盖；目标仍空才铺磨砂占位。
                if (self && blurred && !self->_fullImage && !self->_started) {
                    UIImageView *t = self->_isVideo ? self->_poster : self->_imageView;
                    if (!t.image) { t.image = blurred; }
                }
            }];
        }
    }
    [self showLoadingSpinner];
}

- (void)showLoadingSpinner {
    if (_loadingSpinner) { _loadingSpinner.hidden = NO; [_loadingSpinner startAnimating]; return; }
    _loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _loadingSpinner.color = UIColor.whiteColor;
    _loadingSpinner.hidesWhenStopped = YES;
    _loadingSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_loadingSpinner];
    [NSLayoutConstraint activateConstraints:@[
        [_loadingSpinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_loadingSpinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
    [_loadingSpinner startAnimating];
}

- (void)hideLoadingSpinner { [_loadingSpinner stopAnimating]; }

/// 失效占位覆盖层（大图查看器）：盖满 self.view，⊘ + 文案；点击穿透（单击手势仍能关闭查看器）。
- (void)showExpiredOverlayForVideo:(BOOL)isVideo {
    if (_expiredOverlay) { return; }
    _downloadButton.hidden = YES; // 失效无字节可存：藏掉保存钮，别留一个点了只弹 toast 的死按钮
    _expiredOverlay = [IMMediaPlaceholder expiredOverlayWithCaption:(isVideo ? @"视频已失效" : @"图片已失效")];
    _expiredOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_expiredOverlay];
    [NSLayoutConstraint activateConstraints:@[
        [_expiredOverlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_expiredOverlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_expiredOverlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_expiredOverlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return _imageView; }

- (void)doubleTapZoom:(UITapGestureRecognizer *)gr {
    if (_scroll.zoomScale > 1.0) {
        [_scroll setZoomScale:1.0 animated:YES];
    } else {
        [_scroll setZoomScale:2.5 animated:YES];
    }
}

#pragma mark - 视频

- (void)setupVideo {
    _videoContainer = [UIView new];
    _videoContainer.backgroundColor = UIColor.blackColor;
    [self.view addSubview:_videoContainer];

    BOOL hasLocalOriginal = [IMOriginalVideoCache hasCacheForFullURL:_url];
    // 已知失效**且本机无原件**（铁律 A：缓存过的照放，无视 404）→ 只画失效占位、**不建播放器/控件就 return**：
    // 否则播放键/进度条/「查看原视频」等控件后加、浮在占位之上还可点，且 AVPlayer 仍连 404（code-review #2）。
    // 实时探测「正在播放中」的 404 需 KVO AVPlayer.status，留待后续。
    if (!hasLocalOriginal && [IMMediaExpiryRegistry.shared isExpiredURL:_url]) {
        [self showExpiredOverlayForVideo:YES];
        [self.view addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
            action:(_chromeless ? @selector(handleContentSingleTap) : @selector(dismissSelf))]];
        return; // 播放器/poster/控件一律不建；teardown 对 nil _player/_originalSession/_timeObserver 均安全
    }

    // 已有本地原件（下载过 / 自己发送成功时收编）→ 直接本地播放：秒开、不耗流量，
    // 「查看原视频」chip 也不再显示（用户反馈：看过原视频后重进不该再问一次）。
    NSURL *u = hasLocalOriginal ? [IMOriginalVideoCache cacheURLForFullURL:_url]
                                : [NSURL URLWithString:_url];
    _usingLocalOriginal = u.isFileURL;
    _player = [AVPlayer playerWithURL:u];
    _playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
    _playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    [_videoContainer.layer addSublayer:_playerLayer];

    _poster = [UIImageView new];
    _poster.contentMode = UIViewContentModeScaleAspectFit;
    _poster.backgroundColor = UIColor.blackColor;
    [_videoContainer addSubview:_poster];
    // 路线 A：封面加载前先显内嵌 thumb 磨砂 + 菊花，封面到达后替换。
    [self showThumbPlaceholder];
    __weak typeof(self) ws = self;
    [[IMVideoThumbnailLoader shared] loadPosterForVideoURL:_url completion:^(UIImage *poster) {
        __strong typeof(ws) self = ws;
        if (self && !self->_started && poster) { self->_poster.image = poster; }
        [self hideLoadingSpinner];
    }];

    // 点击容器：独立打开=开播前播放/播放中暂停；无壳（翻页容器）=转给容器切 chrome（播放走中央键）。
    [_videoContainer addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
        action:(_chromeless ? @selector(handleContentSingleTap) : @selector(togglePlayback))]];

    _playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *play = [UIImage systemImageNamed:@"play.fill"
                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:34 weight:UIImageSymbolWeightBold]];
    // 中央播放按钮改标准 Liquid Glass（72pt 圆钮）。
    UIButtonConfiguration *playCfg = IMGlassButtonConfiguration();
    playCfg.image = play;
    playCfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    playCfg.contentInsets = NSDirectionalEdgeInsetsZero;
    playCfg.baseForegroundColor = UIColor.whiteColor;
    _playButton.configuration = playCfg;
    _playButton.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _playButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_playButton];
    [_playButton addTarget:self action:@selector(togglePlayback) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [_playButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_playButton.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_playButton.widthAnchor constraintEqualToConstant:72],
        [_playButton.heightAnchor constraintEqualToConstant:72],
    ]];

    // 进度更新（约每 0.3s）。
    __weak typeof(self) ws2 = self;
    _timeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.3, 600)
                                                          queue:dispatch_get_main_queue()
                                                     usingBlock:^(CMTime time) { [ws2 syncScrubber]; }];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(videoDidEnd)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification object:_player.currentItem];
    // 解不了码/取不到流时 AVPlayer 只会黑屏不报错 → 监听 item 状态，失败就给明确提示 + 保存入口，
    // 别让用户对着黑框猜。iOS 能解 HEVC，故这条主要兜网络异常与对端发来的异常封装。
    [self observePlaybackFailureOn:_player.currentItem];
}

/// KVO 观察 item.status。换 item（切本地原视频）时必须迁移，dealloc 前必须摘，否则崩。
- (void)observePlaybackFailureOn:(AVPlayerItem *)item {
    if (_observedItem == item) { return; }
    [_observedItem removeObserver:self forKeyPath:@"status"];
    _observedItem = item;
    [_observedItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:NULL];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (![keyPath isEqualToString:@"status"] || ![object isKindOfClass:AVPlayerItem.class]) { return; }
    AVPlayerItem *item = object;
    if (item.status != AVPlayerItemStatusFailed) { return; }
    IMLogWarnWithTag(IMLogTagMedia, @"video_playback_failed error=%@", item.error.localizedDescription ?: @"(nil)");
    dispatch_async(dispatch_get_main_queue(), ^{ [self showPlaybackUnsupported]; });
}

/// 播放失败降级：盖一层说明 + 「保存到相册」，封面继续显示（封面是 JPEG，与视频编码无关）。
- (void)showPlaybackUnsupported {
    if (_unplayableLabel) { return; }
    [self hideLoadingSpinner];
    _playButton.hidden = YES;
    _poster.hidden = NO;
    _unplayableLabel = [UILabel new];
    _unplayableLabel.text = @"无法播放该视频\n可保存后用其他播放器打开";
    _unplayableLabel.numberOfLines = 0;
    _unplayableLabel.textAlignment = NSTextAlignmentCenter;
    _unplayableLabel.textColor = UIColor.whiteColor;
    _unplayableLabel.font = [UIFont systemFontOfSize:15];
    _unplayableLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    _unplayableLabel.layer.cornerRadius = 10;
    _unplayableLabel.layer.masksToBounds = YES;
    _unplayableLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_unplayableLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_unplayableLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_unplayableLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_unplayableLabel.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor multiplier:0.8],
        [_unplayableLabel.heightAnchor constraintGreaterThanOrEqualToConstant:64],
    ]];
}

- (void)togglePlayback {
    if (!_started) {
        _started = YES;
        _poster.hidden = YES;
        [self hideLoadingSpinner];
        [_player play];
        [self setPlaying:YES];
        return;
    }
    if (_player.rate > 0) {
        [_player pause];
        [self setPlaying:NO];
    } else {
        [_player play];
        _player.rate = _speeds[_speedIdx].floatValue;   // 恢复所选倍速
        [self setPlaying:YES];
    }
}

- (void)setPlaying:(BOOL)playing {
    if (_chromeless) {
        // 无壳（沉浸）：中央键作 play↔pause 切换键——图标随播放态变，**可见性由 setAuxControlsHidden: 管**
        // （随 chrome 显隐），不再按播放态隐藏；否则播放中单击只切 chrome、将无暂停入口。
        UIImage *icon = [UIImage systemImageNamed:(playing ? @"pause.fill" : @"play.fill")
                                withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:34 weight:UIImageSymbolWeightBold]];
        UIButtonConfiguration *cfg = _playButton.configuration;
        cfg.image = icon;
        _playButton.configuration = cfg;
    } else {
        _playButton.hidden = playing;   // 独立打开：原行为（播放中隐藏中央键，点画面切播放/暂停）
    }
    [self.contentDelegate mediaViewerContent:self playingChanged:playing]; // 容器据此管 3s 自动隐藏（暂停常显）
}

#pragma mark - 无壳模式：容器驱动/查询接口

- (void)handleContentSingleTap { [self.contentDelegate mediaViewerContentDidSingleTap:self]; }

- (BOOL)isVideoContent { return _isVideo; }
- (BOOL)isVideoPlaying { return _player != nil && _player.rate > 0; }
- (BOOL)hasGalleryEntry { return _onOpenGallery != nil; }
- (void)invokeOpenGallery { [self openGallery]; }

/// 沉浸态（随 chrome 显隐）：隐藏中央播放/暂停键 + 倍速 + 「查看原视频」chip；
/// **进度条 _scrubber / 时间 _timeLabel 常驻不隐**（用户要求保留）。
- (void)setAuxControlsHidden:(BOOL)hidden {
    _playButton.hidden = hidden;
    _speedButton.hidden = hidden;
    _originalChip.hidden = hidden ? YES : !_originalChipVisible; // 恢复到其"本应可见"状态（下载完/本地原件时恒隐）
}

- (void)videoDidEnd {
    [_player seekToTime:kCMTimeZero];
    [self setPlaying:NO];
}

- (void)syncScrubber {
    if (_scrubbing || !_player.currentItem) { return; }
    Float64 cur = CMTimeGetSeconds(_player.currentTime);
    Float64 dur = CMTimeGetSeconds(_player.currentItem.duration);
    if (isnan(dur) || dur <= 0) { return; }
    _scrubber.value = (float)(cur / dur);
    _timeLabel.text = [NSString stringWithFormat:@"%@ / %@", [self mmss:cur], [self mmss:dur]];
}

- (NSString *)mmss:(Float64)sec {
    if (isnan(sec) || sec < 0) { sec = 0; }
    int s = (int)round(sec);
    return [NSString stringWithFormat:@"%02d:%02d", s / 60, s % 60];
}

- (void)scrubberChanged:(UISlider *)s {
    Float64 dur = CMTimeGetSeconds(_player.currentItem.duration);
    if (isnan(dur) || dur <= 0) { return; }
    _timeLabel.text = [NSString stringWithFormat:@"%@ / %@", [self mmss:dur * s.value], [self mmss:dur]];
}

- (void)scrubberBegan:(UISlider *)s { _scrubbing = YES; }

- (void)scrubberEnded:(UISlider *)s {
    Float64 dur = CMTimeGetSeconds(_player.currentItem.duration);
    _scrubbing = NO;
    if (isnan(dur) || dur <= 0) { return; }
    if (!_started) { _started = YES; _poster.hidden = YES; }
    [_player seekToTime:CMTimeMakeWithSeconds(dur * s.value, 600)
        toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

- (void)cycleSpeed {
    _speedIdx = (_speedIdx + 1) % _speeds.count;
    float rate = _speeds[_speedIdx].floatValue;
    [_speedButton setTitle:[NSString stringWithFormat:@"%.1fx", rate] forState:UIControlStateNormal];
    if (_started && _player.rate > 0) { _player.rate = rate; }   // 仅播放中即时生效
}

/// 「查看原视频」（#1）：点击开始下载原始文件（chip 内显示百分比），完成后切换播放本地文件并隐藏 chip。
/// 已缓存过 → 直接切本地播放并隐藏。
- (void)tapOriginal {
    if (_downloadingOriginal) { return; }
    NSURL *local = [self originalCacheURL];
    if ([[NSFileManager defaultManager] fileExistsAtPath:local.path]) {
        [self switchToLocalOriginal:local];
        return;
    }
    NSURL *u = [NSURL URLWithString:_url];
    if (!u) { return; }
    _downloadingOriginal = YES;
    [_originalChip setTitle:@"下载中 0%" forState:UIControlStateNormal];
    _originalSession = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration
                                                     delegate:self delegateQueue:NSOperationQueue.mainQueue];
    [[_originalSession downloadTaskWithURL:u] resume];
}

/// 原视频本地缓存路径（逻辑收敛到 IMOriginalVideoCache，发送侧收编共用同一目录/命名）。
- (NSURL *)originalCacheURL {
    return [IMOriginalVideoCache cacheURLForFullURL:_url];
}

/// 切到本地原视频继续播放（保持进度），并隐藏「查看原视频」chip。
- (void)switchToLocalOriginal:(NSURL *)local {
    CMTime pos = _player.currentTime;
    BOOL wasPlaying = _player.rate > 0;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_player.currentItem];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:local];
    [_player replaceCurrentItemWithPlayerItem:item];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(videoDidEnd)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification object:item];
    [self observePlaybackFailureOn:item]; // 观察对象随之迁移，否则会盯着已废弃的 item
    if (CMTIME_IS_VALID(pos) && CMTimeGetSeconds(pos) > 0.1) {
        [_player seekToTime:pos toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    }
    if (wasPlaying || !_started) {
        _started = YES; _poster.hidden = YES;
        [_player play];
        _player.rate = _speeds[_speedIdx].floatValue;
        [self setPlaying:YES];
    }
    _originalChip.hidden = YES;
    _originalChipVisible = NO; // 已切本地原件：chip 恒隐（沉浸态恢复也不再显）
    [self im_showToast:@"已切换为原视频"];
}

#pragma mark - NSURLSessionDownloadDelegate（原视频下载进度，#1）

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    if (totalBytesExpectedToWrite <= 0) { return; }
    int pct = (int)(totalBytesWritten * 100 / totalBytesExpectedToWrite);
    [_originalChip setTitle:[NSString stringWithFormat:@"下载中 %d%%", pct] forState:UIControlStateNormal];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    NSURL *dst = [self originalCacheURL];
    [[NSFileManager defaultManager] removeItemAtURL:dst error:NULL];
    NSError *mv = nil;
    [[NSFileManager defaultManager] moveItemAtURL:location toURL:dst error:&mv];
    _downloadingOriginal = NO;
    [session finishTasksAndInvalidate];
    _originalSession = nil;
    if (mv) {
        [_originalChip setTitle:@"查看原视频" forState:UIControlStateNormal];
        [self im_showToast:@"下载失败"];
        return;
    }
    [self switchToLocalOriginal:dst];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (!error) { return; } // 成功路径已在 didFinishDownloading 处理
    _downloadingOriginal = NO;
    [session finishTasksAndInvalidate];
    _originalSession = nil;
    [_originalChip setTitle:@"查看原视频" forState:UIControlStateNormal];
    [self im_showToast:@"下载失败，请重试"];
}

#pragma mark - 通用控件（关闭 / 下载 / 媒体库 / 视频进度条）

- (void)setupCommonControls {
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    // 无壳模式（翻页容器托管）：✕/下载/媒体库/更多 一律不建——由容器固定层统一绘制并绑定当前页，
    // 翻页时不随内容滑动。此处只保留「视频底部进度条」部分（随页，沉浸态由 setAuxControlsHidden: 协调）。
    if (_chromeless) { [self setupVideoBottomRowIfNeeded:safe]; return; }

    _closeButton = [self circleButtonWithSymbol:@"xmark" pointSize:16];
    [_closeButton addTarget:self action:@selector(dismissSelf) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_closeButton];
    [NSLayoutConstraint activateConstraints:@[
        [_closeButton.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:14],
        [_closeButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [_closeButton.widthAnchor constraintEqualToConstant:40],
        [_closeButton.heightAnchor constraintEqualToConstant:40],
    ]];

    // 右下角一排：媒体库（可选）+ 下载。
    _downloadButton = [self circleButtonWithSymbol:@"arrow.down.to.line" pointSize:16];
    [_downloadButton addTarget:self action:@selector(saveToAlbum) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_downloadButton];
    [NSLayoutConstraint activateConstraints:@[
        [_downloadButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [_downloadButton.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16],
        [_downloadButton.widthAnchor constraintEqualToConstant:44],
        [_downloadButton.heightAnchor constraintEqualToConstant:44],
    ]];

    UIView *rightAnchorView = _downloadButton;
    if (_onOpenGallery) {
        _galleryButton = [self circleButtonWithSymbol:@"square.grid.2x2" pointSize:16];
        [_galleryButton addTarget:self action:@selector(openGallery) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:_galleryButton];
        [NSLayoutConstraint activateConstraints:@[
            [_galleryButton.trailingAnchor constraintEqualToAnchor:_downloadButton.leadingAnchor constant:-14],
            [_galleryButton.centerYAnchor constraintEqualToAnchor:_downloadButton.centerYAnchor],
            [_galleryButton.widthAnchor constraintEqualToConstant:44],
            [_galleryButton.heightAnchor constraintEqualToConstant:44],
        ]];
        rightAnchorView = _galleryButton;
    }
    if (self.moreActions.count > 0) {
        UIButton *more = [self circleButtonWithSymbol:@"ellipsis" pointSize:16];
        [more addTarget:self action:@selector(showMoreSheet) forControlEvents:UIControlEventTouchUpInside];
        _moreButton = more;
        [self.view addSubview:more];
        [NSLayoutConstraint activateConstraints:@[
            [more.trailingAnchor constraintEqualToAnchor:rightAnchorView.leadingAnchor constant:-14],
            [more.centerYAnchor constraintEqualToAnchor:_downloadButton.centerYAnchor],
            [more.widthAnchor constraintEqualToConstant:44],
            [more.heightAnchor constraintEqualToConstant:44],
        ]];
        rightAnchorView = more;
    }

    [self setupVideoBottomRowIfNeeded:safe];
}

/// 视频底部：时间 + 进度条 + 倍速；左下「查看原视频」chip。图片页直接返回。
/// 进度条随视频页（无壳时也在页内、翻页时随内容，沉浸态保留）。锚点在有 ✕/下载壳时贴其上方，
/// 无壳（翻页容器）时用等价的固定常量，使容器画在同位的下载/更多键与本行不重叠、对齐。
- (void)setupVideoBottomRowIfNeeded:(UILayoutGuide *)safe {
    if (!_isVideo) { return; }

    _timeLabel = [UILabel new];
    _timeLabel.textColor = UIColor.whiteColor;
    _timeLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
    _timeLabel.text = @"00:00 / 00:00";
    _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _scrubber = [UISlider new];
    _scrubber.minimumTrackTintColor = UIColor.whiteColor;
    _scrubber.translatesAutoresizingMaskIntoConstraints = NO;
    [_scrubber addTarget:self action:@selector(scrubberBegan:) forControlEvents:UIControlEventTouchDown];
    [_scrubber addTarget:self action:@selector(scrubberChanged:) forControlEvents:UIControlEventValueChanged];
    [_scrubber addTarget:self action:@selector(scrubberEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    _speedButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_speedButton setTitle:@"倍速" forState:UIControlStateNormal];
    [_speedButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _speedButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _speedButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_speedButton addTarget:self action:@selector(cycleSpeed) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_timeLabel, _scrubber, _speedButton]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row setCustomSpacing:16 afterView:_scrubber];
    [self.view addSubview:row];
    // 下载键 44pt 贴 safe.bottom-16 → 其上沿 = safe.bottom-60；本行贴其上方 -14 = safe.bottom-74。
    // 无壳时无 _downloadButton，用等价常量复刻同一高度（容器把下载键画在同处）。
    NSLayoutConstraint *rowBottom = _downloadButton
        ? [row.bottomAnchor constraintEqualToAnchor:_downloadButton.topAnchor constant:-14]
        : [row.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-74];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        rowBottom,
    ]];

    if (_usingLocalOriginal) { return; } // 播的已是本地原件：无需「查看原视频」chip 与 HEAD 探体积
    _originalChip = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *originalConfig = [UIButtonConfiguration plainButtonConfiguration];
    originalConfig.title = @"查看原视频";
    originalConfig.baseForegroundColor = UIColor.whiteColor;
    originalConfig.contentInsets = NSDirectionalEdgeInsetsMake(6, 12, 6, 12);
    originalConfig.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attrs) {
        NSMutableDictionary *updated = [attrs mutableCopy];
        updated[NSFontAttributeName] = [UIFont systemFontOfSize:13];
        return updated;
    };
    _originalChip.configuration = originalConfig;
    _originalChip.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    _originalChip.layer.cornerRadius = 14;
    _originalChip.translatesAutoresizingMaskIntoConstraints = NO;
    [_originalChip addTarget:self action:@selector(tapOriginal) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_originalChip];
    _originalChipVisible = YES; // 已建且当前应显（沉浸态恢复用）
    // 下载键中心 = safe.bottom-38；无壳时复刻同高，使 chip 与容器下载键同排。
    NSLayoutConstraint *chipCenterY = _downloadButton
        ? [_originalChip.centerYAnchor constraintEqualToAnchor:_downloadButton.centerYAnchor]
        : [_originalChip.centerYAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-38];
    [NSLayoutConstraint activateConstraints:@[
        [_originalChip.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        chipCenterY,
    ]];
    // 附带展示原视频体积（best-effort HEAD）。
    [self fetchVideoSize];
}

- (UIButton *)circleButtonWithSymbol:(NSString *)name pointSize:(CGFloat)pt {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *img = [UIImage systemImageNamed:name
                          withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:pt weight:UIImageSymbolWeightSemibold]];
    // 标准 Liquid Glass 圆钮：iOS26 原生玻璃（自带按压放大）；旧系统 gray() 降级。
    UIButtonConfiguration *cfg = IMGlassButtonConfiguration();
    cfg.image = img;
    cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule; // 方形 frame → 圆形
    cfg.contentInsets = NSDirectionalEdgeInsetsZero;
    cfg.baseForegroundColor = UIColor.whiteColor;
    b.configuration = cfg;
    // 查看器恒为全屏黑底：强制暗色外观，使玻璃/灰底偏深、白图标始终有对比。
    b.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    return b;
}

- (void)fetchVideoSize {
    NSURL *u = [NSURL URLWithString:_url];
    if (!u) { return; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u];
    req.HTTPMethod = @"HEAD";
    req.timeoutInterval = 8;
    __weak typeof(self) ws = self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *resp, NSError *err) {
        long long len = resp.expectedContentLength;
        if (len <= 0) { return; }
        double mb = (double)len / (1024.0 * 1024.0);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            NSString *size = mb >= 1.0 ? [NSString stringWithFormat:@"%.0fMB", mb]
                                       : [NSString stringWithFormat:@"%.0fKB", (double)len / 1024.0];
            [self->_originalChip setTitle:[NSString stringWithFormat:@"查看原视频 %@", size] forState:UIControlStateNormal];
        });
    }] resume];
}

/// 「更多」锚点菜单：内置「下载」（不关查看器）+ 外部动作（先关查看器再执行，回到聊天页上下文）。
/// 锚定右下角「⋯」按钮，靠近屏幕下沿时 IMPopoverCard 自动向上展开。
- (void)showMoreSheet {
    __weak typeof(self) ws = self;
    NSMutableArray<IMPopoverCardItem *> *items = [NSMutableArray array];
    [items addObject:[IMPopoverCardItem itemWithTitle:@"下载" symbol:@"arrow.down.to.line" destructive:NO handler:^{
        [ws saveToAlbum];
    }]];
    for (IMPopoverCardItem *ext in self.moreActions) {
        void (^inner)(void) = ext.handler;
        [items addObject:[IMPopoverCardItem itemWithTitle:ext.title symbol:ext.symbol destructive:ext.destructive handler:^{
            __strong typeof(ws) self = ws;
            [self dismissViewControllerAnimated:YES completion:^{ if (inner) { inner(); } }];
        }]];
    }
    [IMPopoverCard presentFromAnchor:_moreButton inHostView:self.view items:items];
}

- (void)openGallery {
    dispatch_block_t cb = _onOpenGallery;
    [self dismissViewControllerAnimated:YES completion:^{ if (cb) { cb(); } }];
}

#pragma mark - 保存到相册（下载）

- (void)saveToAlbum {
    if (_saving) { return; }
    // 失效守卫：曾可用媒体被服务端清理(404) → 无字节可存。铁律A（本机有缓存/原件则仍可存）天然成立：
    // 有缓存/原件时加载不会 404、URL 不会被登记失效，故命中 isExpiredURL 即代表无本机字节，直接拦。
    if ([IMMediaExpiryRegistry.shared isExpiredURL:_url]) {
        [self im_showToast:@"该文件已失效，无法保存"];
        return;
    }
    _saving = YES;
    __weak typeof(self) ws = self;
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
                self->_saving = NO;
                [self im_showToast:@"请在设置中允许访问相册"];
                return;
            }
            if (self->_isVideo) { [self saveVideo]; } else { [self saveImage]; }
        });
    }];
}

- (void)saveImage {
    UIImage *img = _fullImage ?: _imageView.image;
    if (!img) { _saving = NO; [self im_showToast:@"图片未加载完成"]; return; }
    __weak typeof(self) ws = self;
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetChangeRequest creationRequestForAssetFromImage:img];
    } completionHandler:^(BOOL success, NSError *error) {
        [ws finishSave:success];
    }];
}

- (void)saveVideo {
    [self im_showToast:@"正在保存…"];
    NSURL *u = [NSURL URLWithString:_url];
    __weak typeof(self) ws = self;
    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:u
        completionHandler:^(NSURL *location, NSURLResponse *resp, NSError *error) {
        if (error || !location) { [ws finishSave:NO]; return; }
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"mp4"]];
        NSURL *tmpURL = [NSURL fileURLWithPath:tmp];
        NSError *mv = nil;
        [[NSFileManager defaultManager] moveItemAtURL:location toURL:tmpURL error:&mv];
        if (mv) { [ws finishSave:NO]; return; }
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:tmpURL];
        } completionHandler:^(BOOL success, NSError *e) {
            [[NSFileManager defaultManager] removeItemAtURL:tmpURL error:NULL];
            [ws finishSave:success];
        }];
    }];
    [task resume];
}

- (void)finishSave:(BOOL)success {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_saving = NO;
        [self im_showToast:success ? @"已保存到相册" : @"保存失败"];
    });
}

#pragma mark - 关闭 / 清理

- (void)dismissSelf { [self dismissViewControllerAnimated:YES completion:nil]; }

/// 退出页面即停播 + 取消原视频下载。不能只依赖 dealloc：NSURLSession 以 delegate 模式**强持有**
/// 本控制器，下载不结束 dealloc 永远不来——曾导致退出后下载完成、switchToLocalOriginal 里的
/// play 把声音在后台拉起来（幽灵播放）。invalidateAndCancel 同时打破这条保活链。
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [_player pause];
    [_originalSession invalidateAndCancel];
    _originalSession = nil;
    _downloadingOriginal = NO;
}

- (void)dealloc {
    if (_timeObserver && _player) { [_player removeTimeObserver:_timeObserver]; }
    [_observedItem removeObserver:self forKeyPath:@"status"]; // 不摘会崩（KVO 未注销即释放）
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_originalSession invalidateAndCancel]; // 查看器关闭即取消进行中的原视频下载
    [_player pause];
}

@end
