//  IMShareConfirmViewController.m
//
//  呈现方式：**全屏透明 + 自绘底部卡片**（半透明遮罩，卡片从底部滑入，点遮罩取消），不用系统 sheet。
//  为什么：iOS 26 的非全高 sheet 是悬浮 Liquid Glass，系统会对其中带圆角裁剪的图层做材质处理，
//  格子里的彩色头像被合成成白圆（模拟器实测；离屏渲染与单测都复现不了——那是合成阶段的效果）；
//  自定义 detent 还要防「布局 ↔ 解析高度」递归（曾 SIGILL）。自绘卡片高度由约束自然撑开，iOS 15–26 一致。

#import "IMShareConfirmViewController.h"
#import "IMShareSelection.h"
#import "IMSelectedChipStrip.h"
#import "IMShareSelectionBar.h"
#import "IMConversation.h"
#import "IMLocalization.h"
#import "IMTheme.h"

static const CGFloat kIMShareGridRowGap = 12;
/// 网格最多直接摊开几行，再多就在网格内滚动。转发上限后台可调到 50（S2），全摊开会把卡片顶出屏幕。
static const NSUInteger kIMShareGridMaxVisibleRows = 4;
static const CGFloat kIMShareSendHeight = 48;
static const CGFloat kIMShareCardRadius = 16;
static const NSTimeInterval kIMShareCardAnim = 0.25;

@implementation IMShareConfirmViewController {
    IMShareSelection *_selection;
    NSString *_previewText;
    UIView *_dim;
    UIView *_card;
    NSLayoutConstraint *_cardBottom;   // 滑入 / 滑出：0 = 贴底，卡片高度 = 藏到屏外
    UILabel *_titleLabel;
    UIScrollView *_grid;               // 行数 ≤ kIMShareGridMaxVisibleRows 时高度贴合内容；更多则固定高度、内部滚动
    UIView *_gridContent;              // 格子都挂在这里（别直接挂 scrollView：重排时会把滚动条一并删掉）
    NSLayoutConstraint *_gridHeight;
    UILabel *_preview;
    UIView *_previewBox;
    CGFloat _laidOutWidth;
    BOOL _dismissing;
    BOOL _slidIn;
}

- (instancetype)initWithSelection:(IMShareSelection *)selection previewText:(NSString *)previewText {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _selection = selection;
        _previewText = [previewText copy];
        self.modalPresentationStyle = UIModalPresentationOverFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    _dim = [UIView new];
    _dim.translatesAutoresizingMaskIntoConstraints = NO;
    _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4]; // 遮罩：与系统 sheet 背后调暗同一观感
    [_dim addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cancelTapped)]];
    [self.view addSubview:_dim];

    _card = [UIView new];
    _card.translatesAutoresizingMaskIntoConstraints = NO;
    _card.backgroundColor = IMTheme.surface;
    _card.layer.cornerRadius = kIMShareCardRadius;
    _card.layer.cornerCurve = kCACornerCurveContinuous;
    _card.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    [self.view addSubview:_card];

    _titleLabel = [UILabel new];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _titleLabel.textColor = IMTheme.textPrimary;
    [_card addSubview:_titleLabel];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    cancel.translatesAutoresizingMaskIntoConstraints = NO;
    cancel.titleLabel.font = [UIFont systemFontOfSize:16];
    cancel.tintColor = IMTheme.accent;
    [cancel setTitle:IMLocalized(@"common.cancel") forState:UIControlStateNormal];
    [cancel addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:cancel];

    _grid = [UIScrollView new];
    _grid.translatesAutoresizingMaskIntoConstraints = NO;
    _grid.showsHorizontalScrollIndicator = NO;
    _grid.alwaysBounceVertical = NO;
    [_card addSubview:_grid];
    _gridContent = [UIView new];
    [_grid addSubview:_gridContent];

    _previewBox = [UIView new];
    _previewBox.translatesAutoresizingMaskIntoConstraints = NO;
    _previewBox.backgroundColor = IMTheme.groupedBackground;
    _previewBox.layer.cornerRadius = 10;
    _previewBox.layer.cornerCurve = kCACornerCurveContinuous;
    _previewBox.hidden = _previewText.length == 0;
    [_card addSubview:_previewBox];

    _preview = [UILabel new];
    _preview.translatesAutoresizingMaskIntoConstraints = NO;
    _preview.font = [UIFont systemFontOfSize:14];
    _preview.textColor = IMTheme.textPrimary;
    _preview.numberOfLines = 3;
    _preview.text = _previewText;
    [_previewBox addSubview:_preview];

    UIButton *send = [UIButton buttonWithType:UIButtonTypeSystem];
    send.translatesAutoresizingMaskIntoConstraints = NO;
    send.backgroundColor = IMTheme.accent;
    send.layer.cornerRadius = 12;
    send.layer.cornerCurve = kCACornerCurveContinuous;
    send.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [send setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [send setTitle:IMLocalized(@"common.send") forState:UIControlStateNormal];
    [send addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:send];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    CGFloat pad = IMTheme.space4;
    _gridHeight = [_grid.heightAnchor constraintEqualToConstant:IMSelectedChipStrip.chipHeight];
    _cardBottom = [_card.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    // 无预览时发送按钮紧跟网格；有预览时紧跟预览框。
    UIView *aboveSend = _previewBox.hidden ? _grid : _previewBox;
    [NSLayoutConstraint activateConstraints:@[
        [_dim.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_dim.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_dim.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_dim.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [_card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        _cardBottom,
        [_card.topAnchor constraintGreaterThanOrEqualToAnchor:safe.topAnchor constant:IMTheme.space4],

        [_titleLabel.topAnchor constraintEqualToAnchor:_card.topAnchor constant:20],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:pad],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:cancel.leadingAnchor constant:-IMTheme.space2],
        [cancel.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
        [cancel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-pad],

        [_grid.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:IMTheme.space4],
        [_grid.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [_grid.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        _gridHeight,

        [_previewBox.topAnchor constraintEqualToAnchor:_grid.bottomAnchor constant:IMTheme.space3],
        [_previewBox.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:pad],
        [_previewBox.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-pad],
        [_preview.topAnchor constraintEqualToAnchor:_previewBox.topAnchor constant:10],
        [_preview.bottomAnchor constraintEqualToAnchor:_previewBox.bottomAnchor constant:-10],
        [_preview.leadingAnchor constraintEqualToAnchor:_previewBox.leadingAnchor constant:12],
        [_preview.trailingAnchor constraintEqualToAnchor:_previewBox.trailingAnchor constant:-12],

        [send.topAnchor constraintEqualToAnchor:aboveSend.bottomAnchor constant:IMTheme.space4],
        [send.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:pad],
        [send.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-pad],
        [send.heightAnchor constraintEqualToConstant:kIMShareSendHeight],
        [send.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-IMTheme.space3],
    ]];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_slidIn) { return; }
    _slidIn = YES;
    // 卡片从屏幕下方滑入（遮罩随 crossDissolve 淡入）。
    [self.view layoutIfNeeded];
    _cardBottom.constant = CGRectGetHeight(_card.bounds);
    [self.view layoutIfNeeded];
    _cardBottom.constant = 0;
    [UIView animateWithDuration:kIMShareCardAnim delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        [self.view layoutIfNeeded];
    } completion:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = CGRectGetWidth(_grid.bounds);
    if (w > 0 && fabs(w - _laidOutWidth) > 0.5) { [self layoutGrid]; } // 宽度变了（首次 / 旋转）才重排
}

- (void)reload {
    if (!self.isViewLoaded) { return; }
    _titleLabel.text = IMLocalizedFormat(@"share.picker.confirm_title", (long)_selection.count);
    [self layoutGrid];
}

/// 网格 = 若干行横排的已选格子（与底部已选栏同一种格子）。列数按宽度算，格间距均分。
- (void)layoutGrid {
    for (UIView *v in _gridContent.subviews) { [v removeFromSuperview]; }
    CGFloat width = CGRectGetWidth(_grid.bounds);
    _laidOutWidth = width;
    if (width <= 0) { return; }
    CGFloat inset = IMTheme.space4;
    CGFloat chipW = IMSelectedChipStrip.chipWidth, chipH = IMSelectedChipStrip.chipHeight;
    NSUInteger cols = MAX(1, (NSUInteger)floor((width - inset * 2 + IMTheme.space3) / (chipW + IMTheme.space3)));
    cols = MIN(cols, (NSUInteger)5);
    CGFloat gap = cols > 1 ? (width - inset * 2 - chipW * cols) / (cols - 1) : 0;
    NSArray<IMConversation *> *items = _selection.conversations;
    __weak typeof(self) ws = self;
    for (NSUInteger i = 0; i < items.count; i++) {
        NSUInteger row = i / cols, col = i % cols;
        CGPoint origin = CGPointMake(inset + col * (chipW + gap), 4 + row * (chipH + kIMShareGridRowGap));
        [_gridContent addSubview:[IMSelectedChipStrip chipViewForChip:IMShareChipForConversation(items[i]) origin:origin
                                                     onRemove:^(NSString *convID) { [ws removeTapped:convID]; }]];
    }
    NSUInteger rows = items.count == 0 ? 0 : (items.count + cols - 1) / cols;
    CGFloat contentH = rows == 0 ? 0 : 4 + rows * chipH + (rows - 1) * kIMShareGridRowGap;
    _gridContent.frame = CGRectMake(0, 0, width, contentH);
    _grid.contentSize = CGSizeMake(width, contentH);
    CGFloat maxH = 4 + kIMShareGridMaxVisibleRows * chipH + (kIMShareGridMaxVisibleRows - 1) * kIMShareGridRowGap;
    CGFloat newH = MIN(MAX(contentH, chipH), maxH);
    _grid.scrollEnabled = contentH > maxH + 0.5;
    if (fabs(newH - _gridHeight.constant) >= 0.5) { _gridHeight.constant = newH; } // 行数变了：卡片高度随约束变
}

- (void)removeTapped:(NSString *)convID {
    if (self.onRemove) { self.onRemove(convID); }
    if (_selection.count == 0) { [self closeThen:nil]; return; }
    [self reload];
    [UIView animateWithDuration:0.2 animations:^{ [self.view layoutIfNeeded]; }];
}

- (void)cancelTapped { [self closeThen:nil]; }

- (void)sendTapped { [self closeThen:self.onConfirm]; }

/// 卡片滑出 + 收起本页；completion 在收起完成后调用（之后才能安全地收起整个选择页）。
- (void)closeThen:(nullable void (^)(void))completion {
    if (_dismissing) { return; }
    _dismissing = YES;
    void (^done)(void) = [completion copy];
    _cardBottom.constant = CGRectGetHeight(_card.bounds);
    [UIView animateWithDuration:kIMShareCardAnim delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        [self.view layoutIfNeeded];
    } completion:^(BOOL finished) {
        [self dismissViewControllerAnimated:YES completion:^{ if (done) { done(); } }];
    }];
}

@end
