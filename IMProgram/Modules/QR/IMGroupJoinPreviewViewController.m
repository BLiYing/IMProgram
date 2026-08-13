//  IMGroupJoinPreviewViewController.m

#import "IMGroupJoinPreviewViewController.h"
#import "IMTheme.h"
#import "UILabel+IMAvatar.h"

@interface IMGroupJoinPreviewViewController () <UITextFieldDelegate>
@property (nonatomic, strong) IMQRGroupCard *card;
@property (nonatomic, assign) IMQRGroupAction action;
@property (nonatomic, copy) void (^onSubmit)(NSString *hello);
@property (nonatomic, strong, nullable) UITextField *helloField;
@end

@implementation IMGroupJoinPreviewViewController

+ (void)presentFrom:(UIViewController *)host
               card:(IMQRGroupCard *)card
             action:(IMQRGroupAction)action
           onSubmit:(void (^)(NSString *))onSubmit {
    IMGroupJoinPreviewViewController *vc = [IMGroupJoinPreviewViewController new];
    vc.card = card;
    vc.action = action;
    vc.onSubmit = onSubmit;
    vc.title = @"加入群聊";
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [host presentViewController:nav animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = IMTheme.groupedBackground;
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeTapped)];

    // 群头像（复用 UILabel+IMAvatar：有图显图、无图显首字底色）
    UILabel *avatar = [UILabel new];
    avatar.translatesAutoresizingMaskIntoConstraints = NO;
    avatar.layer.cornerRadius = 36;
    avatar.clipsToBounds = YES;
    [avatar im_setAvatarURL:self.card.avatarURL seed:self.card.groupID displayName:self.card.name];
    [self.view addSubview:avatar];

    UILabel *name = [UILabel new];
    name.text = self.card.name.length ? self.card.name : @"群聊";
    name.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    name.textColor = IMTheme.textPrimary;
    name.textAlignment = NSTextAlignmentCenter;
    name.numberOfLines = 2;
    name.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:name];

    NSMutableString *sub = [NSMutableString stringWithFormat:@"%ld 位成员", (long)self.card.memberCount];
    if (self.card.inviterNickname.length > 0) { [sub appendFormat:@" · %@ 邀请你加入", self.card.inviterNickname]; }
    UILabel *subtitle = [UILabel new];
    subtitle.text = sub;
    subtitle.font = [UIFont systemFontOfSize:13];
    subtitle.textColor = IMTheme.textSecondary;
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.numberOfLines = 0;
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:subtitle];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    NSMutableArray<NSLayoutConstraint *> *cons = [NSMutableArray arrayWithArray:@[
        [avatar.topAnchor constraintEqualToAnchor:g.topAnchor constant:28],
        [avatar.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [avatar.widthAnchor constraintEqualToConstant:72],
        [avatar.heightAnchor constraintEqualToConstant:72],

        [name.topAnchor constraintEqualToAnchor:avatar.bottomAnchor constant:14],
        [name.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [name.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],

        [subtitle.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:6],
        [subtitle.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:name.trailingAnchor],
    ]];

    UIView *anchorTop = subtitle;

    // 群简介（G3 修，未入群可见）：非空才显，排在人数下、附言/按钮之上。
    if (self.card.intro.length > 0) {
        UILabel *introLbl = [UILabel new];
        introLbl.text = self.card.intro;
        introLbl.font = [UIFont systemFontOfSize:14];
        introLbl.textColor = IMTheme.textSecondary;
        introLbl.textAlignment = NSTextAlignmentCenter;
        introLbl.numberOfLines = 0;
        introLbl.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:introLbl];
        [cons addObjectsFromArray:@[
            [introLbl.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:14],
            [introLbl.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
            [introLbl.trailingAnchor constraintEqualToAnchor:name.trailingAnchor],
        ]];
        anchorTop = introLbl;
    }

    // 需审批：附言输入框（可不填）。
    if (self.action == IMQRGroupActionApply) {
        UILabel *hdr = [UILabel new];
        hdr.text = @"附言（选填）";
        hdr.font = [UIFont systemFontOfSize:12];
        hdr.textColor = IMTheme.textSecondary;
        hdr.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:hdr];

        UITextField *field = [UITextField new];
        field.placeholder = @"我是…（可不填）";
        field.font = [UIFont systemFontOfSize:16];
        field.textColor = IMTheme.textPrimary;
        field.backgroundColor = IMTheme.cardBackground;
        field.borderStyle = UITextBorderStyleNone;
        field.layer.cornerRadius = 10;
        field.delegate = self;
        field.returnKeyType = UIReturnKeyDone;
        field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
        field.leftViewMode = UITextFieldViewModeAlways;
        field.rightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
        field.rightViewMode = UITextFieldViewModeAlways;
        field.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:field];
        self.helloField = field;

        UILabel *foot = [UILabel new];
        foot.text = @"该群已开启进群确认，管理员同意后你才会加入。";
        foot.font = [UIFont systemFontOfSize:12];
        foot.textColor = IMTheme.textSecondary;
        foot.numberOfLines = 0;
        foot.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:foot];

        [cons addObjectsFromArray:@[
            [hdr.topAnchor constraintEqualToAnchor:anchorTop.bottomAnchor constant:24],
            [hdr.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:18],

            [field.topAnchor constraintEqualToAnchor:hdr.bottomAnchor constant:6],
            [field.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
            [field.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
            [field.heightAnchor constraintEqualToConstant:46],

            [foot.topAnchor constraintEqualToAnchor:field.bottomAnchor constant:8],
            [foot.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:18],
            [foot.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-18],
        ]];
        anchorTop = foot;
    } else {
        NSString *note = IMQRGroupActionNote(self.card);
        if (note.length > 0) {
            UILabel *noteLbl = [UILabel new];
            noteLbl.text = note;
            noteLbl.font = [UIFont systemFontOfSize:13];
            noteLbl.textColor = IMTheme.textSecondary;
            noteLbl.textAlignment = NSTextAlignmentCenter;
            noteLbl.numberOfLines = 0;
            noteLbl.translatesAutoresizingMaskIntoConstraints = NO;
            [self.view addSubview:noteLbl];
            [cons addObjectsFromArray:@[
                [noteLbl.topAnchor constraintEqualToAnchor:anchorTop.bottomAnchor constant:18],
                [noteLbl.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
                [noteLbl.trailingAnchor constraintEqualToAnchor:name.trailingAnchor],
            ]];
            anchorTop = noteLbl;
        }
    }

    // 主按钮：Disabled（满/黑名单）灰且不可点；其余强调色。
    BOOL disabled = (self.action == IMQRGroupActionDisabled);
    UIButton *primary = [UIButton buttonWithType:UIButtonTypeCustom];
    [primary setTitle:IMQRGroupActionLabel(self.action) forState:UIControlStateNormal];
    primary.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [primary setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    primary.backgroundColor = disabled ? IMTheme.textTertiary : IMTheme.accent;
    primary.layer.cornerRadius = 12;
    primary.enabled = !disabled;
    [primary addTarget:self action:@selector(submitTapped) forControlEvents:UIControlEventTouchUpInside];
    primary.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:primary];
    [cons addObjectsFromArray:@[
        [primary.topAnchor constraintGreaterThanOrEqualToAnchor:anchorTop.bottomAnchor constant:24],
        [primary.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [primary.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [primary.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-20],
        [primary.heightAnchor constraintEqualToConstant:50],
    ]];

    [NSLayoutConstraint activateConstraints:cons];
}

- (void)submitTapped {
    NSString *hello = self.helloField.text ?: @"";
    void (^cb)(NSString *) = self.onSubmit;
    [self dismissViewControllerAnimated:YES completion:^{ if (cb) { cb(hello); } }];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
