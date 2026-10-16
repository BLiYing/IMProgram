//  IMDeleteAccountViewController.m

#import "IMDeleteAccountViewController.h"
#import "IMChatDetailViewController.h"
#import "IMHTTPService+Account.h"
#import "IMSessionTeardown.h"
#import "IMTheme.h"
#import "IMLog.h"
#import "IMLocalization.h"

NSInteger const IMDeleteAccountMaxListedGroups = 3;

BOOL IMDeleteAccountCanSubmit(NSString *password, BOOL blocked, BOOL busy) {
    return password.length > 0 && !blocked && !busy;
}

NSArray<NSDictionary<NSString *, NSString *> *> *IMDeleteAccountListedGroups(NSArray<NSDictionary<NSString *, NSString *> *> *groups) {
    NSUInteger n = MIN(groups.count, (NSUInteger)IMDeleteAccountMaxListedGroups);
    return [groups subarrayWithRange:NSMakeRange(0, n)];
}

NSInteger IMDeleteAccountHiddenGroupCount(NSArray<NSDictionary<NSString *, NSString *> *> *groups) {
    return MAX(0, (NSInteger)groups.count - IMDeleteAccountMaxListedGroups);
}

static NSString * const kOwnedGroupScheme = @"imgroup";

@interface IMDeleteAccountViewController () <UITextFieldDelegate, UITextViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UIButton *submitButton;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIView *consequenceCard;
@property (nonatomic, strong) UIView *cooldownTip;
@property (nonatomic, strong) UIView *passwordCard;
@property (nonatomic, strong) UITextView *ownedView;     ///< 群主阻断提示（红）；仅阻断态显示
@property (nonatomic, assign) BOOL blocked;
@property (nonatomic, assign) BOOL busy;
@end

@implementation IMDeleteAccountViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) { _host = [host copy]; _userID = [userID copy]; }
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"delete_account.title");
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
    header.text = IMLocalized(@"delete_account.header");
    header.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    header.textColor = IMTheme.textPrimary;
    header.textAlignment = NSTextAlignmentCenter;
    header.numberOfLines = 0;

    self.ownedView = [self buildOwnedView];
    self.consequenceCard = [self buildConsequenceCard];
    self.cooldownTip = [self buildCooldownTip];
    self.passwordCard = [self buildPasswordCard];

    self.errorLabel = [UILabel new];
    self.errorLabel.font = [UIFont systemFontOfSize:13];
    self.errorLabel.textColor = UIColor.systemRedColor;
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.hidden = YES;

    [self buildSubmitButton];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        warn, header, self.ownedView, self.consequenceCard, self.cooldownTip, self.passwordCard, self.errorLabel, self.submitButton]];
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

/// 4 条后果：分组卡内，每行「•」开头、15pt textPrimary，行间 8，卡片内边距 16，不可点。
- (UIView *)buildConsequenceCard {
    NSMutableArray<UIView *> *rows = [NSMutableArray array];
    NSArray<NSString *> *texts = @[IMLocalized(@"delete_account.consequence_1"), IMLocalized(@"delete_account.consequence_2"),
                                   IMLocalized(@"delete_account.consequence_3"), IMLocalized(@"delete_account.consequence_4")];
    for (NSString *consequence in texts) {
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

/// 冷静期提示条：13pt accent，底 accent 12%（IMTheme.accentSoft），圆角 12，内边距 12。
- (UIView *)buildCooldownTip {
    UILabel *l = [UILabel new];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    l.text = IMLocalized(@"delete_account.cooldown_hint");
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

/// 密码框：与 IMChangePasswordViewController 同款（secureTextEntry + 眼睛 rightView），16pt，卡底 secondarySystemGroupedBackground。
- (UIView *)buildPasswordCard {
    UITextField *f = [UITextField new];
    f.translatesAutoresizingMaskIntoConstraints = NO;
    f.font = [UIFont systemFontOfSize:16];
    f.textColor = UIColor.labelColor;
    f.placeholder = IMLocalized(@"delete_account.password_hint");
    f.secureTextEntry = YES;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.spellCheckingType = UITextSpellCheckingTypeNo;
    f.returnKeyType = UIReturnKeyDone;
    f.delegate = self;
    f.accessibilityIdentifier = @"delete_account.password";
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
    card.layer.cornerRadius = 12;
    [card addSubview:f];
    [NSLayoutConstraint activateConstraints:@[
        [f.topAnchor constraintEqualToAnchor:card.topAnchor], [f.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [f.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [f.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [f.heightAnchor constraintEqualToConstant:44],
    ]];
    return card;
}

/// 红按钮：高 50，圆角 12，systemRed 底，17pt Semibold 白字（同修改密码按钮，仅底色换红）；置灰 = 40% 透明。
- (void)buildSubmitButton {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.backgroundColor = UIColor.systemRedColor;
    b.layer.cornerRadius = 12;
    b.accessibilityIdentifier = @"delete_account.submit";
    [b setTitle:IMLocalized(@"delete_account.title") forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateDisabled];
    b.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [b addTarget:self action:@selector(submitTapped) forControlEvents:UIControlEventTouchUpInside];
    [b.heightAnchor constraintEqualToConstant:50].active = YES;
    self.submitButton = b;
}

/// 群主阻断提示卡：systemRed 12% 底、13pt 红字、圆角 12、内边距 12；群名为可点链接（进该群管理页）。
- (UITextView *)buildOwnedView {
    UITextView *tv = [UITextView new];
    tv.editable = NO;
    tv.scrollEnabled = NO;
    tv.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.12];
    tv.layer.cornerRadius = 12;
    tv.textContainerInset = UIEdgeInsetsMake(IMTheme.space3, IMTheme.space3, IMTheme.space3, IMTheme.space3);
    tv.textContainer.lineFragmentPadding = 0;
    tv.linkTextAttributes = @{ NSForegroundColorAttributeName: UIColor.systemRedColor,
                               NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle) };
    tv.delegate = self;
    tv.hidden = YES;
    return tv;
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
    BOOL ok = IMDeleteAccountCanSubmit(self.passwordField.text, self.blocked, self.busy);
    self.submitButton.enabled = ok;
    self.submitButton.alpha = ok ? 1.0 : 0.4;
}

- (void)fieldChanged {
    if (!self.errorLabel.hidden) { self.errorLabel.hidden = YES; }
    [self refreshSubmitEnabled];
}

- (void)showError:(NSString *)text {
    self.errorLabel.text = text;
    self.errorLabel.hidden = text.length == 0;
}

/// 阻断态：显示红色提示卡（含可点群名），隐藏后果与冷静期条，密码框与按钮置灰。
- (void)enterBlockedStateWithGroups:(NSArray<NSDictionary<NSString *, NSString *> *> *)groups {
    self.blocked = YES;
    NSArray *listed = IMDeleteAccountListedGroups(groups);
    NSInteger hidden = IMDeleteAccountHiddenGroupCount(groups);
    UIFont *font = [UIFont systemFontOfSize:13];
    NSDictionary *base = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: UIColor.systemRedColor };
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc]
        initWithString:[IMLocalized(@"delete_account.owned_groups") stringByAppendingString:@"\n"] attributes:base];
    for (NSUInteger i = 0; i < listed.count; i++) {
        if (i > 0) { [text appendAttributedString:[[NSAttributedString alloc] initWithString:@" · " attributes:base]]; }
        NSDictionary<NSString *, NSString *> *g = listed[i];
        NSMutableDictionary *attrs = [base mutableCopy];
        NSString *gid = g[@"id"];
        NSString *gname = g[@"name"].length > 0 ? g[@"name"] : gid;
        if (gid.length > 0) {
            attrs[NSLinkAttributeName] = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@", kOwnedGroupScheme,
                [gid stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLHostAllowedCharacterSet]]];
        }
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:gname attributes:attrs]];
    }
    if (hidden > 0) {
        NSString *more = IMLocalizedFormat(@"delete_account.owned_groups_more", (long)hidden);
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:[@" · " stringByAppendingString:more] attributes:base]];
    }
    self.ownedView.attributedText = text;
    self.ownedView.hidden = NO;
    self.consequenceCard.hidden = YES;
    self.cooldownTip.hidden = YES;
    self.passwordField.enabled = NO;
    self.passwordCard.alpha = 0.4;
    [self.view endEditing:YES];
    [self refreshSubmitEnabled];
}

#pragma mark - 提交

- (void)submitTapped {
    if (!IMDeleteAccountCanSubmit(self.passwordField.text, self.blocked, self.busy)) { return; }
    [self.view endEditing:YES];
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:IMLocalized(@"delete_account.confirm_title")
                                                                message:IMLocalized(@"delete_account.confirm_message")
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"delete_account.confirm_action") style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) { [ws performDelete]; }]];
    [self presentViewController:ac animated:YES completion:nil];
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

/// 取新鲜 token → POST /account/delete。在途期间置 accountDeletionInProgress，让 SceneDelegate 的被踢通路让路。
- (void)performDelete {
    NSString *password = self.passwordField.text ?: @"";
    [self setBusy:YES];
    [self showError:@""];
    IMSessionTeardown.accountDeletionInProgress = YES;
    IMHTTPService.sharedService.host = self.host;
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *loginErr) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (token.length == 0) { [self failWithError:loginErr]; return; }
        [IMHTTPService.sharedService deleteAccountWithToken:token password:password completion:^(NSError *err) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (err) { [self failWithError:err]; return; }
            [self finishDeletion];
        }];
    }];
}

- (void)failWithError:(NSError *)err {
    IMSessionTeardown.accountDeletionInProgress = NO;
    [self setBusy:NO];
    NSArray *owned = err.userInfo[IMErrorOwnedGroupsKey];
    if (err.code == IMErrCodeNoPermission && owned.count > 0) {
        [self enterBlockedStateWithGroups:owned];
        return;
    }
    NSString *msg = err.localizedDescription;
    [self showError:msg.length > 0 ? msg : IMLocalized(@"common.action_failed")];
}

/// 成功：先清本机聊天缓存（还要靠当前 owner 定位），再走与退出登录同一条清会话路径，回登录页并提示。
- (void)finishDeletion {
    IMLogWithTag(IMLogTagHTTP, @"account_deleted → 清本机会话与聊天缓存");
    UIWindow *window = self.view.window;
    [IMSessionTeardown wipeLocalChatCache];
    [IMSessionTeardown tearDownLocalSession];
    [IMSessionTeardown showLoginInWindow:window notice:IMLocalized(@"delete_account.done_hint")];
    IMSessionTeardown.accountDeletionInProgress = NO;
}

#pragma mark - 交互杂项

- (void)eyeTapped:(UIButton *)b {
    b.selected = !b.selected;
    UITextField *f = self.passwordField;
    BOOL wasFirst = f.isFirstResponder; // 切换 secureTextEntry 的光标跳位守护（同修改密码页）
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

- (BOOL)textView:(UITextView *)tv shouldInteractWithURL:(NSURL *)url inRange:(NSRange)range interaction:(UITextItemInteraction)interaction {
    if (![url.scheme isEqualToString:kOwnedGroupScheme]) { return YES; }
    NSString *convID = url.host.stringByRemovingPercentEncoding ?: url.host;
    if (convID.length == 0) { return NO; }
    NSString *name = [tv.text substringWithRange:range];
    IMChatDetailViewController *detail = [[IMChatDetailViewController alloc] initGroupWithHost:self.host userID:self.userID
                                                                                        convID:convID groupName:name groupAvatarURL:nil];
    [self.navigationController pushViewController:detail animated:YES];
    return NO;
}

@end
