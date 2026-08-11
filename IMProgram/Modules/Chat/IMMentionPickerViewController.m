//  IMMentionPickerViewController.m

#import "IMMentionPickerViewController.h"
#import "IMGroupInfo.h"
#import "IMTheme.h"
#import "IMMediaUtil.h"           // IMMediaFullURL
#import "UILabel+IMAvatar.h"
#import "IMMainTabBarController.h" // kIMLiquidBarHeight
#import "IMProgram-Swift.h"        // IMLiquidNavigationBar
#import "IMSessionStore.h"
#import "IMHTTPService.h"

/// 默认展开高度占屏比。草图定「屏幕一半」，实测 0.55 能多露一行成员、又不遮挡输入区。
static const CGFloat kIMMentionPickerDefaultHeightRatio = 0.55;
/// 关闭钮距 sheet 顶留白（与文件面板一致，避开顶部圆角）。
static const CGFloat kIMMentionPickerTopPadding = 16;

/// 与文件面板同款：恒按 base 外观解析分组背景，避免拖动 detent 时整卡变色。
static UIColor *IMMentionBaseGroupedBackgroundColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        UITraitCollection *base = [UITraitCollection traitCollectionWithUserInterfaceLevel:UIUserInterfaceLevelBase];
        UITraitCollection *merged = [UITraitCollection traitCollectionWithTraitsFromCollections:@[tc, base]];
        return [UIColor.systemGroupedBackgroundColor resolvedColorWithTraitCollection:merged];
    }];
}

#pragma mark - 成员行 Cell

/// 一行成员：头像 + 昵称（命中段高亮）+ 角色标。「@所有人」复用同一 cell，头像位显蓝底 @。
@interface IMMentionRowCell : UITableViewCell
@end

@implementation IMMentionRowCell {
    UILabel *_avatar;
    UILabel *_name;
    UILabel *_role;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        _avatar.textColor = UIColor.whiteColor;
        _avatar.layer.cornerRadius = 18;
        _avatar.layer.masksToBounds = YES;
        [self.contentView addSubview:_avatar];

        _name = [UILabel new];
        _name.translatesAutoresizingMaskIntoConstraints = NO;
        _name.font = [UIFont systemFontOfSize:16];
        [self.contentView addSubview:_name];

        _role = [UILabel new];
        _role.translatesAutoresizingMaskIntoConstraints = NO;
        _role.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _role.textColor = IMTheme.textSecondary;
        _role.layer.cornerRadius = 4;
        _role.layer.borderWidth = 1;
        _role.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:_role];

        UILayoutGuide *g = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
            [_avatar.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:36],
            [_avatar.heightAnchor constraintEqualToConstant:36],
            [_name.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:12],
            [_name.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
            [_role.leadingAnchor constraintGreaterThanOrEqualToAnchor:_name.trailingAnchor constant:8],
            [_role.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_role.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
            [_role.heightAnchor constraintEqualToConstant:18],
            [_role.widthAnchor constraintGreaterThanOrEqualToConstant:44],
            [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:52],
        ]];
    }
    return self;
}

/// 成员行。query 非空时把命中段染成主题色（草图 §03-② 的「高亮命中」）。
- (void)configureWithMember:(IMGroupMember *)m query:(NSString *)query host:(NSString *)host {
    // 不要在这之后动 backgroundColor：im_setAvatarURL 会**立即铺好播种底色 + 首字母**，
    // 再清成 clear 就等于把无头像成员的首字母圈抹掉——白字落在透明底上，那一行看起来是空的
    // （有头像的成员靠图片覆盖看不出问题，所以只有"没设过头像的人"消失，极难察觉）。
    [_avatar im_setAvatarURL:IMMediaFullURL(m.avatarURL, host) seed:m.userID displayName:m.displayName];

    NSString *name = m.displayName;
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc]
        initWithString:name attributes:@{ NSForegroundColorAttributeName: IMTheme.textPrimary,
                                          NSFontAttributeName: [UIFont systemFontOfSize:16] }];
    if (query.length > 0) {
        NSRange hit = [name rangeOfString:query options:NSCaseInsensitiveSearch];
        if (hit.location != NSNotFound) {
            [s addAttributes:@{ NSForegroundColorAttributeName: IMTheme.accent,
                                NSFontAttributeName: [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold] }
                       range:hit];
        }
    }
    _name.attributedText = s;

    NSString *roleText = m.role == IMGroupRoleOwner ? @"群主" : (m.role == IMGroupRoleAdmin ? @"管理员" : nil);
    _role.text = roleText;
    _role.hidden = roleText == nil;
    _role.layer.borderColor = IMTheme.separator.CGColor;
}

/// 「@所有人」置顶行：蓝底 @ 圆 + 副标题说明通知人数。
- (void)configureAsMentionAllWithMemberCount:(NSInteger)others {
    _avatar.text = @"@";
    _avatar.backgroundColor = IMTheme.accent;
    _avatar.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];

    NSString *head = @"所有人";
    NSString *tail = [NSString stringWithFormat:@"  通知全部 %ld 人", (long)others];
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc]
        initWithString:[head stringByAppendingString:tail]
            attributes:@{ NSForegroundColorAttributeName: IMTheme.textPrimary,
                          NSFontAttributeName: [UIFont systemFontOfSize:16] }];
    [s addAttributes:@{ NSForegroundColorAttributeName: IMTheme.textSecondary,
                        NSFontAttributeName: [UIFont systemFontOfSize:12] }
               range:NSMakeRange(head.length, tail.length)];
    _name.attributedText = s;
    _role.hidden = YES;
}

/// 复用前只复位「@所有人」那行改过的样式（蓝底 + 大号 @）；底色/首字母交给 im_setAvatarURL 重铺，
/// 这里不能顺手清 image，否则异步加载中的头像会闪。
- (void)prepareForReuse {
    [super prepareForReuse];
    _avatar.backgroundColor = UIColor.clearColor;
    _avatar.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _role.hidden = YES;
}

@end

#pragma mark - 选择器

@interface IMMentionPickerViewController () <UITableViewDataSource, UITableViewDelegate,
                                             UISearchBarDelegate, IMLiquidNavigationBarDelegate>
/// 唯一指定初始化器：两个公开 init（模态 / 内联）都收敛到这里（共享成员/过滤/host 装配）。
- (instancetype)initCommonWithGroup:(IMGroupInfo *)group
                       initialQuery:(nullable NSString *)initialQuery
                       onPickMember:(void (^)(IMGroupMember *))onPickMember
                          onPickAll:(void (^)(void))onPickAll
                             inline:(BOOL)isInline NS_DESIGNATED_INITIALIZER;
@end

@implementation IMMentionPickerViewController {
    IMGroupInfo *_group;
    NSArray<IMGroupMember *> *_all;      ///< 候选成员（已剔除自己）
    NSArray<IMGroupMember *> *_filtered; ///< 当前过滤结果
    NSString *_query;
    BOOL _canMentionAll;                 ///< 我是群主/管理员——决定「@所有人」行是否渲染
    void (^_onPickMember)(IMGroupMember *);
    void (^_onPickAll)(void);
    UITableView *_tableView;
    UISearchBar *_searchBar;
    NSString *_host;
    BOOL _inline;                        ///< YES=输入栏上方内联面板（不弹 sheet/不抢键盘/无搜索框）
}

// 内联面板：行高与最多可见行数（超出滚动）。
static const CGFloat kIMMentionInlineRowHeight = 52;
static const NSInteger kIMMentionInlineMaxVisibleRows = 4;

- (instancetype)initWithGroup:(IMGroupInfo *)group
                 initialQuery:(NSString *)initialQuery
                 onPickMember:(void (^)(IMGroupMember *))onPickMember
                    onPickAll:(void (^)(void))onPickAll {
    if ((self = [self initCommonWithGroup:group initialQuery:initialQuery
                             onPickMember:onPickMember onPickAll:onPickAll inline:NO])) {
        if (@available(iOS 15.0, *)) {
            self.modalPresentationStyle = UIModalPresentationPageSheet;
            UISheetPresentationController *sheet = self.sheetPresentationController;
            if (@available(iOS 16.0, *)) {
                UISheetPresentationControllerDetent *half =
                    [UISheetPresentationControllerDetent customDetentWithIdentifier:@"mentionHalf"
                        resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                            return context.maximumDetentValue * kIMMentionPickerDefaultHeightRatio;
                        }];
                sheet.detents = @[half, UISheetPresentationControllerDetent.largeDetent];
            } else {
                sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                                  UISheetPresentationControllerDetent.largeDetent];
            }
            sheet.prefersGrabberVisible = YES; // 抓手：提示可上滑放大看更多成员
        }
    }
    return self;
}

- (instancetype)initInlineWithGroup:(IMGroupInfo *)group
                       initialQuery:(NSString *)initialQuery
                       onPickMember:(void (^)(IMGroupMember *))onPickMember
                          onPickAll:(void (^)(void))onPickAll {
    return [self initCommonWithGroup:group initialQuery:initialQuery
                        onPickMember:onPickMember onPickAll:onPickAll inline:YES];
}

- (instancetype)initCommonWithGroup:(IMGroupInfo *)group
                       initialQuery:(NSString *)initialQuery
                       onPickMember:(void (^)(IMGroupMember *))onPickMember
                          onPickAll:(void (^)(void))onPickAll
                             inline:(BOOL)isInline {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _group = group;
        _query = [initialQuery copy] ?: @"";
        _onPickMember = [onPickMember copy];
        _onPickAll = [onPickAll copy];
        _inline = isInline;
        // 「@所有人」仅群主/管理员可见可点。普通成员**整行不渲染**（不是置灰不可点——
        // 避免"看得见用不了"的挫败感）。服务端另有角色校验，客户端隐藏只是 UI 层。
        _canMentionAll = group.myRole == IMGroupRoleOwner || group.myRole == IMGroupRoleAdmin;

        NSString *me = IMSessionStore.userID ?: @"";
        NSMutableArray<IMGroupMember *> *others = [NSMutableArray array];
        for (IMGroupMember *m in group.members) {
            if (![m.userID isEqualToString:me]) { [others addObject:m]; } // @自己无意义
        }
        _all = others;
        _filtered = [self membersMatching:_query];
        _host = IMHTTPService.sharedService.host;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"提醒谁";
    if (@available(iOS 17.0, *)) {
        self.traitOverrides.userInterfaceLevel = UIUserInterfaceLevelBase;
    }
    if (_inline) { [self loadInlineLayout]; return; }

    UIColor *sheetBackground = IMMentionBaseGroupedBackgroundColor();
    self.view.backgroundColor = sheetBackground;

    _searchBar = [UISearchBar new];
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    _searchBar.placeholder = @"搜索成员";
    _searchBar.delegate = self;
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.text = _query;
    [self.view addSubview:_searchBar];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = sheetBackground;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [_tableView registerClass:IMMentionRowCell.class forCellReuseIdentifier:@"row"];
    [self.view addSubview:_tableView];

    [self installLiquidNavigationBar];

    [NSLayoutConstraint activateConstraints:@[
        [_searchBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [_searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [_tableView.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor constant:4],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

/// 内联面板布局：顶部圆角卡 + 顶部一条分隔线；表格铺满，无搜索框/标题栏（过滤走聊天输入框）。
- (void)loadInlineLayout {
    self.view.backgroundColor = IMTheme.surface;
    self.view.layer.cornerRadius = 14;
    self.view.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner; // 仅上圆角
    self.view.layer.masksToBounds = YES;

    UIView *hairline = [UIView new];
    hairline.translatesAutoresizingMaskIntoConstraints = NO;
    hairline.backgroundColor = IMTheme.separator;
    [self.view addSubview:hairline];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = kIMMentionInlineRowHeight;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeNone; // 面板滚动不收键盘（键盘留给输入框）
    _tableView.separatorInset = UIEdgeInsetsMake(0, 56, 0, 0);
    [_tableView registerClass:IMMentionRowCell.class forCellReuseIdentifier:@"row"];
    [self.view addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        [hairline.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [hairline.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [hairline.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [hairline.heightAnchor constraintEqualToConstant:0.5],
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (CGFloat)preferredInlineHeight {
    NSInteger n = (NSInteger)_filtered.count + (self.showsMentionAllRow ? 1 : 0);
    if (n <= 0) { return 0; }
    return MIN(n, kIMMentionInlineMaxVisibleRows) * kIMMentionInlineRowHeight;
}

/// 自持 Liquid Glass 标题栏（同文件面板：模态 sheet 不经导航容器注入，须自己挂一条）。
- (void)installLiquidNavigationBar {
    UIEdgeInsets insets = self.additionalSafeAreaInsets;
    insets.top = kIMMentionPickerTopPadding + kIMLiquidBarHeight;
    self.additionalSafeAreaInsets = insets;

    IMLiquidNavigationBar *bar = [[IMLiquidNavigationBar alloc] initWithTitle:self.title subtitle:@"" actionTitle:nil];
    bar.delegate = self;
    bar.hostExtraTopInset = kIMLiquidBarHeight;
    bar.backgroundEffectProgress = 0; // sheet 自带背景，不再叠磨砂带（深色下会成黑影）
    bar.leftImage = [UIImage systemImageNamed:@"xmark"
                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17
                                                                                              weight:UIImageSymbolWeightSemibold]];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    ]];
}

/// 卡片彻底离场（选中 / 点叉 / 下滑）后通知一次调用方。放在 viewDidDisappear 而非各 dismiss 点，
/// 三条关闭路径才能统一覆盖（编程式 dismiss 不会触发 presentationControllerDidDismiss:）。
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isBeingDismissed || self.presentingViewController == nil) {
        void (^cb)(void) = self.onDismiss;
        self.onDismiss = nil; // 只回调一次
        if (cb) { cb(); }
    }
}

#pragma mark - 过滤

/// 按昵称/uid 子串匹配（大小写不敏感）。空 query 返回全部。
/// 说明：拼音首字母匹配需额外索引，本期先做子串——中文昵称直接键入汉字即可命中。
- (NSArray<IMGroupMember *> *)membersMatching:(NSString *)query {
    NSString *q = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (q.length == 0) { return _all; }
    NSMutableArray<IMGroupMember *> *out = [NSMutableArray array];
    for (IMGroupMember *m in _all) {
        if ([m.displayName rangeOfString:q options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [m.userID rangeOfString:q options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [out addObject:m];
        }
    }
    return out;
}

- (void)updateQuery:(NSString *)query {
    _query = [query copy] ?: @"";
    if (![_searchBar.text isEqualToString:_query]) { _searchBar.text = _query; }
    _filtered = [self membersMatching:_query];
    [_tableView reloadData];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    _query = [searchText copy] ?: @"";
    _filtered = [self membersMatching:_query];
    [_tableView reloadData];
}

#pragma mark - 表格

/// 「@所有人」只在**我有权限**且**无过滤词**时占第 0 行——一旦开始搜人，列表就该只剩人。
- (BOOL)showsMentionAllRow {
    return _canMentionAll && [_query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length == 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _filtered.count + (self.showsMentionAllRow ? 1 : 0);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMMentionRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];
    if (self.showsMentionAllRow && indexPath.row == 0) {
        [cell configureAsMentionAllWithMemberCount:(NSInteger)_all.count];
    } else {
        NSInteger idx = indexPath.row - (self.showsMentionAllRow ? 1 : 0);
        if (idx >= 0 && idx < (NSInteger)_filtered.count) {
            [cell configureWithMember:_filtered[(NSUInteger)idx] query:_query host:_host];
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    // 内联模式：本控制器是 child，不自我 dismiss——回填 token 后由宿主移除面板（onPick* 里负责）。
    if (self.showsMentionAllRow && indexPath.row == 0) {
        void (^pick)(void) = _onPickAll;
        if (_inline) { if (pick) { pick(); } return; }
        [self dismissViewControllerAnimated:YES completion:^{ if (pick) { pick(); } }];
        return;
    }
    NSInteger idx = indexPath.row - (self.showsMentionAllRow ? 1 : 0);
    if (idx < 0 || idx >= (NSInteger)_filtered.count) { return; }
    IMGroupMember *m = _filtered[(NSUInteger)idx];
    void (^pick)(IMGroupMember *) = _onPickMember;
    if (_inline) { if (pick) { pick(m); } return; }
    [self dismissViewControllerAnimated:YES completion:^{ if (pick) { pick(m); } }];
}

#pragma mark - IMLiquidNavigationBarDelegate

- (void)liquidNavigationBarDidTapLeft:(IMLiquidNavigationBar *)bar { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)liquidNavigationBarDidTapBack:(IMLiquidNavigationBar *)bar { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)liquidNavigationBarDidTapAction:(IMLiquidNavigationBar *)bar { /* 无右侧操作 */ }

@end
