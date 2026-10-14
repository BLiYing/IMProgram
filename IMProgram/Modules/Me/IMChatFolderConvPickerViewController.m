//  IMChatFolderConvPickerViewController.m

#import "IMChatFolderConvPickerViewController.h"
#import "IMChatFolderConvCell.h"
#import "IMConversation.h"
#import "IMLocalization.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"
#import "IMMainTabBarController.h" // im_refreshNavigationBar
#import "IMListSearch.h"

@interface IMChatFolderConvPickerViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@end

@implementation IMChatFolderConvPickerViewController {
    NSArray<IMConversation *> *_all;
    NSArray<IMConversation *> *_filtered;
    NSMutableOrderedSet<NSString *> *_selected;
    NSInteger _maxCount;
    void (^_onDone)(NSArray<NSString *> *);
    UITableView *_tableView;
    UISearchBar *_searchBar;
}

- (instancetype)initWithConversations:(NSArray<IMConversation *> *)conversations
                          selectedIDs:(NSArray<NSString *> *)selectedIDs
                             maxCount:(NSInteger)maxCount
                               onDone:(void (^)(NSArray<NSString *> *))onDone {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _all = [conversations copy];
        _filtered = _all;
        _selected = [NSMutableOrderedSet orderedSetWithArray:selectedIDs ?: @[]];
        _maxCount = maxCount;
        _onDone = [onDone copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"folder.picker.title");
    self.view.backgroundColor = IMTheme.groupedBackground;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:IMLocalized(@"common.cancel")
        style:UIBarButtonItemStylePlain target:self action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:IMLocalized(@"common.done")
        style:UIBarButtonItemStyleDone target:self action:@selector(doneTapped)];
    [self im_refreshNavigationBar];

    _searchBar = [UISearchBar new];
    _searchBar.delegate = self;
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.placeholder = IMLocalized(@"common.search");
    [_searchBar sizeToFit];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.tableHeaderView = _searchBar;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [_tableView registerClass:IMChatFolderConvCell.class forCellReuseIdentifier:@"cell"];
    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)cancelTapped { [self.presentingViewController ?: self.navigationController dismissViewControllerAnimated:YES completion:nil]; }

- (void)doneTapped {
    // 按 _all 的顺序回传（与会话列表同序），保持文件夹内展示稳定。
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (IMConversation *c in _all) {
        if ([_selected containsObject:c.convID]) { [out addObject:c.convID]; }
    }
    // 选中集里有不在 _all 中的 id（会话已隐藏 / 已不可见）：原样保留，免得「完成」把它们误移出。
    for (NSString *id_ in _selected) {
        if (![out containsObject:id_]) { [out addObject:id_]; }
    }
    void (^done)(NSArray<NSString *> *) = _onDone;
    [self.presentingViewController ?: self.navigationController dismissViewControllerAnimated:YES completion:^{
        if (done) { done(out); }
    }];
}

#pragma mark - 搜索

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    NSString *q = IMListSearchNormalizedQuery(text);
    if (q.length == 0) { _filtered = _all; }
    else {
        NSMutableArray<IMConversation *> *out = [NSMutableArray array];
        for (IMConversation *c in _all) {
            if (IMListSearchMatches(q, @[c.displayName ?: @"", c.peer ?: @""])) { [out addObject:c]; }
        }
        _filtered = out;
    }
    [_tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

#pragma mark - 表格

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)_filtered.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    IMChatFolderConvCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];
    IMConversation *c = _filtered[(NSUInteger)ip.row];
    [cell configureWithConversation:c checked:@([_selected containsObject:c.convID])];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    NSString *cid = _filtered[(NSUInteger)ip.row].convID;
    if ([_selected containsObject:cid]) { [_selected removeObject:cid]; }
    else {
        if (_maxCount > 0 && (NSInteger)_selected.count >= _maxCount) {
            [self im_showToast:IMLocalized(@"err.300302")];
            return;
        }
        [_selected addObject:cid];
    }
    [tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}

@end
