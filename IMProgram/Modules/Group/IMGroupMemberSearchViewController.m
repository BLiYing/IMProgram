//
//  IMGroupMemberSearchViewController.m
//  群成员搜索页。设计与落点理由见 .h。
//
//  **恒走服务端 `?q=`，不做本地过滤**：超级群本地只有「已翻到的那几页」（2 万人群里通常就 50 个），
//  拿它过滤 = 在 50 人里搜 2 万人，界面看着正常、结果悄悄是错的。普通群 group.members 虽然是全的
//  也不走第二套口径——两套迟早分叉，而分叉那天没人会发现。
//
#import "IMGroupMemberSearchViewController.h"
#import "IMGroupInfo.h"
#import "IMHTTPService.h"
#import "IMTheme.h"
#import "IMGlass.h"                 // IMApplyUnifiedSearchFieldStyle
#import "IMRemarkStore.h"
#import "UILabel+IMAvatar.h"
#import "IMMainTabBarController.h"  // kIMLiquidBarHeight
#import "IMProgram-Swift.h"         // IMLiquidNavigationBar
#import "UIViewController+IMToast.h"

const NSInteger kIMMemberSearchMinMembers = 50;

BOOL IMShouldOfferMemberSearch(IMGroupInfo *group) {
    if (!group) { return NO; }
    NSInteger total = group.memberCount > 0 ? group.memberCount : (NSInteger)group.members.count;
    return total > kIMMemberSearchMinMembers;
}

/// 每页条数。结果本身也可能很长（搜 "big" 能命中几千人），所以结果也要翻页。
static const NSInteger kIMMemberSearchPageSize = 50;
/// 输入到发请求之间的静默期。与 @人选择器同口径，别各调各的。
static const NSTimeInterval kIMMemberSearchDebounce = 0.3;

#pragma mark - 结果行

@interface IMMemberSearchRowCell : UITableViewCell
- (void)configureWithMember:(IMGroupMember *)member highlight:(NSString *)needle;
@end

@implementation IMMemberSearchRowCell {
    UILabel *_avatar;
    UILabel *_name;
    UILabel *_sub;
    UILabel *_badge;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _avatar.textColor = UIColor.whiteColor;
        _avatar.layer.cornerRadius = 18;
        _avatar.layer.masksToBounds = YES;
        [self.contentView addSubview:_avatar];

        _name = [UILabel new];
        _name.translatesAutoresizingMaskIntoConstraints = NO;
        _name.font = [UIFont systemFontOfSize:16];
        _name.textColor = IMTheme.textPrimary;
        [self.contentView addSubview:_name];

        _sub = [UILabel new];
        _sub.translatesAutoresizingMaskIntoConstraints = NO;
        _sub.font = [UIFont systemFontOfSize:12];
        _sub.textColor = IMTheme.textSecondary;
        [self.contentView addSubview:_sub];

        _badge = [UILabel new];
        _badge.translatesAutoresizingMaskIntoConstraints = NO;
        _badge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _badge.textAlignment = NSTextAlignmentCenter;
        _badge.layer.cornerRadius = 8;
        _badge.layer.masksToBounds = YES;
        [self.contentView addSubview:_badge];
        [_badge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_badge setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        UILayoutGuide *g = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
            [_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:36],
            [_avatar.heightAnchor constraintEqualToConstant:36],
            [_name.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:12],
            [_name.topAnchor constraintEqualToAnchor:_avatar.topAnchor],
            [_name.trailingAnchor constraintLessThanOrEqualToAnchor:_badge.leadingAnchor constant:-8],
            [_sub.leadingAnchor constraintEqualToAnchor:_name.leadingAnchor],
            [_sub.topAnchor constraintEqualToAnchor:_name.bottomAnchor constant:2],
            [_sub.trailingAnchor constraintLessThanOrEqualToAnchor:_badge.leadingAnchor constant:-8],
            [_badge.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_badge.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_badge.heightAnchor constraintEqualToConstant:20],
            [_badge.widthAnchor constraintGreaterThanOrEqualToConstant:44],
            [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:60],
        ]];
    }
    return self;
}

/// 把 needle 在 text 里的**首个**命中段染成主题色。大小写不敏感（与服务端 LIKE 同口径）。
static NSAttributedString *IMHighlighted(NSString *text, NSString *needle, UIColor *color) {
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] initWithString:text ?: @""];
    if (needle.length == 0 || text.length == 0) { return out; }
    NSRange r = [text rangeOfString:needle options:NSCaseInsensitiveSearch];
    if (r.location != NSNotFound) {
        [out addAttribute:NSForegroundColorAttributeName value:color range:r];
    }
    return out;
}

- (void)configureWithMember:(IMGroupMember *)member highlight:(NSString *)needle {
    NSString *shown = member.localDisplayName; // 备注优先（仅本机显示）
    [_avatar im_setAvatarURL:member.avatarURL seed:member.userID displayName:shown];
    _name.attributedText = IMHighlighted(shown, needle, IMTheme.accent);
    // 副行是**句柄**而非 user_id：后者是 10 位随机内部 ID，界面上从不显示
    // （docs/design/ACCOUNT_IDENTITY_REDESIGN.md §5.2）。它也正是服务端 ?q= 的匹配源之一。
    NSString *handle = member.username.length > 0 ? [@"@" stringByAppendingString:member.username] : @"";
    _sub.attributedText = IMHighlighted(handle, needle, IMTheme.accent);
    switch (member.role) {
        case IMGroupRoleOwner:
            _badge.hidden = NO; _badge.text = @"群主";
            _badge.textColor = IMTheme.accent;
            _badge.backgroundColor = [IMTheme.accent colorWithAlphaComponent:0.15];
            break;
        case IMGroupRoleAdmin:
            _badge.hidden = NO; _badge.text = @"管理员";
            _badge.textColor = IMTheme.textSecondary;
            _badge.backgroundColor = UIColor.secondarySystemFillColor;
            break;
        default:
            _badge.hidden = YES; _badge.text = @"";
            break;
    }
}

@end

#pragma mark - 搜索页

@interface IMGroupMemberSearchViewController () <UITableViewDataSource, UITableViewDelegate,
                                                 UISearchBarDelegate, IMLiquidNavigationBarDelegate>
@end

@implementation IMGroupMemberSearchViewController {
    IMGroupInfo *_group;
    NSString *_convID;
    void (^_onPickMember)(IMGroupMember *);

    UISearchBar *_searchBar;
    UITableView *_tableView;
    UILabel *_emptyLabel;

    NSMutableArray<IMGroupMember *> *_results;
    NSString *_needle;      ///< 当前**已生效**的搜索词（结果对应的那个，不是输入框里的）
    NSString *_nextCursor;
    BOOL _hasMore;
    BOOL _loading;
    BOOL _failed;
    /// 去抖 + **丢弃过期响应**。快速打字时请求会后发先至，不校验的话结果会闪回上一个词的答案
    /// （@人选择器早就有这套，这里同源）。
    int64_t _searchToken;
}

- (instancetype)initWithGroup:(IMGroupInfo *)group
                 onPickMember:(void (^)(IMGroupMember *))onPickMember {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _group = group;
        _convID = group.convID ?: @"";
        _onPickMember = [onPickMember copy];
        _results = [NSMutableArray array];
        _needle = @"";
        _nextCursor = @"";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"搜索成员";
    self.view.backgroundColor = IMTheme.groupedBackground;

    _searchBar = [UISearchBar new];
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    _searchBar.placeholder = @"搜索成员";
    _searchBar.delegate = self;
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    // 搜的是句柄（^[a-z0-9_]{5,32}$）：不关自动大写，键盘会把首字母顶成 "Big2m0991"。
    // 服务端 LIKE 恰好大小写不敏感所以还搜得到，但输入框里显示的那个词本身就不对。
    _searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    IMApplyUnifiedSearchFieldStyle(_searchBar);
    [self.view addSubview:_searchBar];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = IMTheme.groupedBackground;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [_tableView registerClass:IMMemberSearchRowCell.class forCellReuseIdentifier:@"member"];
    [_tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"plain"];
    [self.view addSubview:_tableView];

    _emptyLabel = [UILabel new];
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyLabel.font = [UIFont systemFontOfSize:14];
    _emptyLabel.textColor = IMTheme.textSecondary;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.text = [NSString stringWithFormat:@"在 %ld 位成员里搜索", (long)[self totalMembers]];
    [self.view addSubview:_emptyLabel];

    [self installLiquidNavigationBar];

    [NSLayoutConstraint activateConstraints:@[
        [_searchBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [_searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [_tableView.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor constant:4],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyLabel.topAnchor constraintEqualToAnchor:_tableView.topAnchor constant:40],
        [_emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24],
        [_emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24],
    ]];
    [self refreshEmptyState];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // 进来就是干这件事的，直接弹键盘——省掉"还得先点一下搜索框"这一步。
    [_searchBar becomeFirstResponder];
}

/// 群总人数。**不能用 group.members.count**：超级群那里只有我自己，会显示成「在 1 位成员里搜索」。
- (NSInteger)totalMembers {
    return _group.memberCount > 0 ? _group.memberCount : (NSInteger)_group.members.count;
}

- (void)installLiquidNavigationBar {
    UIEdgeInsets insets = self.additionalSafeAreaInsets;
    insets.top = kIMLiquidBarHeight;
    self.additionalSafeAreaInsets = insets;

    IMLiquidNavigationBar *bar = [[IMLiquidNavigationBar alloc] initWithTitle:self.title subtitle:@"" actionTitle:nil];
    bar.delegate = self;
    bar.hostExtraTopInset = kIMLiquidBarHeight;
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:kIMLiquidBarHeight],
    ]];
}

- (void)liquidNavigationBarDidTapBack:(IMLiquidNavigationBar *)bar { [self goBack]; }
- (void)liquidNavigationBarDidTapLeft:(IMLiquidNavigationBar *)bar { [self goBack]; }
- (void)liquidNavigationBarDidTapAction:(IMLiquidNavigationBar *)bar { /* 本页无右侧动作 */ }
- (void)goBack {
    [_searchBar resignFirstResponder];
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - 搜索

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    NSString *q = [searchText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    int64_t myToken = ++_searchToken; // 自增即作废所有在途响应
    if (q.length == 0) {
        // 清空回初始态：结果清掉、提示改回「在 N 位成员里搜索」。
        [_results removeAllObjects];
        _needle = @"";
        _nextCursor = @"";
        _hasMore = NO;
        _loading = NO;
        _failed = NO;
        [_tableView reloadData];
        [self refreshEmptyState];
        return;
    }
    _loading = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kIMMemberSearchDebounce * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || myToken != self->_searchToken) { return; } // 去抖：期间又打字了
        [self fetchPageWithQuery:q cursor:nil token:myToken];
    });
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

/// 拉一页结果。cursor 为空 = 首页（替换），非空 = 续页（追加）。
- (void)fetchPageWithQuery:(NSString *)q cursor:(NSString *)cursor token:(int64_t)myToken {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0 || _convID.length == 0) { _loading = NO; return; }
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService groupMembersPageWithToken:token convID:_convID
                                                    cursor:cursor limit:kIMMemberSearchPageSize query:q
                                                completion:^(NSArray<IMGroupMember *> *members,
                                                             NSString *nextCursor, BOOL hasMore, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || myToken != self->_searchToken) { return; } // 过期响应，丢弃
        self->_loading = NO;
        if (error) {
            // **保留上一次结果**，不要清空成「没有匹配」——清空会让用户以为查无此人，
            // 而不是网断了。这两件事必须能分辨。
            self->_failed = YES;
            self->_hasMore = NO; // 否则「加载更多结果」变成点不完的死循环
            [self->_tableView reloadData];
            [self refreshEmptyState];
            [self im_showToast:error.localizedDescription ?: @"搜索失败"];
            return;
        }
        self->_failed = NO;
        self->_needle = q;
        if (cursor.length == 0) { [self->_results removeAllObjects]; }
        // 按 userID 去重再追加：keyset 游标翻页期间有人进群/退群，相邻两页可能覆盖同一个人。
        NSMutableSet<NSString *> *seen = [NSMutableSet setWithCapacity:self->_results.count];
        for (IMGroupMember *m in self->_results) { if (m.userID) { [seen addObject:m.userID]; } }
        for (IMGroupMember *m in members) {
            if (m.userID.length > 0 && [seen containsObject:m.userID]) { continue; }
            if (m.userID) { [seen addObject:m.userID]; }
            [self->_results addObject:m];
        }
        self->_nextCursor = nextCursor ?: @"";
        // has_more 为真但这页一个人都没回时也要停：否则服务端异常时永远点不完。
        self->_hasMore = hasMore && members.count > 0;
        [self->_tableView reloadData];
        [self refreshEmptyState];
    }];
}

- (void)loadMoreResults {
    if (_loading || !_hasMore || _needle.length == 0) { return; }
    _loading = YES;
    [_tableView reloadData]; // 立刻刷成「加载中…」，否则点下去几百毫秒毫无反馈会连点
    // 续页**不自增 token**：它属于当前这次搜索，自增会把自己的响应判成过期。
    [self fetchPageWithQuery:_needle cursor:_nextCursor token:_searchToken];
}

/// 空态文案。三种空是三回事，不能都写「没有匹配」。
- (void)refreshEmptyState {
    if (_results.count > 0) { _emptyLabel.hidden = YES; return; }
    _emptyLabel.hidden = NO;
    if (_failed) {
        _emptyLabel.text = @"搜索失败，请重试";
    } else if (_needle.length > 0) {
        _emptyLabel.text = @"没有匹配的成员";
    } else {
        _emptyLabel.text = [NSString stringWithFormat:@"在 %ld 位成员里搜索", (long)[self totalMembers]];
    }
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_results.count + (_hasMore ? 1 : 0);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.row >= (NSInteger)_results.count ? 52 : 60;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= (NSInteger)_results.count) { // 末尾「加载更多结果」
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"plain" forIndexPath:indexPath];
        cell.textLabel.text = _loading ? @"加载中…" : @"加载更多结果";
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = IMTheme.accent;
        cell.imageView.image = nil;
        return cell;
    }
    IMMemberSearchRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"member" forIndexPath:indexPath];
    [cell configureWithMember:_results[indexPath.row] highlight:_needle];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)_results.count) { [self loadMoreResults]; return; }
    IMGroupMember *m = _results[indexPath.row];
    [_searchBar resignFirstResponder];
    if (_onPickMember) { _onPickMember(m); }
}

@end
