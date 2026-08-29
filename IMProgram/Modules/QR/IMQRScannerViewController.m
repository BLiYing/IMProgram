//  IMQRScannerViewController.m

#import "IMQRScannerViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <PhotosUI/PhotosUI.h>

#import "IMAnimator.h"
#import "IMHTTPService.h"
#import "IMLog.h"
#import "IMQRCardView.h"
#import "IMQRImage.h"
#import "IMQRModels.h"
#import "IMUserCard.h"
#import "UIViewController+IMToast.h"
#import "IMAccountIdentity.h"

static const CGFloat kIMReticleSide = 220;

@interface IMQRScannerViewController () <AVCaptureMetadataOutputObjectsDelegate, PHPickerViewControllerDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;

@property (nonatomic, strong, nullable) AVCaptureSession *session;
@property (nonatomic, strong, nullable) AVCaptureVideoPreviewLayer *preview;
@property (nonatomic, strong) dispatch_queue_t sessionQueue;   ///< startRunning 阻塞，绝不能上主线程
@property (nonatomic, assign) BOOL handling;                   ///< 已命中一枚码，忽略后续帧

@property (nonatomic, strong) UIView *scanPage;                ///< 「扫码」页签内容（取景框 + 提示 + 工具）
@property (nonatomic, strong) UIView *cardPage;                ///< 「我的二维码」页签内容
@property (nonatomic, strong) IMQRCardView *cardView;
@property (nonatomic, assign) BOOL cardLoaded;
@property (nonatomic, copy, nullable) NSString *myCardURL;   ///< 名片码内容串
@property (nonatomic, copy, nullable) NSString *myNickname;  ///< 卡片展示名（拉到资料后补正）
@property (nonatomic, copy, nullable) NSString *myUsername;  ///< 公开句柄：副标题显 @xxx，绝不显内部 ID
@property (nonatomic, copy, nullable) NSString *myAvatarURL;
@property (nonatomic, strong) UIView *deniedView;              ///< 相机权限被拒的页面内引导
@property (nonatomic, strong) UIView *reticle;
@property (nonatomic, strong) UIView *scanLine;
@property (nonatomic, strong) UIButton *torchButton;
@property (nonatomic, strong) UIButton *scanTab;
@property (nonatomic, strong) UIButton *cardTab;
@end

@implementation IMQRScannerViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        _sessionQueue = dispatch_queue_create("com.improgram.qr.session", DISPATCH_QUEUE_SERIAL);
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor; // 相机页恒暗色，不跟随外观设置
    [self setupChrome];
    [self setupScanPage];
    [self setupCardPage];
    [self requestCameraAccess];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // 从后台/相册选择器/系统弹窗返回时恢复取景——只在「扫码」页且未命中码时重启（startSession 内部再判 isRunning，重复调用无副作用）。
    if (!self.scanPage.hidden && !self.handling) { [self startSession]; }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.preview.frame = self.scanPage.bounds;
    // 只认取景框内的码：整屏识别会在多码画面里随机命中一个（用户明明已经对准了其中一个）。
    // reticle 与 preview 同挂 scanPage，故 frame 直接可用，无需坐标换算。
    if (self.preview) {
        AVCaptureMetadataOutput *output = (AVCaptureMetadataOutput *)self.session.outputs.firstObject;
        if ([output isKindOfClass:AVCaptureMetadataOutput.class]) {
            output.rectOfInterest = [self.preview metadataOutputRectOfInterestForRect:self.reticle.frame];
        }
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self setTorchOn:NO];
    [self stopSession];
}

- (BOOL)prefersStatusBarHidden { return NO; }
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

#pragma mark - 固定装饰（顶栏 / 页签）

- (void)setupChrome {
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    close.tintColor = UIColor.whiteColor;
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"扫一扫";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [self.view addSubview:title];

    self.torchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.torchButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.torchButton setImage:[UIImage systemImageNamed:@"flashlight.off.fill"] forState:UIControlStateNormal];
    self.torchButton.tintColor = UIColor.whiteColor;
    [self.torchButton addTarget:self action:@selector(toggleTorch) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.torchButton];

    self.scanTab = [self makeTabWithTitle:@"扫码" action:@selector(showScanPage)];
    self.cardTab = [self makeTabWithTitle:@"我的二维码" action:@selector(showCardPage)];
    UIStackView *tabs = [[UIStackView alloc] initWithArrangedSubviews:@[ self.scanTab, self.cardTab ]];
    tabs.translatesAutoresizingMaskIntoConstraints = NO;
    tabs.axis = UILayoutConstraintAxisHorizontal;
    tabs.spacing = 26;
    [self.view addSubview:tabs];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [close.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:18],
        [close.topAnchor constraintEqualToAnchor:safe.topAnchor constant:6],
        [close.widthAnchor constraintEqualToConstant:36],
        [close.heightAnchor constraintEqualToConstant:36],
        [title.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [title.centerYAnchor constraintEqualToAnchor:close.centerYAnchor],
        [self.torchButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-18],
        [self.torchButton.centerYAnchor constraintEqualToAnchor:close.centerYAnchor],
        [self.torchButton.widthAnchor constraintEqualToConstant:36],
        [self.torchButton.heightAnchor constraintEqualToConstant:36],
        [tabs.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [tabs.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-14],
    ]];
    [self updateTabs];
}

- (UIButton *)makeTabWithTitle:(NSString *)title action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:14];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)updateTabs {
    BOOL scanning = !self.scanPage.hidden;
    [self.scanTab setTitleColor:(scanning ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:0.5])
                       forState:UIControlStateNormal];
    [self.cardTab setTitleColor:(scanning ? [UIColor colorWithWhite:1 alpha:0.5] : UIColor.whiteColor)
                       forState:UIControlStateNormal];
    self.torchButton.hidden = !scanning;
}

#pragma mark - 扫码页

- (void)setupScanPage {
    self.scanPage = [UIView new];
    self.scanPage.translatesAutoresizingMaskIntoConstraints = NO;
    self.scanPage.backgroundColor = UIColor.blackColor;
    [self.view insertSubview:self.scanPage atIndex:0];

    self.reticle = [UIView new];
    self.reticle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scanPage addSubview:self.reticle];
    for (NSInteger i = 0; i < 4; i++) { [self addCornerAtIndex:i]; }

    self.scanLine = [UIView new];
    self.scanLine.translatesAutoresizingMaskIntoConstraints = NO;
    self.scanLine.backgroundColor = [UIColor colorWithRed:0.36 green:0.78 blue:1 alpha:1];
    [self.reticle addSubview:self.scanLine];

    UILabel *hint = [UILabel new];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    hint.text = @"将二维码放入框内，即可自动扫描";
    hint.textColor = [UIColor colorWithWhite:1 alpha:0.82];
    hint.font = [UIFont systemFontOfSize:13];
    hint.numberOfLines = 0;
    hint.textAlignment = NSTextAlignmentCenter;
    [self.scanPage addSubview:hint];

    UIButton *album = [UIButton buttonWithType:UIButtonTypeSystem];
    album.translatesAutoresizingMaskIntoConstraints = NO;
    [album setTitle:@"从相册选择" forState:UIControlStateNormal];
    [album setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    album.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [album addTarget:self action:@selector(pickFromAlbum) forControlEvents:UIControlEventTouchUpInside];
    [self.scanPage addSubview:album];

    [NSLayoutConstraint activateConstraints:@[
        [self.scanPage.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scanPage.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.scanPage.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scanPage.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.reticle.centerXAnchor constraintEqualToAnchor:self.scanPage.centerXAnchor],
        [self.reticle.centerYAnchor constraintEqualToAnchor:self.scanPage.centerYAnchor constant:-40],
        [self.reticle.widthAnchor constraintEqualToConstant:kIMReticleSide],
        [self.reticle.heightAnchor constraintEqualToConstant:kIMReticleSide],

        [self.scanLine.leadingAnchor constraintEqualToAnchor:self.reticle.leadingAnchor constant:8],
        [self.scanLine.trailingAnchor constraintEqualToAnchor:self.reticle.trailingAnchor constant:-8],
        [self.scanLine.topAnchor constraintEqualToAnchor:self.reticle.topAnchor constant:10],
        [self.scanLine.heightAnchor constraintEqualToConstant:2],

        [hint.topAnchor constraintEqualToAnchor:self.reticle.bottomAnchor constant:22],
        [hint.leadingAnchor constraintEqualToAnchor:self.scanPage.leadingAnchor constant:40],
        [hint.trailingAnchor constraintEqualToAnchor:self.scanPage.trailingAnchor constant:-40],

        [album.centerXAnchor constraintEqualToAnchor:self.scanPage.centerXAnchor],
        [album.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:26],
    ]];
}

/// 取景框四角（0 左上 / 1 右上 / 2 左下 / 3 右下）：每角两条细边拼成 L 形，比画遮罩直观。
- (void)addCornerAtIndex:(NSInteger)index {
    UIView *h = [UIView new]; h.translatesAutoresizingMaskIntoConstraints = NO; h.backgroundColor = UIColor.whiteColor;
    UIView *v = [UIView new]; v.translatesAutoresizingMaskIntoConstraints = NO; v.backgroundColor = UIColor.whiteColor;
    [self.reticle addSubview:h];
    [self.reticle addSubview:v];

    BOOL right = (index == 1 || index == 3);
    BOOL bottom = (index == 2 || index == 3);
    NSLayoutXAxisAnchor *hx = right ? h.trailingAnchor : h.leadingAnchor;
    NSLayoutXAxisAnchor *vx = right ? v.trailingAnchor : v.leadingAnchor;
    NSLayoutXAxisAnchor *boxX = right ? self.reticle.trailingAnchor : self.reticle.leadingAnchor;
    NSLayoutYAxisAnchor *hy = bottom ? h.bottomAnchor : h.topAnchor;
    NSLayoutYAxisAnchor *vy = bottom ? v.bottomAnchor : v.topAnchor;
    NSLayoutYAxisAnchor *boxY = bottom ? self.reticle.bottomAnchor : self.reticle.topAnchor;

    [NSLayoutConstraint activateConstraints:@[
        [h.widthAnchor constraintEqualToConstant:26], [h.heightAnchor constraintEqualToConstant:3],
        [v.widthAnchor constraintEqualToConstant:3],  [v.heightAnchor constraintEqualToConstant:26],
        [hx constraintEqualToAnchor:boxX], [hy constraintEqualToAnchor:boxY],
        [vx constraintEqualToAnchor:boxX], [vy constraintEqualToAnchor:boxY],
    ]];
}

- (void)startScanLineAnimation {
    [self.scanLine.layer removeAnimationForKey:@"im_scan"];
    CABasicAnimation *move = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
    move.fromValue = @(0);
    move.toValue = @(kIMReticleSide - 20);
    move.duration = 2.2;
    move.repeatCount = HUGE_VALF;
    move.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.scanLine.layer addAnimation:move forKey:@"im_scan"];
}

#pragma mark - 我的二维码页签

- (void)setupCardPage {
    self.cardPage = [UIView new];
    self.cardPage.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardPage.backgroundColor = UIColor.blackColor;
    self.cardPage.hidden = YES;
    [self.view insertSubview:self.cardPage aboveSubview:self.scanPage];

    self.cardView = [IMQRCardView new];
    self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cardPage addSubview:self.cardView];

    [NSLayoutConstraint activateConstraints:@[
        [self.cardPage.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.cardPage.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.cardPage.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.cardPage.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.cardView.centerYAnchor constraintEqualToAnchor:self.cardPage.centerYAnchor],
        [self.cardView.leadingAnchor constraintEqualToAnchor:self.cardPage.leadingAnchor constant:24],
        [self.cardView.trailingAnchor constraintEqualToAnchor:self.cardPage.trailingAnchor constant:-24],
    ]];
}

- (void)showScanPage {
    self.scanPage.hidden = NO;
    self.cardPage.hidden = YES;
    [self updateTabs];
    [self startSession];
}

- (void)showCardPage {
    self.scanPage.hidden = YES;
    self.cardPage.hidden = NO;
    [self setTorchOn:NO];
    [self updateTabs];
    [self stopSession]; // 不在取景时就别占着摄像头
    [self loadMyCardIfNeeded];
}

- (void)loadMyCardIfNeeded {
    if (self.cardLoaded) { return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:@"登录已失效，请重新登录"]; return; }
    self.cardLoaded = YES;
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService qrMyCardWithToken:token completion:^(NSDictionary *card, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) {
            self.cardLoaded = NO; // 允许切回来重试
            [self im_showToast:error.localizedDescription ?: @"获取名片码失败"];
            return;
        }
        NSString *url = [card[@"url"] isKindOfClass:NSString.class] ? card[@"url"] : nil;
        self.myCardURL = url;
        [self renderMyCard];
        [self loadMyProfileForCard]; // 昵称/头像另拉一次，慢到也只是先显 uid 再补正
    }];
}

/// 把当前已知的昵称/头像/码串灌进卡片。资料未回来时先用 uid 占位——码本身不依赖资料，先能扫要紧。
- (void)renderMyCard {
    NSString *display = IMDisplayName(self.myNickname, self.myUsername);
    // 副标题显示公开句柄，不是 userID——这张卡是给别人扫的，一串随机数字对方认不出是谁。
    NSString *sub = self.myUsername.length > 0 ? [@"@" stringByAppendingString:self.myUsername] : @"";
    [self.cardView configureWithAvatarURL:self.myAvatarURL seed:self.userID name:display
                                 subtitle:sub
                                 qrString:self.myCardURL hint:@"扫描二维码，加我为朋友"];
}

/// 拉本人资料补齐卡片的昵称+头像：这张卡是给对方看的，只显 uid 对方认不出是谁
/// （与「我」页进入的名片码页保持一致）。失败静默回退 uid。
- (void)loadMyProfileForCard {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0 || self.myNickname.length > 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService myProfileWithToken:token completion:^(IMUserCard *profile, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || error || !profile) { return; }
        self.myNickname = profile.displayName;
        self.myUsername = profile.username;
        self.myAvatarURL = profile.avatarURL;
        [self renderMyCard];
    }];
}

#pragma mark - 相机权限与会话

- (void)requestCameraAccess {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) { [self setupSession]; return; }
    if (status == AVAuthorizationStatusNotDetermined) {
        __weak typeof(self) ws = self;
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(ws) self = ws;
                if (!self) { return; }
                if (granted) { [self setupSession]; } else { [self showDeniedView]; }
            });
        }];
        return;
    }
    [self showDeniedView]; // denied / restricted：系统弹窗不会再出现，必须给页面内引导
}

- (void)setupSession {
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!device) { [self showDeniedViewWithTitle:@"没有可用的摄像头" detail:@"你可以从相册选择一张带二维码的图片。"]; return; }
    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (!input || error) {
        IMLogErrorWithTag(IMLogTagUI, @"qr scanner input failed: %@", error.localizedDescription);
        [self showDeniedViewWithTitle:@"无法打开摄像头" detail:@"你可以从相册选择一张带二维码的图片。"];
        return;
    }
    AVCaptureSession *session = [AVCaptureSession new];
    session.sessionPreset = AVCaptureSessionPresetHigh;
    if (![session canAddInput:input]) { [self showDeniedViewWithTitle:@"无法打开摄像头" detail:@"你可以从相册选择一张带二维码的图片。"]; return; }
    [session addInput:input];

    AVCaptureMetadataOutput *output = [AVCaptureMetadataOutput new];
    if (![session canAddOutput:output]) { [self showDeniedViewWithTitle:@"无法打开摄像头" detail:@"你可以从相册选择一张带二维码的图片。"]; return; }
    [session addOutput:output];
    [output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
    output.metadataObjectTypes = @[ AVMetadataObjectTypeQRCode ];

    AVCaptureVideoPreviewLayer *preview = [AVCaptureVideoPreviewLayer layerWithSession:session];
    preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    preview.frame = self.scanPage.bounds;
    [self.scanPage.layer insertSublayer:preview atIndex:0];

    self.session = session;
    self.preview = preview;
    [self startSession];
    [self startScanLineAnimation];
    [self.view setNeedsLayout];
}

// 起停一律「派发到串行队列、在队列里现判 isRunning」。**不能在主线程判**：start/stop 是异步执行的，
// 主线程读到的 isRunning 是上一次派发生效前的旧值——快速切「我的二维码」→「扫码」时，start 会看到
// 还没来得及停的 isRunning=YES 而直接 return，随后排队的 stopRunning 才执行，相机就永久停住了。
- (void)startSession {
    AVCaptureSession *session = self.session;
    if (!session) { return; }
    self.handling = NO;
    dispatch_async(self.sessionQueue, ^{ if (!session.isRunning) { [session startRunning]; } });
}

- (void)stopSession {
    AVCaptureSession *session = self.session;
    if (!session) { return; }
    dispatch_async(self.sessionQueue, ^{ if (session.isRunning) { [session stopRunning]; } });
}

- (void)showDeniedView {
    [self showDeniedViewWithTitle:@"需要相机权限"
                           detail:@"开启后即可扫描二维码加好友、进群。\n你也可以直接从相册选择一张带码的图片。"];
}

- (void)showDeniedViewWithTitle:(NSString *)title detail:(NSString *)detail {
    if (self.deniedView) { return; }
    UIView *box = [UIView new];
    box.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *t = [UILabel new];
    t.translatesAutoresizingMaskIntoConstraints = NO;
    t.text = title;
    t.textColor = UIColor.whiteColor;
    t.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    t.textAlignment = NSTextAlignmentCenter;

    UILabel *d = [UILabel new];
    d.translatesAutoresizingMaskIntoConstraints = NO;
    d.text = detail;
    d.numberOfLines = 0;
    d.textAlignment = NSTextAlignmentCenter;
    d.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    d.font = [UIFont systemFontOfSize:13];

    UIButton *settings = [UIButton buttonWithType:UIButtonTypeSystem];
    settings.translatesAutoresizingMaskIntoConstraints = NO;
    [settings setTitle:@"去设置开启" forState:UIControlStateNormal];
    [settings setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    settings.backgroundColor = [UIColor colorWithRed:0.04 green:0.52 blue:1 alpha:1];
    settings.layer.cornerRadius = 12;
    settings.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [settings addTarget:self action:@selector(openSystemSettings) forControlEvents:UIControlEventTouchUpInside];

    [box addSubview:t]; [box addSubview:d]; [box addSubview:settings];
    [self.scanPage addSubview:box];
    self.deniedView = box;

    [NSLayoutConstraint activateConstraints:@[
        [box.centerXAnchor constraintEqualToAnchor:self.scanPage.centerXAnchor],
        [box.centerYAnchor constraintEqualToAnchor:self.scanPage.centerYAnchor],
        [box.leadingAnchor constraintEqualToAnchor:self.scanPage.leadingAnchor constant:34],
        [box.trailingAnchor constraintEqualToAnchor:self.scanPage.trailingAnchor constant:-34],
        [t.topAnchor constraintEqualToAnchor:box.topAnchor],
        [t.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
        [t.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],
        [d.topAnchor constraintEqualToAnchor:t.bottomAnchor constant:10],
        [d.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
        [d.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],
        [settings.topAnchor constraintEqualToAnchor:d.bottomAnchor constant:20],
        [settings.centerXAnchor constraintEqualToAnchor:box.centerXAnchor],
        [settings.widthAnchor constraintEqualToConstant:180],
        [settings.heightAnchor constraintEqualToConstant:44],
        [settings.bottomAnchor constraintEqualToAnchor:box.bottomAnchor],
    ]];
    // 取景框在无相机时没有意义，藏掉；「从相册选择」仍在（不需要相机的那条路）。
    self.reticle.hidden = YES;
}

- (void)openSystemSettings {
    NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if (url) { [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil]; }
}

#pragma mark - 手电筒

- (void)toggleTorch {
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    [self setTorchOn:!(device.torchMode == AVCaptureTorchModeOn)];
}

- (void)setTorchOn:(BOOL)on {
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!device.hasTorch || !device.isTorchAvailable) { return; }
    NSError *error = nil;
    if (![device lockForConfiguration:&error]) {
        IMLogWarnWithTag(IMLogTagUI, @"torch lock failed: %@", error.localizedDescription);
        return;
    }
    device.torchMode = on ? AVCaptureTorchModeOn : AVCaptureTorchModeOff;
    [device unlockForConfiguration];
    [self.torchButton setImage:[UIImage systemImageNamed:(on ? @"flashlight.on.fill" : @"flashlight.off.fill")]
                      forState:UIControlStateNormal];
}

#pragma mark - 相机命中

- (void)captureOutput:(AVCaptureOutput *)output
didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)metadataObjects
       fromConnection:(AVCaptureConnection *)connection {
    if (self.handling) { return; }
    for (AVMetadataObject *obj in metadataObjects) {
        if (![obj isKindOfClass:AVMetadataMachineReadableCodeObject.class]) { continue; }
        NSString *raw = ((AVMetadataMachineReadableCodeObject *)obj).stringValue;
        if (raw.length == 0) { continue; }
        [self handleRaw:raw];
        return;
    }
}

/// 命中即停帧 + 震动，再去 resolve——先给反馈、后跳页，避免"画面自己闪了一下"的失控感。
- (void)handleRaw:(NSString *)raw {
    if (self.handling) { return; }
    self.handling = YES;
    [self stopSession];
    [self setTorchOn:NO];
    [IMAnimator lightImpact];

    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) {
        [self finishWithResolved:nil raw:raw error:[NSError errorWithDomain:@"IMQR" code:-1
                                                                  userInfo:@{ NSLocalizedDescriptionKey: @"登录已失效，请重新登录" }]];
        return;
    }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService qrResolveWithToken:token raw:raw completion:^(NSDictionary *resolved, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        [self finishWithResolved:(error ? nil : [IMQRResolved fromDictionary:resolved]) raw:raw error:error];
    }];
}

- (void)finishWithResolved:(IMQRResolved *)resolved raw:(NSString *)raw error:(NSError *)error {
    void (^callback)(IMQRResolved *, NSString *, NSError *) = self.onResult;
    [self dismissViewControllerAnimated:YES completion:^{
        if (callback) { callback(resolved, raw ?: @"", error); }
    }];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 相册识别

- (void)pickFromAlbum {
    PHPickerConfiguration *cfg = [PHPickerConfiguration new]; // 不带 photoLibrary：进程外选择器，免相册权限
    cfg.filter = PHPickerFilter.imagesFilter;
    cfg.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:cfg];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *first = results.firstObject;
    if (!first) { return; }
    __weak typeof(self) ws = self;
    [first.itemProvider loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (![object isKindOfClass:UIImage.class]) {
                [self im_showToast:error.localizedDescription ?: @"无法读取该图片"];
                return;
            }
            [self handleDecodedCodes:[IMQRImage decodeAllInImage:(UIImage *)object]];
        });
    }];
}

/// 一图多码时让用户点选，**不默认取第一个**（群公告截图常同时有群码与客服码）。
- (void)handleDecodedCodes:(NSArray<NSString *> *)codes {
    if (codes.count == 0) { [self im_showToast:@"图片里没有发现二维码"]; return; }
    if (codes.count == 1) { [self handleRaw:codes.firstObject]; return; }

    UIAlertController *sheet =
        [UIAlertController alertControllerWithTitle:@"这张图里有多个二维码"
                                            message:@"选择你要打开的那个"
                                     preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) ws = self;
    for (NSString *code in codes) {
        [sheet addAction:[UIAlertAction actionWithTitle:[self labelForRaw:code] style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *_Nonnull a) { [ws handleRaw:code]; }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view; // iPad 锚点
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),
                                                                CGRectGetMaxY(self.view.bounds) - 60, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

/// 候选码的可读摘要。本站码按前缀标注，其余给域名或文本首段——只为让用户分得清，不做语义判定（那在服务端）。
- (NSString *)labelForRaw:(NSString *)raw {
    if ([raw containsString:@"/q/u/"]) { return @"名片码（本应用）"; }
    if ([raw containsString:@"/q/g/"]) { return @"群二维码（本应用）"; }
    NSString *domain = IMQRUnknownDomain(raw);
    if (domain.length > 0) { return [NSString stringWithFormat:@"网址 · %@", domain]; }
    return raw.length > 20 ? [[raw substringToIndex:20] stringByAppendingString:@"…"] : raw;
}

@end
