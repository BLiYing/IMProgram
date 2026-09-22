//  IMQRCardViewController.m

#import "IMQRCardViewController.h"
#import "IMLocalization.h"

#import "IMAnimator.h"
#import "IMHTTPService.h"
#import "IMQRCardView.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"
#import "IMAccountIdentity.h"

typedef NS_ENUM(NSInteger, IMQRCardMode) {
    IMQRCardModeUser = 0,  ///< 我的名片码
    IMQRCardModeGroup,     ///< 群二维码
};

@interface IMQRCardViewController ()
@property (nonatomic, assign) IMQRCardMode mode;
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
/// 公开句柄：副标题显示 @xxx。**绝不显示 userID**——那是 10 位随机数字内部 ID。
@property (nonatomic, copy, nullable) NSString *username;
@property (nonatomic, copy, nullable) NSString *convID;
@property (nonatomic, copy, nullable) NSString *displayName;
@property (nonatomic, copy, nullable) NSString *avatarURL;
@property (nonatomic, assign) NSInteger memberCount;
@property (nonatomic, assign) BOOL canReset;
@property (nonatomic, assign) BOOL asLink; ///< 群码页按「群邀请链接」呈现（仅改标题/文案，码一致）

@property (nonatomic, strong) IMQRCardView *cardView;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UIButton *shareButton;
@property (nonatomic, strong) UIButton *linkCopyButton;
@property (nonatomic, strong) UIButton *resetButton;

@property (nonatomic, copy, nullable) NSString *codeString;  ///< 码内容串（服务端下发）
@property (nonatomic, assign) int64_t expiresAt;             ///< 毫秒；0=长期有效
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) CGFloat previousBrightness;    ///< 进页提亮前的屏幕亮度，退出还原
@property (nonatomic, assign) BOOL brightnessBoosted;
@end

@implementation IMQRCardViewController

#pragma mark - 初始化

- (instancetype)initMyCardWithHost:(NSString *)host userID:(NSString *)userID
                          username:(NSString *)username
                          nickname:(NSString *)nickname avatarURL:(NSString *)avatarURL {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _mode = IMQRCardModeUser;
        _host = [host copy];
        _userID = [userID copy];
        _username = [username copy];
        _displayName = [IMDisplayName(nickname, username) copy];
        _avatarURL = [avatarURL copy];
    }
    return self;
}

- (instancetype)initGroupCardWithHost:(NSString *)host userID:(NSString *)userID convID:(NSString *)convID
                            groupName:(NSString *)groupName avatarURL:(NSString *)avatarURL
                          memberCount:(NSInteger)memberCount canReset:(BOOL)canReset asLink:(BOOL)asLink {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _mode = IMQRCardModeGroup;
        _host = [host copy];
        _userID = [userID copy];
        _convID = [convID copy];
        _displayName = [(groupName.length ? groupName : IMLocalized(@"common.group_chat")) copy];
        _avatarURL = [avatarURL copy];
        _memberCount = memberCount;
        _canReset = canReset;
        _asLink = asLink;
    }
    return self;
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = (self.mode == IMQRCardModeGroup) ? (self.asLink ? IMLocalized(@"qr.card.group_title_link") : IMLocalized(@"qr.card.group_title_code")) : IMLocalized(@"qr.scan.my_code");
    self.view.backgroundColor = IMTheme.groupedBackground;
    [self setupUI];
    [self reloadCode];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self boostBrightness]; // 展示页要给别人扫：临时拉满亮度，退出还原
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self restoreBrightness];
}

- (void)dealloc {
    [self restoreBrightness]; // 异常路径（未走 viewWillDisappear）兜底，别把用户屏幕留在满亮度
}

- (void)boostBrightness {
    if (self.brightnessBoosted) { return; }
    self.previousBrightness = UIScreen.mainScreen.brightness;
    self.brightnessBoosted = YES;
    UIScreen.mainScreen.brightness = 1.0;
}

- (void)restoreBrightness {
    if (!self.brightnessBoosted) { return; }
    self.brightnessBoosted = NO;
    UIScreen.mainScreen.brightness = self.previousBrightness;
}

#pragma mark - UI

- (void)setupUI {
    self.cardView = [IMQRCardView new];
    self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.cardView];

    self.saveButton = [self makeButtonWithTitle:IMLocalized(@"qr.card.save_to_album") primary:NO action:@selector(saveToAlbum)];
    self.shareButton = [self makeButtonWithTitle:IMLocalized(@"common.share") primary:YES action:@selector(shareCode)];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ self.saveButton, self.shareButton ]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = IMTheme.space3;
    [self.view addSubview:row];

    // 复制链接：码内容串本身就是邀请/名片链接（/q/g|u/<token>），二级文字按钮，不挤主行两键布局。
    self.linkCopyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.linkCopyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.linkCopyButton setTitle:(self.mode == IMQRCardModeGroup ? IMLocalized(@"qr.card.copy_group_link") : IMLocalized(@"qr.copy_link")) forState:UIControlStateNormal];
    [self.linkCopyButton setTitleColor:IMTheme.accent forState:UIControlStateNormal];
    self.linkCopyButton.titleLabel.font = [UIFont systemFontOfSize:15];
    [self.linkCopyButton addTarget:self action:@selector(shareLinkCopy) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.linkCopyButton];

    self.resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.resetButton setTitle:(self.mode == IMQRCardModeGroup ? IMLocalized(@"qr.card.reset_group") : IMLocalized(@"qr.reset"))
                      forState:UIControlStateNormal];
    [self.resetButton setTitleColor:IMTheme.textSecondary forState:UIControlStateNormal];
    self.resetButton.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.resetButton addTarget:self action:@selector(confirmReset) forControlEvents:UIControlEventTouchUpInside];
    // 群码重置限群主/管理员：无权限时整个入口不渲染（服务端仍二次校验，隐藏不算鉴权）。
    self.resetButton.hidden = (self.mode == IMQRCardModeGroup && !self.canReset);
    [self.view addSubview:self.resetButton];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    CGFloat pad = IMTheme.space4;
    [NSLayoutConstraint activateConstraints:@[
        [self.cardView.topAnchor constraintEqualToAnchor:safe.topAnchor constant:IMTheme.space3],
        [self.cardView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:pad],
        [self.cardView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-pad],

        [row.topAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:pad],
        [row.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor],
        [row.heightAnchor constraintEqualToConstant:44],

        [self.linkCopyButton.topAnchor constraintEqualToAnchor:row.bottomAnchor constant:IMTheme.space3],
        [self.linkCopyButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [self.resetButton.topAnchor constraintEqualToAnchor:self.linkCopyButton.bottomAnchor constant:IMTheme.space2],
        [self.resetButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    ]];
    [self renderCard];
}

- (UIButton *)makeButtonWithTitle:(NSString *)title primary:(BOOL)primary action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    b.backgroundColor = primary ? IMTheme.accent : IMTheme.cardBackground;
    [b setTitleColor:(primary ? UIColor.whiteColor : IMTheme.accent) forState:UIControlStateNormal];
    b.layer.cornerRadius = 12;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

/// 把当前状态灌进卡片（取码前后都会调，故 codeString 为空时卡片自己显占位）。
- (void)renderCard {
    NSString *subtitle;
    NSString *hint;
    if (self.mode == IMQRCardModeGroup) {
        subtitle = IMLocalizedFormat(@"qr.branch.group_meta", (long)self.memberCount);
        hint = self.expiresAt > 0
            ? IMLocalizedFormat(@"qr.card.group_hint_expiry", [self dateStringFromMillis:self.expiresAt])
            : IMLocalized(@"qr.card.group_subtitle_code");
    } else {
        // 副标题显示公开句柄，不是 userID（10 位随机数字内部 ID）——这张卡是给别人看的，
        // 显示一串随机数字对方认不出是谁（docs/UI.md「用户标识」）。没有句柄就留空。
        subtitle = self.username.length > 0 ? [@"@" stringByAppendingString:self.username] : @"";
        hint = IMLocalized(@"qr.card.my_hint");
    }
    NSString *seed = (self.mode == IMQRCardModeGroup) ? (self.convID ?: @"") : self.userID;
    [self.cardView configureWithAvatarURL:self.avatarURL seed:seed name:self.displayName ?: @""
                                 subtitle:subtitle qrString:self.codeString hint:hint];
    BOOL hasCode = self.codeString.length > 0;
    self.saveButton.enabled = hasCode;
    self.shareButton.enabled = hasCode;
    self.linkCopyButton.enabled = hasCode;
}

- (NSString *)dateStringFromMillis:(int64_t)ms {
    // 走统一日期词汇（time.month_day / time.full_date，随 App 语言）；往年的码会带年份，比原先「M月d日」更不含糊。
    return [IMTheme dateLabelForDate:[NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)ms / 1000.0]];
}

#pragma mark - 取码 / 重置

- (void)reloadCode {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:IMLocalized(@"common.login_expired")]; return; }
    if (self.loading) { return; }
    self.loading = YES;
    __weak typeof(self) ws = self;
    void (^done)(NSDictionary *, NSError *) = ^(NSDictionary *card, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        self.loading = NO;
        if (error) { [self im_showToast:error.localizedDescription ?: IMLocalized(@"qr.card.fetch_failed")]; return; }
        [self applyCard:card];
    };
    if (self.mode == IMQRCardModeGroup) {
        [IMHTTPService.sharedService groupQRWithToken:token convID:self.convID ?: @"" completion:done];
    } else {
        [IMHTTPService.sharedService qrMyCardWithToken:token completion:done];
    }
}

- (void)applyCard:(NSDictionary *)card {
    NSString *url = [card[@"url"] isKindOfClass:NSString.class] ? card[@"url"] : nil;
    self.codeString = url.length ? url : ([card[@"token"] isKindOfClass:NSString.class] ? card[@"token"] : nil);
    id expires = card[@"expires_at"];
    self.expiresAt = [expires respondsToSelector:@selector(longLongValue)] ? [expires longLongValue] : 0;
    [self renderCard];
}

/// 重置是不可撤销且影响外部世界的操作（旧码可能已发出去/贴在群公告里），故强制二次确认。
- (void)confirmReset {
    NSString *message = (self.mode == IMQRCardModeGroup)
        ? IMLocalized(@"qr.card.reset_group_message")
        : IMLocalized(@"qr.card.reset_user_message");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:IMLocalized(@"qr.card.reset_confirm_title")
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"qr.confirm_reset") style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *_Nonnull a) { [ws performReset]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performReset {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:IMLocalized(@"common.login_expired")]; return; }
    __weak typeof(self) ws = self;
    void (^done)(NSDictionary *, NSError *) = ^(NSDictionary *card, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) { [self im_showToast:error.localizedDescription ?: IMLocalized(@"qr.card.reset_failed")]; return; }
        [self applyCard:card];
        [IMAnimator lightImpact];
        [self im_showToast:IMLocalized(@"qr.card.reset_done")];
    };
    if (self.mode == IMQRCardModeGroup) {
        [IMHTTPService.sharedService groupQRResetWithToken:token convID:self.convID ?: @"" completion:done];
    } else {
        [IMHTTPService.sharedService qrResetMyCardWithToken:token completion:done];
    }
}

#pragma mark - 保存 / 分享

- (void)saveToAlbum {
    UIImage *image = self.cardView.qrImage;
    if (!image) { [self im_showToast:IMLocalized(@"qr.card.not_ready")]; return; }
    UIImageWriteToSavedPhotosAlbum(image, self, @selector(image:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    // 相册权限被拒也会走这里（error 非空），必须给出可行动的提示而不是静默。
    [self im_showToast:error ? (error.localizedDescription ?: IMLocalized(@"qr.card.save_failed")) : IMLocalized(@"qr.card.saved")];
}

- (void)shareCode {
    UIImage *image = self.cardView.qrImage;
    if (!image || self.codeString.length == 0) { [self im_showToast:IMLocalized(@"qr.card.not_ready")]; return; }
    UIActivityViewController *share =
        [[UIActivityViewController alloc] initWithActivityItems:@[ image, self.codeString ] applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.shareButton;      // iPad 必须给锚点，否则崩
    share.popoverPresentationController.sourceRect = self.shareButton.bounds;
    [self presentViewController:share animated:YES completion:nil];
}

/// 复制链接：把码内容串（即 /q/g|u/<token> 邀请/名片链接）拷进剪贴板。
- (void)shareLinkCopy {
    if (self.codeString.length == 0) { [self im_showToast:IMLocalized(@"qr.card.link_not_ready")]; return; }
    UIPasteboard.generalPasteboard.string = self.codeString;
    [self im_showToast:(self.mode == IMQRCardModeGroup ? IMLocalized(@"qr.card.copied_group_link") : IMLocalized(@"common.copied_link"))];
}

@end
