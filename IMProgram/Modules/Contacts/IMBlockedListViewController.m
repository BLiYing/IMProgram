//  IMBlockedListViewController.m

#import "IMBlockedListViewController.h"
#import "IMContactCells.h"
#import "IMHTTPService.h"
#import "IMUserCard.h"
#import "IMTheme.h"
#import "IMLog.h"

@interface IMBlockedListViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy, nullable) NSString *token;
@property (nonatomic, strong) NSArray<IMUserCard *> *blocked;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation IMBlockedListViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        _blocked = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"黑名单";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 68;
    [self.tableView registerClass:IMContactCell.class forCellReuseIdentifier:@"blocked"];
    [self.view addSubview:self.tableView];

    self.emptyLabel = [UILabel new];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = @"没有拉黑的用户";
    self.emptyLabel.textColor = IMTheme.textSecondary;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
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
            [self showError:[NSString stringWithFormat:@"登录失败：%@", error.localizedDescription]];
            return;
        }
        self.token = token;
        [IMHTTPService.sharedService friendsWithToken:token status:@"blocked" completion:^(NSArray<IMUserCard *> *list, NSError *err) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            if (err) {
                [self showError:[NSString stringWithFormat:@"拉取黑名单失败：%@", err.localizedDescription]];
                return;
            }
            self.blocked = list ?: @[];
            self.emptyLabel.hidden = self.blocked.count > 0;
            [self.tableView reloadData];
        }];
    }];
}

- (void)unblockPeer:(NSString *)peerID {
    if (self.token.length == 0 || peerID.length == 0) { return; }
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService friendActionWithToken:self.token action:@"unblock" peerID:peerID completion:^(NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (error) {
            [self showError:[NSString stringWithFormat:@"解除失败：%@", error.localizedDescription]];
            return;
        }
        [self reload];
    }];
}

- (void)showError:(NSString *)message {
    IMLog(@"%@", message);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.blocked.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMContactCell *cell = [tableView dequeueReusableCellWithIdentifier:@"blocked" forIndexPath:indexPath];
    IMUserCard *c = self.blocked[indexPath.row];
    NSString *peer = c.userID;
    [cell configureWithCard:c subtitle:c.userID];
    __weak typeof(self) weakSelf = self;
    [cell setActionTitle:@"解除" enabled:YES action:^{ [weakSelf unblockPeer:peer]; }];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

@end
