//  IMShareContactListViewController.m

#import "IMShareContactListViewController.h"
#import "IMShareTargetDirectory.h"
#import "IMShareSelection.h"
#import "IMShareSelectionBar.h"
#import "IMShareTargetCell.h"
#import "IMContactSectionIndex.h"
#import "IMListSearch.h"
#import "IMConversation.h"
#import "IMUserCard.h"
#import "IMLocalization.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"

@interface IMShareContactListViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, weak, readonly) id<IMSharePickerHost> host;
@end

@implementation IMShareContactListViewController {
    IMShareContactListKind _kind;
    IMShareTargetDirectory *_directory;
    UITableView *_tableView;
    UISearchBar *_searchBar;
    UIView *_searchHeader;
    UILabel *_emptyLabel;
    IMShareSelectionBar *_bar;
    IMContactSectionIndex *_friendIndex;    // 好友：当前搜索词下的 A–Z 分组
    NSUInteger _indexGeneration;            // 分组异步构建代号，丢弃过期结果
    NSArray<IMConversation *> *_groups;     // 群：当前搜索词下的可见行
}

- (instancetype)initWithKind:(IMShareContactListKind)kind directory:(IMShareTargetDirectory *)directory
                        host:(id<IMSharePickerHost>)host {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _kind = kind;
        _directory = directory;
        _host = host;
        _groups = @[];
    }
    return self;
}

- (BOOL)isFriends { return _kind == IMShareContactListFriends; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [_tableView registerClass:IMShareTargetCell.class forCellReuseIdentifier:@"target"];
    NSString *ph = IMLocalized([self isFriends] ? @"share.picker.search_friends" : @"share.picker.search_groups");
    _searchBar = IMListSearchBarMake(self.view.bounds.size.width, ph, self);
    _searchHeader = IMListSearchHeaderMake(_searchBar);
    _tableView.tableHeaderView = _searchHeader;
    [self.view addSubview:_tableView];

    _bar = [IMShareSelectionBar new];
    _bar.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) ws = self;
    _bar.onRemove = ^(NSString *convID) { [ws.host shareHostRemoveConvID:convID from:ws]; };
    _bar.onSend = ^{ [ws.host shareHostSendFrom:ws]; };
    [self.view addSubview:_bar];

    _emptyLabel = [UILabel new];
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyLabel.font = [UIFont systemFontOfSize:15];
    _emptyLabel.textColor = IMTheme.textSecondary;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.hidden = YES;
    // 拉取失败时空态文案是「加载失败，点击重试」：点它重新拉（名录失败不算 loaded，loadIfNeeded 会真的重发）。
    _emptyLabel.userInteractionEnabled = YES;
    [_emptyLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(emptyTapped)]];
    [self.view addSubview:_emptyLabel];

    BOOL multi = _host.shareMultiSelect;
    _bar.hidden = !multi;
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:(multi ? _bar.topAnchor : self.view.bottomAnchor)],
        [_bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_bar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:120],
        [_emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:32],
        [_emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-32],
    ]];

    [self selectionDidChangeScrollToEnd:NO];
    [_directory loadIfNeeded:^{ [ws applyFilter]; }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    IMListSearchHeaderSyncWidth(_searchHeader, _tableView);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self selectionDidChangeScrollToEnd:NO]; // 从确认面板删了人回来 / 主页改过：对齐一次
}

- (void)selectionDidChangeScrollToEnd:(BOOL)scrollToEnd {
    if (!self.isViewLoaded) { return; }
    id<IMSharePickerHost> host = _host;
    NSString *title = IMLocalized([self isFriends] ? @"share.picker.my_friends" : @"share.picker.my_groups");
    NSString *sub = host.shareMultiSelect
        ? IMLocalizedFormat(@"share.picker.selected_of_max", (long)host.shareSelection.count, (long)host.shareSelection.limit)
        : nil;
    self.navigationItem.titleView = IMShareTitleView(title, sub);
    if (host.shareMultiSelect) { [_bar reloadWithSelection:host.shareSelection scrollToEnd:scrollToEnd]; }
    for (NSIndexPath *ip in _tableView.indexPathsForVisibleRows) {
        IMShareTargetCell *cell = [_tableView cellForRowAtIndexPath:ip];
        IMConversation *c = [self targetAt:ip];
        if (cell && c) {
            [cell configureWithConversation:c multiSelect:host.shareMultiSelect
                                   selected:[host.shareSelection containsConvID:c.convID]];
        }
    }
}

#pragma mark - 数据

- (void)applyFilter {
    NSString *q = IMListSearchNormalizedQuery(_searchBar.text);
    if ([self isFriends]) {
        NSArray<IMUserCard *> *all = _directory.friendCards;
        NSMutableArray<IMUserCard *> *visible = [NSMutableArray array];
        for (IMUserCard *c in all) {
            // 与选好友页同一搜索口径：显示名 + @句柄 + 内部 ID（不展示但可搜）。
            if (q.length == 0 || IMListSearchMatches(q, @[c.displayName, c.username ?: @"", c.userID ?: @""])) {
                [visible addObject:c];
            }
        }
        NSUInteger generation = ++_indexGeneration;
        __weak typeof(self) ws = self;
        [IMContactSectionIndex buildWithCards:visible completion:^(IMContactSectionIndex *index) {
            __strong typeof(ws) self = ws;
            if (!self || generation != self->_indexGeneration) { return; }
            self->_friendIndex = index;
            [self showEmpty:visible.count == 0 searching:q.length > 0 && all.count > 0];
            [self->_tableView reloadData];
        }];
        return;
    }
    NSMutableArray<IMConversation *> *visible = [NSMutableArray array];
    for (IMConversation *c in _directory.groupTargets) {
        if (q.length == 0 || IMListSearchMatches(q, @[c.displayName])) { [visible addObject:c]; }
    }
    _groups = visible;
    [self showEmpty:visible.count == 0 searching:q.length > 0 && _directory.groupTargets.count > 0];
    [_tableView reloadData];
}

- (BOOL)loadFailed {
    return [self isFriends] ? _directory.friendsFailed : _directory.groupsFailed;
}

- (void)emptyTapped {
    if (![self loadFailed] || _directory.loading) { return; }
    _emptyLabel.hidden = YES;
    __weak typeof(self) ws = self;
    [_directory loadIfNeeded:^{ [ws applyFilter]; }];
}

- (void)showEmpty:(BOOL)empty searching:(BOOL)searching {
    BOOL failed = [self loadFailed];
    NSString *text;
    if (searching) {
        text = IMLocalized([self isFriends] ? @"friend.picker.no_match" : @"forward.picker.no_match");
    } else if (failed) {
        text = IMLocalized(@"share.picker.load_failed_retry");
    } else {
        text = IMLocalized([self isFriends] ? @"share.picker.no_friends" : @"share.picker.no_groups");
    }
    _emptyLabel.text = text;
    _emptyLabel.hidden = !empty;
}

- (nullable IMConversation *)targetAt:(NSIndexPath *)ip {
    if ([self isFriends]) {
        IMUserCard *card = [_friendIndex cardAtSection:ip.section row:ip.row];
        return card ? [_directory targetForFriend:card] : nil;
    }
    return ip.row < (NSInteger)_groups.count ? _groups[ip.row] : nil;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText { [self applyFilter]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self isFriends] ? [_friendIndex numberOfSections] : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self isFriends] ? [_friendIndex numberOfRowsInSection:section] : (NSInteger)_groups.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self isFriends] ? [_friendIndex titleForSection:section] : nil;
}

- (NSArray<NSString *> *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    return ([self isFriends] && _friendIndex.titles.count > 0) ? _friendIndex.titles : nil;
}

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
    return index;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    IMShareTargetCell *cell = [tableView dequeueReusableCellWithIdentifier:@"target" forIndexPath:ip];
    IMConversation *c = [self targetAt:ip];
    id<IMSharePickerHost> host = _host;
    if (c) {
        [cell configureWithConversation:c multiSelect:host.shareMultiSelect
                               selected:[host.shareSelection containsConvID:c.convID]];
    }
    cell.accessoryType = host.shareMultiSelect ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    [_searchBar resignFirstResponder];
    IMConversation *c = [self targetAt:ip];
    if (c) { [_host shareHostDidTapTarget:c from:self]; }
}

@end
