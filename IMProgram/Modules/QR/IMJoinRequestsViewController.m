//  IMJoinRequestsViewController.m

#import "IMJoinRequestsViewController.h"
#import "IMQRModels.h"
#import "IMTheme.h"
#import "IMImageLoader.h"
#import "IMHTTPService.h"
#import "UIViewController+IMToast.h"
#import "IMAccountIdentity.h"

@interface IMJoinRequestsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *token;
@property (nonatomic, copy) NSString *convID;
@property (nonatomic, copy, nullable) void (^onChanged)(void);
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<IMJoinRequest *> *requests;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, assign) BOOL loaded;
@end

@implementation IMJoinRequestsViewController

- (instancetype)initWithToken:(NSString *)token convID:(NSString *)convID onChanged:(void (^)(void))onChanged {
    if (self = [super init]) {
        _token = [token copy];
        _convID = [convID copy];
        _onChanged = [onChanged copy];
        _requests = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"待审入群申请";
    self.view.backgroundColor = IMTheme.groupedBackground;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 64;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.emptyLabel = [UILabel new];
    self.emptyLabel.text = @"暂无待审批的入群申请";
    self.emptyLabel.textColor = IMTheme.textSecondary;
    self.emptyLabel.font = [UIFont systemFontOfSize:14];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.hidden = YES;
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    [self reload];
}

- (void)reload {
    [IMHTTPService.sharedService joinRequestsWithToken:self.token convID:self.convID
        completion:^(NSArray<NSDictionary *> *requests, NSError *error) {
            self.loaded = YES;
            if (error) { [self im_showToast:error.localizedDescription]; return; }
            self.requests = [[IMJoinRequest fromArray:requests] mutableCopy];
            [self refreshUI];
        }];
}

- (void)refreshUI {
    self.emptyLabel.hidden = (self.requests.count > 0) || !self.loaded;
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.requests.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuse = @"joinreq";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuse];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.imageView.layer.cornerRadius = 20;
        cell.imageView.clipsToBounds = YES;
    }
    IMJoinRequest *r = self.requests[indexPath.row];
    cell.textLabel.text = IMDisplayName(r.nickname, nil);
    cell.detailTextLabel.text = r.hello.length ? r.hello : @"申请加入群聊";
    cell.detailTextLabel.textColor = IMTheme.textSecondary;
    cell.imageView.image = nil;
    cell.imageView.backgroundColor = [IMTheme avatarColorForSeed:r.userID];
    if (r.avatarURL.length > 0) {
        NSString *uid = r.userID;
        [[IMImageLoader shared] loadImageURL:r.avatarURL completion:^(UIImage *image) {
            NSIndexPath *now = [tableView indexPathForCell:cell];
            if (image && now && [self.requests[now.row].userID isEqualToString:uid]) {
                cell.imageView.image = image;
                [cell setNeedsLayout];
            }
        }];
    }

    UIButton *accept = [self smallButton:@"同意" filled:YES tag:indexPath.row action:@selector(acceptTapped:)];
    UIButton *reject = [self smallButton:@"拒绝" filled:NO tag:indexPath.row action:@selector(rejectTapped:)];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[reject, accept]];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = 8;
    [stack sizeToFit];
    stack.frame = CGRectMake(0, 0, 128, 32);
    cell.accessoryView = stack;
    return cell;
}

- (UIButton *)smallButton:(NSString *)title filled:(BOOL)filled tag:(NSInteger)tag action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *cfg = filled ? [UIButtonConfiguration filledButtonConfiguration]
                                        : [UIButtonConfiguration grayButtonConfiguration];
    cfg.title = title;
    cfg.buttonSize = UIButtonConfigurationSizeSmall;
    if (filled) { cfg.baseBackgroundColor = IMTheme.accent; }
    b.configuration = cfg;
    b.tag = tag;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

#pragma mark - Actions

- (void)acceptTapped:(UIButton *)sender { [self decideRow:sender.tag accept:YES]; }
- (void)rejectTapped:(UIButton *)sender { [self decideRow:sender.tag accept:NO]; }

- (void)decideRow:(NSInteger)row accept:(BOOL)accept {
    if (row < 0 || row >= (NSInteger)self.requests.count) { return; }
    IMJoinRequest *r = self.requests[row];
    [IMHTTPService.sharedService decideJoinRequestWithToken:self.token convID:self.convID
                                                     userID:r.userID accept:accept
        completion:^(NSError *error) {
            if (error) { [self im_showToast:error.localizedDescription]; return; }
            NSUInteger idx = [self.requests indexOfObject:r];
            if (idx != NSNotFound) { [self.requests removeObjectAtIndex:idx]; }
            [self refreshUI];
            if (self.onChanged) { self.onChanged(); }
            [self im_showToast:accept ? @"已同意入群" : @"已拒绝"];
        }];
}

@end
