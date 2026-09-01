//  IMFriendPickerViewController.m

#import "IMFriendPickerViewController.h"
#import "IMMainTabBarController.h" // im_refreshNavigationBar / kIMLiquidBarHeight
#import "IMContactCells.h"
#import "IMContactSectionIndex.h"
#import "IMListSearch.h"
#import "IMHTTPService.h"
#import "IMUserCard.h"
#import "IMGroupInfo.h"        // IMGroupMember（远端候选源映射用）
#import "IMTheme.h"
#import "IMLog.h"
#import "UIViewController+IMToast.h"

@interface IMFriendPickerViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, strong, nullable) NSSet<NSString *> *excludedIDs;
@property (nonatomic, copy) NSString *confirmTitle;
@property (nonatomic, copy) NSString *baseTitle;                       // 未选中时的页面标题
@property (nonatomic, strong, nullable) NSArray<IMUserCard *> *injectedCandidates; // 非 nil = 不联网，直接用它
@property (nonatomic, copy) void (^onDone)(NSArray<NSString *> *selectedIDs);
@property (nonatomic, strong) NSArray<IMUserCard *> *usable;           // 可选好友全集（已排除 excludedIDs），搜索的输入
/// 远端候选模式的请求序号：去抖 + **丢弃过期响应**（快速打字后发先至会让候选闪回旧词的结果）。
/// 与 @人选择器/成员搜索页同一套路。
@property (nonatomic, assign) int64_t remoteSearchToken;
@property (nonatomic, strong) IMContactSectionIndex *friendIndex;     // **当前搜索词下**可见好友的 A–Z 分组索引，兼作表格数据源
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *picked; // 选中的 uid（保持点选顺序）
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIView *searchHeader;   // 托住 searchBar 的表头容器（宽度随表格实时对齐）
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation IMFriendPickerViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID
                 excludedIDs:(NSSet<NSString *> *)excludedIDs
                confirmTitle:(NSString *)confirmTitle
                      onDone:(void (^)(NSArray<NSString *> *))onDone {
    return [self initWithHost:host userID:userID candidates:nil excludedIDs:excludedIDs
                        title:@"选择好友" confirmTitle:confirmTitle onDone:onDone];
}

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID
                  candidates:(NSArray<IMUserCard *> *)candidates
                 excludedIDs:(NSSet<NSString *> *)excludedIDs
                       title:(NSString *)title
                confirmTitle:(NSString *)confirmTitle
                      onDone:(void (^)(NSArray<NSString *> *))onDone {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        _injectedCandidates = [candidates copy];
        _excludedIDs = [excludedIDs copy];
        _baseTitle = [(title.length > 0 ? title : @"选择好友") copy];
        _confirmTitle = [confirmTitle copy];
        _onDone = [onDone copy];
        _picked = [NSMutableOrderedSet orderedSet];
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.baseTitle;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    // 单选即确认模式不需要「确定」按钮（点行就走完了），留着只会让人以为还要再点一下。
    if (!self.selectsImmediately) {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:self.confirmTitle style:UIBarButtonItemStyleDone
                                            target:self action:@selector(confirmTapped)];
        self.navigationItem.rightBarButtonItem.enabled = NO; // 至少选 1 个才可确认
    }
    // 返回键用系统默认（与全局各页一致）。长按弹出的「导航历史菜单」是 iOS 标准特性、无害——普通点击直接返回。

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 60;
    [self.tableView registerClass:IMContactCell.class forCellReuseIdentifier:@"pick"];
    // 搜索框：好友一多就得搜。外观与匹配口径走 IMListSearch，与转发选择页/@面板同一套。
    self.searchBar = IMListSearchBarMake(self.view.bounds.size.width,
                                         self.searchPlaceholder.length ? self.searchPlaceholder : @"搜索好友", self);
    // 搜索框挂在容器里而不是直接当 tableHeaderView：直接挂时它的宽度停在 viewDidLoad 那一刻的
    // view.bounds，与表格真实宽度（本页右侧还有 A–Z 索引尺）对不上，整个框看起来左右都偏。
    self.searchHeader = IMListSearchHeaderMake(self.searchBar);
    self.tableView.tableHeaderView = self.searchHeader;
    [self.view addSubview:self.tableView];

    self.emptyLabel = [UILabel new];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = self.emptyText.length ? self.emptyText : @"没有可选的好友";
    self.emptyLabel.textColor = IMTheme.textSecondary;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    [self reload];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    IMListSearchHeaderSyncWidth(self.searchHeader, self.tableView); // 表头宽度对齐表格（宽度没变即空转）
}

+ (void (^)(NSString *, void (^)(NSArray<IMUserCard *> *, NSError *)))groupMemberSearchForConvID:(NSString *)convID {
    NSString *cid = [convID copy];
    return ^(NSString *query, void (^done)(NSArray<IMUserCard *> *, NSError *)) {
        NSString *token = IMHTTPService.sharedService.currentToken;
        if (token.length == 0 || cid.length == 0) { done(@[], nil); return; }
        // 一次 50 条。**不翻页**：这是"找某个人"而不是"浏览全体"——2 万人里靠翻页找人本就不成立，
        // 打更精确的关键词才是路径（与 @人选择器同取舍）。
        [IMHTTPService.sharedService groupMembersPageWithToken:token convID:cid cursor:nil limit:50 query:query
                                                    completion:^(NSArray<IMGroupMember *> *members,
                                                                 NSString *nextCursor, BOOL hasMore, NSError *error) {
            if (error) { done(nil, error); return; }
            NSMutableArray<IMUserCard *> *cards = [NSMutableArray arrayWithCapacity:members.count];
            for (IMGroupMember *m in members) {
                // 与 IMGroupAdminLogic pickerCardsFromMembers: 同一套映射（群内公开名，绝不回退内部 ID）。
                IMUserCard *c = [IMUserCard new];
                c.userID = m.userID;
                c.nickname = m.displayName;
                c.username = m.username ?: @"";
                c.avatarURL = m.avatarURL ?: @"";
                [cards addObject:c];
            }
            done(cards, nil);
        }];
    };
}

- (IMUserCard *)cardForUserID:(NSString *)userID {
    if (userID.length == 0) { return nil; }
    for (IMUserCard *c in self.usable) {
        if ([c.userID isEqualToString:userID]) { return c; }
    }
    return nil;
}

/// 拉好友列表（accepted），排除 excludedIDs。候选已注入时直接用它，不联网。
/// 设了 remoteCandidateSearch（超级群）则改走服务端：候选全集不在端上。
- (void)reload {
    if (self.remoteCandidateSearch) {
        [self runRemoteSearch]; // 空词 = 取第一页
        return;
    }
    if (self.injectedCandidates) {
        [self applyCandidates:self.injectedCandidates];
        return;
    }
    IMHTTPService.sharedService.host = self.host;
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (token.length == 0) {
            IMLog(@"picker 登录失败：%@", error.localizedDescription);
            return;
        }
        [IMHTTPService.sharedService friendsWithToken:token status:@"accepted"
                                           completion:^(NSArray<IMUserCard *> *friends, NSError *err) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            if (err) {
                IMLog(@"picker 拉好友失败：%@", err.localizedDescription);
                return;
            }
            [self applyCandidates:friends];
        }];
    }];
}

/// 候选全集 → 排除 excludedIDs → 重算可见行。注入与联网两条来源共用它。
- (void)applyCandidates:(NSArray<IMUserCard *> *)candidates {
    NSMutableArray<IMUserCard *> *usable = [NSMutableArray array];
    for (IMUserCard *c in candidates) {
        if (![self.excludedIDs containsObject:c.userID]) { [usable addObject:c]; }
    }
    self.usable = usable;
    [self applyFilter];
}

#pragma mark - 搜索

/// 重算可见行：按显示名（备注 > 昵称 > uid）与 uid 子串匹配，再交给 A–Z 索引重新分组。
/// 选中集 `picked` 存的是 uid、与过滤无关——先勾选再搜索把人过滤掉，确认时仍会带上他。
- (void)applyFilter {
    NSString *q = IMListSearchNormalizedQuery(self.searchBar.text);
    NSArray<IMUserCard *> *visible = self.usable ?: @[];
    // 远端模式：服务端已经按 q 过滤过了，usable 就是要显示的行。
    // 再本地过一遍不但多余，还会**二次收窄**——服务端按句柄/群昵称/全局昵称三源命中，
    // 本地只认显示名+句柄，命中群昵称的那些人会被本地这一道悄悄滤掉。
    if (self.remoteCandidateSearch) {
        self.friendIndex = [[IMContactSectionIndex alloc] initWithCards:visible];
        self.emptyLabel.text = q.length > 0 ? @"没有匹配的成员"
                                            : (self.emptyText.length ? self.emptyText : @"群里还没有其他成员");
        self.emptyLabel.hidden = visible.count > 0;
        [self.tableView reloadData];
        return;
    }
    // 搜索维度 = 显示名 + @句柄（+ 好友场景的内部 ID）。
    // 好友场景内部 ID **不展示但可搜**：排障时能粘贴 ID 精准定位，且 10 位随机数字不可能撞上昵称/备注。
    // 注入候选（群成员）场景**刻意不收 uid**：那等于把搜索框变成 ID 探测器，与账号身份体系
    // 「内部 ID 不可枚举」的初衷相悖（GROUP_ADMIN_TRANSFER_DESIGN.md §1.3）。
    BOOL searchUserID = (self.injectedCandidates == nil);
    if (q.length > 0) {
        NSMutableArray<IMUserCard *> *out = [NSMutableArray array];
        for (IMUserCard *c in visible) {
            NSArray<NSString *> *fields = searchUserID
                ? @[c.displayName, c.username ?: @"", c.userID]
                : @[c.displayName, c.username ?: @""];
            if (IMListSearchMatches(q, fields)) { [out addObject:c]; }
        }
        visible = out;
    }
    self.friendIndex = [[IMContactSectionIndex alloc] initWithCards:visible]; // A–Z 分组，兼作数据源
    NSString *noneText = self.emptyText.length ? self.emptyText : @"没有可选的好友";
    NSString *noHitText = searchUserID ? @"没有匹配的好友" : @"没有匹配的成员";
    self.emptyLabel.text = (q.length > 0 && self.usable.count > 0) ? noHitText : noneText;
    self.emptyLabel.hidden = visible.count > 0;
    [self.tableView reloadData];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (self.remoteCandidateSearch) { [self runRemoteSearch]; return; }
    [self applyFilter];
}

/// 远端候选：300ms 去抖 + 请求序号丢弃过期响应（与 @人选择器同口径）。
- (void)runRemoteSearch {
    if (!self.remoteCandidateSearch) { return; }
    int64_t myToken = ++self.remoteSearchToken;
    NSString *q = IMListSearchNormalizedQuery(self.searchBar.text) ?: @"";
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || myToken != self.remoteSearchToken) { return; } // 期间又打字了
        self.remoteCandidateSearch(q, ^(NSArray<IMUserCard *> *cards, NSError *error) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || myToken != self.remoteSearchToken) { return; } // 过期响应，丢弃
            if (error) { return; }                                     // 保留上一批结果，别清成"没有匹配"
            [self applyCandidates:cards ?: @[]];                       // 内含 excludedIDs 过滤
        });
    });
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

- (void)confirmTapped {
    if (self.picked.count == 0) { return; }
    if (self.onDone) { self.onDone(self.picked.array); }
}

/// 更新标题与确认按钮态（已选 N）。
- (void)updateSelectionUI {
    if (self.picked.count == 0) {
        self.title = self.baseTitle;
    } else if (self.maxSelection > 0) {
        self.title = [NSString stringWithFormat:@"已选 %lu/%lu 人",
                      (unsigned long)self.picked.count, (unsigned long)self.maxSelection];
    } else {
        self.title = [NSString stringWithFormat:@"已选 %lu 人", (unsigned long)self.picked.count];
    }
    self.navigationItem.rightBarButtonItem.enabled = self.picked.count > 0;
    // 标题栏按本页 navigationItem 渲染，改完必须显式请求刷新，
    // 否则「创建」按钮的 enabled 停留在初始 NO，点击被吞、无法建群。
    [self im_refreshNavigationBar];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self.friendIndex numberOfSections];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.friendIndex numberOfRowsInSection:section];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self.friendIndex titleForSection:section]; // 字母表头（索引 head）
}

/// 右侧纵向索引尺：A–Z / #，点击跳转到对应分组；无好友则不显示。
- (NSArray<NSString *> *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    return self.friendIndex.titles.count > 0 ? self.friendIndex.titles : nil;
}

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
    return index; // 本页只有好友分组，section 与 titles 一一对应
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMContactCell *cell = [tableView dequeueReusableCellWithIdentifier:@"pick" forIndexPath:indexPath];
    IMUserCard *c = [self.friendIndex cardAtSection:indexPath.section row:indexPath.row];
    // 副标题 = @句柄（无则留空），绝不显示 userID——那是 10 位随机数字内部 ID。
    [cell configureWithCard:c subtitle:(c.username.length > 0 ? [@"@" stringByAppendingString:c.username] : @"")];
    [cell setActionTitle:nil enabled:NO action:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    // 行首圆形勾选框（对齐 Web/微信 + 转发选择器），替代原尾部系统 ✓。
    BOOL checked = [self.picked containsObject:c.userID];
    // 单选即确认模式不画勾选框：空心圆圈的视觉语言是"可以多选、选完再确认"，
    // 而这一模式点一下就直接走完，留着圆圈只会误导（转让群主页）。
    [cell setChecked:checked showCheckbox:!self.selectsImmediately];
    cell.accessoryType = UITableViewCellAccessoryNone;
    // 达上限后**未选中**行置灰不可点（已选中的仍可点=取消选择，否则用户会卡死在满选态）。
    BOOL atCap = self.maxSelection > 0 && self.picked.count >= self.maxSelection && !checked;
    cell.contentView.alpha = atCap ? 0.4 : 1.0;
    // 配了 capToast 就让灰行仍可点（点了只吐司），否则沿用原来的"点不动"。
    cell.userInteractionEnabled = !atCap || self.capToast.length > 0;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.searchBar resignFirstResponder];
    IMUserCard *c = [self.friendIndex cardAtSection:indexPath.section row:indexPath.row];
    NSString *uid = c.userID;
    if (uid.length == 0) { return; }
    // 单选即确认：不进选中集、不改标题，直接把这一个 uid 交回去（调用方负责二次确认与导航）。
    if (self.selectsImmediately) {
        if (self.onDone) { self.onDone(@[uid]); }
        return;
    }
    if ([self.picked containsObject:uid]) {
        [self.picked removeObject:uid];
    } else {
        if (self.maxSelection > 0 && self.picked.count >= self.maxSelection) {
            // 满选：不进选中集。配了 capToast 就说清楚为什么，否则静默（行已置灰）。
            if (self.capToast.length > 0) { [self im_showToast:self.capToast]; }
            return;
        }
        [self.picked addObject:uid];
    }
    // 整表刷新而非单行：达/离开上限时**其余所有行**的置灰态都要跟着变。
    [tableView reloadData];
    [self updateSelectionUI];
}

@end
