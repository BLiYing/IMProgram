//  IMMediaPickerBars.m

#import "IMMediaPickerBars.h"
#import "IMMediaPickLogic.h"
#import "IMLocalization.h"
#import "IMTheme.h"

static const CGFloat kBarPadding = 12;      // space3
static const CGFloat kSendButtonHeight = 36;
static const CGFloat kCheckSize = 18;       // 原图勾选圆

#pragma mark - 顶栏

@implementation IMMediaPickerTopBar {
    UIButton *_cancel;
    UIButton *_title;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = IMTheme.surface;
        _cancel = [UIButton buttonWithType:UIButtonTypeSystem];
        [_cancel setTitle:IMLocalized(@"common.cancel") forState:UIControlStateNormal];
        _cancel.titleLabel.font = [UIFont systemFontOfSize:17];
        _cancel.tintColor = IMTheme.accent;
        _cancel.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
        [_cancel addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];

        _title = [UIButton buttonWithType:UIButtonTypeCustom];
        _title.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
        [_title setTitleColor:IMTheme.textPrimary forState:UIControlStateNormal];
        [_title addTarget:self action:@selector(titleTapped) forControlEvents:UIControlEventTouchUpInside];

        UIView *spacer = [UIView new]; // 右侧 64 占位，保证标题视觉居中
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_cancel, _title, spacer]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.alignment = UIStackViewAlignmentCenter;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:row];
        _cancel.translatesAutoresizingMaskIntoConstraints = NO;
        spacer.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [_cancel.widthAnchor constraintEqualToConstant:64],
            [spacer.widthAnchor constraintEqualToConstant:64],
            [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:kBarPadding],
            [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-kBarPadding],
            [row.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:kBarPadding],
            [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-kBarPadding],
            [row.heightAnchor constraintGreaterThanOrEqualToConstant:20],
        ]];
    }
    return self;
}

- (void)cancelTapped { if (self.onCancel) { self.onCancel(); } }
- (void)titleTapped { if (self.onTitleTap) { self.onTitleTap(); } }

- (void)setTitle:(NSString *)title canSwitch:(BOOL)canSwitch expanded:(BOOL)expanded {
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightMedium],
        NSForegroundColorAttributeName: IMTheme.textPrimary,
    }];
    if (canSwitch) {
        // 用文字箭头而不是图标：与 Android 同做法（▲ / ▼，10pt，textSecondary，与标题间距 4）
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:4]}]];
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:(expanded ? @"▲" : @"▼") attributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:10],
            NSForegroundColorAttributeName: IMTheme.textSecondary,
        }]];
    }
    [_title setAttributedTitle:text forState:UIControlStateNormal];
    _title.enabled = canSwitch;
}

@end

#pragma mark - 底栏

@implementation IMMediaPickerBottomBar {
    BOOL _dark;
    UILabel *_banner;
    UIButton *_preview;
    UIView *_checkCircle;
    UILabel *_checkMark;
    UILabel *_originalLabel;
    UIView *_originalTap;
    UIButton *_send;
}

- (instancetype)initWithDarkStyle:(BOOL)dark {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _dark = dark;
        self.backgroundColor = dark ? [UIColor.blackColor colorWithAlphaComponent:0.8] : IMTheme.surface;
        [self buildSubviews];
    }
    return self;
}

- (UIColor *)primaryTextColor { return _dark ? UIColor.whiteColor : IMTheme.textPrimary; }
- (UIColor *)strokeColor { return _dark ? [UIColor.whiteColor colorWithAlphaComponent:0.6] : IMTheme.textSecondary; }

- (void)buildSubviews {
    _banner = [UILabel new];
    _banner.font = [UIFont systemFontOfSize:13];
    _banner.textColor = IMTheme.accent;
    _banner.text = IMLocalized(@"media.picker.partial_access");
    _banner.userInteractionEnabled = YES;
    [_banner addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(bannerTapped)]];

    _preview = [UIButton buttonWithType:UIButtonTypeCustom];
    _preview.titleLabel.font = [UIFont systemFontOfSize:15];
    [_preview setTitle:IMLocalized(@"media.picker.preview") forState:UIControlStateNormal];
    [_preview addTarget:self action:@selector(previewTapped) forControlEvents:UIControlEventTouchUpInside];

    // 原图勾选：未选 = 1.5pt 描边空心圈（实心会被读成「已选中、只是灰」），选中 = accent 填充 + ✓
    _checkCircle = [UIView new];
    _checkCircle.layer.cornerRadius = kCheckSize / 2;
    _checkCircle.userInteractionEnabled = NO;
    _checkMark = [UILabel new];
    _checkMark.text = @"✓";
    _checkMark.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    _checkMark.textColor = UIColor.whiteColor;
    _checkMark.textAlignment = NSTextAlignmentCenter;
    _checkMark.translatesAutoresizingMaskIntoConstraints = NO;
    [_checkCircle addSubview:_checkMark];
    _originalLabel = [UILabel new];
    _originalLabel.font = [UIFont systemFontOfSize:14];
    UIStackView *original = [[UIStackView alloc] initWithArrangedSubviews:@[_checkCircle, _originalLabel]];
    original.axis = UILayoutConstraintAxisHorizontal;
    original.alignment = UIStackViewAlignmentCenter;
    original.spacing = 4;
    original.userInteractionEnabled = NO;
    _originalTap = [UIView new];
    original.translatesAutoresizingMaskIntoConstraints = NO;
    [_originalTap addSubview:original];
    [_originalTap addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(originalTapped)]];
    _checkCircle.translatesAutoresizingMaskIntoConstraints = NO;

    _send = [UIButton buttonWithType:UIButtonTypeCustom];
    _send.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [_send setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _send.layer.cornerRadius = 6;
    _send.contentEdgeInsets = UIEdgeInsetsMake(0, 16, 0, 16);
    [_send addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];

    UIView *flex = [UIView new];
    [flex setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    if (!_dark) { [items addObject:_preview]; }
    [items addObjectsFromArray:@[_originalTap, flex, _send]];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:items];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 16; // 「预览」右距 16
    if (!_dark) { [row setCustomSpacing:16 afterView:_preview]; }

    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:(_dark ? @[row] : @[_banner, row])];
    column.axis = UILayoutConstraintAxisVertical;
    column.spacing = 8;
    column.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:column];
    [NSLayoutConstraint activateConstraints:@[
        [column.topAnchor constraintEqualToAnchor:self.topAnchor constant:kBarPadding],
        [column.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:kBarPadding],
        [column.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-kBarPadding],
        [column.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-kBarPadding],
        [_send.heightAnchor constraintEqualToConstant:kSendButtonHeight],
        [_checkCircle.widthAnchor constraintEqualToConstant:kCheckSize],
        [_checkCircle.heightAnchor constraintEqualToConstant:kCheckSize],
        [_checkMark.centerXAnchor constraintEqualToAnchor:_checkCircle.centerXAnchor],
        [_checkMark.centerYAnchor constraintEqualToAnchor:_checkCircle.centerYAnchor],
        [original.leadingAnchor constraintEqualToAnchor:_originalTap.leadingAnchor],
        [original.trailingAnchor constraintEqualToAnchor:_originalTap.trailingAnchor],
        [original.topAnchor constraintEqualToAnchor:_originalTap.topAnchor],
        [original.bottomAnchor constraintEqualToAnchor:_originalTap.bottomAnchor],
    ]];
}

- (void)updateWithSelectedCount:(NSInteger)count
                     originalOn:(BOOL)originalOn
                     totalBytes:(long long)totalBytes
                    showsBanner:(BOOL)showsBanner {
    BOOL enabled = count > 0;
    BOOL on = originalOn && enabled;
    _banner.hidden = !showsBanner || _dark;

    [_preview setTitleColor:(enabled ? IMTheme.accent : IMTheme.textSecondary) forState:UIControlStateNormal];
    _preview.enabled = enabled;

    _checkCircle.backgroundColor = on ? IMTheme.accent : UIColor.clearColor;
    _checkCircle.layer.borderWidth = on ? 0 : 1.5;
    [self applyCheckBorderColor];
    _checkMark.hidden = !on;
    NSString *label = IMLocalized(@"media.picker.original");
    if (on && totalBytes > 0) {
        label = IMLocalizedFormat(@"media.picker.original_size", [IMMediaPickLogic sizeLabelForBytes:totalBytes]);
    }
    _originalLabel.text = label;
    _originalLabel.textColor = enabled ? self.primaryTextColor
                                       : (_dark ? [UIColor.whiteColor colorWithAlphaComponent:0.53] : IMTheme.textSecondary);
    _originalTap.userInteractionEnabled = enabled;

    NSString *title = enabled ? IMLocalizedFormat(@"media.picker.send_count", (long)count) : IMLocalized(@"common.send");
    [_send setTitle:title forState:UIControlStateNormal];
    _send.backgroundColor = [IMTheme.accent colorWithAlphaComponent:(enabled ? 1 : 0.4)];
    _send.enabled = enabled;
}

/// CALayer 的 CGColor 不跟主题：按当前 trait 解析后再赋值，主题切换时由 traitCollectionDidChange: 重赋（docs/UI_COLOR.md）。
- (void)applyCheckBorderColor {
    _checkCircle.layer.borderColor = [self.strokeColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self applyCheckBorderColor];
    }
}

- (void)bannerTapped { if (self.onManageAccess) { self.onManageAccess(); } }
- (void)previewTapped { if (self.onPreview) { self.onPreview(); } }
- (void)originalTapped { if (self.onOriginalToggle) { self.onOriginalToggle(); } }
- (void)sendTapped { if (self.onSend) { self.onSend(); } }

@end
