//  IMDirectorySearchViewController.m

#import "IMDirectorySearchViewController.h"
#import "IMContactCells.h"
#import "IMDirectoryViewController.h"
#import "IMHTTPService.h"
#import "IMHTTPService+Directory.h"
#import "IMGroupNameDefault.h"
#import "IMJSONValue.h"
#import "NSObject+IMCoalescedPerform.h"
#import "IMLocalization.h"
#import "IMLog.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"

static const NSTimeInterval kIMDirSearchDebounce = 0.3;
static const NSUInteger kIMDirSearchMaxLen = 32;
static NSString * const kIMDirSearchCell = @"member";

NSString *IMDirectorySearchQuery(NSString *raw) {
    NSString *q = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (q.length == 0) { return nil; }
    // 按 Unicode 码点数（与服务端 utf8.RuneCountInString 同口径），不按 UTF-16 码元也不按字素簇。
    return IMGroupNameRuneLength(q) > kIMDirSearchMaxLen ? nil : q;
}

@interface IMDirectorySearchViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSArray<NSDictionary *> *results;
@property (nonatomic, copy, nullable) NSString *pendingQuery; // 防抖中的查询；回来的结果不是它就丢掉
@end

@implementation IMDirectorySearchViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _host = [host copy]; _userID = [userID copy]; _results = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = IMTheme.groupedBackground;
    UISearchBar *bar = [UISearchBar new];
    bar.placeholder = IMLocalized(@"org.search.placeholder");
    bar.delegate = self;
    bar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar = bar;
    self.navigationItem.titleView = bar;

    UITableView *tv = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.dataSource = self; tv.delegate = self;
    tv.backgroundColor = IMTheme.groupedBackground;
    tv.rowHeight = 64;
    tv.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [tv registerClass:IMContactCell.class forCellReuseIdentifier:kIMDirSearchCell];
    self.tableView = tv;
    [self.view addSubview:tv];

    UILabel *empty = [UILabel new];
    empty.text = IMLocalized(@"org.search.no_results");
    empty.font = [UIFont systemFontOfSize:15];
    empty.textColor = IMTheme.textSecondary;
    empty.textAlignment = NSTextAlignmentCenter;
    empty.hidden = YES;
    self.emptyLabel = empty;
    tv.backgroundView = empty;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.results.count == 0) { [self.searchBar becomeFirstResponder]; }
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.pendingQuery = IMDirectorySearchQuery(searchText);
    if (!self.pendingQuery) {
        [self im_cancelCoalescedPerform:@selector(runSearch)];
        self.results = @[];
        self.emptyLabel.hidden = YES;
        [self.tableView reloadData];
        return;
    }
    [self im_coalescedPerform:@selector(runSearch) afterDelay:kIMDirSearchDebounce];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

- (void)runSearch {
    NSString *q = self.pendingQuery;
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (q.length == 0 || token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService directorySearchWithToken:token query:q completion:^(NSDictionary *data, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || ![q isEqualToString:self.pendingQuery]) { return; } // 已经改了关键字：旧结果作废
        if (error) {
            IMLogWarnWithTag(IMLogTagHTTP, @"directory_search_failed code=%ld", (long)error.code);
            // 失败不当成「没找到」：保留上一次结果、吐司说明原因（断网 / 5xx 时用户才不会以为查无此人）。
            [self im_showToast:error.localizedDescription ?: IMLocalized(@"common.search_failed")];
            return;
        } else {
            self.results = IMJSONDicts(data[@"members"]);
        }
        self.emptyLabel.hidden = self.results.count > 0;
        [self.tableView reloadData];
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.results.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *m = self.results[indexPath.row];
    IMContactCell *cell = [tableView dequeueReusableCellWithIdentifier:kIMDirSearchCell forIndexPath:indexPath];
    IMDirectoryConfigureMemberCell(cell, m, IMJSONString(m[@"unit_label"]));
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.navigationController pushViewController:IMDirectoryProfileController(self.host, self.userID, self.results[indexPath.row])
                                         animated:YES];
}

@end
