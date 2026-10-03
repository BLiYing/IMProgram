//  IMJoinRequestsViewController.m

#import "IMJoinRequestsViewController.h"
#import "IMLocalization.h"
#import "IMQRModels.h"
#import "IMTheme.h"
#import "IMImageLoader.h"
#import "IMHTTPService.h"
#import "UIViewController+IMToast.h"
#import "IMAccountIdentity.h"
#import "IMLiquidSegmentedControl.h"

@interface IMJoinRequestsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *token;
@property (nonatomic, copy) NSString *convID;
@property (nonatomic, copy, nullable) void (^onChanged)(void);
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<IMJoinRequest *> *requests;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) IMLiquidSegmentedControl *segmented;
@property (nonatomic, strong) NSLayoutConstraint *segmentedWidth; ///< 控件没有固有宽度，必须显式给（否则 0 宽、整条看不见）
/// 当前页签下显示的申请（待处理 / 已处理）。
@property (nonatomic, strong) NSArray<IMJoinRequest *> *shown;
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
    self.title = IMLocalized(@"qr.join_req.title");
    self.view.backgroundColor = IMTheme.groupedBackground;

    // 页签：待处理 / 已处理（与 Web `JoinRequestsModal`、Android 同结构；审批完的那条落到「已处理」，
    // 不再整条消失——用户最需要看到「刚才那下确实生效了」）。
    self.segmented = [[IMLiquidSegmentedControl alloc] initWithFrame:CGRectZero];
    self.segmented.translatesAutoresizingMaskIntoConstraints = NO;
    [self.segmented addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.segmented];
    [self updateSegmentTitles];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 64;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.segmented.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.segmented.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.segmented.heightAnchor constraintEqualToConstant:36],
        (self.segmentedWidth = [self.segmented.widthAnchor constraintEqualToConstant:200]),
        [self.tableView.topAnchor constraintEqualToAnchor:self.segmented.bottomAnchor constant:4],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.emptyLabel = [UILabel new];
    self.emptyLabel.text = IMLocalized(@"qr.join_req.empty_pending");
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

- (BOOL)showingDone { return self.segmented.selectedIndex == 1; }

- (void)updateSegmentTitles {
    NSInteger pending = 0;
    for (IMJoinRequest *r in self.requests) { if ([r.status isEqualToString:@"pending"]) { pending++; } }
    NSString *first = pending > 0 ? IMLocalizedFormat(@"qr.join_req.tab_pending_count", (long)pending)
                                  : IMLocalized(@"qr.join_req.tab_pending");
    self.segmented.titles = @[first, IMLocalized(@"qr.join_req.tab_done")];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // 按内容宽、下限 200、不超过屏宽（与会话详情页 `layoutSegmented:` 同口径）
    CGFloat maxW = MAX(200, self.view.bounds.size.width - 32);
    CGFloat w = [self.segmented sizeThatFits:CGSizeMake(maxW, 36)].width;
    w = MIN(MAX(w, 200), maxW);
    if (fabs(self.segmentedWidth.constant - w) > 0.5) { self.segmentedWidth.constant = w; }
}

- (void)segmentChanged:(IMLiquidSegmentedControl *)seg { [self refreshUI]; }

- (void)refreshUI {
    BOOL done = [self showingDone];
    NSMutableArray<IMJoinRequest *> *rows = [NSMutableArray array];
    for (IMJoinRequest *r in self.requests) {
        if ([r.status isEqualToString:@"pending"] != done) { [rows addObject:r]; }
    }
    self.shown = rows;
    [self updateSegmentTitles];
    self.emptyLabel.text = done ? IMLocalized(@"qr.join_req.empty_done") : IMLocalized(@"qr.join_req.empty_pending");
    self.emptyLabel.hidden = (rows.count > 0) || !self.loaded;
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.shown.count;
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
    IMJoinRequest *r = self.shown[indexPath.row];
    cell.textLabel.text = IMDisplayName(r.nickname, nil);
    cell.detailTextLabel.text = r.hello.length ? r.hello : IMLocalized(@"qr.join_req.default_hello");
    cell.detailTextLabel.textColor = IMTheme.textSecondary;
    cell.imageView.image = nil;
    cell.imageView.backgroundColor = [IMTheme avatarColorForSeed:r.userID];
    if (r.avatarURL.length > 0) {
        NSString *uid = r.userID;
        [[IMImageLoader shared] loadImageURL:r.avatarURL completion:^(UIImage *image) {
            NSIndexPath *now = [tableView indexPathForCell:cell];
            if (image && now && now.row < (NSInteger)self.shown.count && [self.shown[now.row].userID isEqualToString:uid]) {
                cell.imageView.image = image;
                [cell setNeedsLayout];
            }
        }];
    }

    if ([r.status isEqualToString:@"pending"]) {
        UIButton *accept = [self smallButton:IMLocalized(@"common.agree") filled:YES tag:indexPath.row action:@selector(acceptTapped:)];
        UIButton *reject = [self smallButton:IMLocalized(@"common.reject") filled:NO tag:indexPath.row action:@selector(rejectTapped:)];
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[reject, accept]];
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.spacing = 8;
        [stack sizeToFit];
        stack.frame = CGRectMake(0, 0, 128, 32);
        cell.accessoryView = stack;
    } else {
        // 已处理：只读结果文案，没有按钮
        BOOL ok = [r.status isEqualToString:@"approved"];
        UILabel *lab = [UILabel new];
        lab.text = ok ? IMLocalized(@"qr.join_req.approved") : IMLocalized(@"qr.join_req.rejected");
        lab.font = [UIFont systemFontOfSize:14];
        lab.textColor = ok ? IMTheme.textSecondary : IMTheme.textTertiary;
        [lab sizeToFit];
        cell.accessoryView = lab;
    }
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
    if (row < 0 || row >= (NSInteger)self.shown.count) { return; }
    IMJoinRequest *r = self.shown[row];
    [IMHTTPService.sharedService decideJoinRequestWithToken:self.token convID:self.convID
                                                     userID:r.userID accept:accept
        completion:^(NSError *error) {
            if (error) { [self im_showToast:error.localizedDescription]; return; }
            r.status = accept ? @"approved" : @"rejected"; // 落到「已处理」页签，不整条消失
            [self refreshUI];
            if (self.onChanged) { self.onChanged(); }
            [self im_showToast:accept ? IMLocalized(@"qr.join_req.approved_toast") : IMLocalized(@"qr.join_req.rejected")];
        }];
}

@end
