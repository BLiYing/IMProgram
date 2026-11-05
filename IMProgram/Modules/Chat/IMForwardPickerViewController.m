//  IMForwardPickerViewController.m

#import "IMForwardPickerViewController.h"
#import "IMHTTPService.h"
#import "IMSocketManager.h"
#import "IMConversation.h"
#import "IMUserCard.h"
#import "IMAccountIdentity.h"
#import "IMListSearch.h"
#import "IMShareSelection.h"
#import "IMShareSelectionBar.h"
#import "IMShareTargetCell.h"
#import "IMShareTargetDirectory.h"
#import "IMShareConfirmViewController.h"
#import "IMShareContactListViewController.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import "IMLocalization.h"

static const NSUInteger kIMForwardMaxSelection = 9;

/// 表格分组。无搜索词：入口 + 最近聊天；有搜索词：最近聊天 / 好友 / 群聊（空组不出现）。
typedef NS_ENUM(NSInteger, IMForwardSectionKind) {
    IMForwardSectionEntries,
    IMForwardSectionRecent,
    IMForwardSectionFriends,
    IMForwardSectionGroups,
};

@interface IMForwardPickerViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, IMSharePickerHost>
@end

@implementation IMForwardPickerViewController {
    NSString *_host;
    NSString *_token;
    void (^_onDone)(NSArray<IMConversation *> *);
    NSArray<IMConversation *> *_convs;
    IMShareSelection *_selection;               // 三页共用的选中集（按 conv_id，存会话对象：搜完再搜也不丢已选）
    IMShareTargetDirectory *_directory;         // 好友 + 我的群（showsContactEntries 时才建）
    NSArray<NSNumber *> *_sectionKinds;         // 当前可见分组（IMForwardSectionKind）
    NSArray<IMConversation *> *_recentRows;     // 当前搜索词下的最近聊天
    NSArray<IMConversation *> *_friendRows;     // 搜索时：命中且不在 _recentRows 里的好友
    NSArray<IMConversation *> *_groupRows;      // 搜索时：命中且不在 _recentRows 里的群
    BOOL _multiSelect;
    BOOL _convsLoaded;
    UITableView *_tableView;
    UISearchBar *_searchBar;
    UIView *_searchHeader;   // 托住 _searchBar 的表头容器（宽度随表格实时对齐）
    UILabel *_emptyLabel;
    IMShareSelectionBar *_bar;
    NSLayoutConstraint *_tableBottomToView;
    NSLayoutConstraint *_tableBottomToBar;
}

- (instancetype)initWithHost:(NSString *)host token:(NSString *)token onDone:(void (^)(NSArray<IMConversation *> *))onDone {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _host = [host copy];
        _token = [token copy];
        _onDone = [onDone copy];
        _selection = [[IMShareSelection alloc] initWithLimit:kIMForwardMaxSelection];
        _showsContactEntries = YES;
        _convs = @[];
        _recentRows = @[];
        _friendRows = @[];
        _groupRows = @[];
        _sectionKinds = @[];
    }
    return self;
}

/// 入口真正生效的条件：调用方没关，且拿得到本人 uid（好友 conv_id 要靠它推导）。
- (NSString *)resolvedSelfUID {
    return self.selfUID.length > 0 ? self.selfUID : (IMSocketManager.sharedManager.userID ?: @"");
}

- (BOOL)entriesEnabled {
    return self.showsContactEntries && [self resolvedSelfUID].length > 0;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTapped)];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [_tableView registerClass:IMShareTargetCell.class forCellReuseIdentifier:@"conv"];
    [_tableView registerClass:IMShareEntryCell.class forCellReuseIdentifier:@"entry"];

    // 搜索框（会话多了以后必需）：外观与匹配口径走 IMListSearch，与选好友页/@面板同一套。
    // 放 tableHeaderView 而非 UISearchController：本页是 modal + 自带导航栏，
    // UISearchController 会再叠一层导航态，交互与「取消/多选」两个 bar button 打架。
    _searchBar = IMListSearchBarMake(self.view.bounds.size.width, IMLocalized(@"forward.picker.search_placeholder"), self);
    _searchHeader = IMListSearchHeaderMake(_searchBar);
    _tableView.tableHeaderView = _searchHeader;
    [self.view addSubview:_tableView];

    // 多选态底部已选栏（单选态隐藏、表格贴底）。
    _bar = [IMShareSelectionBar new];
    _bar.translatesAutoresizingMaskIntoConstraints = NO;
    _bar.hidden = YES;
    __weak typeof(self) ws = self;
    _bar.onRemove = ^(NSString *convID) { [ws shareHostRemoveConvID:convID from:ws]; };
    _bar.onSend = ^{ [ws shareHostSendFrom:ws]; };
    [self.view addSubview:_bar];

    _emptyLabel = [UILabel new];
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyLabel.font = [UIFont systemFontOfSize:15];
    _emptyLabel.textColor = IMTheme.textSecondary;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.hidden = YES;
    [self.view addSubview:_emptyLabel];

    _tableBottomToView = [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    _tableBottomToBar = [_tableView.bottomAnchor constraintEqualToAnchor:_bar.topAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        _tableBottomToView,
        [_bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_bar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:120],
        [_emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:IMTheme.space4 * 2],
        [_emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-IMTheme.space4 * 2],
    ]];

    [self updateChrome];
    [self applyFilter];
    [self loadConversations];
    if ([self entriesEnabled]) {
        _directory = [[IMShareTargetDirectory alloc] initWithToken:_token selfUID:[self resolvedSelfUID]
                                                      excludedUserIDs:self.excludedUserIDs
                                                      excludedConvIDs:self.excludedConvIDs];
        // 预取：搜索时好友 / 群分组要用，进子页也能秒开。失败不吐司（子页显示「加载失败，点击重试」，点了重拉）。
        [_directory loadIfNeeded:^{
            __strong typeof(ws) self = ws;
            if (self && IMListSearchNormalizedQuery(self->_searchBar.text).length > 0) { [self applyFilter]; }
        }];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    IMListSearchHeaderSyncWidth(_searchHeader, _tableView); // 表头宽度对齐表格（宽度没变即空转）
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 从子页返回：那边勾 / 取消过的要在这里同步出来。
    if (_multiSelect) { [self selectionDidChangeScrollToEnd:NO]; }
}

- (void)loadConversations {
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService conversationsWithToken:_token completion:^(NSArray<IMConversation *> *convs, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) {
            [self im_showToast:IMLocalized(@"forward.picker.load_failed")];
            [self applyFilter];
            return;
        }
        // 剔除「系统通知」单聊：那是只读会话，服务端直接拒 send_msg to=system（护栏见
        // IMServer/docs/design/SYSTEM_NOTICE_SESSION_DESIGN.md §2.2），列出来只会点了报错。
        // 群聊不看 peer（群会话的 peer 无意义），故先判 isGroup。**该剔除始终生效**，与 extraFilter 无关。
        NSMutableArray<IMConversation *> *forwardable = [NSMutableArray arrayWithCapacity:convs.count];
        for (IMConversation *c in convs) {
            if (!c.isGroup && IMIsSystemUserID(c.peer)) { continue; }
            if (!c.isGroup && c.peer.length > 0 && [self.excludedUserIDs containsObject:c.peer]) { continue; }
            if (c.convID.length > 0 && [self.excludedConvIDs containsObject:c.convID]) { continue; }
            if (self.extraFilter && !self.extraFilter(c)) { continue; }
            [forwardable addObject:c];
        }
        // 零会话：有好友 / 群入口时照常展示入口（这正是要补的场景）；没有入口的旧调用方保持原行为——
        // 没设 emptyText 就 toast，不留一个空表格在那儿。
        if (forwardable.count == 0 && self.emptyText.length == 0 && ![self entriesEnabled]) {
            [self im_showToast:IMLocalized(@"forward.picker.no_conversations")];
            return;
        }
        self->_convs = forwardable;
        self->_convsLoaded = YES; // 只在成功后置位：加载失败时不显示「没有可选会话」空态（那是误导，失败已吐司）
        [self applyFilter];
    }];
}

#pragma mark - 搜索 / 分组

/// 重算可见行。会话匹配显示名（会话备注 > 好友备注 > 昵称 > 群名）与单聊对端 uid，大小写不敏感。
/// 备注参与匹配是安全的：转发选择页只在本机显示，选中后发出去的是消息本身，不含任何名字。
/// 有搜索词且开了入口时，再搜好友（显示名 / @句柄 / uid）与群（显示名），按 conv_id 剔除已在最近聊天里命中的。
- (void)applyFilter {
    NSString *q = IMListSearchNormalizedQuery(_searchBar.text);
    NSMutableArray<IMConversation *> *recent = [NSMutableArray array];
    for (IMConversation *c in _convs) {
        // 只有显示名 + 内部 ID（兜底，不展示）。**这里没有 @句柄维度**：会话列表接口刻意不下发 username
        // （见 IMServer/docs/ACCOUNT_IDENTITY_REDESIGN.md §7.4）。好友分组里有句柄维度。
        if (q.length == 0 || IMListSearchMatches(q, @[c.displayName, c.peer ?: @""])) { [recent addObject:c]; }
    }
    _recentRows = recent;
    _friendRows = @[];
    _groupRows = @[];
    BOOL entries = [self entriesEnabled];
    if (q.length > 0 && entries && _directory) {
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        for (IMConversation *c in recent) { if (c.convID.length) { [seen addObject:c.convID]; } }
        NSMutableArray<IMConversation *> *friends = [NSMutableArray array];
        for (IMUserCard *card in _directory.friendCards) {
            if (!IMListSearchMatches(q, @[card.displayName, card.username ?: @"", card.userID ?: @""])) { continue; }
            IMConversation *t = [_directory targetForFriend:card];
            if (t) { [friends addObject:t]; }
        }
        _friendRows = [IMShareSelection conversations:friends excludingConvIDs:seen];
        NSMutableArray<IMConversation *> *groups = [NSMutableArray array];
        for (IMConversation *g in _directory.groupTargets) {
            if (IMListSearchMatches(q, @[g.displayName])) { [groups addObject:g]; }
        }
        _groupRows = [IMShareSelection conversations:groups excludingConvIDs:seen];
    }

    NSMutableArray<NSNumber *> *kinds = [NSMutableArray array];
    if (q.length == 0 && entries) { [kinds addObject:@(IMForwardSectionEntries)]; }
    // 无入口（添加例外页）时最近聊天恒为唯一一组，空也保留：它的表尾脚注（footerText）要照常显示。
    if (_recentRows.count > 0 || !entries) { [kinds addObject:@(IMForwardSectionRecent)]; }
    if (_friendRows.count > 0) { [kinds addObject:@(IMForwardSectionFriends)]; }
    if (_groupRows.count > 0) { [kinds addObject:@(IMForwardSectionGroups)]; }
    _sectionKinds = kinds;

    BOOL noRows = _recentRows.count == 0 && _friendRows.count == 0 && _groupRows.count == 0;
    if (q.length > 0) {
        _emptyLabel.text = IMLocalized(@"forward.picker.no_match");
        _emptyLabel.hidden = !noRows;
    } else {
        // 无搜索词：入口行在时不显示空态（入口本身就是去处）；emptyText 调用方（添加例外）零会话显示空态。
        _emptyLabel.text = self.emptyText;
        _emptyLabel.hidden = !(noRows && !entries && self.emptyText.length > 0 && _convsLoaded);
    }
    [_tableView reloadData];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self applyFilter];
    // 预取失败过：搜索时再试一次。在途时不再排队——viewDidLoad 那次的回调在有搜索词时已会重算，
    // 否则每敲一个字就多挂一个 waiter，回来时重复 reloadData。
    if (IMListSearchNormalizedQuery(searchText).length > 0 && _directory && !_directory.loaded && !_directory.loading) {
        __weak typeof(self) ws = self;
        [_directory loadIfNeeded:^{ [ws applyFilter]; }];
    }
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

#pragma mark - 单选 / 多选切换

- (NSString *)baseTitle {
    return self.titleOverride.length > 0 ? self.titleOverride : IMLocalized(@"forward.picker.destination_title");
}

/// 标题（多选态带「已选 N/9」副标题）、右上按钮、底部已选栏显隐。
- (void)updateChrome {
    NSString *sub = _multiSelect
        ? IMLocalizedFormat(@"share.picker.selected_of_max", (long)_selection.count, (long)_selection.limit) : nil;
    self.title = [self baseTitle];
    self.navigationItem.titleView = IMShareTitleView([self baseTitle], sub);
    if (_multiSelect || self.immediateSingleSelect) {
        self.navigationItem.rightBarButtonItem = nil; // 多选：发送在底部已选栏；立即模式：点一行即选定
    } else {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:IMLocalized(@"forward.picker.multi") style:UIBarButtonItemStylePlain
                                            target:self action:@selector(enterMultiSelect)];
    }
    _bar.hidden = !_multiSelect;
    _tableBottomToView.active = !_multiSelect;
    _tableBottomToBar.active = _multiSelect;
}

- (void)enterMultiSelect {
    _multiSelect = YES;
    [self updateChrome];
    [_bar reloadWithSelection:_selection scrollToEnd:NO];
    [_tableView reloadData];
}

- (void)cancelTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

/// 选中集变了：本页标题 / 栏 / 可见行勾选，以及栈顶子页（若有）一起刷。
- (void)selectionDidChangeScrollToEnd:(BOOL)scrollToEnd {
    [self updateChrome];
    [_bar reloadWithSelection:_selection scrollToEnd:scrollToEnd];
    for (NSIndexPath *ip in _tableView.indexPathsForVisibleRows) {
        IMConversation *c = [self conversationAt:ip];
        IMShareTargetCell *cell = (IMShareTargetCell *)[_tableView cellForRowAtIndexPath:ip];
        if (c && [cell isKindOfClass:IMShareTargetCell.class]) {
            [cell configureWithConversation:c multiSelect:_multiSelect selected:[_selection containsConvID:c.convID]];
        }
    }
    UIViewController *top = self.navigationController.topViewController;
    if ([top isKindOfClass:IMShareContactListViewController.class]) {
        [(IMShareContactListViewController *)top selectionDidChangeScrollToEnd:scrollToEnd];
    }
}

/// 交回选中会话并收起整个选择页（含子页）。
- (void)finishWith:(NSArray<IMConversation *> *)result {
    void (^done)(NSArray<IMConversation *> *) = _onDone;
    [self dismissViewControllerAnimated:YES completion:^{ if (done) { done(result); } }];
}

#pragma mark - IMSharePickerHost

- (IMShareSelection *)shareSelection { return _selection; }
- (BOOL)shareMultiSelect { return _multiSelect; }

- (void)shareHostDidTapTarget:(IMConversation *)c from:(UIViewController *)presenter {
    if (!_multiSelect && self.immediateSingleSelect) { // 单选·立即模式：不弹确认，选中即回调（§2）
        [self finishWith:@[c]];
        return;
    }
    if (!_multiSelect) { // 单选：确认后立即回调
        __weak typeof(self) ws = self;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:IMLocalized(@"common.forward")
            message:IMLocalizedFormat(@"forward.picker.confirm_single", c.displayName)
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.send") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [ws finishWith:@[c]];
        }]];
        [presenter presentViewController:a animated:YES completion:nil];
        return;
    }
    // 多选：切换选中，三处合计上限 9；满了不置灰，点了吐司。
    IMShareToggleResult r = [_selection toggle:c];
    if (r == IMShareToggleCapped) {
        [presenter im_showToast:IMLocalizedFormat(@"forward.picker.max_selection", (long)kIMForwardMaxSelection)];
        return;
    }
    if (r == IMShareToggleInvalid) { return; }
    [self selectionDidChangeScrollToEnd:(r == IMShareToggleAdded)];
}

- (void)shareHostRemoveConvID:(NSString *)convID from:(UIViewController *)presenter {
    if ([_selection removeConvID:convID]) { [self selectionDidChangeScrollToEnd:NO]; }
}

- (void)shareHostSendFrom:(UIViewController *)presenter {
    if (_selection.count == 0) { return; }
    IMShareConfirmViewController *confirm = [[IMShareConfirmViewController alloc] initWithSelection:_selection
                                                                                       previewText:self.previewText];
    __weak typeof(self) ws = self;
    confirm.onRemove = ^(NSString *convID) { [ws shareHostRemoveConvID:convID from:ws]; };
    confirm.onConfirm = ^{
        __strong typeof(ws) self = ws;
        if (!self || self->_selection.count == 0) { return; }
        [self finishWith:self->_selection.conversations];
    };
    [presenter presentViewController:confirm animated:YES completion:nil];
}

#pragma mark - 展示

- (IMForwardSectionKind)kindAt:(NSInteger)section {
    return (IMForwardSectionKind)_sectionKinds[(NSUInteger)section].integerValue;
}

- (NSArray<IMConversation *> *)rowsFor:(IMForwardSectionKind)kind {
    switch (kind) {
        case IMForwardSectionRecent: return _recentRows;
        case IMForwardSectionFriends: return _friendRows;
        case IMForwardSectionGroups: return _groupRows;
        case IMForwardSectionEntries: return @[];
    }
    return @[];
}

- (nullable IMConversation *)conversationAt:(NSIndexPath *)ip {
    if (ip.section >= (NSInteger)_sectionKinds.count) { return nil; }
    NSArray<IMConversation *> *rows = [self rowsFor:[self kindAt:ip.section]];
    return ip.row < (NSInteger)rows.count ? rows[ip.row] : nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return (NSInteger)_sectionKinds.count; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    IMForwardSectionKind kind = [self kindAt:section];
    return kind == IMForwardSectionEntries ? 2 : (NSInteger)[self rowsFor:kind].count;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch ([self kindAt:section]) {
        case IMForwardSectionEntries: return nil;
        // 无入口（添加例外页）时只有这一组，不加标题，保持原样。
        case IMForwardSectionRecent: return [self entriesEnabled] ? IMLocalized(@"share.picker.recent") : nil;
        case IMForwardSectionFriends: return IMLocalized(@"share.picker.section_friends");
        case IMForwardSectionGroups: return IMLocalized(@"share.picker.section_groups");
    }
    return nil;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == (NSInteger)_sectionKinds.count - 1 ? self.footerText : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    if ([self kindAt:ip.section] == IMForwardSectionEntries) {
        IMShareEntryCell *cell = [tableView dequeueReusableCellWithIdentifier:@"entry" forIndexPath:ip];
        if (ip.row == 0) {
            [cell configureWithTitle:IMLocalized(@"share.picker.my_friends") symbol:@"person.fill" tint:IMTheme.accent];
        } else {
            [cell configureWithTitle:IMLocalized(@"share.picker.my_groups") symbol:@"person.2.fill" tint:IMTheme.checkRead];
        }
        return cell;
    }
    IMShareTargetCell *cell = [tableView dequeueReusableCellWithIdentifier:@"conv" forIndexPath:ip];
    IMConversation *c = [self conversationAt:ip];
    if (c) { [cell configureWithConversation:c multiSelect:_multiSelect selected:[_selection containsConvID:c.convID]]; }
    // 多选态：选中态由行首圆圈承载，不再挂尾部系统 ✓；单选态保留 disclosure「>」。
    cell.accessoryType = _multiSelect ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    [_searchBar resignFirstResponder];
    if ([self kindAt:ip.section] == IMForwardSectionEntries) {
        if (!_directory) { return; }
        IMShareContactListKind kind = ip.row == 0 ? IMShareContactListFriends : IMShareContactListGroups;
        IMShareContactListViewController *vc = [[IMShareContactListViewController alloc] initWithKind:kind
                                                                                            directory:_directory
                                                                                                 host:self];
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }
    IMConversation *c = [self conversationAt:ip];
    if (c) { [self shareHostDidTapTarget:c from:self]; }
}

@end
