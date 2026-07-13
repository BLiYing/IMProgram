//  IMGroupMemberPickerViewController.m

#import "IMGroupMemberPickerViewController.h"
#import "IMContactCells.h"
#import "IMHTTPService.h"
#import "IMUserCard.h"
#import "IMTheme.h"
#import "IMLog.h"

@interface IMGroupMemberPickerViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, strong, nullable) NSSet<NSString *> *excludedIDs;
@property (nonatomic, copy) NSString *confirmTitle;
@property (nonatomic, copy) void (^onDone)(NSArray<NSString *> *selectedIDs);
@property (nonatomic, strong) NSArray<IMUserCard *> *friends;          // 可选好友（已排除 excludedIDs）
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *picked; // 选中的 uid（保持点选顺序）
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation IMGroupMemberPickerViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID
                 excludedIDs:(NSSet<NSString *> *)excludedIDs
                confirmTitle:(NSString *)confirmTitle
                      onDone:(void (^)(NSArray<NSString *> *))onDone {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        _excludedIDs = [excludedIDs copy];
        _confirmTitle = [confirmTitle copy];
        _onDone = [onDone copy];
        _friends = @[];
        _picked = [NSMutableOrderedSet orderedSet];
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"选择好友";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:self.confirmTitle style:UIBarButtonItemStyleDone
                                        target:self action:@selector(confirmTapped)];
    self.navigationItem.rightBarButtonItem.enabled = NO; // 至少选 1 个才可确认
    // 返回键用系统默认（与全局各页一致）。长按弹出的「导航历史菜单」是 iOS 标准特性、无害——普通点击直接返回。

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 60;
    [self.tableView registerClass:IMContactCell.class forCellReuseIdentifier:@"pick"];
    [self.view addSubview:self.tableView];

    self.emptyLabel = [UILabel new];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = @"没有可选的好友";
    self.emptyLabel.textColor = IMTheme.textSecondary;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    [self reload];
}

/// 拉好友列表（accepted），排除 excludedIDs。
- (void)reload {
    IMHTTPService.sharedService.host = self.host;
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (token.length == 0) {
            IMLog(@"picker 登录失败：%@", error.localizedDescription);
            return;
        }
        [IMHTTPService.sharedService friendsWithToken:token status:@"accepted"
                                           completion:^(NSArray<IMUserCard *> *friends, NSError *err) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            if (err) {
                IMLog(@"picker 拉好友失败：%@", err.localizedDescription);
                return;
            }
            NSMutableArray<IMUserCard *> *usable = [NSMutableArray array];
            for (IMUserCard *c in friends) {
                if (![self.excludedIDs containsObject:c.userID]) { [usable addObject:c]; }
            }
            self.friends = usable;
            self.emptyLabel.hidden = usable.count > 0;
            [self.tableView reloadData];
        }];
    }];
}

- (void)confirmTapped {
    if (self.picked.count == 0) { return; }
    if (self.onDone) { self.onDone(self.picked.array); }
}

/// 更新标题与确认按钮态（已选 N）。
- (void)updateSelectionUI {
    self.title = self.picked.count > 0
        ? [NSString stringWithFormat:@"已选 %lu 人", (unsigned long)self.picked.count]
        : @"选择好友";
    self.navigationItem.rightBarButtonItem.enabled = self.picked.count > 0;
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.friends.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMContactCell *cell = [tableView dequeueReusableCellWithIdentifier:@"pick" forIndexPath:indexPath];
    IMUserCard *c = self.friends[indexPath.row];
    [cell configureWithCard:c subtitle:c.userID];
    [cell setActionTitle:nil enabled:NO action:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryType = [self.picked containsObject:c.userID]
        ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.tintColor = IMTheme.accent;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *uid = self.friends[indexPath.row].userID;
    if ([self.picked containsObject:uid]) { [self.picked removeObject:uid]; }
    else { [self.picked addObject:uid]; }
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [self updateSelectionUI];
}

@end
