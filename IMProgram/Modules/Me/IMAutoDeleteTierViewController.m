//  IMAutoDeleteTierViewController.m
//  不用 UITableViewController：注入的液态标题栏会把它的表格下移（同 IMLanguageViewController）。

#import "IMAutoDeleteTierViewController.h"
#import "IMAutoDelete.h"
#import "IMLocalization.h"
#import "IMHTTPService.h"
#import "IMHTTPService+AutoDelete.h"
#import "UIViewController+IMToast.h"

@interface IMAutoDeleteTierViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, assign) int64_t currentSec;
@property (nonatomic, copy) NSString *footerText;
@property (nonatomic, assign) BOOL optimistic;
@property (nonatomic, copy) IMAutoDeleteTierSelect onSelect;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, assign) BOOL saving; ///< 保存在途：不接受二次点击
@property (nonatomic, assign) BOOL fetchesOnAppear; ///< 账号默认页：进页时 GET /users/me/privacy 取最新值
@end

@implementation IMAutoDeleteTierViewController

- (instancetype)initWithCurrentSec:(int64_t)currentSec footer:(NSString *)footer
                        optimistic:(BOOL)optimistic onSelect:(IMAutoDeleteTierSelect)onSelect {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _currentSec = IMAutoDeleteIsValidSec(currentSec) ? currentSec : 0;
        _footerText = [footer copy];
        _optimistic = optimistic;
        _onSelect = [onSelect copy];
    }
    return self;
}

+ (instancetype)accountDefaultPickerWithInitialSec:(int64_t)sec onSaved:(void (^)(int64_t))onSaved {
    __block __weak IMAutoDeleteTierViewController *weakVC = nil;
    IMAutoDeleteTierViewController *vc = [[self alloc] initWithCurrentSec:sec footer:IMLocalized(@"autodel.default.footer") optimistic:YES
        onSelect:^(int64_t newSec, void (^done)(BOOL)) {
            NSString *token = IMHTTPService.sharedService.currentToken;
            [IMHTTPService.sharedService saveAutoDeleteDefault:newSec token:token ?: @"" completion:^(NSError *error) {
                if (error) { [weakVC im_showToast:IMLocalized(@"autodel.save_failed")]; done(NO); return; }
                if (onSaved) { onSaved(newSec); }
                done(YES);
            }];
        }];
    weakVC = vc;
    vc.fetchesOnAppear = YES;
    return vc;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.fetchesOnAppear) { return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService fetchAutoDeleteDefaultWithToken:token completion:^(int64_t sec, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || error || self.saving) { return; }
        self.currentSec = sec;
        [self.tableView reloadData];
    }];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"ps.row.auto_delete_messages");
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.accessibilityIdentifier = @"autodel.tiers";
    [self.view addSubview:self.tableView];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)IMAutoDeleteTiers().count; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return self.footerText; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    int64_t sec = IMAutoDeleteTiers()[indexPath.row].longLongValue;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = IMAutoDeleteTierTitle(sec);
    cell.accessoryType = sec == self.currentSec ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessibilityIdentifier = [NSString stringWithFormat:@"autodel.tier.%lld", sec];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.saving) { return; }
    int64_t sec = IMAutoDeleteTiers()[indexPath.row].longLongValue;
    if (sec == self.currentSec) { [self.navigationController popViewControllerAnimated:YES]; return; }
    int64_t previous = self.currentSec;
    self.saving = YES;
    if (self.optimistic) { self.currentSec = sec; [self.tableView reloadData]; }
    __weak typeof(self) ws = self;
    self.onSelect(sec, ^(BOOL saved) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            self.saving = NO;
            if (saved) {
                self.currentSec = sec;
                [self.tableView reloadData];
                [self.navigationController popViewControllerAnimated:YES];
            } else {
                self.currentSec = previous; // 失败 / 取消：✓ 回到原档位
                [self.tableView reloadData];
            }
        });
    });
}

@end
