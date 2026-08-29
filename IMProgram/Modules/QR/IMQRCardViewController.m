//  IMQRCardViewController.m

#import "IMQRCardViewController.h"

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
                          nickname:(NSString *)nickname avatarURL:(NSString *)avatarURL {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _mode = IMQRCardModeUser;
        _host = [host copy];
        _userID = [userID copy];
        _displayName = [IMDisplayName(nickname, nil) copy];
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
        _displayName = [(groupName.length ? groupName : @"群聊") copy];
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
    self.title = (self.mode == IMQRCardModeGroup) ? (self.asLink ? @"群邀请链接" : @"群二维码") : @"我的二维码";
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

    self.saveButton = [self makeButtonWithTitle:@"保存到相册" primary:NO action:@selector(saveToAlbum)];
    self.shareButton = [self makeButtonWithTitle:@"分享" primary:YES action:@selector(shareCode)];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ self.saveButton, self.shareButton ]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = IMTheme.space3;
    [self.view addSubview:row];

    // 复制链接：码内容串本身就是邀请/名片链接（/q/g|u/<token>），二级文字按钮，不挤主行两键布局。
    self.linkCopyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.linkCopyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.linkCopyButton setTitle:(self.mode == IMQRCardModeGroup ? @"复制群邀请链接" : @"复制链接") forState:UIControlStateNormal];
    [self.linkCopyButton setTitleColor:IMTheme.accent forState:UIControlStateNormal];
    self.linkCopyButton.titleLabel.font = [UIFont systemFontOfSize:15];
    [self.linkCopyButton addTarget:self action:@selector(shareLinkCopy) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.linkCopyButton];

    self.resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.resetButton setTitle:(self.mode == IMQRCardModeGroup ? @"重置群二维码" : @"重置二维码")
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
        subtitle = [NSString stringWithFormat:@"%ld 名成员", (long)self.memberCount];
        hint = self.expiresAt > 0
            ? [NSString stringWithFormat:@"扫描二维码，加入群聊\n该二维码 %@ 前有效", [self dateStringFromMillis:self.expiresAt]]
            : @"扫描二维码，加入群聊";
    } else {
        subtitle = [NSString stringWithFormat:@"ID %@", self.userID];
        hint = @"扫描二维码，加我为朋友\n该码长期有效，重置后旧码立即失效";
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
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    f.dateFormat = @"M月d日";
    return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)ms / 1000.0]];
}

#pragma mark - 取码 / 重置

- (void)reloadCode {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:@"登录已失效，请重新登录"]; return; }
    if (self.loading) { return; }
    self.loading = YES;
    __weak typeof(self) ws = self;
    void (^done)(NSDictionary *, NSError *) = ^(NSDictionary *card, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        self.loading = NO;
        if (error) { [self im_showToast:error.localizedDescription ?: @"获取二维码失败"]; return; }
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
        ? @"重置后旧的群二维码立即失效，已拿到旧码但还没进群的人将无法加入。"
        : @"重置后旧二维码立即失效，已经把码发出去的人将无法通过它加你。";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重置二维码？"
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"确认重置" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *_Nonnull a) { [ws performReset]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performReset {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:@"登录已失效，请重新登录"]; return; }
    __weak typeof(self) ws = self;
    void (^done)(NSDictionary *, NSError *) = ^(NSDictionary *card, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) { [self im_showToast:error.localizedDescription ?: @"重置失败"]; return; }
        [self applyCard:card];
        [IMAnimator lightImpact];
        [self im_showToast:@"已重置，旧二维码已失效"];
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
    if (!image) { [self im_showToast:@"二维码还没准备好"]; return; }
    UIImageWriteToSavedPhotosAlbum(image, self, @selector(image:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    // 相册权限被拒也会走这里（error 非空），必须给出可行动的提示而不是静默。
    [self im_showToast:error ? (error.localizedDescription ?: @"保存失败，请检查相册权限") : @"已保存到相册"];
}

- (void)shareCode {
    UIImage *image = self.cardView.qrImage;
    if (!image || self.codeString.length == 0) { [self im_showToast:@"二维码还没准备好"]; return; }
    UIActivityViewController *share =
        [[UIActivityViewController alloc] initWithActivityItems:@[ image, self.codeString ] applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.shareButton;      // iPad 必须给锚点，否则崩
    share.popoverPresentationController.sourceRect = self.shareButton.bounds;
    [self presentViewController:share animated:YES completion:nil];
}

/// 复制链接：把码内容串（即 /q/g|u/<token> 邀请/名片链接）拷进剪贴板。
- (void)shareLinkCopy {
    if (self.codeString.length == 0) { [self im_showToast:@"链接还没准备好"]; return; }
    UIPasteboard.generalPasteboard.string = self.codeString;
    [self im_showToast:(self.mode == IMQRCardModeGroup ? @"已复制群邀请链接" : @"已复制链接")];
}

@end
