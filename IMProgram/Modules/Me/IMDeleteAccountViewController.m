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
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UIView *cooldownTip;
@property (nonatomic, strong) UIView *passwordCard;
@property (nonatomic, strong) UITextView *ownedView;     ///< 群主阻断提示（红）；仅阻断态显示
@property (nonatomic, assign) BOOL blocked;
@property (nonatomic, weak, nullable) UIWindow *deletionWindow; ///< 提交时的宿主窗口（页面被 pop 后 view.window 为 nil，收尾要用）
@end

@implementation IMDeleteAccountViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) { _host = [host copy]; _userID = [userID copy]; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"delete_account.title");
}

#pragma mark - 版式覆写（共用版式见 IMDangerPageViewController）

- (NSString *)dangerHeaderText { return IMLocalized(@"delete_account.header"); }
- (NSString *)dangerSubmitTitle { return IMLocalized(@"delete_account.title"); }
- (NSString *)dangerSubmitIdentifier { return @"delete_account.submit"; }

- (NSArray<NSString *> *)dangerConsequenceTexts {
    return @[IMLocalized(@"delete_account.consequence_1"), IMLocalized(@"delete_account.consequence_2"),
             IMLocalized(@"delete_account.consequence_3"), IMLocalized(@"delete_account.consequence_4")];
}

- (NSArray<UIView *> *)dangerViewsAboveConsequences {
    self.ownedView = [self buildOwnedView];
    return @[self.ownedView];
}

- (NSArray<UIView *> *)dangerViewsBelowConsequences {
    self.cooldownTip = [self dangerInfoTipWithText:IMLocalized(@"delete_account.cooldown_hint")];
    self.passwordCard = [self buildPasswordCard];
    return @[self.cooldownTip, self.passwordCard];
}

- (BOOL)dangerSubmitEnabled { return IMDeleteAccountCanSubmit(self.passwordField.text, self.blocked, self.busy); }
- (void)dangerSubmitTapped { [self submitTapped]; }

#pragma mark - 构造

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

#pragma mark - 状态

- (void)fieldChanged {
    if (!self.errorLabel.hidden) { self.errorLabel.hidden = YES; }
    [self refreshSubmitEnabled];
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

/// 从群页（转让 / 解散群主身份）返回时退出阻断态：名单已过时，服务端在下一次提交时重新判定。
/// 否则按钮与密码框一直置灰，只能退出本页再进。首次出现时 blocked 为 NO，不受影响。
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.blocked) { return; }
    self.blocked = NO;
    self.ownedView.hidden = YES;
    self.consequenceCard.hidden = NO;
    self.cooldownTip.hidden = NO;
    self.passwordField.enabled = YES;
    self.passwordCard.alpha = 1;
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

/// 取新鲜 token → POST /account/delete。在途期间置 accountDeletionInProgress，让 SceneDelegate 的被踢通路让路。
- (void)performDelete {
    NSString *password = self.passwordField.text ?: @"";
    [self setBusy:YES];
    [self showError:@""];
    IMSessionTeardown.accountDeletionInProgress = YES;
    IMHTTPService.sharedService.host = self.host;
    // 回调里**强持有** self：请求在途时用户可能侧滑返回导致页面释放，若用 weak 早退，
    // accountDeletionInProgress 会永远停在 YES（被踢通路被永久屏蔽），且服务端已注销而本机会话没清。
    // 请求有超时，强持有的生命周期有限。窗口在点击时先取好：页面被 pop 后 self.view.window 为 nil。
    self.deletionWindow = self.view.window;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *loginErr) {
        if (token.length == 0) { [self failWithError:loginErr]; return; }
        [IMHTTPService.sharedService deleteAccountWithToken:token password:password completion:^(NSError *err) {
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
    UIWindow *window = self.view.window ?: self.deletionWindow;
    [IMSessionTeardown wipeLocalChatCacheThen:^{ // 清库在后台队列；回主线程后才清会话（清库要靠当前 owner）
        [IMSessionTeardown tearDownLocalSession];
        [IMSessionTeardown showLoginInWindow:window notice:IMLocalized(@"delete_account.done_hint")];
        IMSessionTeardown.accountDeletionInProgress = NO;
    }];
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
