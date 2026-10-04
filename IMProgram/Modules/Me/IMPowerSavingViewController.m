//  IMPowerSavingViewController.m
//  严格照 UI 稿 iOS 规格表：写法同 IMDataStorageViewController / IMNotificationSettingsViewController
//  （InsetGrouped + 原生 header/footer + IMLiquidNavigationBar 由 self.title 驱动）。不引入新颜色。

#import "IMPowerSavingViewController.h"

#import "IMAppearance.h"
#import "IMLocalization.h"
#import "IMPowerSaving.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"

typedef NS_ENUM(NSInteger, IMPSSection) {
    IMPSSectionStatus = 0,
    IMPSSectionMode,
    IMPSSectionFollow,
    IMPSSectionItems,
    IMPSSectionCount,
};

typedef NS_ENUM(NSInteger, IMPSItem) {
    IMPSItemAnimations = 0,
    IMPSItemAutoDownload,
    IMPSItemVideoPreload,
    IMPSItemCount,
};

static const CGFloat kStatusRowH = 62;
static const CGFloat kModeRowH = 58;
static const CGFloat kToggleRowH = 62;
static const NSInteger kModeRowCount = 3;       // 关闭 / 自动 / 始终；auto 时第 4 行是阈值滑块

#pragma mark - 行 Cell（可选图标块 + 标题 + 副标题 + 右值；开关 / 勾走 accessory）

@interface IMPowerRowCell : UITableViewCell
@property (nonatomic, copy, nullable) void (^onSwitch)(BOOL on);
@property (nonatomic, strong, readonly) UISwitch *toggle;
/// iconSide = 0 表示无图标；glyph 为符号点数。
- (void)configureTitle:(NSString *)title titleColor:(UIColor *)titleColor subtitle:(NSString *)subtitle value:(nullable NSString *)value
                symbol:(nullable NSString *)symbol tile:(nullable UIColor *)tile side:(CGFloat)side glyph:(CGFloat)glyph;
@end

@implementation IMPowerRowCell {
    UIView *_iconBg;
    UIImageView *_iconView;
    UILabel *_titleLabel;
    UILabel *_subtitleLabel;
    UILabel *_valueLabel;
    NSLayoutConstraint *_iconW, *_iconH, *_textLeadingIcon, *_textLeadingEdge;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (!(self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) { return nil; }
    _toggle = [UISwitch new];
    _toggle.onTintColor = IMTheme.accent;
    [_toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];

    _iconBg = [UIView new];
    _iconBg.translatesAutoresizingMaskIntoConstraints = NO;
    _iconBg.layer.cornerRadius = 7;
    _iconBg.layer.masksToBounds = YES;
    [self.contentView addSubview:_iconBg];
    _iconView = [UIImageView new];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.tintColor = UIColor.whiteColor;
    _iconView.contentMode = UIViewContentModeCenter;
    [_iconBg addSubview:_iconView];

    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont systemFontOfSize:17];
    _subtitleLabel = [UILabel new];
    _subtitleLabel.font = [UIFont systemFontOfSize:13];
    _subtitleLabel.textColor = IMTheme.textSecondary;
    UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _subtitleLabel]];
    texts.translatesAutoresizingMaskIntoConstraints = NO;
    texts.axis = UILayoutConstraintAxisVertical;
    texts.spacing = 2;
    [self.contentView addSubview:texts];

    _valueLabel = [UILabel new];
    _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _valueLabel.font = [UIFont systemFontOfSize:16];
    _valueLabel.textColor = IMTheme.textSecondary;
    _valueLabel.textAlignment = NSTextAlignmentRight;
    [_valueLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_valueLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.contentView addSubview:_valueLabel];

    UILayoutGuide *m = self.contentView.layoutMarginsGuide;
    _iconW = [_iconBg.widthAnchor constraintEqualToConstant:29];
    _iconH = [_iconBg.heightAnchor constraintEqualToConstant:29];
    _textLeadingIcon = [texts.leadingAnchor constraintEqualToAnchor:_iconBg.trailingAnchor constant:IMTheme.space3]; // 图标→标题 12
    _textLeadingEdge = [texts.leadingAnchor constraintEqualToAnchor:m.leadingAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [_iconBg.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [_iconBg.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        _iconW, _iconH,
        [_iconView.centerXAnchor constraintEqualToAnchor:_iconBg.centerXAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:_iconBg.centerYAnchor],
        _textLeadingIcon,
        [texts.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [texts.trailingAnchor constraintLessThanOrEqualToAnchor:_valueLabel.leadingAnchor constant:-IMTheme.space2],
        [_valueLabel.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [_valueLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
    ]];
    return self;
}

- (void)configureTitle:(NSString *)title titleColor:(UIColor *)titleColor subtitle:(NSString *)subtitle value:(NSString *)value
                symbol:(NSString *)symbol tile:(UIColor *)tile side:(CGFloat)side glyph:(CGFloat)glyph {
    _titleLabel.text = title;
    _titleLabel.textColor = titleColor;
    _subtitleLabel.text = subtitle;
    _valueLabel.text = value;
    BOOL hasIcon = side > 0 && symbol.length > 0;
    _iconBg.hidden = !hasIcon;
    _textLeadingIcon.active = hasIcon;
    _textLeadingEdge.active = !hasIcon;
    if (hasIcon) {
        _iconW.constant = side; _iconH.constant = side;
        _iconBg.backgroundColor = tile;
        _iconView.image = [UIImage systemImageNamed:symbol
                                  withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:glyph weight:UIImageSymbolWeightSemibold]];
    }
}

- (void)toggled:(UISwitch *)sender { if (_onSwitch) { _onSwitch(sender.on); } }

@end

#pragma mark - 阈值滑块行（同 IMAutoDownloadNetworkViewController 的滑块行：标题 15 / 刻度 11，间距 10 / 8）

@interface IMPowerSliderCell : UITableViewCell
@property (nonatomic, strong, readonly) UISlider *slider;
@property (nonatomic, strong, readonly) UILabel *valueLabel;
@end

@implementation IMPowerSliderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (!(self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) { return nil; }
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [UIFont systemFontOfSize:15];
    title.text = IMLocalized(@"power_saving.threshold.label");
    _valueLabel = [UILabel new];
    _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _valueLabel.font = [UIFont systemFontOfSize:15];
    _valueLabel.textColor = UIColor.secondaryLabelColor;
    _valueLabel.textAlignment = NSTextAlignmentRight;
    _slider = [UISlider new];
    _slider.translatesAutoresizingMaskIntoConstraints = NO;
    _slider.minimumValue = (float)IMPowerSaveThresholdMin;
    _slider.maximumValue = (float)IMPowerSaveThresholdMax;
    _slider.minimumTrackTintColor = IMTheme.accent;
    _slider.accessibilityLabel = title.text;
    UILabel *lo = [self tickLabel:[NSString stringWithFormat:@"%ld%%", (long)IMPowerSaveThresholdMin] align:NSTextAlignmentLeft];
    UILabel *hi = [self tickLabel:[NSString stringWithFormat:@"%ld%%", (long)IMPowerSaveThresholdMax] align:NSTextAlignmentRight];
    for (UIView *v in @[title, _valueLabel, _slider, lo, hi]) { [self.contentView addSubview:v]; }
    UILayoutGuide *m = self.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [title.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [_valueLabel.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [_valueLabel.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [_slider.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [_slider.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [_slider.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
        [lo.leadingAnchor constraintEqualToAnchor:_slider.leadingAnchor],
        [lo.topAnchor constraintEqualToAnchor:_slider.bottomAnchor constant:2],
        [hi.trailingAnchor constraintEqualToAnchor:_slider.trailingAnchor],
        [hi.topAnchor constraintEqualToAnchor:_slider.bottomAnchor constant:2],
        [lo.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12],
        [hi.bottomAnchor constraintEqualToAnchor:lo.bottomAnchor],
    ]];
    return self;
}

- (UILabel *)tickLabel:(NSString *)text align:(NSTextAlignment)align {
    UILabel *l = [UILabel new];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    l.font = [UIFont systemFontOfSize:11];
    l.textColor = UIColor.secondaryLabelColor;
    l.text = text;
    l.textAlignment = align;
    return l;
}

@end

#pragma mark - 控制器

@interface IMPowerSavingViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation IMPowerSavingViewController {
    BOOL _showsSlider;          // 与 mode==auto 同步；变化时用 insert/deleteRows 动画
    NSInteger _draftThreshold;  // 拖动中的未保存值（0 = 没在拖）；松手才写入 IMPowerSaving
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"ios.settings.row.power_saving");
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.estimatedRowHeight = 96; // 仅滑块行自适应高度用
    [self.tableView registerClass:IMPowerRowCell.class forCellReuseIdentifier:@"row"];
    [self.tableView registerClass:IMPowerSliderCell.class forCellReuseIdentifier:@"slider"];
    [self.view addSubview:self.tableView];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(powerSavingChanged)
                                               name:IMPowerSavingDidChangeNotification object:nil];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _showsSlider = IMPowerSaving.shared.mode == IMPowerSaveModeAuto;
    [self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _draftThreshold = 0; // 拖动被打断（来电 / 手势返回）时不留陈旧草稿值
}

#pragma mark - 状态同步

/// 单一入口：偏好 / 电量 / 外观动画任何变化都走这里。mode 进出 auto 时插删滑块行，其余只重配可见行。
- (void)powerSavingChanged {
    BOOL wantSlider = IMPowerSaving.shared.mode == IMPowerSaveModeAuto;
    if (!self.isViewLoaded || !self.view.window) { _showsSlider = wantSlider; [self.tableView reloadData]; return; }
    if (wantSlider != _showsSlider) {
        _showsSlider = wantSlider;
        NSIndexPath *ip = [NSIndexPath indexPathForRow:kModeRowCount inSection:IMPSSectionMode];
        [self.tableView performBatchUpdates:^{
            if (wantSlider) { [self.tableView insertRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationFade]; }
            else { [self.tableView deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationFade]; }
        } completion:nil];
    }
    [self reconfigureVisibleCells];
}

- (void)reconfigureVisibleCells {
    for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:ip];
        if ([cell isKindOfClass:IMPowerRowCell.class]) { [self configureCell:(IMPowerRowCell *)cell at:ip]; }
    }
}

- (NSInteger)displayThreshold { return _draftThreshold > 0 ? _draftThreshold : IMPowerSaving.shared.threshold; }

#pragma mark - 文案

- (NSString *)reasonText {
    switch (IMPowerSaving.shared.reason) {
        case IMPowerSaveReasonAlways: return IMLocalized(@"power_saving.reason.always");
        case IMPowerSaveReasonBattery: return IMLocalizedFormat(@"power_saving.reason.battery", (long)[self displayThreshold]);
        case IMPowerSaveReasonSystem: return IMLocalized(@"power_saving.reason.system_ios");
        case IMPowerSaveReasonNone: break;
    }
    return @"";
}

- (NSString *)statusSubtitle {
    IMPowerSaving *ps = IMPowerSaving.shared;
    if (ps.active) { return IMLocalizedFormat(@"power_saving.status.active", [self reasonText], (long)ps.pausedCount); }
    if (ps.mode == IMPowerSaveModeAuto) { return IMLocalizedFormat(@"power_saving.status.hint_auto", (long)[self displayThreshold]); }
    return IMLocalized(@"power_saving.status.hint_off");
}

#pragma mark - 数据源

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return IMPSSectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case IMPSSectionMode: return kModeRowCount + (_showsSlider ? 1 : 0);
        case IMPSSectionItems: return IMPSItemCount;
        default: return 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == IMPSSectionMode) { return IMLocalized(@"power_saving.mode.header"); }
    if (section == IMPSSectionItems) { return IMLocalized(@"power_saving.items.header"); }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == IMPSSectionMode) { return IMLocalized(@"power_saving.mode.footer"); }
    if (section == IMPSSectionItems) { return IMLocalized(@"power_saving.items.footer"); }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)ip {
    switch (ip.section) {
        case IMPSSectionStatus: return kStatusRowH;
        case IMPSSectionMode: return ip.row < kModeRowCount ? kModeRowH : UITableViewAutomaticDimension;
        default: return kToggleRowH;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == IMPSSectionMode && ip.row == kModeRowCount) {
        IMPowerSliderCell *cell = [tableView dequeueReusableCellWithIdentifier:@"slider" forIndexPath:ip];
        NSInteger t = [self displayThreshold];
        cell.slider.value = (float)t;
        cell.valueLabel.text = [NSString stringWithFormat:@"%ld%%", (long)t];
        [cell.slider removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
        [cell.slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [cell.slider addTarget:self action:@selector(sliderCommitted:)
              forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        return cell;
    }
    IMPowerRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:ip];
    [self configureCell:cell at:ip];
    return cell;
}

- (void)configureCell:(IMPowerRowCell *)cell at:(NSIndexPath *)ip {
    IMPowerSaving *ps = IMPowerSaving.shared;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.onSwitch = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    switch (ip.section) {
        case IMPSSectionStatus: {
            NSString *value = ps.batteryLevel ? [NSString stringWithFormat:@"%ld%%", (long)ps.batteryLevel.integerValue] : nil;
            [cell configureTitle:IMLocalized(ps.active ? @"power_saving.status.on" : @"power_saving.status.off")
                      titleColor:IMTheme.textPrimary subtitle:[self statusSubtitle] value:value
                          symbol:@"bolt.fill" tile:UIColor.systemYellowColor side:30 glyph:18];
            break;
        }
        case IMPSSectionMode: [self configureModeCell:cell row:ip.row]; break;
        case IMPSSectionFollow: {
            [cell configureTitle:IMLocalized(@"power_saving.follow.title_ios") titleColor:IMTheme.textPrimary
                        subtitle:IMLocalized(@"power_saving.follow.sub_ios") value:nil
                          symbol:@"iphone" tile:UIColor.systemBlueColor side:29 glyph:15];
            cell.toggle.on = ps.followSystem;
            cell.toggle.enabled = YES;
            cell.toggle.accessibilityLabel = IMLocalized(@"power_saving.follow.title_ios");
            cell.accessoryView = cell.toggle;
            cell.onSwitch = ^(BOOL on) { IMPowerSaving.shared.followSystem = on; };
            break;
        }
        default: [self configureItemCell:cell item:(IMPSItem)ip.row]; break;
    }
}

- (void)configureModeCell:(IMPowerRowCell *)cell row:(NSInteger)row {
    IMPowerSaveMode modes[] = {IMPowerSaveModeOff, IMPowerSaveModeAuto, IMPowerSaveModeAlways};
    IMPowerSaveMode mode = modes[row];
    NSString *title = nil, *sub = nil;
    if (mode == IMPowerSaveModeOff) {
        title = IMLocalized(@"power_saving.mode.off"); sub = IMLocalized(@"power_saving.mode.off_sub");
    } else if (mode == IMPowerSaveModeAuto) {
        title = IMLocalized(@"power_saving.mode.auto");
        sub = IMLocalizedFormat(@"power_saving.mode.auto_sub", (long)[self displayThreshold]);
    } else {
        title = IMLocalized(@"power_saving.mode.always"); sub = IMLocalized(@"power_saving.mode.always_sub");
    }
    [cell configureTitle:title titleColor:IMTheme.textPrimary subtitle:sub value:nil symbol:nil tile:nil side:0 glyph:0];
    cell.accessoryType = (IMPowerSaving.shared.mode == mode) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
}

- (void)configureItemCell:(IMPowerRowCell *)cell item:(IMPSItem)item {
    IMPowerSaving *ps = IMPowerSaving.shared;
    BOOL locked = ps.active;
    NSString *title, *sub, *symbol; UIColor *tile; BOOL userValue;
    switch (item) {
        case IMPSItemAnimations:
            title = IMLocalized(@"power_saving.item.animations"); sub = IMLocalized(@"power_saving.item.animations_sub");
            symbol = @"sparkles"; tile = UIColor.systemOrangeColor; userValue = IMAppearance.shared.animationsEnabled;
            cell.onSwitch = ^(BOOL on) { IMAppearance.shared.animationsEnabled = on; }; // 与外观页「动画」同一个值
            break;
        case IMPSItemAutoDownload:
            title = IMLocalized(@"power_saving.item.auto_download"); sub = IMLocalized(@"power_saving.item.auto_download_sub");
            symbol = @"arrow.down.circle"; tile = UIColor.systemGreenColor; userValue = ps.autoDownloadPref;
            cell.onSwitch = ^(BOOL on) { IMPowerSaving.shared.autoDownloadPref = on; };
            break;
        default:
            title = IMLocalized(@"power_saving.item.video_preload"); sub = IMLocalized(@"power_saving.item.video_preload_sub");
            symbol = @"video"; tile = UIColor.systemRedColor; userValue = ps.videoPreloadPref;
            cell.onSwitch = ^(BOOL on) { IMPowerSaving.shared.videoPreloadPref = on; };
            break;
    }
    // 锁定态（稿「耗电项 · 锁定态」）：开关显示关且禁用、标题次要色、副标题「省电中，已暂停」；整行仍可点 → Toast。
    [cell configureTitle:title titleColor:(locked ? IMTheme.textSecondary : IMTheme.textPrimary)
                subtitle:(locked ? IMLocalized(@"power_saving.item.paused") : sub) value:nil
                  symbol:symbol tile:tile side:29 glyph:15];
    cell.toggle.on = locked ? NO : userValue;
    cell.toggle.enabled = !locked;
    cell.toggle.accessibilityLabel = title;
    cell.accessoryView = cell.toggle;
    cell.selectionStyle = locked ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
}

#pragma mark - 交互

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == IMPSSectionMode && ip.row < kModeRowCount) {
        IMPowerSaveMode modes[] = {IMPowerSaveModeOff, IMPowerSaveModeAuto, IMPowerSaveModeAlways};
        IMPowerSaving.shared.mode = modes[ip.row]; // 立即生效、留在本页；通知回调负责插删滑块行
    } else if (ip.section == IMPSSectionItems && IMPowerSaving.shared.active) {
        [self im_showToast:IMLocalized(@"power_saving.item.locked_toast")]; // 不改值
    }
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == IMPSSectionMode) { return ip.row < kModeRowCount; }
    return ip.section == IMPSSectionItems && IMPowerSaving.shared.active;
}

/// 拖动：吸附到 5 的倍数；数值、状态行副标题、auto 选项副标题同步变（不落盘）。
- (void)sliderChanged:(UISlider *)slider {
    // VoiceOver / 键盘调节只发 ValueChanged、不发 TouchUp*：不在拖动中就当场保存，否则离开页面即回滚
    if (!slider.isTracking) { [self sliderCommitted:slider]; return; }
    NSInteger step = IMPowerSaveThresholdStep;
    NSInteger snapped = IMPowerSaveClampThreshold(((NSInteger)lroundf(slider.value / step)) * step);
    slider.value = (float)snapped;
    if (snapped == _draftThreshold) { return; }
    _draftThreshold = snapped;
    NSIndexPath *ip = [NSIndexPath indexPathForRow:kModeRowCount inSection:IMPSSectionMode];
    IMPowerSliderCell *cell = (IMPowerSliderCell *)[self.tableView cellForRowAtIndexPath:ip];
    cell.valueLabel.text = [NSString stringWithFormat:@"%ld%%", (long)snapped];
    [self reconfigureVisibleCells];
}

/// 松手即保存。
- (void)sliderCommitted:(UISlider *)slider {
    NSInteger step = IMPowerSaveThresholdStep;
    NSInteger snapped = IMPowerSaveClampThreshold(((NSInteger)lroundf(slider.value / step)) * step);
    slider.value = (float)snapped;
    _draftThreshold = 0;
    IMPowerSaving.shared.threshold = snapped; // 值没变时不通知，下面手动刷一次可见行
    [self reconfigureVisibleCells];
}

@end
