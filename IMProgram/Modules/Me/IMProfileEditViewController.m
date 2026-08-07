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

@interface IMProfileEditViewController ()
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy, nullable) NSString *token;
@property (nonatomic, strong) UIImageView *avatarView;   // 可点圆形头像（点→选图→裁切→上传）
@property (nonatomic, copy, nullable) NSString *avatarURL; // 当前头像 URL（选图上传后更新，保存时提交）
@property (nonatomic, strong) UITextField *nicknameField;
@property (nonatomic, strong) UITextField *phoneField;
@property (nonatomic, strong) UITextField *tagsField;
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
    self.title = @"编辑资料";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    // 用显式标题而非 UIBarButtonSystemItemSave：本页 push 进液态标题栏容器，栏靠读 item 的 title/image
    // 渲染按钮，系统项两样都没有会渲染不出（不像模态里的系统导航栏能自绘系统项）。
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(saveTapped)];

    self.nicknameField = [self fieldWithPlaceholder:@"昵称"];
    self.phoneField = [self fieldWithPlaceholder:@"手机号"];
    self.phoneField.keyboardType = UIKeyboardTypePhonePad;
    self.tagsField = [self fieldWithPlaceholder:@"标签（空格或逗号分隔）"];
    self.tagsField.autocapitalizationType = UITextAutocapitalizationTypeNone;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self avatarHeader],
        [self labeledRow:@"昵称" field:self.nicknameField],
        [self labeledRow:@"手机号" field:self.phoneField],
        [self labeledRow:@"标签" field:self.tagsField],
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = IMTheme.space4;
    [self.view addSubview:stack];
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:guide.topAnchor constant:IMTheme.space4 * 2],
        [stack.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:IMTheme.space4],
        [stack.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-IMTheme.space4],
    ]];

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
            self.nicknameField.text = profile.nickname;
            self.avatarURL = profile.avatarURL;
            self.phoneField.text = profile.phone;
            self.tagsField.text = [profile.tags componentsJoinedByString:@" "];
            // 载入当前头像预览（IMImageLoader 支持相对 URL 拼 host / data URL 兜底）。
            if (profile.avatarURL.length) {
                [[IMImageLoader shared] loadImageURL:IMMediaFullURL(profile.avatarURL, self.host) completion:^(UIImage *img) {
                    if (img) { self.avatarView.image = img; }
                }];
            }
        }];
    }];
}

- (void)saveTapped {
    if (self.token.length == 0) { [self showMessage:@"尚未登录，请稍候重试"]; return; }
    [self.view endEditing:YES];
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
        [self.navigationController popViewControllerAnimated:YES];
    }];
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
