//  IMDeviceListViewController.m

#import "IMDeviceListViewController.h"
#import "IMDeviceDetailViewController.h"
#import "IMDeviceModels.h"
#import "IMHTTPService.h"
#import "IMTheme.h"
#import "IMLog.h"
#import "UIViewController+IMToast.h"

#pragma mark - 设备行 cell（emoji 图标 + 名 + 「当前」标 + 在线圆点 + 状态）

@interface IMDeviceCell : UITableViewCell
- (void)configureWithDevice:(IMDeviceSession *)device;
@end

@implementation IMDeviceCell {
    UILabel *_iconLabel;
    UILabel *_nameLabel;
    UILabel *_pillLabel;
    UIView *_dotView;
    UILabel *_statusLabel;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) { [self setup]; }
    return self;
}

- (void)setup {
    UIView *iconBox = [UIView new];
    iconBox.backgroundColor = IMTheme.groupedBackground;
    iconBox.layer.cornerRadius = 9;
    iconBox.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:iconBox];

    _iconLabel = [UILabel new];
    _iconLabel.font = [UIFont systemFontOfSize:19];
    _iconLabel.textAlignment = NSTextAlignmentCenter;
    _iconLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [iconBox addSubview:_iconLabel];

    _nameLabel = [UILabel new];
    _nameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    _nameLabel.textColor = IMTheme.textPrimary;
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_nameLabel];

    _pillLabel = [UILabel new];
    _pillLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    _pillLabel.textColor = IMTheme.accent;
    _pillLabel.text = @" 当前 ";
    _pillLabel.backgroundColor = [IMTheme.accent colorWithAlphaComponent:0.14];
    _pillLabel.layer.cornerRadius = 4;
    _pillLabel.layer.masksToBounds = YES;
    _pillLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_pillLabel];

    _dotView = [UIView new];
    _dotView.layer.cornerRadius = 4;
    _dotView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_dotView];

    _statusLabel = [UILabel new];
    _statusLabel.font = [UIFont systemFontOfSize:12];
    _statusLabel.textColor = IMTheme.textSecondary;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_statusLabel];

    [_nameLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    // 名过长时截断，避免与「当前」标/内容边距冲突。
    [_nameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [_pillLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_statusLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    [NSLayoutConstraint activateConstraints:@[
        [iconBox.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14],
        [iconBox.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [iconBox.widthAnchor constraintEqualToConstant:36],
        [iconBox.heightAnchor constraintEqualToConstant:36],
        [_iconLabel.centerXAnchor constraintEqualToAnchor:iconBox.centerXAnchor],
        [_iconLabel.centerYAnchor constraintEqualToAnchor:iconBox.centerYAnchor],

        [_nameLabel.leadingAnchor constraintEqualToAnchor:iconBox.trailingAnchor constant:11],
        [_nameLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:11],

        [_pillLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor constant:6],
        [_pillLabel.centerYAnchor constraintEqualToAnchor:_nameLabel.centerYAnchor],
        [_pillLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-14],
        [_pillLabel.heightAnchor constraintEqualToConstant:16],

        [_dotView.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
        [_dotView.centerYAnchor constraintEqualToAnchor:_statusLabel.centerYAnchor],
        [_dotView.widthAnchor constraintEqualToConstant:8],
        [_dotView.heightAnchor constraintEqualToConstant:8],

        [_statusLabel.leadingAnchor constraintEqualToAnchor:_dotView.trailingAnchor constant:6],
        [_statusLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:3],
        [_statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-14],
        [_statusLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-11],
    ]];
}

- (void)configureWithDevice:(IMDeviceSession *)device {
    _iconLabel.text = device.platformEmoji;
    _nameLabel.text = device.deviceName.length ? device.deviceName : @"未知设备";
    _pillLabel.hidden = !device.current;
    _dotView.backgroundColor = device.online ? IMTheme.onlineDot : IMTheme.textTertiary;
    _statusLabel.text = device.statusLine;
}

@end

#pragma mark - 列表

@interface IMDeviceListViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy, nullable) NSString *token;
@property (nonatomic, strong) UITableView *tableView;
// 分区描述：kind=0 设备行；kind=1 动作（退出其他所有设备）。
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
@property (nonatomic, strong) NSArray<NSNumber *> *sectionKinds;
@property (nonatomic, strong) NSArray<NSArray *> *sectionItems;
@end

@implementation IMDeviceListViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        _sectionTitles = @[];
        _sectionKinds = @[];
        _sectionItems = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"已登录设备";
    self.view.backgroundColor = IMTheme.groupedBackground;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:IMDeviceCell.class forCellReuseIdentifier:@"device"];
    [self.view addSubview:self.tableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

#pragma mark - 数据

- (void)reload {
    IMHTTPService.sharedService.host = self.host;
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (token.length == 0) {
            IMLog(@"设备列表登录失败（保留当前内容）：%@", error.localizedDescription ?: @"未知错误");
            return;
        }
        self.token = token;
        [IMHTTPService.sharedService devicesWithToken:token completion:^(NSArray<IMDeviceSession *> *devices, NSError *err) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (err) {
                IMLog(@"设备列表刷新失败（保留当前内容）：%@", err.localizedDescription ?: @"未知错误");
                return;
            }
            [self applyDevices:devices ?: @[]];
        }];
    }];
}

- (void)applyDevices:(NSArray<IMDeviceSession *> *)devices {
    IMDeviceSession *current = nil;
    NSMutableArray<IMDeviceSession *> *others = [NSMutableArray array];
    for (IMDeviceSession *d in devices) {
        if (d.current && current == nil) { current = d; }
        else { [others addObject:d]; }
    }

    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    NSMutableArray<NSNumber *> *kinds = [NSMutableArray array];
    NSMutableArray<NSArray *> *items = [NSMutableArray array];
    if (current) {
        [titles addObject:@"这台设备"]; [kinds addObject:@0]; [items addObject:@[current]];
        if (others.count > 0) {
            [titles addObject:@"其他设备"]; [kinds addObject:@0]; [items addObject:others];
        }
    } else if (others.count > 0) {
        // 后端未标出本机（理论上不该发生：本机 sid 恒在列表里）。此时不谎称「其他设备」——用中性标题，
        // 避免把本机当成他人设备诱导误踢；「退出其他所有设备」由服务端按本次请求 sid 保留本机，仍安全。
        [titles addObject:@"已登录设备"]; [kinds addObject:@0]; [items addObject:others];
    }
    if (others.count > 0) {
        [titles addObject:@""]; [kinds addObject:@1]; [items addObject:@[@"退出其他所有设备"]];
    }
    self.sectionTitles = titles;
    self.sectionKinds = kinds;
    self.sectionItems = items;
    [self.tableView reloadData];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sectionItems.count; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.sectionItems[section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSString *t = self.sectionTitles[section];
    return t.length ? t : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.sectionKinds[section].integerValue == 1) {
        return @"退出后该设备需重新登录。若你不认识某台设备，请退出它并尽快修改密码。";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.sectionKinds[indexPath.section].integerValue == 1) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"action"];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.font = [UIFont systemFontOfSize:16];
            cell.textLabel.textColor = IMTheme.danger;
        }
        cell.textLabel.text = self.sectionItems[indexPath.section][indexPath.row];
        return cell;
    }
    IMDeviceCell *cell = [tableView dequeueReusableCellWithIdentifier:@"device" forIndexPath:indexPath];
    IMDeviceSession *d = self.sectionItems[indexPath.section][indexPath.row];
    [cell configureWithDevice:d];
    // 本机行不进详情（退出本机=退出登录，走设置页「退出登录」）；其他设备可点进详情退出。
    cell.accessoryType = d.current ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = d.current ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 60;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.sectionKinds[indexPath.section].integerValue == 1) {
        [self confirmRevokeOthers];
        return;
    }
    IMDeviceSession *d = self.sectionItems[indexPath.section][indexPath.row];
    if (d.current) { return; }
    IMDeviceDetailViewController *detail =
        [[IMDeviceDetailViewController alloc] initWithHost:self.host userID:self.userID device:d];
    [self.navigationController pushViewController:detail animated:YES];
}

#pragma mark - 退出其他所有设备

- (void)confirmRevokeOthers {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"退出其他所有设备"
                                                               message:@"除这台设备外，其余设备都将立即下线并需重新登录。"
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"退出" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [ws revokeOthers];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)revokeOthers {
    NSString *token = self.token ?: IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:@"登录已失效，请重新登录"]; return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService revokeOtherDevicesWithToken:token completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) {
            [self im_showToast:(error.localizedDescription.length ? error.localizedDescription : @"退出其他设备失败")];
            return;
        }
        [self im_showToast:@"已退出其他所有设备"];
        [self reload];
    }];
}

@end
