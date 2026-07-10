//  IMGroupInfoViewController.m

#import "IMGroupInfoViewController.h"
#import "IMGroupMemberPickerViewController.h"
#import "IMHTTPService.h"
#import "IMSocketManager.h"
#import "IMGroupInfo.h"
#import "UILabel+IMAvatar.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import "IMLog.h"

#pragma mark - 成员行 Cell（头像 + 昵称/uid + 角色徽章）

static CGFloat const kIMMemberAvatarSize = 40;

@interface IMGroupMemberCell : UITableViewCell
- (void)configureWithMember:(IMGroupMember *)member isMe:(BOOL)isMe;
@end

@implementation IMGroupMemberCell {
    UILabel *_avatar;
    UILabel *_name;
    UILabel *_sub;
    UILabel *_roleBadge;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleDefault;

        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textColor = UIColor.whiteColor;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _avatar.layer.cornerRadius = kIMMemberAvatarSize / 2;
        _avatar.layer.masksToBounds = YES;
        [self.contentView addSubview:_avatar];

        _name = [UILabel new];
        _name.translatesAutoresizingMaskIntoConstraints = NO;
        _name.font = [UIFont systemFontOfSize:16];
        _name.textColor = IMTheme.textPrimary;
        [self.contentView addSubview:_name];

        _sub = [UILabel new];
        _sub.translatesAutoresizingMaskIntoConstraints = NO;
        _sub.font = [UIFont systemFontOfSize:12];
        _sub.textColor = IMTheme.textSecondary;
        [self.contentView addSubview:_sub];

        _roleBadge = [UILabel new];
        _roleBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _roleBadge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _roleBadge.textAlignment = NSTextAlignmentCenter;
        _roleBadge.layer.cornerRadius = 8;
        _roleBadge.layer.masksToBounds = YES;
        [self.contentView addSubview:_roleBadge];
        [_roleBadge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_roleBadge setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        UILayoutGuide *g = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
            [_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:kIMMemberAvatarSize],
            [_avatar.heightAnchor constraintEqualToConstant:kIMMemberAvatarSize],
            [_name.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:IMTheme.space3],
            [_name.topAnchor constraintEqualToAnchor:_avatar.topAnchor],
            [_name.trailingAnchor constraintLessThanOrEqualToAnchor:_roleBadge.leadingAnchor constant:-8],
            [_sub.leadingAnchor constraintEqualToAnchor:_name.leadingAnchor],
            [_sub.topAnchor constraintEqualToAnchor:_name.bottomAnchor constant:2],
            [_roleBadge.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_roleBadge.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_roleBadge.heightAnchor constraintEqualToConstant:20],
            [_roleBadge.widthAnchor constraintGreaterThanOrEqualToConstant:44],
        ]];
    }
    return self;
}

- (void)configureWithMember:(IMGroupMember *)member isMe:(BOOL)isMe {
    [_avatar im_setAvatarURL:member.avatarURL seed:member.userID displayName:member.displayName];
    _name.text = isMe ? [NSString stringWithFormat:@"%@（我）", member.displayName] : member.displayName;
    _sub.text = member.userID;
    switch (member.role) {
        case IMGroupRoleOwner:
            _roleBadge.hidden = NO;
            _roleBadge.text = @"群主";
            _roleBadge.textColor = IMTheme.accent;
            _roleBadge.backgroundColor = [IMTheme.accent colorWithAlphaComponent:0.15];
            break;
        case IMGroupRoleAdmin:
            _roleBadge.hidden = NO;
            _roleBadge.text = @"管理员";
            _roleBadge.textColor = IMTheme.textSecondary;
            _roleBadge.backgroundColor = UIColor.secondarySystemFillColor;
            break;
        default:
            _roleBadge.hidden = YES;
            _roleBadge.text = @"";
            break;
    }
}

@end

#pragma mark - 群资料页

/// 分区：0=群头卡（群名+成员数），1=动作（邀请成员/退出群聊），2=成员列表。
typedef NS_ENUM(NSInteger, IMGroupInfoSection) {
    IMGroupInfoSectionHeader = 0,
    IMGroupInfoSectionActions,
    IMGroupInfoSectionMembers,
    IMGroupInfoSectionCount,
};

@interface IMGroupInfoViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy) NSString *convID;
@property (nonatomic, strong, nullable) IMGroupInfo *group;
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation IMGroupInfoViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID convID:(NSString *)convID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        _convID = [convID copy];
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"群资料";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:IMGroupMemberCell.class forCellReuseIdentifier:@"member"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"plain"];
    [self.view addSubview:self.tableView];

    // 群变更（他人被邀/被移/角色变化/改名）实时刷新；自己被移出 → 退出本页。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onGroupEvent:)
                                               name:IMSocketDidReceiveGroupEventNotification object:nil];
    [self reload];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)onGroupEvent:(NSNotification *)note {
    if (![note.userInfo[kIMConvIDKey] isEqualToString:self.convID]) { return; }
    NSString *event = note.userInfo[kIMGroupEventKey];
    NSString *target = note.userInfo[kIMGroupTargetKey];
    if ([event isEqualToString:@"remove"] && [target isEqualToString:self.userID]) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    [self reload];
}

#pragma mark - 数据

- (void)reload {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService groupInfoWithToken:token convID:self.convID
                                         completion:^(IMGroupInfo *group, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (error || !group) {
            [self im_showToast:error.localizedDescription ?: @"拉取群资料失败"];
            return;
        }
        self.group = group;
        // 改群名：群主/管理员可见（服务端二次校验）。
        BOOL canEdit = group.myRole == IMGroupRoleOwner || group.myRole == IMGroupRoleAdmin;
        self.navigationItem.rightBarButtonItem = canEdit
            ? [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.pencil"]
                                               style:UIBarButtonItemStylePlain target:self action:@selector(renameTapped)]
            : nil;
        [self.tableView reloadData];
    }];
}

/// 统一收口：执行一个群管理动作（完成后刷新，失败吐司透传服务端文案）。
- (void)runGroupAction:(void (^)(NSString *token, void (^done)(NSError *_Nullable)))action {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) {
        [self im_showToast:@"未登录"];
        return;
    }
    __weak typeof(self) weakSelf = self;
    action(token, ^(NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (error) {
            [self im_showToast:error.localizedDescription];
            return;
        }
        [self reload];
    });
}

#pragma mark - 动作

- (void)renameTapped {
    if (!self.group) { return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"修改群名"
        message:@"1~30 字" preferredStyle:UIAlertControllerStyleAlert];
    NSString *current = self.group.name;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = current; }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *name = [alert.textFields.firstObject.text
                          stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || name.length == 0 || [name isEqualToString:current]) { return; }
        NSString *avatar = self.group.avatarURL;
        [self runGroupAction:^(NSString *token, void (^done)(NSError *)) {
            [IMHTTPService.sharedService updateGroupWithToken:token convID:self.convID
                                                         name:name avatarURL:avatar completion:done];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

/// 邀请成员：好友多选（排除已在群的），确认即邀请。
- (void)inviteTapped {
    NSMutableSet<NSString *> *inGroup = [NSMutableSet set];
    for (IMGroupMember *m in self.group.members) { [inGroup addObject:m.userID]; }
    __weak typeof(self) weakSelf = self;
    IMGroupMemberPickerViewController *picker =
        [[IMGroupMemberPickerViewController alloc] initWithHost:self.host userID:self.userID
                                                    excludedIDs:inGroup confirmTitle:@"邀请"
                                                         onDone:^(NSArray<NSString *> *selectedIDs) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            [self.navigationController popToViewController:self animated:YES];
            [self runGroupAction:^(NSString *token, void (^done)(NSError *)) {
                [IMHTTPService.sharedService inviteToGroupWithToken:token convID:self.convID
                                                          memberIDs:selectedIDs completion:done];
            }];
        }];
    [self.navigationController pushViewController:picker animated:YES];
}

/// 退出群聊（群主会被服务端拦：需先转让，文案透传）。
- (void)leaveTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"退出群聊"
        message:@"退出后将不再接收该群消息" preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"退出" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        NSString *token = IMHTTPService.sharedService.currentToken;
        if (token.length == 0) { return; }
        [IMHTTPService.sharedService leaveGroupWithToken:token convID:self.convID completion:^(NSError *error) {
            __strong typeof(weakSelf) self2 = weakSelf;
            if (!self2) { return; }
            if (error) {
                [self2 im_showToast:error.localizedDescription]; // 群主未转让 → "群主需先转让群主再退群"
                return;
            }
            // 退出成功：连退两级（群资料 + 群聊页）回列表。
            NSArray *vcs = self2.navigationController.viewControllers;
            NSInteger idx = (NSInteger)vcs.count - 3; // self 之前还有群聊页
            if (idx >= 0) {
                [self2.navigationController popToViewController:vcs[idx] animated:YES];
            } else {
                [self2.navigationController popViewControllerAnimated:YES];
            }
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

/// 点成员行：按权限矩阵弹管理菜单（owner 管所有人；admin 只管 member；不能管自己）。
- (void)showActionsForMember:(IMGroupMember *)member {
    IMGroupInfo *g = self.group;
    if (!g || [member.userID isEqualToString:self.userID]) { return; }
    BOOL iAmOwner = g.myRole == IMGroupRoleOwner;
    BOOL iAmAdmin = g.myRole == IMGroupRoleAdmin;
    BOOL canRemove = iAmOwner || (iAmAdmin && member.role == IMGroupRoleMember);
    if (!iAmOwner && !canRemove) { return; } // member 无任何管理项

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:member.displayName
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    NSString *convID = self.convID;
    NSString *target = member.userID;

    if (iAmOwner && member.role == IMGroupRoleMember) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"设为管理员" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [weakSelf runGroupAction:^(NSString *token, void (^done)(NSError *)) {
                [IMHTTPService.sharedService setGroupRoleWithToken:token convID:convID userID:target role:@"admin" completion:done];
            }];
        }]];
    }
    if (iAmOwner && member.role == IMGroupRoleAdmin) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"撤销管理员" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [weakSelf runGroupAction:^(NSString *token, void (^done)(NSError *)) {
                [IMHTTPService.sharedService setGroupRoleWithToken:token convID:convID userID:target role:@"member" completion:done];
            }];
        }]];
    }
    if (iAmOwner) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"转让群主" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [weakSelf confirmTransferTo:member];
        }]];
    }
    if (canRemove) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"移出群聊" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            [weakSelf runGroupAction:^(NSString *token, void (^done)(NSError *)) {
                [IMHTTPService.sharedService removeGroupMemberWithToken:token convID:convID userID:target completion:done];
            }];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    // iPad 兜底锚点。
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)confirmTransferTo:(IMGroupMember *)member {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"转让群主"
        message:[NSString stringWithFormat:@"确定把群主转让给 %@？你将变为普通成员。", member.displayName]
        preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    NSString *convID = self.convID;
    NSString *target = member.userID;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"转让" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [weakSelf runGroupAction:^(NSString *token, void (^done)(NSError *)) {
            [IMHTTPService.sharedService transferGroupWithToken:token convID:convID userID:target completion:done];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.group ? IMGroupInfoSectionCount : 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case IMGroupInfoSectionHeader:  return 1;
        case IMGroupInfoSectionActions: return 2; // 邀请成员 / 退出群聊
        default:                        return (NSInteger)self.group.members.count;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == IMGroupInfoSectionMembers) {
        return [NSString stringWithFormat:@"成员（%lu）", (unsigned long)self.group.members.count];
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == IMGroupInfoSectionMembers ? 60 : 52;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == IMGroupInfoSectionMembers) {
        IMGroupMemberCell *cell = [tableView dequeueReusableCellWithIdentifier:@"member" forIndexPath:indexPath];
        IMGroupMember *m = self.group.members[indexPath.row];
        [cell configureWithMember:m isMe:[m.userID isEqualToString:self.userID]];
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"plain" forIndexPath:indexPath];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.imageView.image = nil;
    if (indexPath.section == IMGroupInfoSectionHeader) {
        cell.textLabel.text = self.group.name;
        cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        cell.textLabel.textColor = IMTheme.textPrimary;
        cell.detailTextLabel.text = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.imageView.image = [UIImage systemImageNamed:@"person.3.fill"];
        cell.imageView.tintColor = IMTheme.accent;
        return cell;
    }
    // 动作区。
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if (indexPath.row == 0) {
        cell.textLabel.text = @"邀请成员";
        cell.textLabel.font = [UIFont systemFontOfSize:17];
        cell.textLabel.textColor = IMTheme.accent;
        cell.imageView.image = [UIImage systemImageNamed:@"person.badge.plus"];
        cell.imageView.tintColor = IMTheme.accent;
    } else {
        cell.textLabel.text = @"退出群聊";
        cell.textLabel.font = [UIFont systemFontOfSize:17];
        cell.textLabel.textColor = UIColor.systemRedColor;
        cell.imageView.image = [UIImage systemImageNamed:@"rectangle.portrait.and.arrow.right"];
        cell.imageView.tintColor = UIColor.systemRedColor;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == IMGroupInfoSectionActions) {
        if (indexPath.row == 0) { [self inviteTapped]; }
        else { [self leaveTapped]; }
        return;
    }
    if (indexPath.section == IMGroupInfoSectionMembers) {
        [self showActionsForMember:self.group.members[indexPath.row]];
    }
}

@end
