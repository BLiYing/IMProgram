//  IMGroupManageViewController.m
//  群管理二级页（仿 Telegram 群编辑）：顶部居中头像「设置新头像」→ 卡片1(群名称/简介) →
//  卡片2(进群确认/全员禁言/自定义壁纸)。当前已接后端：群名称、群头像；其余标「即将上线」占位，
//  待 IMServer 群设置字段落地后接入（见 docs/TASKS 群设置项）。

#import "IMGroupManageViewController.h"
#import "IMGroupInfo.h"
#import "IMHTTPService.h"
#import "IMMediaPicker.h"
#import "IMImageLoader.h"
#import "IMMediaUtil.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"

#pragma mark - 顶部头像编辑视图（相机圈 + 「设置新头像」）

@interface IMGroupAvatarHeader : UIView
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *caption;
@end
@implementation IMGroupAvatarHeader
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _avatar = [UIImageView new];
        _avatar.backgroundColor = [IMTheme.accent colorWithAlphaComponent:0.18];
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.clipsToBounds = YES; _avatar.layer.cornerRadius = 45;
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_avatar];
        UIImageView *cam = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"camera.fill"]];
        cam.tintColor = IMTheme.accent; cam.translatesAutoresizingMaskIntoConstraints = NO;
        [_avatar addSubview:cam];
        _caption = [UILabel new];
        _caption.text = @"设置新头像"; _caption.textColor = IMTheme.accent;
        _caption.font = [UIFont systemFontOfSize:15]; _caption.textAlignment = NSTextAlignmentCenter;
        _caption.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_caption];
        [NSLayoutConstraint activateConstraints:@[
            [_avatar.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_avatar.topAnchor constraintEqualToAnchor:self.topAnchor constant:16],
            [_avatar.widthAnchor constraintEqualToConstant:90], [_avatar.heightAnchor constraintEqualToConstant:90],
            [cam.centerXAnchor constraintEqualToAnchor:_avatar.centerXAnchor],
            [cam.centerYAnchor constraintEqualToAnchor:_avatar.centerYAnchor],
            [_caption.topAnchor constraintEqualToAnchor:_avatar.bottomAnchor constant:8],
            [_caption.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        ]];
    }
    return self;
}
@end

#pragma mark - 群管理页

typedef NS_ENUM(NSInteger, IMManageSection) {
    IMManageSecProfile = 0, ///< 群名称 / 简介
    IMManageSecFeatures,    ///< 进群确认 / 全员禁言 / 自定义壁纸
    IMManageSecCount,
};

@interface IMGroupManageViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy) NSString *convID;
@property (nonatomic, strong) IMGroupInfo *group;
@property (nonatomic, copy, nullable) void (^onChanged)(void);
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) IMGroupAvatarHeader *header;
@end

@implementation IMGroupManageViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID convID:(NSString *)convID
                       group:(IMGroupInfo *)group onChanged:(void (^)(void))onChanged {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy]; _userID = [userID copy]; _convID = [convID copy];
        _group = group; _onChanged = [onChanged copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"群管理";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self; self.tableView.delegate = self;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"c"];
    [self.view addSubview:self.tableView];

    self.header = [[IMGroupAvatarHeader alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 150)];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pickAvatar)];
    [self.header addGestureRecognizer:tap];
    self.tableView.tableHeaderView = self.header;
    [self refreshHeaderAvatar];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated]; // 详情页隐藏了导航栏，这里恢复
}

- (void)refreshHeaderAvatar {
    NSString *url = self.group.avatarURL.length ? IMMediaFullURL(self.group.avatarURL, self.host) : @"";
    self.header.avatar.image = nil;
    if (url.length) {
        __weak typeof(self) ws = self;
        [[IMImageLoader shared] loadImageURL:url completion:^(UIImage *img) {
            if (img) { ws.header.avatar.image = img; }
        }];
    }
}

#pragma mark - 数据源

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return IMManageSecCount; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == IMManageSecProfile ? 2 : 3;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == IMManageSecFeatures ? @"进群确认 / 全员禁言 / 自定义壁纸即将上线（待后端）。" : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"c"];
    cell.textLabel.textColor = IMTheme.textPrimary;
    cell.detailTextLabel.textColor = IMTheme.textSecondary;
    if (indexPath.section == IMManageSecProfile) {
        if (indexPath.row == 0) {
            cell.imageView.image = [UIImage systemImageNamed:@"textformat"];
            cell.textLabel.text = @"群名称";
            cell.detailTextLabel.text = self.group.name;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.imageView.image = [UIImage systemImageNamed:@"text.alignleft"];
            cell.textLabel.text = @"简介";
            cell.detailTextLabel.text = @"即将上线";
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
    } else {
        NSArray *titles = @[ @"进群确认", @"全员禁言", @"自定义壁纸" ];
        NSArray *icons = @[ @"lock.shield", @"mic.slash", @"photo" ];
        cell.imageView.image = [UIImage systemImageNamed:icons[indexPath.row]];
        cell.textLabel.text = titles[indexPath.row];
        cell.detailTextLabel.text = @"即将上线";
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    cell.imageView.tintColor = IMTheme.accent;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == IMManageSecProfile && indexPath.row == 0) { [self editName]; }
    else { [self im_showToast:@"该功能即将上线（待后端）"]; }
}

#pragma mark - 动作

/// 统一收口：改群资料（名/头像其一变更），成功后回填 + 通知上一页。
- (void)commitName:(NSString *)name avatarURL:(NSString *)avatarURL {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:@"未登录"]; return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService updateGroupWithToken:token convID:self.convID name:name avatarURL:avatarURL
                                          completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) { [self im_showToast:error.localizedDescription ?: @"修改失败"]; return; }
        self.group.name = name;
        self.group.avatarURL = avatarURL;
        [self.tableView reloadData];
        [self refreshHeaderAvatar];
        [self im_showToast:@"已更新"];
        if (self.onChanged) { self.onChanged(); }
    }];
}

- (void)editName {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"修改群名" message:@"1~30 字"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    NSString *current = self.group.name ?: @"";
    NSString *avatar = self.group.avatarURL ?: @"";
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = current; }];
    __weak typeof(self) ws = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *name = [alert.textFields.firstObject.text
                          stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (name.length == 0 || [name isEqualToString:current]) { return; }
        [ws commitName:name avatarURL:avatar];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

/// 设置群头像：相册选 1 张图片（仅图片、选完不弹发送表）→ 上传 → 拿 URL 更新群资料。
- (void)pickAvatar {
    __weak typeof(self) ws = self;
    [IMMediaPicker presentImagePickerFromViewController:self limit:1 handlesCompletion:^(NSArray<IMPickedMediaHandle *> *handles) {
        IMPickedMediaHandle *h = handles.firstObject;
        if (!h) { return; }
        [ws uploadAvatarHandle:h];
    }];
}

- (void)uploadAvatarHandle:(IMPickedMediaHandle *)handle {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:@"未登录"]; return; }
    [self im_showToast:@"上传中…"];
    __weak typeof(self) ws = self;
    [handle loadData:^(IMPickedMedia *item) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (!item.data) { [self im_showToast:@"图片处理失败"]; return; }
        [IMHTTPService.sharedService uploadData:item.data fileName:item.fileName mimeType:item.mimeType token:token
                                    completion:^(NSString *url, NSString *ct, NSError *error) {
            __strong typeof(ws) self2 = ws;
            if (!self2) { return; }
            if (error || url.length == 0) { [self2 im_showToast:error.localizedDescription ?: @"上传失败"]; return; }
            [self2 commitName:(self2.group.name ?: @"") avatarURL:url];
        }];
    }];
}

@end
