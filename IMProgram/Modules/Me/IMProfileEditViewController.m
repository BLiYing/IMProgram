//  IMProfileEditViewController.m

#import "IMProfileEditViewController.h"
#import "IMMainTabBarController.h" // im_refreshNavigationBar / kIMLiquidBarHeight
#import "IMHTTPService.h"
#import "IMUserCard.h"
#import "IMMediaPicker.h"
#import "IMImageLoader.h"
#import "IMMediaUtil.h"
#import "IMAvatarCropViewController.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import "IMLog.h"
#import "IMSessionStore.h"
#import "IMAccountIdentity.h"

@interface IMProfileEditViewController ()
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy, nullable) NSString *token;
@property (nonatomic, strong) UIImageView *avatarView;   // 可点圆形头像（点→选图→裁切→上传）
@property (nonatomic, copy, nullable) NSString *avatarURL; // 当前头像 URL（选图上传后更新，保存时提交）
@property (nonatomic, strong) UITextField *nicknameField;
@property (nonatomic, strong) UITextField *usernameField; ///< 公开句柄（@xxx），与昵称是两回事
@property (nonatomic, copy, nullable) NSString *loadedUsername; ///< 载入时的原值，未改动就不发改名请求
@property (nonatomic, strong) UITextField *phoneField;
@property (nonatomic, strong) UITextField *tagsField;

// 双态（2026-08-30，对齐 Telegram iOS 个人资料页）：
// 默认**只读**——大头像 + 昵称 + 在线态 + 信息卡；点右上角「编辑」才切到可修改的表单。
// 从「我」页点头像/昵称/句柄进来的用户多数只是想看一眼，直接给一屏输入框既突兀又容易误改。
@property (nonatomic, assign) BOOL editingMode;
@property (nonatomic, strong) UIStackView *readonlyStack;  ///< 只读态根容器
@property (nonatomic, strong) UIStackView *editStack;      ///< 编辑态根容器（原有表单）
@property (nonatomic, strong) UIImageView *roAvatar;       ///< 只读态大头像（不可点换）
@property (nonatomic, strong) UILabel *roName;             ///< 只读态昵称（大字）
@property (nonatomic, strong) UILabel *roStatus;           ///< 只读态在线态（本人恒「在线」）
@property (nonatomic, strong) UILabel *roPhoneValue;
@property (nonatomic, strong) UILabel *roUsernameValue;
@property (nonatomic, strong) UIView *roPhoneRow;          ///< 手机号为空时整行隐藏
@end

@implementation IMProfileEditViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.nicknameField = [self fieldWithPlaceholder:@"昵称"];
    // 用户名（公开句柄）与昵称分开：前者是别人搜索到我的凭据、也是登录名，规则严格；后者随便填。
    self.usernameField = [self fieldWithPlaceholder:@"a-z、0-9、下划线，≥5 位"];
    self.usernameField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.usernameField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.usernameField.keyboardType = UIKeyboardTypeASCIICapable;
    self.phoneField = [self fieldWithPlaceholder:@"手机号"];
    self.phoneField.keyboardType = UIKeyboardTypePhonePad;
    self.tagsField = [self fieldWithPlaceholder:@"标签（空格或逗号分隔）"];
    self.tagsField.autocapitalizationType = UITextAutocapitalizationTypeNone;

    self.editStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self avatarHeader],
        [self labeledRow:@"昵称" field:self.nicknameField],
        [self labeledRow:@"用户名" field:self.usernameField],
        [self labeledRow:@"手机号" field:self.phoneField],
        [self labeledRow:@"标签" field:self.tagsField],
    ]];
    self.editStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.editStack.axis = UILayoutConstraintAxisVertical;
    self.editStack.spacing = IMTheme.space4;
    [self.view addSubview:self.editStack];

    self.readonlyStack = [self buildReadonlyStack];
    [self.view addSubview:self.readonlyStack];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    for (UIStackView *stack in @[self.editStack, self.readonlyStack]) {
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:guide.topAnchor constant:IMTheme.space4 * 2],
            [stack.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:IMTheme.space4],
            [stack.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-IMTheme.space4],
        ]];
    }

    [self applyEditingMode:NO];  // 进页默认只读
    [self load];
}

#pragma mark - 构建

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder {
    UITextField *f = [UITextField new];
    f.translatesAutoresizingMaskIntoConstraints = NO;
    f.placeholder = placeholder;
    f.font = [UIFont systemFontOfSize:16];
    f.textColor = IMTheme.textPrimary;
    f.borderStyle = UITextBorderStyleRoundedRect;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    [f.heightAnchor constraintEqualToConstant:40].active = YES;
    return f;
}

// 顶部圆形头像（86pt）+ 相机角标 + 「点击头像更换」→ 选图裁切上传（方案 C，弃用手填 URL）。
- (UIView *)avatarHeader {
    UIView *wrap = [UIView new];

    self.avatarView = [UIImageView new];
    self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    self.avatarView.backgroundColor = [IMTheme.accent colorWithAlphaComponent:0.18];
    self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
    self.avatarView.clipsToBounds = YES;
    self.avatarView.layer.cornerRadius = 43; // 86/2
    self.avatarView.userInteractionEnabled = YES;
    [self.avatarView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pickAvatar)]];
    [wrap addSubview:self.avatarView];

    // 相机角标：给 SF Symbol 显式尺寸（13pt），否则默认尺寸过大在 28pt 圆里被裁，看着像两个图标叠一起。
    UIImageSymbolConfiguration *camCfg = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightMedium];
    UIImageView *cam = [[UIImageView alloc] initWithImage:
        [[UIImage systemImageNamed:@"camera.fill"] imageByApplyingSymbolConfiguration:camCfg]];
    cam.tintColor = UIColor.whiteColor;
    cam.backgroundColor = IMTheme.accent;
    cam.contentMode = UIViewContentModeCenter;
    cam.clipsToBounds = YES;
    cam.layer.cornerRadius = 14; // 28/2
    cam.layer.borderWidth = 2;
    cam.layer.borderColor = UIColor.systemGroupedBackgroundColor.CGColor;
    cam.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:cam];

    UILabel *caption = [UILabel new];
    caption.text = @"点击头像更换";
    caption.textColor = IMTheme.accent;
    caption.font = [UIFont systemFontOfSize:13];
    caption.textAlignment = NSTextAlignmentCenter;
    caption.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:caption];

    [NSLayoutConstraint activateConstraints:@[
        [self.avatarView.centerXAnchor constraintEqualToAnchor:wrap.centerXAnchor],
        [self.avatarView.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:8],
        [self.avatarView.widthAnchor constraintEqualToConstant:86],
        [self.avatarView.heightAnchor constraintEqualToConstant:86],
        [cam.trailingAnchor constraintEqualToAnchor:self.avatarView.trailingAnchor constant:2],
        [cam.bottomAnchor constraintEqualToAnchor:self.avatarView.bottomAnchor constant:2],
        [cam.widthAnchor constraintEqualToConstant:28],
        [cam.heightAnchor constraintEqualToConstant:28],
        [caption.topAnchor constraintEqualToAnchor:self.avatarView.bottomAnchor constant:10],
        [caption.centerXAnchor constraintEqualToAnchor:wrap.centerXAnchor],
        [caption.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor],
    ]];
    return wrap;
}

// 选图 → 圆形裁切 → 头像专用上传 → 更新 avatarURL + 预览。
- (void)pickAvatar {
    __weak typeof(self) ws = self;
    [IMMediaPicker presentImagePickerFromViewController:self limit:1 handlesCompletion:^(NSArray<IMPickedMediaHandle *> *handles) {
        IMPickedMediaHandle *h = handles.firstObject;
        if (!h) { return; }
        [h loadData:^(IMPickedMedia *item) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            UIImage *img = item.data ? [UIImage imageWithData:item.data] : nil;
            if (!img) { [self showMessage:@"图片处理失败"]; return; }
            IMAvatarCropViewController *crop = [[IMAvatarCropViewController alloc] initWithImage:img];
            crop.onComplete = ^(NSData *jpeg) {
                __strong typeof(ws) self2 = ws;
                if (!self2 || !jpeg) { return; } // nil = 取消
                [self2 uploadAvatarJPEG:jpeg];
            };
            [self presentViewController:crop animated:YES completion:nil];
        }];
    }];
}

- (void)uploadAvatarJPEG:(NSData *)jpeg {
    if (self.token.length == 0) { [self showMessage:@"尚未登录，请稍候重试"]; return; }
    UIImage *preview = [UIImage imageWithData:jpeg];
    [self im_showToast:@"上传中…"]; // 与群头像流程一致的进行态反馈
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService uploadAvatarData:jpeg token:self.token completion:^(NSString *url, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error || url.length == 0) { [self showMessage:error.localizedDescription ?: @"头像上传失败"]; return; }
        self.avatarURL = url;
        self.avatarView.image = preview; // 立即预览
        [[IMImageLoader shared] cacheImage:preview forURL:IMMediaFullURL(url, self.host)]; // 种缓存，别处不再重下
        [self im_showToast:@"头像已更新，记得保存"];
    }];
}

#pragma mark - 只读态（对齐 Telegram iOS 个人资料页）

/// 只读态：大圆头像 + 昵称 + 在线态 + 一张信息卡（手机 / 用户名）。
///
/// 刻意**不显示内部 ID、不显示标签**：前者是 10 位随机数字（docs/UI.md「用户标识」），
/// 后者是本项目自有的次要字段，Telegram 那张卡上没有对应物，塞进来只会稀释信息密度。
/// 生日/动态同理不做（本项目无此数据）。
- (UIStackView *)buildReadonlyStack {
    self.roAvatar = [UIImageView new];
    self.roAvatar.translatesAutoresizingMaskIntoConstraints = NO;
    self.roAvatar.backgroundColor = [IMTheme.accent colorWithAlphaComponent:0.18];
    self.roAvatar.contentMode = UIViewContentModeScaleAspectFill;
    self.roAvatar.clipsToBounds = YES;
    self.roAvatar.layer.cornerRadius = 48; // 96/2
    UIView *avatarWrap = [UIView new];
    [avatarWrap addSubview:self.roAvatar];
    [NSLayoutConstraint activateConstraints:@[
        [self.roAvatar.centerXAnchor constraintEqualToAnchor:avatarWrap.centerXAnchor],
        [self.roAvatar.topAnchor constraintEqualToAnchor:avatarWrap.topAnchor],
        [self.roAvatar.bottomAnchor constraintEqualToAnchor:avatarWrap.bottomAnchor],
        [self.roAvatar.widthAnchor constraintEqualToConstant:96],
        [self.roAvatar.heightAnchor constraintEqualToConstant:96],
    ]];

    self.roName = [UILabel new];
    self.roName.font = [UIFont systemFontOfSize:24 weight:UIFontWeightSemibold];
    self.roName.textColor = IMTheme.textPrimary;
    self.roName.textAlignment = NSTextAlignmentCenter;

    self.roStatus = [UILabel new];
    self.roStatus.font = [UIFont systemFontOfSize:15];
    self.roStatus.textColor = IMTheme.textSecondary;
    self.roStatus.textAlignment = NSTextAlignmentCenter;
    self.roStatus.text = @"在线";  // 本人页面：自己永远在线，不必查 presence

    self.roPhoneValue = [self readonlyValueLabel];
    self.roUsernameValue = [self readonlyValueLabel];
    self.roPhoneRow = [self readonlyRow:@"手机" value:self.roPhoneValue];
    UIView *usernameRow = [self readonlyRow:@"用户名" value:self.roUsernameValue];

    UIStackView *card = [[UIStackView alloc] initWithArrangedSubviews:@[self.roPhoneRow, usernameRow]];
    card.axis = UILayoutConstraintAxisVertical;
    card.spacing = 0;
    card.layoutMargins = UIEdgeInsetsMake(4, 16, 4, 16);
    card.layoutMarginsRelativeArrangement = YES;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 12;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[avatarWrap, self.roName, self.roStatus, card]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    [stack setCustomSpacing:14 afterView:avatarWrap];
    [stack setCustomSpacing:24 afterView:self.roStatus];
    return stack;
}

/// 信息卡里的值（蓝色，对齐 Telegram 的可点感；本项目暂不挂点击动作）。
- (UILabel *)readonlyValueLabel {
    UILabel *l = [UILabel new];
    l.font = [UIFont systemFontOfSize:16];
    l.textColor = IMTheme.accent;
    return l;
}

/// 信息卡的一行：上灰小字 label、下蓝字 value。
- (UIView *)readonlyRow:(NSString *)title value:(UILabel *)value {
    UILabel *label = [UILabel new];
    label.text = title;
    label.font = [UIFont systemFontOfSize:13];
    label.textColor = IMTheme.textSecondary;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label, value]];
    row.axis = UILayoutConstraintAxisVertical;
    row.spacing = 2;
    row.layoutMargins = UIEdgeInsetsMake(12, 0, 12, 0);
    row.layoutMarginsRelativeArrangement = YES;
    return row;
}

/// 切换只读/编辑。右上角按钮随之变「编辑」/「保存」，编辑态左上角给「取消」。
- (void)applyEditingMode:(BOOL)editing {
    self.editingMode = editing;
    self.editStack.hidden = !editing;
    self.readonlyStack.hidden = editing;
    self.title = editing ? @"编辑资料" : @"我的资料";
    // 用显式标题而非 UIBarButtonSystemItem*：本页 push 进液态标题栏容器，栏靠读 item 的 title/image
    // 渲染按钮，系统项两样都没有会渲染不出（不像模态里的系统导航栏能自绘系统项）。
    self.navigationItem.rightBarButtonItem = editing
        ? [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(saveTapped)]
        : [[UIBarButtonItem alloc] initWithTitle:@"编辑" style:UIBarButtonItemStylePlain target:self action:@selector(enterEditing)];
    self.navigationItem.leftBarButtonItem = editing
        ? [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(cancelEditing)]
        : nil;
    [self im_refreshNavigationBar]; // 液态标题栏按 navigationItem 渲染，改完必须显式刷新
}

- (void)enterEditing { [self applyEditingMode:YES]; }

/// 取消编辑：丢弃未保存的输入，用最后一次载入/保存的值重填表单，回只读态。
- (void)cancelEditing {
    [self.view endEditing:YES];
    [self fillFieldsFromReadonly];
    [self applyEditingMode:NO];
}

/// 用只读态当前展示的值回填表单（取消编辑时用；只读态的值即最后一次权威数据）。
- (void)fillFieldsFromReadonly {
    self.nicknameField.text = self.roName.text;
    self.usernameField.text = self.loadedUsername;
    self.phoneField.text = self.roPhoneValue.text;
}

/// 把一份权威资料同时铺进只读态与编辑态（载入后、保存成功后都走这里，避免两处各填一遍而漂移）。
- (void)applyProfile:(IMUserCard *)profile {
    self.nicknameField.text = profile.nickname;
    self.usernameField.text = profile.username;
    self.loadedUsername = profile.username;
    self.avatarURL = profile.avatarURL;
    self.phoneField.text = profile.phone;
    self.tagsField.text = [profile.tags componentsJoinedByString:@" "];

    self.roName.text = IMDisplayName(profile.nickname, profile.username);
    self.roUsernameValue.text = profile.username.length > 0 ? [@"@" stringByAppendingString:profile.username] : @"未设置";
    self.roPhoneValue.text = profile.phone;
    self.roPhoneRow.hidden = profile.phone.length == 0;  // 没填手机号就整行不占位（Telegram 同款）

    if (profile.avatarURL.length) {
        // 载入当前头像预览（IMImageLoader 支持相对 URL 拼 host / data URL 兜底）。
        __weak typeof(self) ws = self;
        [[IMImageLoader shared] loadImageURL:IMMediaFullURL(profile.avatarURL, self.host) completion:^(UIImage *img) {
            __strong typeof(ws) self = ws;
            if (!img || !self) { return; }
            self.avatarView.image = img;
            self.roAvatar.image = img;
        }];
    }
}

- (UIStackView *)labeledRow:(NSString *)title field:(UITextField *)field {
    UILabel *label = [UILabel new];
    label.text = title;
    label.font = [UIFont systemFontOfSize:13];
    label.textColor = IMTheme.textSecondary;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label, field]];
    row.axis = UILayoutConstraintAxisVertical;
    row.spacing = IMTheme.space1;
    return row;
}

#pragma mark - 数据

- (void)load {
    IMHTTPService.sharedService.host = self.host;
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (token.length == 0) {
            IMLog(@"资料自动加载登录失败（静默保留当前内容）：%@", error.localizedDescription ?: @"未知错误");
            return;
        }
        self.token = token;
        [IMHTTPService.sharedService myProfileWithToken:token completion:^(IMUserCard *profile, NSError *err) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || !profile) {
                if (err) { IMLog(@"资料自动加载失败（保留当前内容）：%@", err.localizedDescription ?: @"未知错误"); }
                return;
            }
            [self applyProfile:profile];
        }];
    }];
}

- (void)saveTapped {
    if (self.token.length == 0) { [self showMessage:@"尚未登录，请稍候重试"]; return; }
    [self.view endEditing:YES];
    // 昵称必填：它是全端显示名回退链的终点，清空会让各处露出 10 位数字内部 ID。后端也会拒，这里前置提示。
    if ([self trimmed:self.nicknameField.text].length == 0) {
        [self showMessage:@"昵称不能为空"];
        return;
    }
    NSArray<NSString *> *tags = [self tagsFromString:self.tagsField.text];
    self.navigationItem.rightBarButtonItem.enabled = NO;
    [self im_refreshNavigationBar]; // 标题栏按 navigationItem 渲染，改完 enabled 必须显式刷新
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService updateProfileWithToken:self.token
                                               nickname:[self trimmed:self.nicknameField.text]
                                              avatarURL:(self.avatarURL ?: @"")
                                                  phone:[self trimmed:self.phoneField.text]
                                                   tags:tags
                                             completion:^(IMUserCard *profile, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        self.navigationItem.rightBarButtonItem.enabled = YES;
        [self im_refreshNavigationBar]; // 否则栏上仍是置灰态，「保存」再也点不动
        if (error) {
            [self showMessage:[NSString stringWithFormat:@"保存失败：%@", error.localizedDescription]];
            return;
        }
        [self saveUsernameIfChangedThenExitEditing];
    }];
}

/// 改名是**独立接口**（POST /users/me/username），只在用户真改了才发——
/// 每次保存都发会把「用户名已被占用」的错误抛给一个压根没动用户名的用户。
/// 资料已保存成功，故改名失败只提示、不回滚、不挡住返回路径（用户可留在页内重试）。
///
/// 保存完**回只读态而不是退页**（2026-08-30 双态改造）：用户刚改完就被弹回上一页，
/// 看不到改后的样子；留在页内看到新昵称/新句柄才是完整的反馈闭环（对齐 Telegram）。
- (void)saveUsernameIfChangedThenExitEditing {
    NSString *newName = [self trimmed:self.usernameField.text];
    if (newName.length == 0 || [newName isEqualToString:self.loadedUsername ?: @""]) {
        [self exitEditingAfterSave];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService updateUsername:newName token:self.token completion:^(NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (error) {
            [self showMessage:[NSString stringWithFormat:@"用户名未能修改：%@", error.localizedDescription]];
            return;
        }
        self.loadedUsername = newName;
        // 改名不吊销会话，但**下次冷启动要用它重登**——不写回本地会话，重启后会拿旧名登录而失败。
        IMHTTPService.sharedService.username = newName;
        [IMSessionStore saveHost:(IMSessionStore.host ?: @"") userID:(IMSessionStore.userID ?: @"")
                        username:newName];
        [self exitEditingAfterSave];
    }];
}

/// 保存成功的收尾：回只读态 + 重新拉一次权威资料铺进去。
/// 重拉而非就地拼：改名走的是独立接口，updateProfile 回的 profile 里 username 还是旧值，
/// 两处各拼一份迟早漂移——多一次 GET /users/me 换取"只读态显示的一定是服务端认的值"。
- (void)exitEditingAfterSave {
    [self applyEditingMode:NO];
    [self load];
    [self im_showToast:@"已保存"];
}

/// 标签串按空格/逗号切分，去空白去空项。
- (NSArray<NSString *> *)tagsFromString:(NSString *)s {
    NSCharacterSet *sep = [NSCharacterSet characterSetWithCharactersInString:@" ,，\n\t"];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *raw in [s componentsSeparatedByCharactersInSet:sep]) {
        NSString *t = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (t.length > 0) { [out addObject:t]; }
    }
    return out;
}

- (NSString *)trimmed:(NSString *)s {
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

- (void)showMessage:(NSString *)message {
    IMLog(@"%@", message);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
