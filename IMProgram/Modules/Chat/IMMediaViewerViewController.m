//  IMMediaViewerViewController.m

#import "IMMediaViewerViewController.h"
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "UIViewController+IMToast.h"
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>

@interface IMMediaViewerViewController () <UIScrollViewDelegate>
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
    id                _timeObserver;
    BOOL              _started;    // 是否已首次播放
    BOOL              _scrubbing;
    NSArray<NSNumber *> *_speeds;
    NSUInteger        _speedIdx;

    // 通用控件
    UIButton *_closeButton;
    UIButton *_downloadButton;
    UIButton *_galleryButton;
    BOOL      _saving;
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

    UITapGestureRecognizer *single = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissSelf)];
    UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapZoom:)];
    dbl.numberOfTapsRequired = 2;
    [single requireGestureRecognizerToFail:dbl];
    [_imageView addGestureRecognizer:single];
    [_imageView addGestureRecognizer:dbl];

    // 拉取（可能更清晰的）原图，兼作下载源。
    __weak typeof(self) ws = self;
    [[IMImageLoader shared] loadImageURL:_url completion:^(UIImage *image) {
        __strong typeof(ws) self = ws;
        if (self && image) { self->_imageView.image = image; self->_fullImage = image; }
    }];
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

    NSURL *u = [NSURL URLWithString:_url];
    _player = [AVPlayer playerWithURL:u];
    _playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
    _playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    [_videoContainer.layer addSublayer:_playerLayer];

    _poster = [UIImageView new];
    _poster.contentMode = UIViewContentModeScaleAspectFit;
    _poster.backgroundColor = UIColor.blackColor;
    [_videoContainer addSubview:_poster];
    __weak typeof(self) ws = self;
    [[IMVideoThumbnailLoader shared] loadPosterForVideoURL:_url completion:^(UIImage *poster) {
        __strong typeof(ws) self = ws;
        if (self && !self->_started) { self->_poster.image = poster; }
    }];

    // 点击容器：开播前=开始播放；播放中=暂停/继续。
    [_videoContainer addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(togglePlayback)]];

    _playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *play = [UIImage systemImageNamed:@"play.fill"
                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:34 weight:UIImageSymbolWeightBold]];
    [_playButton setImage:play forState:UIControlStateNormal];
    _playButton.tintColor = UIColor.whiteColor;
    _playButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    _playButton.layer.cornerRadius = 36;
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
}

- (void)togglePlayback {
    if (!_started) {
        _started = YES;
        _poster.hidden = YES;
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
    _playButton.hidden = playing;   // 播放中隐藏中央按钮；暂停显示
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

- (void)tapOriginal {
    // 本版本单一原始文件即最高清（无压缩变体），点击等价于开始播放原视频。
    if (!_started) { [self togglePlayback]; }
    else if (_player.rate == 0) { [self togglePlayback]; }
}

#pragma mark - 通用控件（关闭 / 下载 / 媒体库 / 视频进度条）

- (void)setupCommonControls {
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

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

    if (!_isVideo) { return; }

    // —— 视频专属：底部时间 + 进度条 + 倍速；左下「查看原视频」——
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
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [row.bottomAnchor constraintEqualToAnchor:_downloadButton.topAnchor constant:-14],
    ]];

    _originalChip = [UIButton buttonWithType:UIButtonTypeSystem];
    [_originalChip setTitle:@"查看原视频" forState:UIControlStateNormal];
    [_originalChip setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _originalChip.titleLabel.font = [UIFont systemFontOfSize:13];
    _originalChip.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    _originalChip.contentEdgeInsets = UIEdgeInsetsMake(6, 12, 6, 12);
    _originalChip.layer.cornerRadius = 14;
    _originalChip.translatesAutoresizingMaskIntoConstraints = NO;
    [_originalChip addTarget:self action:@selector(tapOriginal) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_originalChip];
    [NSLayoutConstraint activateConstraints:@[
        [_originalChip.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [_originalChip.centerYAnchor constraintEqualToAnchor:_downloadButton.centerYAnchor],
    ]];
    // 附带展示原视频体积（best-effort HEAD）。
    [self fetchVideoSize];
}

- (UIButton *)circleButtonWithSymbol:(NSString *)name pointSize:(CGFloat)pt {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *img = [UIImage systemImageNamed:name
                          withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:pt weight:UIImageSymbolWeightSemibold]];
    [b setImage:img forState:UIControlStateNormal];
    b.tintColor = UIColor.whiteColor;
    b.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    b.layer.cornerRadius = 20;
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

- (void)openGallery {
    dispatch_block_t cb = _onOpenGallery;
    [self dismissViewControllerAnimated:YES completion:^{ if (cb) { cb(); } }];
}

#pragma mark - 保存到相册（下载）

- (void)saveToAlbum {
    if (_saving) { return; }
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
        _saving = NO;
        [self im_showToast:success ? @"已保存到相册" : @"保存失败"];
    });
}

#pragma mark - 关闭 / 清理

- (void)dismissSelf { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)dealloc {
    if (_timeObserver && _player) { [_player removeTimeObserver:_timeObserver]; }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_player pause];
}

@end
