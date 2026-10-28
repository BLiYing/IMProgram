//  IMExportDataViewController.m

#import "IMExportDataViewController.h"
#import "IMDataExport.h"
#import "IMExportDownloader.h"
#import "IMHTTPService.h"
#import "IMHTTPService+Export.h"
#import "IMTheme.h"
#import "IMLog.h"
#import "IMLocalization.h"
#import "UIViewController+IMToast.h"

static NSTimeInterval const kExportPollInterval = 2.0;
static NSInteger const kExportPollFailuresBeforeError = 3;
static NSInteger const kExportSpinnerTag = 7001; // 按钮忙碌态的转圈视图 tag
static NSString * const kExportFormatHTML = @"html";
static NSString * const kExportFormatJSON = @"json";
static CGFloat const kExportCardRadius = 10;
static CGFloat const kExportFootInset = 16; // 页脚 / 页眉相对卡片再缩进 16（= 屏幕边 32，同草图 margin 32）

#pragma mark - 勾选行

/// 格式行：左标题、右 ✓（选中时显示）。整行可点。
@interface IMExportCheckRow : UIControl
@property (nonatomic, strong) UIImageView *check;
- (instancetype)initWithTitle:(NSString *)title;
@end

@implementation IMExportCheckRow
- (instancetype)initWithTitle:(NSString *)title {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        UILabel *l = [UILabel new];
        l.translatesAutoresizingMaskIntoConstraints = NO;
        l.text = title;
        l.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        l.textColor = UIColor.labelColor;
        l.numberOfLines = 0;
        _check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark"
            withConfiguration:[UIImageSymbolConfiguration configurationWithWeight:UIImageSymbolWeightSemibold]]];
        _check.translatesAutoresizingMaskIntoConstraints = NO;
        _check.tintColor = UIColor.systemBlueColor;
        [self addSubview:l]; [self addSubview:_check];
        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:44],
            [l.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [l.topAnchor constraintEqualToAnchor:self.topAnchor constant:11],
            [l.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-11],
            [_check.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [_check.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [l.trailingAnchor constraintLessThanOrEqualToAnchor:_check.leadingAnchor constant:-8],
        ]];
        self.accessibilityLabel = title;
        self.isAccessibilityElement = YES;
    }
    return self;
}
- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    self.check.hidden = !selected;
    self.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
}
@end

#pragma mark - 控制器

@interface IMExportDataViewController () <UITextFieldDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UISwitch *mediaSwitch;
@property (nonatomic, strong) IMExportCheckRow *htmlRow;
@property (nonatomic, strong) IMExportCheckRow *jsonRow;
@property (nonatomic, strong) UIButton *startButton, *cancelButton, *downloadButton, *retryButton;
@property (nonatomic, strong) UILabel *introLabel, *mediaFootLabel, *formatHeaderLabel, *runningFootLabel, *doneFootLabel;
@property (nonatomic, strong) UILabel *cooldownLabel, *expiredLabel, *failedLabel, *errorLabel;
@property (nonatomic, strong) UILabel *runningTitle, *runningDetail, *doneTitle, *doneSummary;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, copy) NSArray<UIView *> *configViews, *cooldownViews, *runningViews, *doneViews, *failedViews;
@property (nonatomic, strong, nullable) IMExportJob *job;
@property (nonatomic, copy, nullable) NSString *ackFailedID;
@property (nonatomic, strong, nullable) NSDate *cooldownUntil;
@property (nonatomic, assign) BOOL starting, cancelling, downloading, fetching, loadErrorShown;
@property (nonatomic, assign) BOOL pendingRefresh; ///< 请求在途时又来了刷新（如 401 失效后）：记下，结束后补发一次
@property (nonatomic, assign) NSInteger fetchFailures;
@property (nonatomic, assign) NSUInteger stateEpoch; ///< 本地发起开始导出时 +1，使更早发出的 latest 回包作废
@property (nonatomic, strong, nullable) NSTimer *pollTimer;
@property (nonatomic, strong) NSMutableArray<UIView *> *noteWraps; ///< 说明标签的外包容器（superview 是弱引用，需有人强持有）
@property (nonatomic, strong, nullable) NSURLSessionDownloadTask *downloadTask;
// 下载中卡片（DATA_EXPORT_DESIGN §1 ④b）
@property (nonatomic, strong) UILabel *dlTitle, *dlDetail, *keepOpenLabel;
@property (nonatomic, strong) UIProgressView *dlProgress;
@property (nonatomic, strong) UIView *dlIndeterminate; ///< 总长度未知时在进度条内左右滑动的色块
@property (nonatomic, copy) NSArray<UIView *> *downloadingViews;
@property (nonatomic, assign) int64_t dlWritten, dlExpected;
@property (nonatomic, assign) BOOL dlHasProgress;
@end

@implementation IMExportDataViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) { _host = [host copy]; _userID = [userID copy]; }
    return self;
}

- (void)dealloc {
    [self.pollTimer invalidate];
    [self.downloadTask cancel];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"ps.row.export_data");
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self buildScrollAndStack];
    [self buildViews];
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [nc addObserver:self selector:@selector(appDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [self render];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshLatest];
    [self render];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopPolling];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // 放在 DidDisappear：侧滑返回中途取消时 WillDisappear 也会触发（且 isMovingFromParent 为 YES），那会误杀进行中的下载。
    if (self.isMovingFromParentViewController) { [self.downloadTask cancel]; }
}

- (void)appDidBecomeActive {
    if (!self.viewIfLoaded.window) { return; }
    [self refreshLatest];
    [self render];
}

#pragma mark - 构造

- (void)buildScrollAndStack {
    self.scrollView = [UIScrollView new];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];
    self.stack = [UIStackView new];
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 8;
    [self.scrollView addSubview:self.stack];
    UILayoutGuide *content = self.scrollView.contentLayoutGuide, *frame = self.scrollView.frameLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:IMTheme.space4],
        [self.stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-IMTheme.space4 * 2],
        [self.stack.leadingAnchor constraintEqualToAnchor:frame.leadingAnchor constant:IMTheme.space4],
        [self.stack.trailingAnchor constraintEqualToAnchor:frame.trailingAnchor constant:-IMTheme.space4],
    ]];
}

/// 小字说明标签（13pt secondary），外包一层左右各缩进 16；返回的 label 的 superview 就是放进 stack 的容器。
- (UILabel *)noteLabelWithColor:(UIColor *)color {
    UILabel *l = [UILabel new];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    l.font = [UIFont systemFontOfSize:13];
    l.textColor = color;
    l.numberOfLines = 0;
    UIView *wrap = [UIView new];
    [wrap addSubview:l];
    if (!self.noteWraps) { self.noteWraps = [NSMutableArray array]; }
    [self.noteWraps addObject:wrap];
    [NSLayoutConstraint activateConstraints:@[
        [l.topAnchor constraintEqualToAnchor:wrap.topAnchor], [l.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor],
        [l.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:kExportFootInset],
        [l.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-kExportFootInset],
    ]];
    return l;
}

/// 分组卡：行垂直堆叠，行间 0.5pt 分割线（左缩进 16），圆角 10。
- (UIView *)cardWithRows:(NSArray<UIView *> *)rows {
    UIStackView *card = [[UIStackView alloc] initWithArrangedSubviews:rows];
    card.axis = UILayoutConstraintAxisVertical;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = kExportCardRadius;
    card.clipsToBounds = YES;
    for (NSUInteger i = 1; i < rows.count; i++) {
        UIView *sep = [UIView new];
        sep.translatesAutoresizingMaskIntoConstraints = NO;
        sep.backgroundColor = UIColor.separatorColor;
        [rows[i] addSubview:sep];
        [NSLayoutConstraint activateConstraints:@[
            [sep.topAnchor constraintEqualToAnchor:rows[i].topAnchor], [sep.heightAnchor constraintEqualToConstant:0.5],
            [sep.leadingAnchor constraintEqualToAnchor:rows[i].leadingAnchor constant:16],
            [sep.trailingAnchor constraintEqualToAnchor:rows[i].trailingAnchor]]];
    }
    return card;
}

- (UIButton *)buttonWithTitle:(NSString *)title ident:(NSString *)ident destructiveGhost:(BOOL)ghost action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.layer.cornerRadius = 12;
    b.accessibilityIdentifier = ident;
    [b setTitle:title forState:UIControlStateNormal];
    UIColor *fg = ghost ? UIColor.systemRedColor : UIColor.whiteColor;
    [b setTitleColor:fg forState:UIControlStateNormal];
    [b setTitleColor:fg forState:UIControlStateDisabled];
    b.backgroundColor = ghost ? UIColor.secondarySystemGroupedBackgroundColor : UIColor.systemBlueColor;
    b.titleLabel.font = [UIFont systemFontOfSize:17 weight:ghost ? UIFontWeightRegular : UIFontWeightSemibold];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [b.heightAnchor constraintEqualToConstant:50].active = YES;
    return b;
}

- (void)buildViews {
    UIColor *sec = UIColor.secondaryLabelColor;
    self.introLabel = [self noteLabelWithColor:sec];
    self.introLabel.text = IMLocalized(@"export.intro");
    UIView *mediaCard = [self buildMediaCard];
    self.mediaFootLabel = [self noteLabelWithColor:sec];
    self.mediaFootLabel.text = IMLocalized(@"export.media.footer");
    self.formatHeaderLabel = [self noteLabelWithColor:sec];
    self.formatHeaderLabel.text = [IMLocalized(@"export.format.header") uppercaseStringWithLocale:IMLocalization.shared.locale];
    UIView *formatCard = [self buildFormatCard];
    UIView *passwordCard = [self buildPasswordCard];
    self.cooldownLabel = [self noteLabelWithColor:sec];
    self.expiredLabel = [self noteLabelWithColor:sec];
    self.expiredLabel.text = IMLocalized(@"export.expired");
    self.failedLabel = [self noteLabelWithColor:UIColor.systemRedColor];
    self.failedLabel.text = IMLocalized(@"export.failed");
    self.errorLabel = [self noteLabelWithColor:UIColor.systemRedColor];
    self.startButton = [self buttonWithTitle:IMLocalized(@"export.start") ident:@"export.start" destructiveGhost:NO action:@selector(startTapped)];
    UIView *runningCard = [self buildRunningCard];
    self.runningFootLabel = [self noteLabelWithColor:sec];
    self.runningFootLabel.text = IMLocalized(@"export.running.footer");
    self.cancelButton = [self buttonWithTitle:IMLocalized(@"export.cancel") ident:@"export.cancel" destructiveGhost:YES action:@selector(cancelTapped)];
    UIView *doneCard = [self buildDoneCard];
    self.doneFootLabel = [self noteLabelWithColor:sec];
    self.downloadButton = [self buttonWithTitle:IMLocalized(@"export.download") ident:@"export.download" destructiveGhost:NO action:@selector(downloadTapped)];
    UIView *downloadingCard = [self buildDownloadingCard];
    self.keepOpenLabel = [self noteLabelWithColor:UIColor.systemRedColor];
    self.keepOpenLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.keepOpenLabel.text = IMLocalized(@"export.download_keep_open");
    self.keepOpenLabel.accessibilityIdentifier = @"export.download_keep_open";
    self.retryButton = [self buttonWithTitle:IMLocalized(@"export.retry") ident:@"export.retry" destructiveGhost:NO action:@selector(retryTapped)];

    // stack 内固定顺序；各态只切 hidden（UIStackView 对 hidden 的 arranged 视图不占位）。
    UIView *(^w)(UILabel *) = ^UIView *(UILabel *l) { return l.superview; };
    self.configViews = @[w(self.introLabel), mediaCard, w(self.mediaFootLabel), w(self.formatHeaderLabel), formatCard, passwordCard,
                         w(self.expiredLabel), self.startButton];
    self.cooldownViews = @[w(self.cooldownLabel), self.startButton];
    self.runningViews = @[runningCard, w(self.runningFootLabel), self.cancelButton];
    self.doneViews = @[doneCard, w(self.doneFootLabel), self.downloadButton];
    self.failedViews = @[w(self.failedLabel), self.retryButton];
    self.downloadingViews = @[downloadingCard, w(self.keepOpenLabel)];
    NSArray<UIView *> *all = @[w(self.introLabel), mediaCard, w(self.mediaFootLabel), w(self.formatHeaderLabel), formatCard, passwordCard,
        runningCard, w(self.runningFootLabel), doneCard, w(self.doneFootLabel), w(self.cooldownLabel), w(self.expiredLabel),
        w(self.failedLabel), w(self.errorLabel), self.startButton, self.cancelButton, self.downloadButton, self.retryButton,
        downloadingCard, w(self.keepOpenLabel)];
    for (UIView *v in all) { [self.stack addArrangedSubview:v]; }
    [self applyCustomSpacing];
}

- (void)applyCustomSpacing {
    UIStackView *s = self.stack;
    [s setCustomSpacing:14 afterView:self.introLabel.superview];
    [s setCustomSpacing:22 afterView:self.mediaFootLabel.superview];
    [s setCustomSpacing:6 afterView:self.formatHeaderLabel.superview];
    [s setCustomSpacing:22 afterView:self.configViews[4]];  // formatCard
    [s setCustomSpacing:12 afterView:self.configViews[5]];  // passwordCard
    [s setCustomSpacing:22 afterView:self.runningFootLabel.superview];
    [s setCustomSpacing:22 afterView:self.doneFootLabel.superview];
    [s setCustomSpacing:12 afterView:self.downloadingViews[0]];
    [s setCustomSpacing:22 afterView:self.cooldownLabel.superview];
    [s setCustomSpacing:12 afterView:self.expiredLabel.superview];
    [s setCustomSpacing:12 afterView:self.failedLabel.superview];
    [s setCustomSpacing:12 afterView:self.errorLabel.superview];
}

- (UIView *)buildMediaCard {
    UILabel *l = [UILabel new];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    l.text = IMLocalized(@"export.media.title");
    l.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    l.textColor = UIColor.labelColor;
    l.numberOfLines = 0;
    self.mediaSwitch = [UISwitch new];
    self.mediaSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    self.mediaSwitch.accessibilityLabel = l.text;
    self.mediaSwitch.accessibilityIdentifier = @"export.media";
    UIView *row = [UIView new];
    [row addSubview:l]; [row addSubview:self.mediaSwitch];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [l.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
        [l.topAnchor constraintEqualToAnchor:row.topAnchor constant:11],
        [l.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-11],
        [self.mediaSwitch.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16],
        [self.mediaSwitch.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [l.trailingAnchor constraintLessThanOrEqualToAnchor:self.mediaSwitch.leadingAnchor constant:-8],
    ]];
    return [self cardWithRows:@[row]];
}

- (UIView *)buildFormatCard {
    self.htmlRow = [[IMExportCheckRow alloc] initWithTitle:IMLocalized(@"export.format.html")];
    self.jsonRow = [[IMExportCheckRow alloc] initWithTitle:IMLocalized(@"export.format.json")];
    self.htmlRow.accessibilityIdentifier = @"export.format.html";
    self.jsonRow.accessibilityIdentifier = @"export.format.json";
    self.htmlRow.selected = YES; self.jsonRow.selected = YES; // 默认两者都要（设计 §0）
    for (IMExportCheckRow *r in @[self.htmlRow, self.jsonRow]) {
        [r addTarget:self action:@selector(formatTapped:) forControlEvents:UIControlEventTouchUpInside];
    }
    return [self cardWithRows:@[self.htmlRow, self.jsonRow]];
}

/// 密码框：与注销账号页同款（secureTextEntry + 眼睛 rightView，16pt，卡底 secondarySystemGroupedBackground）。
- (UIView *)buildPasswordCard {
    UITextField *f = [UITextField new];
    f.translatesAutoresizingMaskIntoConstraints = NO;
    f.font = [UIFont systemFontOfSize:16];
    f.textColor = UIColor.labelColor;
    f.placeholder = IMLocalized(@"export.password.placeholder");
    f.secureTextEntry = YES;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.spellCheckingType = UITextSpellCheckingTypeNo;
    f.returnKeyType = UIReturnKeyDone;
    f.delegate = self;
    f.accessibilityIdentifier = @"export.password";
    [f addTarget:self action:@selector(fieldChanged) forControlEvents:UIControlEventEditingChanged];
    UIButton *eye = [UIButton buttonWithType:UIButtonTypeSystem];
    eye.frame = CGRectMake(0, 0, 34, 34);
    eye.tintColor = UIColor.secondaryLabelColor;
    [eye setImage:[UIImage systemImageNamed:@"eye.slash.fill"] forState:UIControlStateNormal];
    [eye setImage:[UIImage systemImageNamed:@"eye.fill"] forState:UIControlStateSelected];
    [eye addTarget:self action:@selector(eyeTapped:) forControlEvents:UIControlEventTouchUpInside];
    f.rightView = eye;
    f.rightViewMode = UITextFieldViewModeAlways;
    self.passwordField = f;
    UIView *card = [UIView new];
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = kExportCardRadius;
    [card addSubview:f];
    [NSLayoutConstraint activateConstraints:@[
        [f.topAnchor constraintEqualToAnchor:card.topAnchor], [f.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [f.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [f.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [f.heightAnchor constraintEqualToConstant:44],
    ]];
    return card;
}

/// 卡内竖排：16 内边距、行间 10（同草图进行中 / 完成卡）。
- (UIView *)cardWithContent:(NSArray<UIView *> *)content {
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:content];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 10;
    s.layoutMargins = UIEdgeInsetsMake(16, 16, 16, 16);
    s.layoutMarginsRelativeArrangement = YES;
    s.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    s.layer.cornerRadius = kExportCardRadius;
    return s;
}

- (UILabel *)plainLabelSize:(CGFloat)size color:(UIColor *)color {
    UILabel *l = [UILabel new];
    l.font = [UIFont systemFontOfSize:size];
    l.textColor = color;
    l.numberOfLines = 0;
    return l;
}

- (UIView *)buildRunningCard {
    self.runningTitle = [self plainLabelSize:17 color:UIColor.labelColor];
    self.runningTitle.text = IMLocalized(@"export.running");
    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.progressTintColor = UIColor.systemBlueColor;
    self.progressView.accessibilityIdentifier = @"export.progress";
    self.runningDetail = [self plainLabelSize:13 color:UIColor.secondaryLabelColor];
    return [self cardWithContent:@[self.runningTitle, self.progressView, self.runningDetail]];
}

- (UIView *)buildDownloadingCard {
    self.dlTitle = [self plainLabelSize:17 color:UIColor.labelColor];
    self.dlTitle.text = IMLocalized(@"export.downloading");
    self.dlProgress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.dlProgress.progressTintColor = UIColor.systemBlueColor;
    self.dlProgress.clipsToBounds = YES;
    self.dlProgress.accessibilityIdentifier = @"export.download_progress";
    self.dlIndeterminate = [UIView new];
    self.dlIndeterminate.backgroundColor = UIColor.systemBlueColor;
    self.dlIndeterminate.hidden = YES;
    [self.dlProgress addSubview:self.dlIndeterminate];
    self.dlDetail = [self plainLabelSize:13 color:UIColor.secondaryLabelColor];
    self.dlDetail.accessibilityIdentifier = @"export.download_detail";
    return [self cardWithContent:@[self.dlTitle, self.dlProgress, self.dlDetail]];
}

- (UIView *)buildDoneCard {
    self.doneTitle = [self plainLabelSize:17 color:UIColor.labelColor];
    self.doneTitle.text = IMLocalized(@"export.done.title");
    self.doneSummary = [self plainLabelSize:13 color:UIColor.secondaryLabelColor];
    UIView *card = [self cardWithContent:@[self.doneTitle, self.doneSummary]];
    ((UIStackView *)card).spacing = 6;
    return card;
}

#pragma mark - 渲染

- (IMExportViewState)currentState {
    return IMExportResolveViewState(self.job, self.ackFailedID, self.cooldownUntil, NSDate.date);
}

- (void)render {
    IMExportViewState st = [self currentState];
    NSDictionary<NSNumber *, NSArray<UIView *> *> *sets = @{
        @(IMExportViewStateConfig): self.configViews, @(IMExportViewStateCooldown): self.cooldownViews,
        @(IMExportViewStateRunning): self.runningViews, @(IMExportViewStateDone): self.doneViews,
        @(IMExportViewStateFailed): self.failedViews };
    BOOL showDownloading = self.downloading && st == IMExportViewStateDone;
    NSSet<UIView *> *visible = [NSSet setWithArray:showDownloading ? self.downloadingViews : sets[@(st)]];
    for (UIView *v in self.stack.arrangedSubviews) { v.hidden = ![visible containsObject:v]; }
    // 配置态的「已过期」提示只在确有过期任务时出现。
    self.expiredLabel.superview.hidden = !(st == IMExportViewStateConfig && [self jobIsExpired]);
    [self renderStateDetails:st];
    [self renderDownloadProgress:showDownloading];
    [self renderError];
    [self refreshButtons];
}

- (BOOL)jobIsExpired {
    return self.job.status == IMExportStatusExpired || self.job.status == IMExportStatusDone;
}

- (void)renderStateDetails:(IMExportViewState)st {
    if (st == IMExportViewStateRunning) {
        BOOL known = self.job.totalConvs > 0;
        self.progressView.progress = IMExportProgressFraction(self.job.doneConvs, self.job.totalConvs);
        self.runningDetail.hidden = !known;
        self.runningDetail.text = known ? IMLocalizedFormat(@"export.progress", (long)self.job.doneConvs, (long)self.job.totalConvs) : nil;
    } else if (st == IMExportViewStateDone) {
        self.doneSummary.text = IMExportSummaryText(self.job);
        self.doneFootLabel.text = IMExportExpiresText(self.job);
        self.doneFootLabel.superview.hidden = self.downloading || self.doneFootLabel.text.length == 0;
    } else if (st == IMExportViewStateCooldown) {
        NSTimeInterval left = [IMExportCooldownUntil(self.job, self.cooldownUntil, NSDate.date) timeIntervalSinceNow];
        self.cooldownLabel.text = IMLocalizedFormat(@"export.cooldown", (long)IMExportCooldownHours(left));
    }
}

/// 下载中卡片：已知总长度 → 定长条 + 「已下载 a / b」；未知 → 不定长滑块 + 「已下载 a」；尚无首个回调时只显条。
- (void)renderDownloadProgress:(BOOL)visible {
    BOOL known = self.dlExpected > 0;
    self.dlDetail.hidden = !self.dlHasProgress;
    if (self.dlHasProgress) {
        NSString *w = [NSByteCountFormatter stringFromByteCount:self.dlWritten countStyle:NSByteCountFormatterCountStyleFile];
        NSString *t = known ? [NSByteCountFormatter stringFromByteCount:self.dlExpected countStyle:NSByteCountFormatterCountStyleFile] : nil;
        self.dlDetail.text = known ? IMLocalizedFormat(@"export.download_progress", w, t)
                                   : IMLocalizedFormat(@"export.download_progress_unknown", w);
    }
    self.dlProgress.progress = known ? (float)MIN(1.0, (double)self.dlWritten / (double)self.dlExpected) : 0;
    BOOL slide = visible && !known;
    self.dlIndeterminate.hidden = !slide;
    [self.dlIndeterminate.layer removeAllAnimations];
    if (!slide) { return; }
    [self.view layoutIfNeeded];
    CGFloat w = self.dlProgress.bounds.size.width, seg = MAX(40, w * 0.3);
    self.dlIndeterminate.frame = CGRectMake(-seg, 0, seg, self.dlProgress.bounds.size.height);
    [UIView animateWithDuration:1.1 delay:0 options:UIViewAnimationOptionRepeat | UIViewAnimationOptionCurveEaseInOut animations:^{
        self.dlIndeterminate.frame = CGRectMake(w, 0, seg, self.dlProgress.bounds.size.height);
    } completion:nil];
}

- (void)renderError {
    self.errorLabel.superview.hidden = self.errorLabel.text.length == 0;
}

- (void)showError:(nullable NSString *)text {
    self.errorLabel.text = text;
    self.loadErrorShown = NO;
    [self renderError];
}

- (void)refreshButtons {
    BOOL cooling = [self currentState] == IMExportViewStateCooldown;
    BOOL ok = IMExportCanStart(self.passwordField.text, self.htmlRow.selected, self.jsonRow.selected, self.starting, cooling);
    [self setButton:self.startButton enabled:ok busy:self.starting];
    [self setButton:self.cancelButton enabled:!self.cancelling busy:self.cancelling];
    [self setButton:self.downloadButton enabled:!self.downloading busy:self.downloading];
    [self setButton:self.retryButton enabled:YES busy:NO];
}

- (void)setButton:(UIButton *)b enabled:(BOOL)enabled busy:(BOOL)busy {
    b.enabled = enabled;
    b.alpha = enabled ? 1.0 : 0.4;
    b.titleLabel.alpha = busy ? 0 : 1;
    UIActivityIndicatorView *spin = [b viewWithTag:kExportSpinnerTag];
    if (busy && !spin) {
        spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        spin.tag = kExportSpinnerTag;
        spin.color = b == self.cancelButton ? UIColor.systemRedColor : UIColor.whiteColor;
        spin.translatesAutoresizingMaskIntoConstraints = NO;
        [b addSubview:spin];
        [NSLayoutConstraint activateConstraints:@[[spin.centerXAnchor constraintEqualToAnchor:b.centerXAnchor],
                                                  [spin.centerYAnchor constraintEqualToAnchor:b.centerYAnchor]]];
        [spin startAnimating];
    } else if (!busy) {
        [spin removeFromSuperview];
    }
}

#pragma mark - 拉取 / 轮询

- (void)withToken:(void (^)(NSString *_Nullable token, NSError *_Nullable error))block {
    IMHTTPService.sharedService.host = self.host;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *err) {
        block(token.length > 0 ? token : nil, err);
    }];
}

- (void)refreshLatest {
    if (self.fetching) { self.pendingRefresh = YES; return; }
    self.fetching = YES;
    NSUInteger epoch = self.stateEpoch;
    __weak typeof(self) ws = self;
    [self withToken:^(NSString *token, NSError *tokenErr) {
        if (!token) { [ws latestFinishedWithJob:nil error:tokenErr ?: [NSError errorWithDomain:@"IMExport" code:-1 userInfo:nil] epoch:epoch]; return; }
        [IMHTTPService.sharedService fetchLatestExportWithToken:token completion:^(IMExportJob *job, NSError *err) {
            [ws latestFinishedWithJob:job error:err epoch:epoch];
        }];
    }];
}

- (void)latestFinishedWithJob:(nullable IMExportJob *)job error:(nullable NSError *)error epoch:(NSUInteger)epoch {
    self.fetching = NO;
    [self applyLatestJob:job error:error epoch:epoch];
    if (self.pendingRefresh) { self.pendingRefresh = NO; [self refreshLatest]; }
}

- (void)applyLatestJob:(nullable IMExportJob *)job error:(nullable NSError *)error epoch:(NSUInteger)epoch {
    if (!IMExportShouldApplyLatest(epoch, self.stateEpoch)) { [self syncPolling]; return; } // 旧状态，丢弃
    if (error) {
        self.fetchFailures++;
        BOOL firstLoad = self.job == nil && self.fetchFailures == 1;
        if (firstLoad || self.fetchFailures == kExportPollFailuresBeforeError) {
            NSString *msg = error.localizedDescription.length > 0 ? error.localizedDescription : IMLocalized(@"common.action_failed");
            IMLogWithTag(IMLogTagUI, @"export latest failed code=%ld failures=%ld", (long)error.code, (long)self.fetchFailures);
            [self showError:msg];
            self.loadErrorShown = YES;
        }
        [self syncPolling];
        return;
    }
    self.fetchFailures = 0;
    if (self.loadErrorShown) { [self showError:nil]; }
    self.job = job;
    [self render];
    [self syncPolling];
}

/// 进行中且页面在屏 → 保证 2s 定时器在跑；否则停掉。
- (void)syncPolling {
    BOOL need = self.viewIfLoaded.window != nil && [self currentState] == IMExportViewStateRunning;
    if (need && !self.pollTimer) {
        __weak typeof(self) ws = self;
        self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:kExportPollInterval repeats:YES block:^(NSTimer *t) { if (!ws.fetching) { [ws refreshLatest]; } }];
    } else if (!need) {
        [self stopPolling];
    }
}

- (void)stopPolling {
    [self.pollTimer invalidate];
    self.pollTimer = nil;
}

#pragma mark - 动作

- (void)startTapped {
    BOOL cooling = [self currentState] == IMExportViewStateCooldown;
    if (!IMExportCanStart(self.passwordField.text, self.htmlRow.selected, self.jsonRow.selected, self.starting, cooling)) { return; }
    [self.view endEditing:YES];
    NSMutableArray<NSString *> *formats = [NSMutableArray array];
    if (self.htmlRow.selected) { [formats addObject:kExportFormatHTML]; }
    if (self.jsonRow.selected) { [formats addObject:kExportFormatJSON]; }
    NSString *password = self.passwordField.text ?: @"";
    BOOL media = self.mediaSwitch.on;
    self.starting = YES;
    [self showError:nil];
    [self refreshButtons];
    __weak typeof(self) ws = self;
    [self withToken:^(NSString *token, NSError *tokenErr) {
        if (!token) { [ws startFailedWithError:tokenErr]; return; }
        [IMHTTPService.sharedService startExportWithToken:token password:password includeMedia:media formats:formats
                                               completion:^(IMExportJob *job, NSError *err) {
            if (err) { [ws startFailedWithError:err]; } else { [ws startSucceededWithJob:job]; }
        }];
    }];
}

- (void)startSucceededWithJob:(IMExportJob *)job {
    self.starting = NO;
    self.stateEpoch++;
    self.job = job;
    self.cooldownUntil = nil;
    self.passwordField.text = nil;
    IMLogWithTag(IMLogTagUI, @"export started status=%ld", (long)job.status);
    [self render];
    [self syncPolling];
}

- (void)startFailedWithError:(nullable NSError *)err {
    self.starting = NO;
    IMLogWithTag(IMLogTagUI, @"export start failed code=%ld", (long)err.code);
    if (err.code == IMErrCodeExportCooldown) {
        NSTimeInterval sec = [err.userInfo[IMErrorRetryAfterSecKey] doubleValue];
        self.cooldownUntil = [NSDate dateWithTimeIntervalSinceNow:sec > 0 ? sec : IMExportCooldownSec];
        [self showError:nil];
        [self render];
        return;
    }
    if (err.code == IMErrCodeExportBusy) {
        // 别处（另一台设备）已有进行中任务：拉最新状态切到进度页，并说明原因。
        [self showError:nil];
        [self refreshLatest];
        [self im_showToast:err.localizedDescription];
        [self render];
        return;
    }
    NSString *msg = err.localizedDescription;
    [self showError:msg.length > 0 ? msg : IMLocalized(@"common.action_failed")]; // 200002 密码错：内联红字，输入保留
    [self render];
}

- (void)cancelTapped {
    NSString *jobID = self.job.jobID;
    if (jobID.length == 0 || self.cancelling) { return; }
    self.cancelling = YES;
    [self showError:nil];
    [self refreshButtons];
    __weak typeof(self) ws = self;
    [self withToken:^(NSString *token, NSError *tokenErr) {
        if (!token) { [ws cancelFinishedWithError:tokenErr]; return; }
        [IMHTTPService.sharedService cancelExport:jobID token:token completion:^(NSError *err) { [ws cancelFinishedWithError:err]; }];
    }];
}

- (void)cancelFinishedWithError:(nullable NSError *)err {
    self.cancelling = NO;
    if (err) {
        IMLogWithTag(IMLogTagUI, @"export cancel failed code=%ld", (long)err.code);
        [self showError:err.localizedDescription.length > 0 ? err.localizedDescription : IMLocalized(@"common.action_failed")];
    }
    [self refreshLatest]; // 成功 → 任务变 canceled → 回配置态；失败（含任务刚好跑完）→ 以服务端状态为准
    [self render];
}

- (void)retryTapped {
    self.ackFailedID = self.job.jobID;
    [self showError:nil];
    [self render];
}

- (void)formatTapped:(IMExportCheckRow *)row {
    row.selected = !row.selected;
    [self fieldChanged];
}

- (void)fieldChanged {
    if (self.errorLabel.text.length > 0) { [self showError:nil]; }
    [self refreshButtons];
}

#pragma mark - 下载

- (void)downloadTapped {
    NSString *jobID = self.job.jobID;
    if (jobID.length == 0 || self.downloading) { return; }
    self.downloading = YES;
    [self resetDownloadProgress];
    [self showError:nil];
    [self render];
    __weak typeof(self) ws = self;
    [self withToken:^(NSString *token, NSError *tokenErr) {
        if (!token) { [ws downloadFailedWithMessage:tokenErr.localizedDescription refresh:NO]; return; }
        [IMHTTPService.sharedService exportDownloadURLForJob:jobID token:token completion:^(NSString *url, NSError *err) {
            if (err) { [ws downloadFailedWithMessage:err.localizedDescription refresh:YES]; return; }
            [ws downloadFromRelativeURL:url];
        }];
    }];
}

- (void)downloadFromRelativeURL:(NSString *)relative {
    NSURL *url = IMExportDownloadURL(relative, self.host);
    if (!url) { [self downloadFailedWithMessage:nil refresh:NO]; return; }
    NSString *name = IMExportFileName(self.job, NSDate.date);
    __weak typeof(self) ws = self;
    __block NSURLSessionDownloadTask *mine = nil;
    IMExportDownloadProgress onProgress = ^(int64_t written, int64_t expected) { // 已在主线程
        __strong typeof(ws) self = ws;
        if (!self || !self.downloading || self.downloadTask != mine) { return; }
        self.dlWritten = written; self.dlExpected = expected > 0 ? expected : 0; self.dlHasProgress = YES;
        [self renderDownloadProgress:YES];
    };
    self.downloadTask = mine = [IMExportDownloader downloadFromURL:url fileName:name progress:onProgress completion:^(NSURL *file, NSError *err) {
        __strong typeof(ws) self = ws;
        if (!self) { if (file) { [NSFileManager.defaultManager removeItemAtURL:file error:NULL]; } return; }
        self.downloadTask = nil;
        if (file) { [self presentShareForFile:file]; return; }
        if ([err.domain isEqualToString:NSURLErrorDomain] && err.code == NSURLErrorCancelled) { self.downloading = NO; [self resetDownloadProgress]; [self render]; return; }
        BOOL gone = [err.domain isEqualToString:IMExportDownloadErrorDomain] && IMExportDownloadFailureIsGone(err.code); // token 失效 / 文件已被清理（服务端回 401）
        [self downloadFailedWithMessage:gone ? IMLocalized(@"export.expired") : nil refresh:gone];
    }];
}

- (void)resetDownloadProgress {
    self.dlWritten = 0; self.dlExpected = 0; self.dlHasProgress = NO;
}

- (void)downloadFailedWithMessage:(nullable NSString *)msg refresh:(BOOL)refresh {
    self.downloading = NO;
    [self resetDownloadProgress];
    [self showError:msg.length > 0 ? msg : IMLocalized(@"export.download_failed")];
    if (refresh) { [self refreshLatest]; }
    [self render];
}

/// 从 root 沿 presentedViewController 链走到最上层；root 为 nil 返回 nil。
+ (UIViewController *)topPresentableFrom:(UIViewController *)root {
    UIViewController *top = root;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) { top = top.presentedViewController; }
    return top;
}

- (nullable UIViewController *)shareHostViewController {
    UIWindow *window = self.viewIfLoaded.window;
    if (!window) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) { continue; }
            for (UIWindow *w in ((UIWindowScene *)scene).windows) { if (w.isKeyWindow) { window = w; break; } }
            if (window) { break; }
        }
    }
    return [IMExportDataViewController topPresentableFrom:window.rootViewController];
}

- (void)presentShareForFile:(NSURL *)file {
    self.downloading = NO;
    [self resetDownloadProgress];
    [self render];
    UIViewController *host = [self shareHostViewController];
    if (!host) {
        // 确实无处可弹：清掉临时文件并告知，不静默吞掉。
        [NSFileManager.defaultManager removeItemAtURL:file error:NULL];
        [self im_showToast:IMLocalized(@"export.download_failed")];
        return;
    }
    UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
    vc.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *error) {
        if (error) { IMLogWithTag(IMLogTagUI, @"export share failed code=%ld", (long)error.code); }
        [NSFileManager.defaultManager removeItemAtURL:file error:NULL];
    };
    UIView *anchor = host == self ? self.downloadButton : host.view;
    vc.popoverPresentationController.sourceView = anchor;
    vc.popoverPresentationController.sourceRect = host == self ? anchor.bounds : CGRectMake(CGRectGetMidX(anchor.bounds), CGRectGetMidY(anchor.bounds), 1, 1);
    [host presentViewController:vc animated:YES completion:nil];
}

#pragma mark - 交互杂项

- (void)eyeTapped:(UIButton *)b {
    b.selected = !b.selected;
    UITextField *f = self.passwordField;
    BOOL wasFirst = f.isFirstResponder; // 切换 secureTextEntry 的光标跳位守护（同注销账号页）
    if (wasFirst) { [f resignFirstResponder]; }
    f.secureTextEntry = !b.selected;
    if (wasFirst) { [f becomeFirstResponder]; }
}

- (BOOL)textFieldShouldReturn:(UITextField *)f {
    [f resignFirstResponder];
    return NO;
}

- (void)keyboardWillChange:(NSNotification *)note {
    CGRect end = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:end fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - converted.origin.y);
    UIEdgeInsets ins = self.scrollView.contentInset;
    ins.bottom = overlap;
    self.scrollView.contentInset = ins;
    self.scrollView.verticalScrollIndicatorInsets = ins;
}

@end
