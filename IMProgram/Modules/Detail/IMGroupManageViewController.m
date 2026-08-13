//  IMGroupManageViewController.m
//  群管理二级页（仿 Telegram 群编辑）：顶部居中头像 → 卡片1(群名称/简介/群公告，G1) →
//  卡片2(全员禁言自助开关，G1)。进群确认/成员权限/黑名单等属 G2，届时再加卡片。
//  自定义壁纸判为"会话外观"，移出本页（走详情页「更多」，客户端本地，方案决策 6）。

#import "IMGroupManageViewController.h"
#import "IMGroupBanListViewController.h"
#import "IMJoinRequestsViewController.h"
#import "IMGroupInfo.h"
#import "IMHTTPService.h"
#import "IMMediaPicker.h"
#import "IMImageLoader.h"
#import "IMMediaUtil.h"
#import "IMAvatarCropViewController.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"

#pragma mark - 顶部头像编辑视图（相机圈 + 「设置新头像」）

@interface IMGroupAvatarHeader : UIView
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UIImageView *cam;   ///< 中间相机提示：已有头像时隐藏
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
        UIImageSymbolConfiguration *camCfg = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightRegular];
        _cam = [[UIImageView alloc] initWithImage:[[UIImage systemImageNamed:@"camera.fill"] imageByApplyingSymbolConfiguration:camCfg]];
        UIImageView *cam = _cam;
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
    IMManageSecProfile = 0, ///< 群名称 / 简介 / 群公告（G1）
    IMManageSecJoinSpeak,   ///< 进群确认（G2）/ 全员禁言（G1）
    IMManageSecPerms,       ///< 谁可邀请 / 改资料 / 置顶 / 新成员可见历史（G2）
    IMManageSecGovernance,  ///< 黑名单（G2）
    IMManageSecCount,
};

// 资料卡三行。
typedef NS_ENUM(NSInteger, IMManageProfileRow) {
    IMManageRowName = 0,
    IMManageRowIntro,
    IMManageRowAnnouncement,
    IMManageProfileRowCount,
};

// 加入与发言卡两行。
typedef NS_ENUM(NSInteger, IMManageJoinRow) {
    IMManageRowJoinApproval = 0, ///< 进群确认
    IMManageRowMuteAll,          ///< 全员禁言
    IMManageJoinRowCount,
};

// 成员权限卡四行（三个"仅管理员"开关 + 历史可见）。
typedef NS_ENUM(NSInteger, IMManagePermRow) {
    IMManageRowPermInvite = 0,   ///< 谁可邀请（开=仅管理员）
    IMManageRowPermEditInfo,     ///< 谁可改资料（开=仅管理员）
    IMManageRowPermPin,          ///< 谁可置顶（开=仅管理员）
    IMManageRowHistoryVisible,   ///< 新成员可见历史（开=仅入群后）
    IMManagePermRowCount,
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
}

- (void)refreshHeaderAvatar {
    NSString *url = self.group.avatarURL.length ? IMMediaFullURL(self.group.avatarURL, self.host) : @"";
    BOOL hasAvatar = url.length > 0;
    self.header.cam.hidden = hasAvatar;                              // 已有头像时不再盖住图
    self.header.caption.text = hasAvatar ? @"更换头像" : @"设置新头像";
    self.header.avatar.image = nil;
    if (hasAvatar) {
        __weak typeof(self) ws = self;
        [[IMImageLoader shared] loadImageURL:url completion:^(UIImage *img) {
            if (img) { ws.header.avatar.image = img; }
        }];
    }
}

#pragma mark - 数据源

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return IMManageSecCount; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case IMManageSecProfile:    return IMManageProfileRowCount;
        case IMManageSecJoinSpeak:  return IMManageJoinRowCount;
        case IMManageSecPerms:      return IMManagePermRowCount;
        default:                    return 2; // 治理：待审入群申请(G3) + 黑名单(G2)
    }
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case IMManageSecJoinSpeak: return @"加入与发言";
        case IMManageSecPerms:     return @"成员权限";
        case IMManageSecGovernance: return @"治理";
        default: return nil;
    }
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case IMManageSecProfile:   return @"简介与公告展示给全体成员；公告发布后会通知所有人。";
        case IMManageSecJoinSpeak: return @"进群确认：凭二维码加入需管理员审批。全员禁言：仅群主 / 管理员可发言。";
        case IMManageSecPerms:     return @"「新成员可见历史」开启后，新成员看不到加入前的聊天记录。";
        default: return nil;
    }
}

/// 全员禁言当前是否生效（mute_until 超过此刻；-1/极大值=永久）。
- (BOOL)muteActive {
    int64_t now = (int64_t)([NSDate date].timeIntervalSince1970 * 1000);
    return self.group.muteUntil > now;
}

/// 组装一个带右侧开关的行。
- (UITableViewCell *)switchCell:(NSString *)title icon:(NSString *)icon on:(BOOL)on action:(SEL)action {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.textLabel.textColor = IMTheme.textPrimary;
    cell.imageView.image = [UIImage systemImageNamed:icon];
    cell.imageView.tintColor = IMTheme.accent;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UISwitch *sw = [UISwitch new];
    sw.onTintColor = IMTheme.accent;
    sw.on = on;
    [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == IMManageSecProfile) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"c"];
        cell.textLabel.textColor = IMTheme.textPrimary;
        cell.detailTextLabel.textColor = IMTheme.textSecondary;
        cell.imageView.tintColor = IMTheme.accent;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        switch (indexPath.row) {
            case IMManageRowName:
                cell.imageView.image = [UIImage systemImageNamed:@"textformat"];
                cell.textLabel.text = @"群名称";
                cell.detailTextLabel.text = self.group.name;
                break;
            case IMManageRowIntro:
                cell.imageView.image = [UIImage systemImageNamed:@"text.alignleft"];
                cell.textLabel.text = @"简介";
                cell.detailTextLabel.text = self.group.intro.length ? self.group.intro : @"未填写";
                break;
            default:
                cell.imageView.image = [UIImage systemImageNamed:@"megaphone"];
                cell.textLabel.text = @"群公告";
                cell.detailTextLabel.text = self.group.announcement.length ? @"已发布" : @"未发布";
                break;
        }
        return cell;
    }
    if (indexPath.section == IMManageSecJoinSpeak) {
        if (indexPath.row == IMManageRowJoinApproval) {
            return [self switchCell:@"进群确认" icon:@"lock.shield" on:self.group.joinApproval action:@selector(joinApprovalChanged:)];
        }
        return [self switchCell:@"全员禁言" icon:@"mic.slash" on:[self muteActive] action:@selector(muteSwitchChanged:)];
    }
    if (indexPath.section == IMManageSecPerms) {
        switch (indexPath.row) {
            case IMManageRowPermInvite:
                return [self switchCell:@"仅管理员可邀请" icon:@"person.badge.plus" on:self.group.permInvite action:@selector(permInviteChanged:)];
            case IMManageRowPermEditInfo:
                return [self switchCell:@"仅管理员可改群资料" icon:@"square.and.pencil" on:self.group.permEditInfo action:@selector(permEditInfoChanged:)];
            case IMManageRowPermPin:
                return [self switchCell:@"仅管理员可置顶消息" icon:@"pin" on:self.group.permPin action:@selector(permPinChanged:)];
            default:
                return [self switchCell:@"新成员仅可见入群后历史" icon:@"clock.arrow.circlepath" on:self.group.historyVisible action:@selector(historyVisibleChanged:)];
        }
    }
    // 治理：待审入群申请（G3，row 0）+ 黑名单（G2，row 1）。
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"g"];
    cell.textLabel.textColor = IMTheme.textPrimary;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (indexPath.row == 0) {
        cell.textLabel.text = @"待审入群申请";
        cell.detailTextLabel.text = self.group.pendingCount > 0 ? [NSString stringWithFormat:@"%ld 待处理", (long)self.group.pendingCount] : @"无";
        cell.detailTextLabel.textColor = self.group.pendingCount > 0 ? IMTheme.accent : IMTheme.textSecondary;
        cell.imageView.image = [UIImage systemImageNamed:@"person.crop.circle.badge.checkmark"];
    } else {
        cell.textLabel.text = @"黑名单";
        cell.imageView.image = [UIImage systemImageNamed:@"nosign"];
    }
    cell.imageView.tintColor = IMTheme.accent;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == IMManageSecProfile) {
        switch (indexPath.row) {
            case IMManageRowName:         [self editName]; break;
            case IMManageRowIntro:        [self editIntro]; break;
            case IMManageRowAnnouncement: [self editAnnouncement]; break;
        }
    } else if (indexPath.section == IMManageSecGovernance) {
        if (indexPath.row == 0) {
            __weak typeof(self) ws = self;
            IMJoinRequestsViewController *vc = [[IMJoinRequestsViewController alloc]
                initWithToken:(IMHTTPService.sharedService.currentToken ?: @"") convID:self.convID
                    onChanged:^{ if (ws.onChanged) { ws.onChanged(); } }];
            [self.navigationController pushViewController:vc animated:YES];
        } else {
            IMGroupBanListViewController *vc = [[IMGroupBanListViewController alloc] initWithConvID:self.convID];
            [self.navigationController pushViewController:vc animated:YES];
        }
    }
}

#pragma mark - 动作

/// 统一收口：改群资料（名/头像/简介整体替换），成功后回填 + 通知上一页。
/// 整体替换语义——三者都回带当前值，只改其一时另两项传现值（避免清空）。
- (void)commitName:(NSString *)name avatarURL:(NSString *)avatarURL intro:(NSString *)intro {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:@"未登录"]; return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService updateGroupWithToken:token convID:self.convID name:name avatarURL:avatarURL intro:intro
                                          completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) { [self im_showToast:error.localizedDescription ?: @"修改失败"]; return; }
        self.group.name = name;
        self.group.avatarURL = avatarURL;
        self.group.intro = intro;
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
        [ws commitName:name avatarURL:avatar intro:(ws.group.intro ?: @"")];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

/// 编辑简介（≤200 字，多行）：用简单 alert 文本框；空串=清空。
- (void)editIntro {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"群简介" message:@"最多 200 字"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    NSString *current = self.group.intro ?: @"";
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = current; tf.placeholder = @"介绍这个群"; }];
    __weak typeof(self) ws = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *intro = [alert.textFields.firstObject.text
                           stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        if ([intro isEqualToString:current]) { return; }
        [ws commitName:(ws.group.name ?: @"") avatarURL:(ws.group.avatarURL ?: @"") intro:intro];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

/// 编辑群公告（≤500 字）：发布走独立接口并落系统消息；清空文本=撤下公告。
- (void)editAnnouncement {
    NSString *current = self.group.announcement ?: @"";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"群公告"
                                                                  message:current.length ? @"编辑后发布，或清空以撤下" : @"发布后通知全体成员"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = current; tf.placeholder = @"输入公告内容"; }];
    __weak typeof(self) ws = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"发布" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *text = [alert.textFields.firstObject.text
                          stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        if ([text isEqualToString:current]) { return; }
        [ws commitAnnouncement:text];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)commitAnnouncement:(NSString *)text {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:@"未登录"]; return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService setGroupAnnouncementWithToken:token convID:self.convID text:text
                                                   completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) { [self im_showToast:error.localizedDescription ?: @"发布失败"]; return; }
        self.group.announcement = text;
        [self.tableView reloadData];
        [self im_showToast:text.length ? @"公告已发布" : @"公告已撤下"];
        if (self.onChanged) { self.onChanged(); }
    }];
}

/// 全员禁言开关：开=永久（until=-1），关=解除（until=0）。限时禁言留待后续（G2 可加时长选择）。
- (void)muteSwitchChanged:(UISwitch *)sw {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:@"未登录"]; sw.on = [self muteActive]; return; }
    BOOL turnOn = sw.on;
    int64_t until = turnOn ? -1 : 0;
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService setGroupMuteWithToken:token convID:self.convID until:until
                                           completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) {
            [self im_showToast:error.localizedDescription ?: @"设置失败"];
            sw.on = [self muteActive]; // 回滚开关到真实状态
            return;
        }
        // 本地 muteUntil 反映新态：永久用一个远未来时间戳（与后端 MutePermanent 语义一致，仅用于本地 muteActive 判定）。
        self.group.muteUntil = turnOn ? (int64_t)1 << 62 : 0;
        [self im_showToast:turnOn ? @"已开启全员禁言" : @"已关闭全员禁言"];
        if (self.onChanged) { self.onChanged(); }
    }];
}

#pragma mark - G2 开关组（进群确认 / 三项权限 / 历史可见）

/// 统一提交开关组：先本地改再发；失败回滚开关到真实值并 toast。
/// changed 块把某个字段应用到 self.group（本地乐观），revert 块把 sw 拨回真实值。
- (void)commitSettingsSwitch:(UISwitch *)sw apply:(void (^)(BOOL on))apply revert:(void (^)(void))revert {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:@"未登录"]; revert(); return; }
    apply(sw.on); // 本地乐观更新，随后整体上报
    __weak typeof(self) ws = self;
    IMGroupInfo *g = self.group;
    [IMHTTPService.sharedService setGroupSettingsWithToken:token convID:self.convID
                                             joinApproval:g.joinApproval permInvite:g.permInvite
                                             permEditInfo:g.permEditInfo permPin:g.permPin
                                           historyVisible:g.historyVisible completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) {
            [self im_showToast:error.localizedDescription ?: @"设置失败"];
            revert();
            return;
        }
        if (self.onChanged) { self.onChanged(); }
    }];
}

- (void)joinApprovalChanged:(UISwitch *)sw {
    [self commitSettingsSwitch:sw apply:^(BOOL on) { self.group.joinApproval = on; }
                        revert:^{ sw.on = self.group.joinApproval; }];
}
- (void)permInviteChanged:(UISwitch *)sw {
    [self commitSettingsSwitch:sw apply:^(BOOL on) { self.group.permInvite = on; }
                        revert:^{ sw.on = self.group.permInvite; }];
}
- (void)permEditInfoChanged:(UISwitch *)sw {
    [self commitSettingsSwitch:sw apply:^(BOOL on) { self.group.permEditInfo = on; }
                        revert:^{ sw.on = self.group.permEditInfo; }];
}
- (void)permPinChanged:(UISwitch *)sw {
    [self commitSettingsSwitch:sw apply:^(BOOL on) { self.group.permPin = on; }
                        revert:^{ sw.on = self.group.permPin; }];
}
- (void)historyVisibleChanged:(UISwitch *)sw {
    [self commitSettingsSwitch:sw apply:^(BOOL on) { self.group.historyVisible = on; }
                        revert:^{ sw.on = self.group.historyVisible; }];
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
    __weak typeof(self) ws = self;
    // 选好图 → 圆形裁切 → 头像专用上传（方案 C）→ 更新群资料。
    [handle loadData:^(IMPickedMedia *item) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        UIImage *img = item.data ? [UIImage imageWithData:item.data] : nil;
        if (!img) { [self im_showToast:@"图片处理失败"]; return; }
        IMAvatarCropViewController *crop = [[IMAvatarCropViewController alloc] initWithImage:img];
        crop.onComplete = ^(NSData *jpeg) {
            __strong typeof(ws) self2 = ws;
            if (!self2 || !jpeg) { return; } // nil = 用户取消
            [self2 im_showToast:@"上传中…"];
            [IMHTTPService.sharedService uploadAvatarData:jpeg token:token completion:^(NSString *url, NSError *error) {
                __strong typeof(ws) self3 = ws;
                if (!self3) { return; }
                if (error || url.length == 0) { [self3 im_showToast:error.localizedDescription ?: @"上传失败"]; return; }
                [self3 commitName:(self3.group.name ?: @"") avatarURL:url intro:(self3.group.intro ?: @"")];
            }];
        };
        [self presentViewController:crop animated:YES completion:nil];
    }];
}

@end
