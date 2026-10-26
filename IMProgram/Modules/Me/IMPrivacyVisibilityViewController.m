//  IMPrivacyVisibilityViewController.m
//  不用 UITableViewController：注入的液态标题栏会把它的表格下移（同 IMLanguageViewController / IMAutoDeleteTierViewController）。

#import "IMPrivacyVisibilityViewController.h"
#import "IMHTTPService.h"
#import "IMHTTPService+AutoDelete.h"
#import "IMLocalization.h"
#import "UIViewController+IMToast.h"

@interface IMPrivacyVisibilityViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, assign) IMPrivacyVisibilityKind kind;
@property (nonatomic, copy, readwrite) NSString *currentLevel;
@property (nonatomic, copy, nullable) void (^onSaved)(NSString *level);
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, assign) BOOL saving; ///< 保存在途：不接受二次点击
@end

@implementation IMPrivacyVisibilityViewController

- (instancetype)initWithKind:(IMPrivacyVisibilityKind)kind currentLevel:(NSString *)level
                     onSaved:(void (^)(NSString *))onSaved {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _kind = kind;
        _currentLevel = IMPrivacyVisibilityParse(kind, level);
        _onSaved = [onSaved copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(IMPrivacyVisibilityRowTitleKey(self.kind));
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.accessibilityIdentifier = @"privacy.visibility.levels";
    [self.view addSubview:self.tableView];
}

#pragma mark - 保存

- (void)chooseLevel:(NSString *)level {
    if (self.saving || ![IMPrivacyVisibilityLevels() containsObject:level]) { return; }
    if ([level isEqualToString:self.currentLevel]) { [self.navigationController popViewControllerAnimated:YES]; return; }
    NSString *previous = self.currentLevel;
    self.saving = YES;
    self.currentLevel = level; // 乐观打 ✓
    [self.tableView reloadData];
    NSString *token = IMHTTPService.sharedService.currentToken;
    __weak typeof(self) ws = self;
    void (^onSaved)(NSString *) = self.onSaved; // 强持：用户在途中点返回、本页已释放时，上一页行右值仍要收到成功结果
    [IMHTTPService.sharedService saveVisibility:level forKind:self.kind token:token ?: @"" completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { if (!error && onSaved) { onSaved(level); } return; }
        self.saving = NO;
        if (error) {
            self.currentLevel = previous; // 失败：✓ 回到原档位
            [self.tableView reloadData];
            [self im_showToast:IMLocalized(@"ps.visibility.save_failed")];
            return;
        }
        if (onSaved) { onSaved(level); }
        [self.navigationController popViewControllerAnimated:YES];
    }];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)IMPrivacyVisibilityLevels().count;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return IMLocalized(IMPrivacyVisibilityFooterKey(self.kind));
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *level = IMPrivacyVisibilityLevels()[indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = IMPrivacyVisibilityTitle(level);
    cell.accessoryType = [level isEqualToString:self.currentLevel] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessibilityIdentifier = [NSString stringWithFormat:@"privacy.visibility.%@", level];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self chooseLevel:IMPrivacyVisibilityLevels()[indexPath.row]];
}

@end
