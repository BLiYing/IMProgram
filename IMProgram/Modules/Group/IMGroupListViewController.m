//  IMGroupListViewController.m

#import "IMGroupListViewController.h"
#import "IMGroupMemberPickerViewController.h"
#import "IMChatViewController.h"
#import "IMHTTPService.h"
#import "IMSocketManager.h"
#import "IMGroupInfo.h"
#import "UILabel+IMAvatar.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import "IMLog.h"

#pragma mark - 群行 Cell（首字母/头像圈 + 群名 + 群主副标题）

static CGFloat const kIMGroupAvatarSize = 44;

@interface IMGroupRowCell : UITableViewCell
- (void)configureWithGroup:(IMGroupInfo *)group mine:(BOOL)mine;
@end

@implementation IMGroupRowCell {
    UILabel *_avatar;
    UILabel *_name;
    UILabel *_sub;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textColor = UIColor.whiteColor;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        _avatar.layer.cornerRadius = kIMGroupAvatarSize / 2;
        _avatar.layer.masksToBounds = YES;
        [self.contentView addSubview:_avatar];

        _name = [UILabel new];
        _name.translatesAutoresizingMaskIntoConstraints = NO;
        _name.font = [UIFont systemFontOfSize:17];
        _name.textColor = IMTheme.textPrimary;
        [self.contentView addSubview:_name];

        _sub = [UILabel new];
        _sub.translatesAutoresizingMaskIntoConstraints = NO;
        _sub.font = [UIFont systemFontOfSize:13];
        _sub.textColor = IMTheme.textSecondary;
        [self.contentView addSubview:_sub];

        UILayoutGuide *g = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
            [_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:kIMGroupAvatarSize],
            [_avatar.heightAnchor constraintEqualToConstant:kIMGroupAvatarSize],
            [_name.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:IMTheme.space3],
            [_name.topAnchor constraintEqualToAnchor:_avatar.topAnchor constant:2],
            [_name.trailingAnchor constraintLessThanOrEqualToAnchor:g.trailingAnchor],
            [_sub.leadingAnchor constraintEqualToAnchor:_name.leadingAnchor],
            [_sub.topAnchor constraintEqualToAnchor:_name.bottomAnchor constant:2],
            [_sub.trailingAnchor constraintLessThanOrEqualToAnchor:g.trailingAnchor],
        ]];
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}

- (void)configureWithGroup:(IMGroupInfo *)group mine:(BOOL)mine {
    [_avatar im_setAvatarURL:group.avatarURL seed:group.convID displayName:group.name];
    _name.text = group.name.length > 0 ? group.name : @"群聊";
    _sub.text = mine ? @"我是群主" : [NSString stringWithFormat:@"群主 %@", group.owner];
}

@end

#pragma mark - 群列表页

@interface IMGroupListViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, strong) NSArray<IMGroupInfo *> *groups;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation IMGroupListViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        _groups = @[];
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"群聊";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self action:@selector(createTapped)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 64;
    [self.tableView registerClass:IMGroupRowCell.class forCellReuseIdentifier:@"group"];
    [self.view addSubview:self.tableView];

    self.emptyLabel = [UILabel new];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = @"还没有加入群聊，点右上角 + 创建";
    self.emptyLabel.textColor = IMTheme.textSecondary;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    IMHTTPService.sharedService.host = self.host;
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (token.length == 0) {
            [self im_showToast:error.localizedDescription ?: @"登录失败"];
            return;
        }
        [IMHTTPService.sharedService groupsWithToken:token completion:^(NSArray<IMGroupInfo *> *groups, NSError *err) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            if (err) {
                [self im_showToast:err.localizedDescription];
                return;
            }
            self.groups = groups ?: @[];
            self.emptyLabel.hidden = self.groups.count > 0;
            [self.tableView reloadData];
        }];
    }];
}

#pragma mark - 建群（选好友 → 起群名 → POST → 进群聊）

- (void)createTapped {
    __weak typeof(self) weakSelf = self;
    IMGroupMemberPickerViewController *picker =
        [[IMGroupMemberPickerViewController alloc] initWithHost:self.host userID:self.userID
                                                    excludedIDs:nil confirmTitle:@"创建"
                                                         onDone:^(NSArray<NSString *> *selectedIDs) {
            [weakSelf promptGroupNameForMembers:selectedIDs];
        }];
    [self.navigationController pushViewController:picker animated:YES];
}

/// 起群名弹窗 → 创建。
- (void)promptGroupNameForMembers:(NSArray<NSString *> *)memberIDs {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"群名"
        message:@"1~30 字" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"给群起个名字"; }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *name = [alert.textFields.firstObject.text
                          stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [weakSelf createGroupNamed:name members:memberIDs];
    }]];
    // 弹在导航栈顶（此刻是 picker 页）。
    [self.navigationController.topViewController presentViewController:alert animated:YES completion:nil];
}

- (void)createGroupNamed:(NSString *)name members:(NSArray<NSString *> *)memberIDs {
    UIViewController *top = self.navigationController.topViewController;
    if (name.length == 0) {
        [top im_showToast:@"请输入群名"];
        return;
    }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) {
        [top im_showToast:@"未登录"];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService createGroupWithToken:token name:name memberIDs:memberIDs
                                           completion:^(IMGroupInfo *group, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (error || !group) {
            [self.navigationController.topViewController im_showToast:
                [NSString stringWithFormat:@"建群失败：%@", error.localizedDescription ?: @"未知错误"]];
            return;
        }
        // 回到群列表页并直接进入新群会话。
        [self.navigationController popToViewController:self animated:NO];
        [self reload];
        [self openGroupChat:group];
    }];
}

- (void)openGroupChat:(IMGroupInfo *)group {
    IMChatViewController *chat = [[IMChatViewController alloc] initWithHost:self.host userID:self.userID
                                                                groupConvID:group.convID groupName:group.name
                                                                    readSeq:0 unread:0];
    [self.navigationController pushViewController:chat animated:YES];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.groups.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMGroupRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"group" forIndexPath:indexPath];
    IMGroupInfo *g = self.groups[indexPath.row];
    [cell configureWithGroup:g mine:[g.owner isEqualToString:self.userID]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self openGroupChat:self.groups[indexPath.row]];
}

@end
