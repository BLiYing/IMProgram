//  IMDangerPageViewController.m

#import "IMDangerPageViewController.h"
#import "IMTheme.h"

@interface IMDangerPageViewController ()
@property (nonatomic, strong, readwrite) UIScrollView *scrollView;
@property (nonatomic, strong, readwrite) UIView *consequenceCard;
@property (nonatomic, strong, readwrite) UILabel *errorLabel;
@property (nonatomic, strong, readwrite) UIButton *submitButton;
@end

@implementation IMDangerPageViewController

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

#pragma mark - 覆写点默认值

- (NSString *)dangerHeaderText { return @""; }
- (NSArray<NSString *> *)dangerConsequenceTexts { return @[]; }
- (NSString *)dangerSubmitTitle { return @""; }
- (NSString *)dangerSubmitIdentifier { return nil; }
- (NSArray<UIView *> *)dangerViewsAboveConsequences { return @[]; }
- (NSArray<UIView *> *)dangerViewsBelowConsequences { return @[]; }
- (BOOL)dangerSubmitEnabled { return !self.busy; }
- (void)dangerSubmitTapped {}

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.scrollView = [UIScrollView new];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    UIStackView *stack = [self buildContentStack];
    [self.scrollView addSubview:stack];
    UILayoutGuide *content = self.scrollView.contentLayoutGuide;
    UILayoutGuide *frame = self.scrollView.frameLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        // 外边距：左右 16，顶 space4 × 2，底留白 space4 × 2
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:IMTheme.space4 * 2],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-IMTheme.space4 * 2],
        [stack.leadingAnchor constraintEqualToAnchor:frame.leadingAnchor constant:IMTheme.space4],
        [stack.trailingAnchor constraintEqualToAnchor:frame.trailingAnchor constant:-IMTheme.space4],
    ]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWillChange:)
                                               name:UIKeyboardWillChangeFrameNotification object:nil];
    [self refreshSubmitEnabled];
}

#pragma mark - 构造

- (UIStackView *)buildContentStack {
    UIView *warn = [self buildWarnIcon];
    UILabel *header = [UILabel new];
    header.text = [self dangerHeaderText];
    header.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    header.textColor = IMTheme.textPrimary;
    header.textAlignment = NSTextAlignmentCenter;
    header.numberOfLines = 0;

    self.consequenceCard = [self buildConsequenceCard];

    self.errorLabel = [UILabel new];
    self.errorLabel.font = [UIFont systemFontOfSize:13];
    self.errorLabel.textColor = UIColor.systemRedColor;
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.hidden = YES;

    [self buildSubmitButton];

    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithObjects:warn, header, nil];
    [views addObjectsFromArray:[self dangerViewsAboveConsequences]];
    [views addObject:self.consequenceCard];
    [views addObjectsFromArray:[self dangerViewsBelowConsequences]];
    [views addObjectsFromArray:@[self.errorLabel, self.submitButton]];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:views];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = IMTheme.space3;
    [stack setCustomSpacing:8 afterView:warn];
    [stack setCustomSpacing:14 afterView:header];
    [stack setCustomSpacing:IMTheme.space4 afterView:self.errorLabel];
    return stack;
}

/// 警示图标：圆 64pt，systemRed 12% 底，SF exclamationmark.triangle.fill 30pt。
- (UIView *)buildWarnIcon {
    UIView *circle = [UIView new];
    circle.translatesAutoresizingMaskIntoConstraints = NO;
    circle.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.12];
    circle.layer.cornerRadius = 32;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:30];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"exclamationmark.triangle.fill" withConfiguration:cfg]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = UIColor.systemRedColor;
    icon.contentMode = UIViewContentModeCenter;
    [circle addSubview:icon];
    UIView *wrap = [UIView new];
    [wrap addSubview:circle];
    [NSLayoutConstraint activateConstraints:@[
        [circle.widthAnchor constraintEqualToConstant:64], [circle.heightAnchor constraintEqualToConstant:64],
        [circle.topAnchor constraintEqualToAnchor:wrap.topAnchor], [circle.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor],
        [circle.centerXAnchor constraintEqualToAnchor:wrap.centerXAnchor],
        [icon.centerXAnchor constraintEqualToAnchor:circle.centerXAnchor], [icon.centerYAnchor constraintEqualToAnchor:circle.centerYAnchor],
    ]];
    return wrap;
}

/// 后果清单：分组卡内，每行「•」开头、15pt textPrimary，行间 8，卡片内边距 16，不可点。
- (UIView *)buildConsequenceCard {
    NSMutableArray<UIView *> *rows = [NSMutableArray array];
    for (NSString *consequence in [self dangerConsequenceTexts]) {
        UILabel *dot = [UILabel new];
        dot.text = @"•";
        dot.font = [UIFont systemFontOfSize:15];
        dot.textColor = IMTheme.textPrimary;
        [dot setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        UILabel *text = [UILabel new];
        text.text = consequence;
        text.font = [UIFont systemFontOfSize:15];
        text.textColor = IMTheme.textPrimary;
        text.numberOfLines = 0;
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[dot, text]];
        row.spacing = 8;
        row.alignment = UIStackViewAlignmentFirstBaseline;
        [rows addObject:row];
    }
    UIStackView *card = [[UIStackView alloc] initWithArrangedSubviews:rows];
    card.axis = UILayoutConstraintAxisVertical;
    card.spacing = 8;
    card.layoutMargins = UIEdgeInsetsMake(IMTheme.space4, IMTheme.space4, IMTheme.space4, IMTheme.space4);
    card.layoutMarginsRelativeArrangement = YES;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 12;
    return card;
}

/// 信息条：13pt accent，底 accent 12%（IMTheme.accentSoft），圆角 12，内边距 12。
- (UIView *)dangerInfoTipWithText:(NSString *)text {
    UILabel *l = [UILabel new];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    l.text = text;
    l.font = [UIFont systemFontOfSize:13];
    l.textColor = IMTheme.accent;
    l.numberOfLines = 0;
    UIView *tip = [UIView new];
    tip.backgroundColor = IMTheme.accentSoft;
    tip.layer.cornerRadius = 12;
    [tip addSubview:l];
    [self pin:l into:tip inset:IMTheme.space3];
    return tip;
}

/// 红按钮：高 50，圆角 12，systemRed 底，17pt Semibold 白字（同修改密码按钮，仅底色换红）；置灰 = 40% 透明。
- (void)buildSubmitButton {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.backgroundColor = UIColor.systemRedColor;
    b.layer.cornerRadius = 12;
    b.accessibilityIdentifier = [self dangerSubmitIdentifier];
    [b setTitle:[self dangerSubmitTitle] forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateDisabled];
    b.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [b addTarget:self action:@selector(dangerSubmitTapped) forControlEvents:UIControlEventTouchUpInside];
    [b.heightAnchor constraintEqualToConstant:50].active = YES;
    self.submitButton = b;
}

- (void)pin:(UIView *)child into:(UIView *)parent inset:(CGFloat)inset {
    [NSLayoutConstraint activateConstraints:@[
        [child.topAnchor constraintEqualToAnchor:parent.topAnchor constant:inset],
        [child.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor constant:-inset],
        [child.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor constant:inset],
        [child.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor constant:-inset],
    ]];
}

#pragma mark - 状态

- (void)refreshSubmitEnabled {
    BOOL ok = [self dangerSubmitEnabled];
    self.submitButton.enabled = ok;
    self.submitButton.alpha = ok ? 1.0 : 0.4;
}

- (void)showError:(NSString *)text {
    self.errorLabel.text = text;
    self.errorLabel.hidden = text.length == 0;
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    [self refreshSubmitEnabled];
    self.submitButton.titleLabel.alpha = busy ? 0 : 1;
    UIActivityIndicatorView *spin = [self.submitButton viewWithTag:7001];
    if (busy && !spin) {
        spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        spin.tag = 7001;
        spin.color = UIColor.whiteColor;
        spin.translatesAutoresizingMaskIntoConstraints = NO;
        [self.submitButton addSubview:spin];
        [NSLayoutConstraint activateConstraints:@[
            [spin.centerXAnchor constraintEqualToAnchor:self.submitButton.centerXAnchor],
            [spin.centerYAnchor constraintEqualToAnchor:self.submitButton.centerYAnchor]]];
        [spin startAnimating];
    } else if (!busy) {
        [spin removeFromSuperview];
    }
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
