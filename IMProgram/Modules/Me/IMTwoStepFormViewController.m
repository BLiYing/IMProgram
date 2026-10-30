//  IMTwoStepFormViewController.m

#import "IMTwoStepFormViewController.h"
#import "IMHTTPService.h"
#import "IMLocalization.h"
#import "UIViewController+IMToast.h"

@implementation IMTwoStepRow
+ (instancetype)rowWithView:(UIView *)view onTap:(void (^)(void))onTap {
    IMTwoStepRow *r = [IMTwoStepRow new];
    r.view = view;
    r.onTap = onTap;
    return r;
}
@end

@implementation IMTwoStepSection
+ (instancetype)sectionWithRows:(NSArray<IMTwoStepRow *> *)rows footer:(NSString *)footer {
    IMTwoStepSection *s = [IMTwoStepSection new];
    s.rows = rows;
    s.footer = footer;
    return s;
}
@end

@interface IMTwoStepFormViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy, readwrite) NSString *host;
@property (nonatomic, copy, readwrite) NSString *userID;
@property (nonatomic, strong, readwrite) UITableView *tableView;
@property (nonatomic, strong, readwrite) UIButton *primaryButton;
@property (nonatomic, strong, readwrite) UILabel *errorLabel;
@property (nonatomic, strong) UIView *errorWrap;
@property (nonatomic, strong) UIStackView *footerStack;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, copy) NSArray<IMTwoStepSection *> *sections;
@property (nonatomic, weak) UIView *errorMarked;
@property (nonatomic, assign) CGFloat lastFooterWidth;
@end

@implementation IMTwoStepFormViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
    }
    return self;
}

#pragma mark - 覆写点默认值

- (NSString *)pageTitle { return @""; }
- (NSArray<IMTwoStepSection *> *)buildSections { return @[]; }
- (UIView *)headerContentView { return nil; }
- (NSString *)primaryTitle { return nil; }
- (UIColor *)primaryColor { return UIColor.systemBlueColor; }
- (BOOL)primaryEnabled { return YES; }
- (void)primaryTapped {}
- (BOOL)locksBackNavigation { return NO; }
- (BOOL)isFlowRoot { return NO; }

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [self pageTitle];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.estimatedRowHeight = 44;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionFooterHeight = 40;
    self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionHeaderHeight = 40;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    [self.view addSubview:self.tableView];

    [self buildFooter];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWillChange:)
                                               name:UIKeyboardWillChangeFrameNotification object:nil];
    [self reloadSections];
    [self refreshPrimary];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyNavigationLock];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self setPopGesturesEnabled:YES]; // 不把「禁用」带给别的页
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (fabs(self.tableView.bounds.size.width - self.lastFooterWidth) > 0.5) {
        [self relayoutHeaderFooter];
        [self.tableView beginUpdates]; [self.tableView endUpdates]; // 宽度变了：重新量说明块高度（不重建 cell，不丢焦点）
    }
}

#pragma mark - 构造

- (void)buildFooter {
    self.errorLabel = [UILabel new];
    self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.errorLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; // 13pt
    self.errorLabel.textColor = UIColor.systemRedColor;
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.accessibilityIdentifier = @"twostep.error";
    self.errorWrap = [UIView new];
    self.errorWrap.translatesAutoresizingMaskIntoConstraints = NO;
    [self.errorWrap addSubview:self.errorLabel];
    [NSLayoutConstraint activateConstraints:@[ // 外层栈已缩进 16，这里再 16 = 左右 32
        [self.errorLabel.leadingAnchor constraintEqualToAnchor:self.errorWrap.leadingAnchor constant:16],
        [self.errorLabel.trailingAnchor constraintEqualToAnchor:self.errorWrap.trailingAnchor constant:-16],
        [self.errorLabel.topAnchor constraintEqualToAnchor:self.errorWrap.topAnchor],
        [self.errorLabel.bottomAnchor constraintEqualToAnchor:self.errorWrap.bottomAnchor],
    ]];
    self.errorWrap.hidden = YES;

    self.primaryButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.primaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.primaryButton.layer.cornerRadius = 12;
    self.primaryButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.primaryButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [self.primaryButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.primaryButton.accessibilityIdentifier = @"twostep.primary";
    [self.primaryButton addTarget:self action:@selector(primaryButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.primaryButton.heightAnchor constraintEqualToConstant:50].active = YES;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.color = UIColor.whiteColor;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.primaryButton addSubview:self.spinner];
    [NSLayoutConstraint activateConstraints:@[
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.primaryButton.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.primaryButton.centerYAnchor],
    ]];

    self.footerStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.errorWrap, self.primaryButton]];
    self.footerStack.axis = UILayoutConstraintAxisVertical;
    self.footerStack.spacing = 14;
    self.footerStack.layoutMarginsRelativeArrangement = YES;
    self.footerStack.layoutMargins = UIEdgeInsetsMake(6, 16, 24, 16);
}

#pragma mark - 刷新

- (void)reloadSections {
    self.sections = [self buildSections];
    UIView *content = [self headerContentView];
    if (content) {
        content.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        self.tableView.tableHeaderView = content;
    } else {
        self.tableView.tableHeaderView = nil;
    }
    [self relayoutHeaderFooter];
    [self.tableView reloadData];
}

/// 表头 / 表尾是 frame 布局的容器：宽度变化（旋转 / 首次布局）或内容变化（红字出现）后手动重算高度。
- (void)relayoutHeaderFooter {
    CGFloat w = self.tableView.bounds.size.width;
    if (w <= 0) { return; }
    self.lastFooterWidth = w;
    UIView *header = self.tableView.tableHeaderView;
    if (header) {
        CGSize s = [header systemLayoutSizeFittingSize:CGSizeMake(w, UILayoutFittingCompressedSize.height)
                         withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
        header.frame = CGRectMake(0, 0, w, s.height);
        self.tableView.tableHeaderView = header;
    }
    BOOL hasButton = [self primaryTitle].length > 0;
    self.primaryButton.hidden = !hasButton;
    if (!hasButton && !self.errorLabel.text.length) {
        self.tableView.tableFooterView = nil;
        return;
    }
    CGSize fs = [self.footerStack systemLayoutSizeFittingSize:CGSizeMake(w, UILayoutFittingCompressedSize.height)
                                withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    self.footerStack.frame = CGRectMake(0, 0, w, fs.height);
    self.tableView.tableFooterView = self.footerStack;
}

- (void)refreshPrimary {
    NSString *title = [self primaryTitle];
    BOOL hasButton = title.length > 0;
    BOOL hiddenChanged = self.primaryButton.hidden == hasButton;
    self.primaryButton.hidden = !hasButton;
    self.primaryButton.backgroundColor = [self primaryColor];
    [self.primaryButton setTitle:self.busy ? @"" : title forState:UIControlStateNormal];
    BOOL enabled = hasButton && [self primaryEnabled] && !self.busy;
    self.primaryButton.enabled = enabled;
    self.primaryButton.alpha = enabled ? 1.0 : (self.busy ? 0.7 : 0.5); // 不可用 alpha 0.5；在途略淡 + 转圈
    if (self.busy) { [self.spinner startAnimating]; } else { [self.spinner stopAnimating]; }
    if (hiddenChanged) { [self relayoutHeaderFooter]; }
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    [self refreshPrimary];
    [self applyNavigationLock];
    self.tableView.allowsSelection = !busy;
}

- (void)primaryButtonTapped {
    if (self.busy || !self.primaryButton.enabled) { return; }
    [self primaryTapped];
}

- (void)showError:(NSString *)text {
    self.errorLabel.text = text.length > 0 ? text : nil;
    self.errorWrap.hidden = text.length == 0;
    if (text.length == 0) { [self markErrorView:nil]; }
    [self relayoutHeaderFooter];
}

- (void)markErrorView:(UIView *)view {
    self.errorMarked.layer.borderWidth = 0;
    self.errorMarked = view;
    if (view) {
        view.layer.borderWidth = 1;
        view.layer.borderColor = UIColor.systemRedColor.CGColor;
    }
}

#pragma mark - 导航锁

- (void)applyNavigationLock {
    BOOL lock = self.busy || [self locksBackNavigation];
    self.navigationItem.hidesBackButton = lock;
    [self setPopGesturesEnabled:!lock];
}

- (void)setPopGesturesEnabled:(BOOL)enabled {
    UINavigationController *nav = self.navigationController;
    nav.interactivePopGestureRecognizer.enabled = enabled;
    if (@available(iOS 26.0, *)) { nav.interactiveContentPopGestureRecognizer.enabled = enabled; }
}

- (void)withToken:(void (^)(NSString *))block {
    __weak typeof(self) ws = self;
    [self withToken:block failure:^(NSError *err) {
        __strong typeof(ws) self = ws;
        self.busy = NO;
        [self showError:err.localizedDescription.length > 0 ? err.localizedDescription : IMLocalized(@"password.error.session_expired")];
    }];
}

- (void)withToken:(void (^)(NSString *))block failure:(void (^)(NSError *))failure {
    IMHTTPService.sharedService.host = self.host;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *err) {
        if (token.length == 0) { if (failure) { failure(err); } return; }
        block(token);
    }];
}

- (void)popToFlowRootWithToast:(NSString *)toast {
    UINavigationController *nav = self.navigationController;
    UIViewController *root = nil;
    for (UIViewController *vc in nav.viewControllers) {
        if ([vc isKindOfClass:IMTwoStepFormViewController.class] && [(IMTwoStepFormViewController *)vc isFlowRoot]) { root = vc; break; }
    }
    if (root) { [nav popToViewController:root animated:YES]; }
    else { [nav popViewControllerAnimated:YES]; root = nav.topViewController; }
    if (toast.length == 0) { return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [root im_showToast:toast];
    });
}

#pragma mark - 键盘

- (void)keyboardWillChange:(NSNotification *)note {
    CGRect end = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:end fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - converted.origin.y);
    UIEdgeInsets ins = self.tableView.contentInset;
    ins.bottom = overlap;
    self.tableView.contentInset = ins;
    self.tableView.verticalScrollIndicatorInsets = ins;
    if (overlap > 0) { dispatch_async(dispatch_get_main_queue(), ^{ [self scrollPrimaryButtonIntoView]; }); }
}

- (void)scrollPrimaryButtonIntoView {
    if (!self.isViewLoaded || self.primaryButton.hidden || !self.tableView.tableFooterView) { return; }
    [self.tableView layoutIfNeeded];
    CGRect footer = self.tableView.tableFooterView.frame;
    [self.tableView scrollRectToVisible:footer animated:YES];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return (NSInteger)self.sections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.sections[section].rows.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    IMTwoStepRow *row = self.sections[ip.section].rows[ip.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = row.onTap ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    cell.accessoryType = row.showsChevron ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    [row.view removeFromSuperview];
    row.view.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:row.view];
    [NSLayoutConstraint activateConstraints:@[
        [row.view.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
        [row.view.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
        [row.view.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
        [row.view.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
    ]];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    IMTwoStepRow *row = self.sections[ip.section].rows[ip.row];
    if (row.onTap && !self.busy) { row.onTap(); }
}

- (BOOL)tableView:(UITableView *)tv shouldHighlightRowAtIndexPath:(NSIndexPath *)ip {
    return self.sections[ip.section].rows[ip.row].onTap != nil;
}

- (UIView *)textBlock:(NSString *)text {
    UILabel *l = [UILabel new];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    l.text = text;
    l.font = [UIFont systemFontOfSize:13];
    l.textColor = UIColor.secondaryLabelColor;
    l.numberOfLines = 0;
    UIView *v = [UIView new];
    [v addSubview:l];
    [NSLayoutConstraint activateConstraints:@[
        [l.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:16],
        [l.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-16],
        [l.topAnchor constraintEqualToAnchor:v.topAnchor constant:8],
        [l.bottomAnchor constraintEqualToAnchor:v.bottomAnchor constant:-8],
    ]];
    return v;
}

- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section {
    NSString *t = self.sections[section].header;
    return t.length > 0 ? [self textBlock:t] : nil;
}
- (UIView *)tableView:(UITableView *)tv viewForFooterInSection:(NSInteger)section {
    NSString *t = self.sections[section].footer;
    return t.length > 0 ? [self textBlock:t] : nil;
}
/// 说明块高度：自定义 header / footer 视图用自动高度会把多行文字截成一行，这里按宽度显式量。
- (CGFloat)textBlockHeight:(NSString *)text {
    CGFloat w = MAX(100, self.tableView.bounds.size.width - 32 - 40); // InsetGrouped 的说明块两侧另有 ~20pt 系统缩进
    CGRect r = [text boundingRectWithSize:CGSizeMake(w, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin
                               attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:13] } context:nil];
    return ceil(r.size.height) + 16;
}
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)section {
    NSString *t = self.sections[section].header;
    if (t.length > 0) { return [self textBlockHeight:t]; }
    return section == 0 ? 8 : 0.01;
}
- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)section {
    NSString *t = self.sections[section].footer;
    return t.length > 0 ? [self textBlockHeight:t] : 16;
}

@end
