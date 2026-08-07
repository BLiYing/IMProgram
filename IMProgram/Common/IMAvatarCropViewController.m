//  IMAvatarCropViewController.m

#import "IMAvatarCropViewController.h"

static const CGFloat kAvatarOut = 256.0;   // 输出边长
static const CGFloat kCircleInset = 16.0;   // 圆左右各留边距（圆直径 = 屏宽 − 32）
static const CGFloat kCenterYRatio = 0.44;  // 圆心 y = 屏高 × 0.44
static const CGFloat kMaxZoom = 4.0;        // 最大缩放
static const CGFloat kBtnDiameter = 52.0;   // 底部按钮直径
static const CGFloat kBtnBottomGap = 30.0;  // 按钮中心距底部安全区

@interface IMAvatarCropViewController () <UIScrollViewDelegate>
@property (nonatomic, strong) UIImage *image;          // 已校正为 up 方向
@property (nonatomic, strong) UIScrollView *scrollView; // frame = 圆的外接正方形，负责平移/缩放
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIView *overlay;          // 圆外压暗 + 圆边（不吃手势）
@property (nonatomic, assign) CGSize laidOutSize;       // 上次布局时的 bounds 尺寸（变化即重布局，支持旋转）
@end

@implementation IMAvatarCropViewController

- (instancetype)initWithImage:(UIImage *)image {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _image = [self normalizedImage:image];
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}

// 把带 EXIF 方向的图重绘为 up 方向，使 CGImage 像素坐标与显示一致（裁切按像素取）。
- (UIImage *)normalizedImage:(UIImage *)img {
    if (img.imageOrientation == UIImageOrientationUp) { return img; }
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = img.scale;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:img.size format:fmt];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [img drawInRect:CGRectMake(0, 0, img.size.width, img.size.height)];
    }];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    self.scrollView = [UIScrollView new];
    self.scrollView.delegate = self;
    self.scrollView.showsHorizontalScrollIndicator = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    self.scrollView.bouncesZoom = YES;
    self.scrollView.clipsToBounds = NO; // 图片可越出圆的外接方形（圆外被 overlay 压暗）
    [self.view addSubview:self.scrollView];

    self.imageView = [[UIImageView alloc] initWithImage:self.image];
    self.imageView.contentMode = UIViewContentModeScaleToFill;
    [self.scrollView addSubview:self.imageView];

    self.overlay = [[UIView alloc] initWithFrame:self.view.bounds];
    self.overlay.userInteractionEnabled = NO;
    self.overlay.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.overlay];

    // 顶部标题「移动和缩放」。
    UILabel *title = [UILabel new];
    title.text = @"移动和缩放";
    title.textColor = [UIColor colorWithWhite:1 alpha:0.95];
    title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];
    [NSLayoutConstraint activateConstraints:@[
        [title.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [title.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4],
    ]];

    // 底部按钮（严格照参考图）：左下 Liquid Glass 返回、右下系统蓝确定。
    UIButton *back = [self glassCircleButtonWithSymbol:@"chevron.left" action:@selector(cancelTapped)];
    UIButton *ok = [self blueCircleButtonWithSymbol:@"checkmark" action:@selector(confirmTapped)];
    [self.view addSubview:back];
    [self.view addSubview:ok];
    CGFloat cy = -kBtnBottomGap - kBtnDiameter / 2.0;
    [NSLayoutConstraint activateConstraints:@[
        [back.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [back.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:cy],
        [back.widthAnchor constraintEqualToConstant:kBtnDiameter],
        [back.heightAnchor constraintEqualToConstant:kBtnDiameter],
        [ok.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [ok.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:cy],
        [ok.widthAnchor constraintEqualToConstant:kBtnDiameter],
        [ok.heightAnchor constraintEqualToConstant:kBtnDiameter],
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.image.size.width <= 0 || self.image.size.height <= 0) { return; }
    // 尺寸未变则跳过（layout 会多次触发）；变化（如旋转）时重新布局，避免遮罩/裁切区错位。
    if (CGSizeEqualToSize(self.view.bounds.size, self.laidOutSize)) { return; }
    self.laidOutSize = self.view.bounds.size;

    CGFloat W = self.view.bounds.size.width;
    CGFloat H = self.view.bounds.size.height;
    CGFloat D = W - kCircleInset * 2.0;           // 圆的外接正方形边长 = 圆直径
    CGFloat cx = W / 2.0;
    CGFloat cy = H * kCenterYRatio;
    CGRect square = CGRectMake(cx - D / 2.0, cy - D / 2.0, D, D);

    self.overlay.frame = self.view.bounds;
    [self drawOverlayWithCircleRect:CGRectMake(cx - D / 2.0, cy - D / 2.0, D, D)];

    self.scrollView.frame = square;
    self.imageView.frame = CGRectMake(0, 0, self.image.size.width, self.image.size.height);
    self.scrollView.contentSize = self.image.size;

    // 最小缩放：图片短边充满圆（外接方形）；最大 = 4×。
    CGFloat minScale = MAX(D / self.image.size.width, D / self.image.size.height);
    self.scrollView.minimumZoomScale = minScale;
    self.scrollView.maximumZoomScale = minScale * kMaxZoom;
    self.scrollView.zoomScale = minScale;
    // 居中。
    CGFloat offX = (self.image.size.width * minScale - D) / 2.0;
    CGFloat offY = (self.image.size.height * minScale - D) / 2.0;
    self.scrollView.contentOffset = CGPointMake(offX, offY);
}

// 圆外压暗（evenOdd 挖圆）+ 1pt 白边。
- (void)drawOverlayWithCircleRect:(CGRect)circle {
    [self.overlay.layer.sublayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:self.overlay.bounds];
    [path appendPath:[UIBezierPath bezierPathWithOvalInRect:circle]];
    CAShapeLayer *dim = [CAShapeLayer layer];
    dim.path = path.CGPath;
    dim.fillRule = kCAFillRuleEvenOdd;
    dim.fillColor = [UIColor colorWithWhite:0 alpha:0.68].CGColor;
    [self.overlay.layer addSublayer:dim];

    CAShapeLayer *ring = [CAShapeLayer layer];
    ring.path = [UIBezierPath bezierPathWithOvalInRect:circle].CGPath;
    ring.fillColor = UIColor.clearColor.CGColor;
    ring.strokeColor = [UIColor colorWithWhite:1 alpha:0.6].CGColor;
    ring.lineWidth = 1.0;
    [self.overlay.layer addSublayer:ring];
}

#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.imageView;
}

#pragma mark - 按钮构建

// 左下返回：与确定钮同为 layer 级实现（可靠渲染，不用 UIVisualEffectView 子视图——那种做法
// 插入时按钮 bounds 尚为 0、autoresizing 会把磨砂层框错位）。半透明深灰圆 + 细高光边，纯黑上清晰可见。
- (UIButton *)glassCircleButtonWithSymbol:(NSString *)symbol action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.backgroundColor = [UIColor colorWithRed:70 / 255.0 green:70 / 255.0 blue:78 / 255.0 alpha:0.72];
    btn.layer.cornerRadius = kBtnDiameter / 2.0;
    btn.layer.borderWidth = 1.0;
    btn.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold];
    [btn setImage:[[UIImage systemImageNamed:symbol] imageByApplyingSymbolConfiguration:cfg] forState:UIControlStateNormal];
    btn.tintColor = UIColor.whiteColor;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

// 右下系统蓝确定：实心圆 + 发光。
- (UIButton *)blueCircleButtonWithSymbol:(NSString *)symbol action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.backgroundColor = [UIColor colorWithRed:10/255.0 green:132/255.0 blue:255/255.0 alpha:1.0];
    btn.layer.cornerRadius = kBtnDiameter / 2.0;
    btn.layer.shadowColor = [UIColor colorWithRed:10/255.0 green:132/255.0 blue:255/255.0 alpha:1.0].CGColor;
    btn.layer.shadowOpacity = 0.55;
    btn.layer.shadowRadius = 8.0;
    btn.layer.shadowOffset = CGSizeMake(0, 4);
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightBold];
    [btn setImage:[[UIImage systemImageNamed:symbol] imageByApplyingSymbolConfiguration:cfg] forState:UIControlStateNormal];
    btn.tintColor = UIColor.whiteColor;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

#pragma mark - 动作

- (void)cancelTapped {
    void (^cb)(NSData *) = self.onComplete;
    [self dismissViewControllerAnimated:YES completion:^{ if (cb) { cb(nil); } }];
}

- (void)confirmTapped {
    NSData *jpeg = [self renderCroppedJPEG];
    void (^cb)(NSData *) = self.onComplete;
    [self dismissViewControllerAnimated:YES completion:^{ if (cb) { cb(jpeg); } }];
}

// 取圆的外接正方形（= scrollView 可见区域）在源图像素坐标的矩形 → 裁出 → 缩 256×256 → JPEG。
- (NSData *)renderCroppedJPEG {
    CGImageRef src = self.image.CGImage;
    if (!src) { return nil; }
    CGFloat zoom = self.scrollView.zoomScale;
    if (zoom <= 0) { return nil; }
    CGFloat s = self.image.scale;
    CGPoint off = self.scrollView.contentOffset;
    CGSize box = self.scrollView.bounds.size;
    // 可见区映射回源图像素：contentOffset/zoom 为图点坐标，再 × image.scale 为像素。
    CGRect px = CGRectMake(off.x / zoom * s, off.y / zoom * s, box.width / zoom * s, box.height / zoom * s);
    // 夹紧到图片像素边界，避免 CGImageCreateWithImageInRect 越界返回 nil。
    CGFloat maxW = CGImageGetWidth(src), maxH = CGImageGetHeight(src);
    px.origin.x = MAX(0, MIN(px.origin.x, maxW));
    px.origin.y = MAX(0, MIN(px.origin.y, maxH));
    px.size.width = MIN(px.size.width, maxW - px.origin.x);
    px.size.height = MIN(px.size.height, maxH - px.origin.y);
    if (px.size.width < 1 || px.size.height < 1) { return nil; }

    CGImageRef cropped = CGImageCreateWithImageInRect(src, px);
    if (!cropped) { return nil; }
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 1.0;
    fmt.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(kAvatarOut, kAvatarOut) format:fmt];
    UIImage *croppedImg = [UIImage imageWithCGImage:cropped];
    CGImageRelease(cropped);
    UIImage *out = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [croppedImg drawInRect:CGRectMake(0, 0, kAvatarOut, kAvatarOut)];
    }];
    return UIImageJPEGRepresentation(out, 0.85);
}

@end
