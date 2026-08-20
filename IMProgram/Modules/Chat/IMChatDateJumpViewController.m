//  IMChatDateJumpViewController.m

#import "IMChatDateJumpViewController.h"
#import "IMTheme.h"
#import "IMGlass.h"                // IMGlassButtonConfiguration（iOS26 玻璃 / 降级 gray）
#import "IMMainTabBarController.h" // kIMLiquidBarHeight
#import "IMProgram-Swift.h"        // IMLiquidNavigationBar（自持沉浸式标题栏）

/// 叉叉距 sheet 顶留白（同 IMFilePickerViewController，避免被顶部圆角遮挡）。
static const CGFloat kIMDateJumpTopPadding = 16;

/// sheet 各 detent 高度一致的分组背景（恒按 base 解析，随明暗自适应）。同 IMFilePickerViewController。
static UIColor *IMDateJumpBaseGroupedBackgroundColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        UITraitCollection *base = [UITraitCollection traitCollectionWithUserInterfaceLevel:UIUserInterfaceLevelBase];
        UITraitCollection *merged = [UITraitCollection traitCollectionWithTraitsFromCollections:@[tc, base]];
        return [UIColor.systemGroupedBackgroundColor resolvedColorWithTraitCollection:merged];
    }];
}

API_AVAILABLE(ios(16.0))
@interface IMChatDateJumpViewController () <IMLiquidNavigationBarDelegate, UICalendarSelectionSingleDateDelegate, UICalendarViewDelegate>
@end

@implementation IMChatDateJumpViewController {
    void (^_onPick)(IMDateJumpKind, NSDate * _Nullable);
    NSSet<NSNumber *> *_activeDayKeys; // yyyymmdd（设备时区）→ O(1) 打点查询
    NSCalendar *_cal;
}

- (instancetype)initWithActiveDays:(nullable NSSet<NSDate *> *)activeDays
                            onPick:(void (^)(IMDateJumpKind, NSDate * _Nullable))onPick {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _onPick = [onPick copy];
        _cal = [NSCalendar currentCalendar];
        NSMutableSet<NSNumber *> *keys = [NSMutableSet set];
        for (NSDate *d in activeDays) {
            NSDateComponents *c = [_cal components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:d];
            [keys addObject:@(c.year * 10000 + c.month * 100 + c.day)];
        }
        _activeDayKeys = keys;
        if (@available(iOS 15.0, *)) {
            self.modalPresentationStyle = UIModalPresentationPageSheet;
            UISheetPresentationController *sheet = self.sheetPresentationController;
            if (@available(iOS 16.0, *)) {
                // 自定义 detent：按月历内容高度（≈ 月历 + 快捷行 + 栏），上拉可到 large。
                UISheetPresentationControllerDetent *fit =
                    [UISheetPresentationControllerDetent customDetentWithIdentifier:@"calFit"
                        resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                            return MIN(context.maximumDetentValue, 520);
                        }];
                sheet.detents = @[fit, UISheetPresentationControllerDetent.largeDetent];
            } else {
                sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                                  UISheetPresentationControllerDetent.largeDetent];
            }
            sheet.prefersGrabberVisible = YES;
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"按日期";
    if (@available(iOS 17.0, *)) { self.traitOverrides.userInterfaceLevel = UIUserInterfaceLevelBase; }
    self.view.backgroundColor = IMDateJumpBaseGroupedBackgroundColor();
    [self installLiquidNavigationBar];

    UIView *content = [UIView new];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:8],
        [content.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-8],
        [content.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4],
    ]];

    UIView *calendar = [self buildCalendar];
    calendar.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:calendar];

    // 底部两颗快捷钮「最早 / 今天」（Liquid Glass）。
    UIButton *earliest = [self glassButtonTitle:@"最早" action:@selector(earliestTapped)];
    UIButton *today = [self glassButtonTitle:@"今天" action:@selector(todayTapped)];
    UIStackView *quick = [[UIStackView alloc] initWithArrangedSubviews:@[earliest, today]];
    quick.axis = UILayoutConstraintAxisHorizontal;
    quick.distribution = UIStackViewDistributionFillEqually;
    quick.spacing = 10;
    quick.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:quick];

    [NSLayoutConstraint activateConstraints:@[
        [calendar.topAnchor constraintEqualToAnchor:content.topAnchor],
        [calendar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [calendar.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [quick.topAnchor constraintEqualToAnchor:calendar.bottomAnchor constant:12],
        [quick.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8],
        [quick.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
        [quick.heightAnchor constraintEqualToConstant:44],
        [quick.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];
}

- (UIView *)buildCalendar {
    if (@available(iOS 16.0, *)) {
        UICalendarView *cv = [UICalendarView new];
        cv.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
        cv.locale = [NSLocale currentLocale];
        cv.fontDesign = UIFontDescriptorSystemDesignRounded;
        cv.delegate = self;
        UICalendarSelectionSingleDate *sel = [[UICalendarSelectionSingleDate alloc] initWithDelegate:self];
        cv.selectionBehavior = sel;
        return cv;
    }
    // iOS 15 兜底：内联日期选择器（无打点，选即跳）。
    UIDatePicker *dp = [UIDatePicker new];
    dp.datePickerMode = UIDatePickerModeDate;
    dp.preferredDatePickerStyle = UIDatePickerStyleInline;
    [dp addTarget:self action:@selector(legacyDatePicked:) forControlEvents:UIControlEventValueChanged];
    return dp;
}

- (void)legacyDatePicked:(UIDatePicker *)dp {
    NSDate *day = [_cal startOfDayForDate:dp.date];
    [self finishWithKind:IMDateJumpKindDate day:day];
}

- (UIButton *)glassButtonTitle:(NSString *)title action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *cfg = IMGlassButtonConfiguration();
    cfg.title = title;
    cfg.baseForegroundColor = IMTheme.accent;
    b.configuration = cfg;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

#pragma mark - 沉浸式标题栏（照 IMFilePickerViewController：自持栏 + Liquid Glass ✕）

- (void)installLiquidNavigationBar {
    UIEdgeInsets insets = self.additionalSafeAreaInsets;
    insets.top = kIMDateJumpTopPadding + kIMLiquidBarHeight;
    self.additionalSafeAreaInsets = insets;

    IMLiquidNavigationBar *bar = [[IMLiquidNavigationBar alloc] initWithTitle:self.title subtitle:@"" actionTitle:nil];
    bar.delegate = self;
    bar.hostExtraTopInset = kIMLiquidBarHeight;
    bar.backgroundEffectProgress = 0;
    bar.leftImage = [UIImage systemImageNamed:@"xmark"
                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17
                                                                                              weight:UIImageSymbolWeightSemibold]];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    ]];
}

- (void)liquidNavigationBarDidTapLeft:(IMLiquidNavigationBar *)bar { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)liquidNavigationBarDidTapBack:(IMLiquidNavigationBar *)bar { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)liquidNavigationBarDidTapAction:(IMLiquidNavigationBar *)bar { /* 无右侧操作 */ }

#pragma mark - 快捷钮

- (void)earliestTapped { [self finishWithKind:IMDateJumpKindEarliest day:nil]; }
- (void)todayTapped { [self finishWithKind:IMDateJumpKindToday day:nil]; }

- (void)finishWithKind:(IMDateJumpKind)kind day:(nullable NSDate *)day {
    void (^cb)(IMDateJumpKind, NSDate * _Nullable) = _onPick;
    [self dismissViewControllerAnimated:YES completion:^{ if (cb) { cb(kind, day); } }];
}

#pragma mark - UICalendarView（iOS 16+）

- (nullable UICalendarViewDecoration *)calendarView:(UICalendarView *)calendarView
                         decorationForDateComponents:(NSDateComponents *)dateComponents API_AVAILABLE(ios(16.0)) {
    NSInteger key = dateComponents.year * 10000 + dateComponents.month * 100 + dateComponents.day;
    if ([_activeDayKeys containsObject:@(key)]) {
        return [UICalendarViewDecoration decorationWithColor:IMTheme.accent size:UICalendarViewDecorationSizeSmall];
    }
    return nil;
}

- (void)dateSelection:(UICalendarSelectionSingleDate *)selection
    didSelectDate:(nullable NSDateComponents *)dateComponents API_AVAILABLE(ios(16.0)) {
    if (!dateComponents) { return; }
    NSDate *picked = [_cal dateFromComponents:dateComponents];
    if (!picked) { return; }
    [self finishWithKind:IMDateJumpKindDate day:[_cal startOfDayForDate:picked]];
}

@end
