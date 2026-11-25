//  IMAppStoreViewController.m

#import "IMAppStoreViewController.h"
#import "IMHTTPService.h"
#import "IMJSONValue.h"
#import "IMHTTPService+Workbench.h"
#import "IMLocalization.h"
#import "IMTheme.h"
#import "IMLog.h"
#import "IMWorkbench.h"
#import "IMWorkbenchCells.h"
#import "IMWorkbenchOpener.h"
#import "UIViewController+IMToast.h"

static NSString *const kStoreCell = @"storeApp";

/// 商店的一行：图标 44×44 r10 + 名称 17 + 简介 14 secondary + 右侧「添加」胶囊 /「已添加」文字。
@interface IMAppStoreCell : UITableViewCell
@property (nonatomic, strong, readonly) IMWorkbenchAppIconView *icon;
@property (nonatomic, strong, readonly) UILabel *nameLabel;
@property (nonatomic, strong, readonly) UILabel *introLabel;
@property (nonatomic, strong, readonly) UIButton *addButton;
@property (nonatomic, strong, readonly) UILabel *addedLabel;
@property (nonatomic, copy, nullable) void (^onAdd)(void);
@end

@implementation IMAppStoreCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    self = [super initWithStyle:style reuseIdentifier:rid];
    if (self) {
        _icon = [[IMWorkbenchAppIconView alloc] initWithSide:44 radius:10];
        _nameLabel = [UILabel new];
        _nameLabel.font = [UIFont systemFontOfSize:17];
        _introLabel = [UILabel new];
        _introLabel.font = [UIFont systemFontOfSize:14];
        _introLabel.textColor = IMTheme.textSecondary;
        UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, _introLabel]];
        text.axis = UILayoutConstraintAxisVertical;
        text.spacing = 2;
        text.translatesAutoresizingMaskIntoConstraints = NO;
        UIButtonConfiguration *cfg = [UIButtonConfiguration grayButtonConfiguration];
        cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        cfg.contentInsets = NSDirectionalEdgeInsetsMake(5, 14, 5, 14);
        NSDictionary *attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold] };
        cfg.attributedTitle = [[NSAttributedString alloc] initWithString:IMLocalized(@"workbench.add") attributes:attrs];
        cfg.baseForegroundColor = IMTheme.accent;
        _addButton = [UIButton buttonWithConfiguration:cfg primaryAction:nil];
        _addButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_addButton addTarget:self action:@selector(addTapped) forControlEvents:UIControlEventTouchUpInside];
        _addedLabel = [UILabel new];
        _addedLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _addedLabel.text = IMLocalized(@"workbench.added");
        _addedLabel.font = [UIFont systemFontOfSize:15];
        _addedLabel.textColor = IMTheme.textSecondary;
        for (UIView *v in @[_icon, text, _addButton, _addedLabel]) { [self.contentView addSubview:v]; }
        [NSLayoutConstraint activateConstraints:@[
            [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:68],
            [_icon.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_icon.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [text.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:12],
            [text.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            // 文字区固定伸到右侧留白处（「添加」胶囊 / 「已添加」二者显隐切换，不能只贴其中一个）
            [text.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-96],
            [_addButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_addButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_addedLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_addedLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
        [_nameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        [_introLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    }
    return self;
}

- (void)addTapped { if (self.onAdd) { self.onAdd(); } }

@end

@interface IMAppStoreViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *unitID;
@property (nonatomic, copy) NSArray<IMWorkbenchSection *> *sections;
/// 乐观更新的「已添加」：app_id → YES（服务端回来前先当已添加显示）。
@property (nonatomic, strong) NSMutableSet<NSString *> *pendingAdded;
@end

@implementation IMAppStoreViewController

- (instancetype)initWithHost:(NSString *)host unitID:(NSString *)unitID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _unitID = [unitID copy];
        _sections = @[];
        _pendingAdded = [NSMutableSet set];
        self.title = IMLocalized(@"workbench.store");
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:IMAppStoreCell.class forCellReuseIdentifier:kStoreCell];
    self.tableView.accessibilityIdentifier = @"workbench.store.list";
    self.tableView.refreshControl = [UIRefreshControl new];
    [self.tableView.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
    [self reload];
}

- (void)reload {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self.tableView.refreshControl endRefreshing]; return; }
    __weak typeof(self) weak = self;
    [IMHTTPService.sharedService workbenchStoreWithToken:token unitID:self.unitID completion:^(NSDictionary *data, NSError *error) {
        typeof(self) s = weak;
        if (!s) { return; }
        [s.tableView.refreshControl endRefreshing];
        if (error) {
            IMLogWarnWithTag(IMLogTagHTTP, @"workbench_store_failed code=%ld", (long)error.code);
            [s im_showToast:error.localizedDescription ?: IMLocalized(@"common.action_failed")];
            return;
        }
        s.sections = [IMWorkbench sectionsFromGroups:data[@"groups"] otherTitle:IMLocalized(@"workbench.group_other") soleTitle:nil];
        // 只清掉服务端已确认添加的：点「添加」前发出的旧列表回来时，不能把乐观的「已添加」冲掉（失败时由添加回调自己撤）
        for (IMWorkbenchSection *sec in s.sections) {
            for (NSDictionary *a in sec.apps) { if (IMJSONBool(a[@"added"])) { [s.pendingAdded removeObject:IMJSONString(a[@"app_id"])]; } }
        }
        [s.tableView reloadData];
    }];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return (NSInteger)self.sections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.sections[section].apps.count; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section { return self.sections[section].title; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    IMAppStoreCell *cell = [tv dequeueReusableCellWithIdentifier:kStoreCell forIndexPath:ip];
    NSDictionary *app = self.sections[ip.section].apps[ip.row];
    NSString *name = IMJSONString(app[@"name"]);
    cell.nameLabel.text = name;
    cell.introLabel.text = IMJSONString(app[@"intro"]);
    [cell.icon setName:name logoURL:IMJSONString(app[@"logo_url"]) host:self.host];
    BOOL added = IMJSONBool(app[@"added"]) || [self.pendingAdded containsObject:app[@"app_id"]];
    cell.addButton.hidden = added;
    cell.addedLabel.hidden = !added;
    cell.addButton.accessibilityIdentifier = [@"workbench.store.add." stringByAppendingString:name];
    __weak typeof(self) weak = self;
    cell.onAdd = ^{ [weak addApp:app]; };
    return cell;
}

- (void)addApp:(NSDictionary *)app {
    NSString *appID = app[@"app_id"], *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0 || ![appID isKindOfClass:NSString.class]) { return; }
    [self.pendingAdded addObject:appID]; // 乐观：立刻显示「已添加」
    [self.tableView reloadData];
    __weak typeof(self) weak = self;
    [IMHTTPService.sharedService workbenchSetAppWithToken:token unitID:self.unitID appID:appID add:YES completion:^(NSDictionary *d, NSError *error) {
        typeof(self) s = weak;
        if (!s) { return; }
        if (error) {
            [s.pendingAdded removeObject:appID];
            [s.tableView reloadData];
            [s im_showToast:error.localizedDescription ?: IMLocalized(@"common.action_failed")];
            return;
        }
        [NSNotificationCenter.defaultCenter postNotificationName:IMWorkbenchDidChangeNotification object:s.unitID];
    }];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *app = self.sections[ip.section].apps[ip.row];
    __weak typeof(self) weak = self;
    [IMWorkbenchOpener openAppID:app[@"app_id"] name:IMJSONString(app[@"name"]) unitID:self.unitID from:self onUnavailable:^{ [weak reload]; }];
}

@end
