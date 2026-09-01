//  IMMentionPickerViewController.m

#import "IMMentionPickerViewController.h"
#import "IMGroupInfo.h"
#import "IMListSearch.h"
#import "IMRemarkStore.h"
#import "IMTheme.h"
#import "IMGlass.h"
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
///
/// **主名恒为群内公开名**（群昵称>全局昵称>uid），因为选中后插进消息的 token 就是它——
/// 主名若显示成我的私有备注，用户会以为发出去的是备注，而群里其他人根本看不到那个名字。
/// 备注只作为**副标记**「备注: 老王」挂在后面（纯本地，仅我可见），让"搜备注也能搜到"这件事
/// 有可见的解释——否则搜「老王」蹦出一行叫「王小二」的人，看着像匹配错了。
- (void)configureWithMember:(IMGroupMember *)m query:(NSString *)query host:(NSString *)host {
    // 不要在这之后动 backgroundColor：im_setAvatarURL 会**立即铺好播种底色 + 首字母**，
    // 再清成 clear 就等于把无头像成员的首字母圈抹掉——白字落在透明底上，那一行看起来是空的
    // （有头像的成员靠图片覆盖看不出问题，所以只有"没设过头像的人"消失，极难察觉）。
    [_avatar im_setAvatarURL:IMMediaFullURL(m.avatarURL, host) seed:m.userID displayName:m.displayName];

    NSString *name = m.displayName;
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc]
        initWithString:name attributes:@{ NSForegroundColorAttributeName: IMTheme.textPrimary,
                                          NSFontAttributeName: [UIFont systemFontOfSize:16] }];
    NSString *remark = [IMRemarkStore.sharedStore remarkForUser:m.userID];
    if (remark.length > 0 && ![remark isEqualToString:name]) {
        NSString *tail = [NSString stringWithFormat:@"  备注: %@", remark];
        NSAttributedString *sub = [[NSAttributedString alloc] initWithString:tail
            attributes:@{ NSForegroundColorAttributeName: IMTheme.textSecondary,
                          NSFontAttributeName: [UIFont systemFontOfSize:12] }];
        [s appendAttributedString:sub];
    }
    if (query.length > 0) {
        // 在整行（含备注副标记）里找命中段：命中备注时也要染色，否则用户看不出这行为何被匹配上。
        NSRange hit = [s.string rangeOfString:query options:NSCaseInsensitiveSearch];
        if (hit.location != NSNotFound) {
            [s addAttribute:NSForegroundColorAttributeName value:IMTheme.accent range:hit];
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
    [_avatar im_clearAvatarImage]; // 复用自带照片的成员格时，先清掉覆盖照片，否则蓝底 @ 被上一格头像盖住（修复）
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
    /// 超级群（2 万人量级）：候选来自**服务端搜索**，不是本地 group.members——
    /// 那里只有我自己（服务端不再全量下发成员），不走服务端就一个候选都搜不到。
    BOOL _isSuper;
    /// 群总人数（不含我）。**不能用 _all.count 代替**：超级群下 _all 只是"当前这一页候选"，
    /// 20000 人的群会把「@所有人」副标题写成「通知全部 20 人」（2 万人群实测所见）。
    NSInteger _mentionAllReach;
    NSString *_convID;
    int64_t _searchToken;                ///< 去抖 + 丢弃过期响应（快速打字时后发先至会让候选闪回旧词的结果）
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

// 内联面板：搜索框上下留白、搜索框高度、行高与最多可见行数（超出滚动）。
static const CGFloat kIMMentionInlineTopPad = 18;    // 搜索框与面板顶（圆角）之间
static const CGFloat kIMMentionInlineSearchGap = 18; // 搜索框与成员列表之间
static const CGFloat kIMMentionInlineSearchHeight = 40;
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
        _isSuper = group.isSuper;
        // 权威人数优先取 memberCount（超级群资料只下发我自己，members.count 恒为 1）；
        // 普通群 memberCount 为 0 时回落到成员表长度。减 1 = 去掉我自己。
        NSInteger total = group.memberCount > 0 ? group.memberCount : (NSInteger)group.members.count;
        _mentionAllReach = MAX(0, total - 1);
        _convID = group.convID ?: @"";
        _filtered = [self membersMatching:_query];
        if (_isSuper) { [self searchRemoteMembers]; } // 超级群：先拉一页，面板打开即有候选
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
    // 搜的是用户名（^[a-z0-9_]{5,32}$）：不关自动大写，键盘会把首字母顶成大写。
    // 服务端 LIKE 恰好大小写不敏感所以还搜得到，但输入框里显示的 "Big2m0991" 本身就不对。
    _searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    _searchBar.text = _query;
    IMApplyUnifiedSearchFieldStyle(_searchBar); // 统一搜索框圆角（24）
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

/// 内联面板布局：顶部一条分隔线 + 搜索框（常驻，过滤本面板）+ 成员表格。圆角卡，无标题栏。
- (void)loadInlineLayout {
    self.view.backgroundColor = IMTheme.surface;
    self.view.layer.cornerRadius = 14;
    self.view.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner; // 仅上圆角
    self.view.layer.masksToBounds = YES;

    UIView *hairline = [UIView new];
    hairline.translatesAutoresizingMaskIntoConstraints = NO;
    hairline.backgroundColor = IMTheme.separator;
    [self.view addSubview:hairline];

    _searchBar = [UISearchBar new];
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    _searchBar.placeholder = @"搜索成员";
    _searchBar.delegate = self;
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    // 搜的是用户名（^[a-z0-9_]{5,32}$）：不关自动大写，键盘会把首字母顶成大写。
    // 服务端 LIKE 恰好大小写不敏感所以还搜得到，但输入框里显示的 "Big2m0991" 本身就不对。
    _searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    // 内联搜索框恒**从空开始**：它是独立搜索，绝不回填聊天输入框里 @后的字（列表已由 effectiveQuery 跟随 @字符）。
    _searchBar.text = @"";
    // 关闭钮改用右侧自绘「叉叉」，不用 UISearchBar 自带 cancel（任务2）：
    // 系统 cancel 的 enabled 态绑定搜索框「正在编辑」，而本内联面板刻意不聚焦搜索框（焦点留在聊天输入框），
    // 于是第一次点只是让搜索框成为 first responder（按钮高亮），第二次才真正触发 cancel——表现为「点两下才关」。
    _searchBar.showsCancelButton = NO;
    _searchBar.backgroundColor = UIColor.clearColor;
    IMApplyUnifiedSearchFieldStyle(_searchBar); // 统一搜索框圆角（24）
    [self.view addSubview:_searchBar];

    // 单击即收面板、焦点回聊天输入框（走 onInlineCancel，与原 cancel 语义一致）。
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"
                                  withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20
                                                                                                   weight:UIImageSymbolWeightRegular]]
                 forState:UIControlStateNormal];
    closeButton.tintColor = IMTheme.textSecondary;
    [closeButton addTarget:self action:@selector(inlineCloseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeButton];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = kIMMentionInlineRowHeight;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeNone; // 面板滚动不收键盘（键盘留给搜索框）
    _tableView.separatorInset = UIEdgeInsetsMake(0, 56, 0, 0);
    [_tableView registerClass:IMMentionRowCell.class forCellReuseIdentifier:@"row"];
    [self.view addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        [hairline.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [hairline.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [hairline.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [hairline.heightAnchor constraintEqualToConstant:0.5],
        [_searchBar.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:kIMMentionInlineTopPad],
        [_searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:4],
        [_searchBar.trailingAnchor constraintEqualToAnchor:closeButton.leadingAnchor constant:-4],
        [_searchBar.heightAnchor constraintEqualToConstant:kIMMentionInlineSearchHeight],
        [closeButton.centerYAnchor constraintEqualToAnchor:_searchBar.centerYAnchor],
        [closeButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [closeButton.widthAnchor constraintEqualToConstant:32],
        [closeButton.heightAnchor constraintEqualToConstant:32],
        [_tableView.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor constant:kIMMentionInlineSearchGap],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (CGFloat)preferredInlineHeight {
    // 顶部留白 + 搜索框（常驻，即使 0 匹配也留着，方便改搜索词）+ 间隔 + 成员行（封顶）。
    NSInteger n = (NSInteger)_filtered.count + (self.showsMentionAllRow ? 1 : 0);
    CGFloat rows = MIN(n, kIMMentionInlineMaxVisibleRows) * kIMMentionInlineRowHeight;
    return kIMMentionInlineTopPad + kIMMentionInlineSearchHeight + kIMMentionInlineSearchGap + rows;
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

/// 按昵称/**我给他起的备注**/uid 子串匹配（大小写不敏感）。空 query 返回全部。
/// 说明：拼音首字母匹配需额外索引，本期先做子串——中文昵称直接键入汉字即可命中。
///
/// 备注参与**匹配**但不参与**插入**：选中后填进消息的 token 仍是群内公开名（见 configureWithMember:），
/// 备注仅本人可见，写进消息就发给全群了。
- (NSArray<IMGroupMember *> *)membersMatching:(NSString *)query {
    NSString *q = IMListSearchNormalizedQuery(query);
    if (q.length == 0) { return _all; }
    NSMutableArray<IMGroupMember *> *out = [NSMutableArray array];
    for (IMGroupMember *m in _all) {
        NSString *remark = [IMRemarkStore.sharedStore remarkForUser:m.userID] ?: @"";
        // 加 @句柄维度（群成员表已下发 username）；内部 ID 保留为不可见兜底。
        if (IMListSearchMatches(q, @[m.displayName, remark, m.username ?: @"", m.userID])) { [out addObject:m]; }
    }
    return out;
}

/// 生效过滤词：用户在**面板搜索框**主动打字时以搜索框为准（独立搜索）；否则跟随**聊天输入框** `@` 后的字符。
/// 这样「列表随 @后字符实时匹配」与「搜索框保持独立、不被 @文字自动回填」两条互不打架；
/// 清空搜索框即自动回落到聊天输入框驱动。
- (NSString *)effectiveQuery {
    NSString *box = _searchBar.text ?: @"";
    return box.length > 0 ? box : _query;
}

/// 聊天输入框 `@` 后的字符实时驱动列表（任务1）。**不回填**面板搜索框——搜索框是独立搜索，用户没打字时保持空。
- (void)updateQuery:(NSString *)query {
    _query = [query copy] ?: @"";
    _filtered = [self membersMatching:[self effectiveQuery]];
    [_tableView reloadData];
    if (_isSuper) { [self searchRemoteMembers]; }
}

/// 超级群：向服务端搜候选（本地成员表只有我自己）。
///
/// 300ms 去抖 —— 每敲一个字打一次请求，在 2 万人的群里既浪费又会让候选闪烁。
/// `_searchToken` 同时用来**丢弃过期响应**：快速打字时请求可能后发先至，
/// 不校验的话候选会闪回上一个搜索词的结果。
///
/// ⚠️ q 必须真的传进 `groupMembersPageWithToken:`。首版算出了 q 却没往下传（那个方法当时也没有 q 参数），
/// 于是每次搜索都只是把"最前 20 个人"重新拉一遍——界面看着有响应、列表纹丝不动，
/// 2 万人群实测才发现（服务端日志里三次请求返回字节数一模一样）。
- (void)searchRemoteMembers {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0 || _convID.length == 0) { return; }
    int64_t myToken = ++_searchToken;
    NSString *q = [self effectiveQuery] ?: @"";
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || myToken != self->_searchToken) { return; } // 去抖：期间又打字了
        [IMHTTPService.sharedService groupMembersPageWithToken:token convID:self->_convID
                                                        cursor:nil limit:20 query:q
                                                    completion:^(NSArray<IMGroupMember *> *members,
                                                                 NSString *nextCursor, BOOL hasMore, NSError *error) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || myToken != self->_searchToken) { return; } // 过期响应：丢弃
            if (error) { return; }                                  // 搜不到就维持现状，不打断输入
            NSString *me = IMSessionStore.userID ?: @"";
            NSMutableArray<IMGroupMember *> *others = [NSMutableArray array];
            for (IMGroupMember *m in members) {
                if (![m.userID isEqualToString:me]) { [others addObject:m]; }
            }
            self->_all = others;
            self->_filtered = others; // 服务端已按 q 过滤，不再本地二次筛（本地筛会把服务端命中的项误滤掉）
            [self->_tableView reloadData];
            if (self->_inline && self.onInlineFilterChanged) { self.onInlineFilterChanged(); }
        }];
    });
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    // 面板搜索框＝独立搜索：只改「生效过滤词」，不写回 _query（聊天输入框的 @查询词），二者互不覆盖。
    _filtered = [self membersMatching:[self effectiveQuery]];
    [_tableView reloadData];
    if (_isSuper) { [self searchRemoteMembers]; }
    if (_inline && self.onInlineFilterChanged) { self.onInlineFilterChanged(); } // 宿主据此更新面板高度
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    if (_inline && self.onInlineCancel) { self.onInlineCancel(); return; } // 内联：收面板、焦点回聊天输入框
    [self dismissViewControllerAnimated:YES completion:nil]; // 模态兜底（当前模态无 cancel 按钮，保险起见）
}

/// 内联面板右上角「叉叉」：单击即收面板（等价于原 UISearchBar cancel，但不受其 first-responder 态限制）。
- (void)inlineCloseTapped {
    if (self.onInlineCancel) { self.onInlineCancel(); }
}

#pragma mark - 表格

/// 「@所有人」只在**我有权限**且**无过滤词**时占第 0 行——一旦开始搜人，列表就该只剩人。
- (BOOL)showsMentionAllRow {
    return _canMentionAll && [[self effectiveQuery] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length == 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _filtered.count + (self.showsMentionAllRow ? 1 : 0);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMMentionRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];
    if (self.showsMentionAllRow && indexPath.row == 0) {
        [cell configureAsMentionAllWithMemberCount:_mentionAllReach];
    } else {
        NSInteger idx = indexPath.row - (self.showsMentionAllRow ? 1 : 0);
        if (idx >= 0 && idx < (NSInteger)_filtered.count) {
            [cell configureWithMember:_filtered[(NSUInteger)idx] query:[self effectiveQuery] host:_host];
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
