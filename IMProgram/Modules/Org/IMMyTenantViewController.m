//  IMMyTenantViewController.m

#import "IMMyTenantViewController.h"
#import "IMHTTPService.h"
#import "IMHTTPService+Directory.h"
#import "IMLocalization.h"
#import "IMLog.h"
#import "IMServerConfigStore.h"
#import "IMTenantStore.h"
#import "IMDirectoryViewController.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"

BOOL IMMyTenantShowsInvite(BOOL hasTenant, BOOL isCustomer, BOOL inviteEnabled) {
    return inviteEnabled && (!hasTenant || isCustomer);
}

typedef NS_ENUM(NSInteger, IMMyTenantSection) { IMMyTenantSectionInvite, IMMyTenantSectionTenant };

static NSString * const kIMMyTenantCell = @"cell";
static const CGFloat kIMMyTenantFooterInset = 20;

@interface IMMyTenantViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextField *codeField;
@property (nonatomic, strong) UIButton *joinButton;
@property (nonatomic, copy, nullable) NSString *errorText;   // 提交失败的原因（段下红字）
@property (nonatomic, assign) BOOL submitting;
@property (nonatomic, copy, nullable) NSArray<NSNumber *> *renderedSections; // 表格当前按哪几段画的（判断能否局部刷新）
@property (nonatomic, weak, nullable) UILabel *inviteFooterLabel; // 只改它的字，不 reloadData（否则输入框被摘下、键盘收起）
@end

@implementation IMMyTenantViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    if ((self = [super initWithNibName:nil bundle:nil])) { _host = [host copy]; _userID = [userID copy]; }
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"org.invite.entry");
    self.view.backgroundColor = IMTheme.groupedBackground;
    UITableView *tv = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.dataSource = self; tv.delegate = self;
    tv.backgroundColor = IMTheme.groupedBackground;
    tv.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [tv registerClass:UITableViewCell.class forCellReuseIdentifier:kIMMyTenantCell];
    self.tableView = tv;
    [self.view addSubview:tv];
    [self buildCodeField];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onTenantChanged)
                                               name:IMTenantStoreDidChangeNotification object:nil];
    [IMTenantStore.shared refresh];
}

/// 快照变了：段结构没变且正在输入邀请码时只刷已绑定段——整表 reload 会把输入框从 cell 摘下、键盘收起
///（回前台 / 重连都会重拉 me，用户正打字时也会来）。
- (void)onTenantChanged {
    NSArray<NSNumber *> *now = [self sections];
    // 看着这页时身份变成员工（后台加人 / 调岗）：两段都没了，留着就是空白页，退回上一页。
    if (now.count == 0 && IMTenantStore.shared.loaded && IMTenantStore.shared.hasTenant) {
        if (self.navigationController.topViewController == self) { [self.navigationController popViewControllerAnimated:YES]; }
        return;
    }
    BOOL sameShape = [now isEqualToArray:self.renderedSections ?: @[]];
    self.renderedSections = now;
    if (!(sameShape && self.codeField.isFirstResponder)) { [self.tableView reloadData]; return; }
    NSUInteger idx = [now indexOfObject:@(IMMyTenantSectionTenant)];
    if (idx != NSNotFound) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:idx] withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void)buildCodeField {
    UITextField *f = [UITextField new];
    f.placeholder = IMLocalized(@"org.invite.placeholder");
    f.font = [UIFont systemFontOfSize:17];
    f.autocapitalizationType = UITextAutocapitalizationTypeNone; // 不预校验、不转大写：原样交服务端（大小写不敏感）
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.spellCheckingType = UITextSpellCheckingTypeNo;
    f.returnKeyType = UIReturnKeyJoin;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.delegate = self;
    f.accessibilityIdentifier = @"org.invite.field";
    [f addTarget:self action:@selector(codeChanged) forControlEvents:UIControlEventEditingChanged];
    self.codeField = f;
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:IMLocalized(@"org.invite.join") forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15];
    [b setTitleColor:IMTheme.accent forState:UIControlStateNormal];
    [b setTitleColor:IMTheme.textTertiary forState:UIControlStateDisabled];
    b.enabled = NO;
    b.accessibilityIdentifier = @"org.invite.join";
    [b addTarget:self action:@selector(submit) forControlEvents:UIControlEventTouchUpInside];
    self.joinButton = b;
}

- (void)updateJoinEnabled { self.joinButton.enabled = !self.submitting && self.codeField.text.length > 0; }

- (void)codeChanged {
    [self updateJoinEnabled];
    if (self.errorText) { [self setInviteError:nil]; }
}

/// 改段下红字：就地换字 + 重算高度，不 reload 行（reload 会把输入框从 cell 摘下，正在输入时键盘被收起）。
- (void)setInviteError:(nullable NSString *)text {
    self.errorText = text;
    UILabel *label = self.inviteFooterLabel;
    if (!label) { [self.tableView reloadData]; return; }
    label.attributedText = [self inviteFooterText];
    [self.tableView beginUpdates];
    [self.tableView endUpdates];
}

- (NSAttributedString *)inviteFooterText {
    NSMutableAttributedString *text = [NSMutableAttributedString new];
    if (self.errorText.length > 0) {
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:[self.errorText stringByAppendingString:@"\n"]
            attributes:@{ NSForegroundColorAttributeName: UIColor.systemRedColor }]];
    }
    // 审计告知小字：2026-11-22 起暂停（服务端不动），恢复时取消注释：
    // [text appendAttributedString:[[NSAttributedString alloc] initWithString:IMLocalized(@"org.audit_notice")
    //     attributes:@{ NSForegroundColorAttributeName: IMTheme.textSecondary }]];
    [text addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:13] range:NSMakeRange(0, text.length)];
    return text;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField { [self submit]; return NO; }

- (void)submit {
    NSString *code = self.codeField.text ?: @"";
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (code.length == 0 || token.length == 0 || self.submitting) { return; }
    self.submitting = YES;
    [self updateJoinEnabled];
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService redeemInviteCodeWithToken:token code:code completion:^(NSDictionary *data, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        self.submitting = NO;
        [self updateJoinEnabled];
        if (error) {
            IMLogWarnWithTag(IMLogTagHTTP, @"invite_redeem_failed code=%ld", (long)error.code);
            [self setInviteError:error.localizedDescription ?: IMLocalized(@"common.action_failed")];
            return;
        }
        NSArray<IMTenantUnit *> *before = IMTenantStore.shared.bindings;
        [IMTenantStore.shared applyMe:data ?: @{}];
        self.codeField.text = @"";
        [self updateJoinEnabled];
        [self im_showToast:IMLocalizedFormat(@"org.invite.joined", IMMyTenantJoinedName(before, IMTenantStore.shared.bindings))];
        // 不再 reloadData：applyMe 发的变更通知已经触发 onTenantChanged 重绘
    }];
}

/// 绑码成功提示里的名字：新出现的那家子公司；找不到（如重复绑定被当成功）就用集团名。
static NSString *IMMyTenantJoinedName(NSArray<IMTenantUnit *> *before, NSArray<IMTenantUnit *> *after) {
    NSMutableSet *old = [NSMutableSet set];
    for (IMTenantUnit *u in before) { [old addObject:u.unitID]; }
    for (IMTenantUnit *u in after) { if (![old containsObject:u.unitID]) { return u.name; } }
    return IMTenantStore.shared.tenantName;
}

#pragma mark - 表格

- (NSArray<NSNumber *> *)sections {
    IMTenantStore *st = IMTenantStore.shared;
    NSMutableArray *s = [NSMutableArray array];
    if (st.loaded && IMMyTenantShowsInvite(st.hasTenant, st.isCustomer, IMServerConfigStore.shared.inviteEnabled)) {
        [s addObject:@(IMMyTenantSectionInvite)];
    }
    if (st.hasTenant && st.isCustomer && st.bindings.count > 0) { [s addObject:@(IMMyTenantSectionTenant)]; } // 员工没有这一段
    return s;
}

- (IMMyTenantSection)kindAt:(NSInteger)section { return (IMMyTenantSection)[[self sections][section] integerValue]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    self.renderedSections = [self sections];
    return (NSInteger)self.renderedSections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self kindAt:section] == IMMyTenantSectionInvite) { return 1; }
    return (NSInteger)IMTenantStore.shared.bindings.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self kindAt:section] == IMMyTenantSectionInvite ? IMLocalized(@"org.invite.section")
                                                             : IMLocalizedFormat(@"org.invite.bound", IMTenantStore.shared.tenantName);
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    BOOL invite = [self kindAt:section] == IMMyTenantSectionInvite;
    UILabel *label = [UILabel new];
    if (invite) {
        label.attributedText = [self inviteFooterText];
        self.inviteFooterLabel = label;
    } else {
        label.text = IMLocalized(@"org.leave_hint");
        label.font = [UIFont systemFontOfSize:13];
        label.textColor = IMTheme.textSecondary;
    }
    label.numberOfLines = 0;
    label.accessibilityIdentifier = invite ? @"org.invite.footer" : @"org.tenant.footer";
    label.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *wrap = [UIView new];
    [wrap addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:8],
        [label.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor constant:-8],
        [label.leadingAnchor constraintEqualToAnchor:wrap.layoutMarginsGuide.leadingAnchor constant:kIMMyTenantFooterInset - 16],
        [label.trailingAnchor constraintEqualToAnchor:wrap.layoutMarginsGuide.trailingAnchor],
    ]];
    return wrap;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kIMMyTenantCell forIndexPath:indexPath];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    for (UIView *v in cell.contentView.subviews) { if (v == self.codeField || v == self.joinButton) { [v removeFromSuperview]; } }
    cell.contentConfiguration = nil;
    if ([self kindAt:indexPath.section] == IMMyTenantSectionInvite) {
        [self layoutCodeRowInCell:cell];
        return cell;
    }
    UIListContentConfiguration *cfg = UIListContentConfiguration.valueCellConfiguration;
    cfg.text = IMTenantStore.shared.bindings[indexPath.row].name;
    cell.contentConfiguration = cfg;
    return cell;
}

- (void)layoutCodeRowInCell:(UITableViewCell *)cell {
    UITextField *f = self.codeField;
    UIButton *b = self.joinButton;
    f.translatesAutoresizingMaskIntoConstraints = NO;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [cell.contentView addSubview:f];
    [cell.contentView addSubview:b];
    UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [f.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [f.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
        [f.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
        [f.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [b.leadingAnchor constraintEqualToAnchor:f.trailingAnchor constant:12],
        [b.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [b.centerYAnchor constraintEqualToAnchor:f.centerYAnchor],
    ]];
}

@end

#pragma mark - 组织架构空态（无集团）

@interface IMOrgJoinViewController ()
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@end

@implementation IMOrgJoinViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    if ((self = [super initWithNibName:nil bundle:nil])) { _host = [host copy]; _userID = [userID copy]; }
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self leaveIfJoined]; // 从「填写邀请码」绑码成功后返回：已有集团，空态不该再留着
}

/// 已加入集团：开了手机端入口就换成组织架构，否则退回通讯录（入口本身也会随之消失）。只在本页在栈顶时动导航。
- (void)leaveIfJoined {
    if (!IMTenantStore.shared.loaded || !IMTenantStore.shared.hasTenant) { return; }
    UINavigationController *nav = self.navigationController;
    if (nav.topViewController != self) { return; }
    if (IMServerConfigStore.shared.directoryEntryMobile) {
        NSMutableArray *stack = [nav.viewControllers mutableCopy];
        stack[stack.count - 1] = [[IMDirectoryViewController alloc] initRootWithHost:self.host userID:self.userID];
        [nav setViewControllers:stack animated:NO];
    } else {
        [nav popViewControllerAnimated:YES];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"contacts.entry.org");
    self.view.backgroundColor = IMTheme.groupedBackground;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(leaveIfJoined)
                                               name:IMTenantStoreDidChangeNotification object:nil];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"building.2"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:44 weight:UIImageSymbolWeightRegular]]];
    icon.tintColor = IMTheme.textTertiary;
    UILabel *title = [UILabel new];
    title.text = IMLocalized(@"org.join.empty_title");
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    title.textColor = IMTheme.textPrimary;
    UILabel *desc = [UILabel new];
    desc.text = IMLocalized(@"org.join.empty_desc");
    desc.font = [UIFont systemFontOfSize:14];
    desc.textColor = IMTheme.textSecondary;
    desc.numberOfLines = 0;
    desc.textAlignment = NSTextAlignmentCenter;
    UIButtonConfiguration *bc = UIButtonConfiguration.filledButtonConfiguration;
    bc.title = IMLocalized(@"org.invite.entry");
    bc.baseBackgroundColor = IMTheme.accent;
    bc.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    bc.contentInsets = NSDirectionalEdgeInsetsMake(10, 28, 10, 28);
    UIButton *button = [UIButton buttonWithConfiguration:bc primaryAction:nil];
    button.accessibilityIdentifier = @"org.join.invite";
    [button addTarget:self action:@selector(openInvite) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, title, desc, button]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 10;
    [stack setCustomSpacing:20 afterView:desc];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:g.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:g.centerYAnchor constant:-40],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:g.leadingAnchor constant:32],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:g.trailingAnchor constant:-32],
    ]];
}

- (void)openInvite {
    [self.navigationController pushViewController:[[IMMyTenantViewController alloc] initWithHost:self.host userID:self.userID]
                                         animated:YES];
}

@end
