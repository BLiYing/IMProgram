//  IMGlobalSearchViewController.m

#import "IMGlobalSearchViewController.h"
#import "IMDatabase.h"
#import "IMConversation.h"
#import "IMUserCard.h"
#import "IMMessageModel.h"
#import "IMChatViewController.h"
#import "IMUserSearchViewController.h"   // 「搜索用户「x」」下钻在线找人（加好友）
#import "IMTheme.h"
#import "IMMainTabBarController.h" // kIMLiquidBarHeight
#import "IMProgram-Swift.h"        // IMLiquidNavigationBar（searchMode）
#import "UILabel+IMAvatar.h"       // im_setAvatarURL:（真实头像 + 首字母兜底，全 app 统一头像逻辑）

typedef NS_ENUM(NSInteger, IMSearchGroup) {
    IMSearchGroupConversation = 0,
    IMSearchGroupContact,
    IMSearchGroupRecord,
    IMSearchGroupUser,   // 「搜索用户「x」」：下钻在线找人（uid/手机号精确、加好友）——把原找人页收成一个次要入口
};

#pragma mark - 结果行 cell（自持，不复用会话列表私有 cell）

static NSAttributedString *IMSearchHighlighted(NSString *text, NSString *keyword, UIFont *font, UIColor *color);

@interface IMSearchResultCell : UITableViewCell
@property (nonatomic, strong) UILabel *avatarLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
- (void)configureAvatarURL:(nullable NSString *)avatarURL seed:(NSString *)seed displayName:(NSString *)name
                     title:(NSString *)title subtitle:(nullable NSString *)subtitle keyword:(nullable NSString *)keyword;
@end

@implementation IMSearchResultCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        _avatarLabel = [UILabel new];
        _avatarLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _avatarLabel.textAlignment = NSTextAlignmentCenter;
        _avatarLabel.textColor = UIColor.whiteColor;
        _avatarLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
        _avatarLabel.layer.cornerRadius = 22; _avatarLabel.clipsToBounds = YES;

        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        _titleLabel.textColor = IMTheme.textPrimary;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

        _subtitleLabel = [UILabel new];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [UIFont systemFontOfSize:13];
        _subtitleLabel.textColor = IMTheme.textSecondary;
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

        [self.contentView addSubview:_avatarLabel];
        [self.contentView addSubview:_titleLabel];
        [self.contentView addSubview:_subtitleLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_avatarLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_avatarLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatarLabel.widthAnchor constraintEqualToConstant:44],
            [_avatarLabel.heightAnchor constraintEqualToConstant:44],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_avatarLabel.trailingAnchor constant:12],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.centerYAnchor constant:-18],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
        ]];
    }
    return self;
}

- (void)configureAvatarURL:(nullable NSString *)avatarURL seed:(NSString *)seed displayName:(NSString *)name
                     title:(NSString *)title subtitle:(nullable NSString *)subtitle keyword:(nullable NSString *)keyword {
    // 头像复用全 app 统一逻辑（UILabel+IMAvatar）：先首字母取色底立即显示，异步加载真实头像覆盖；cell 复用安全。
    [self.avatarLabel im_setAvatarURL:avatarURL seed:seed displayName:name];
    self.titleLabel.attributedText = IMSearchHighlighted(title, keyword, self.titleLabel.font, IMTheme.textPrimary);
    self.subtitleLabel.attributedText = subtitle.length > 0
        ? IMSearchHighlighted(subtitle, keyword, self.subtitleLabel.font, IMTheme.textSecondary) : nil;
    self.subtitleLabel.hidden = (subtitle.length == 0);
}

@end

/// 命中词高亮（与 Web `<mark class="search-hit">` 对齐）：所有大小写不敏感命中段染 accent 前景 + accentSoft 底。
static NSAttributedString *IMSearchHighlighted(NSString *text, NSString *keyword, UIFont *font, UIColor *color) {
    NSMutableAttributedString *att = [[NSMutableAttributedString alloc]
        initWithString:(text ?: @"")
            attributes:@{ NSFontAttributeName: font, NSForegroundColorAttributeName: color }];
    if (keyword.length == 0 || att.length == 0) { return att; }
    NSRange search = NSMakeRange(0, att.length);
    while (search.location < att.length) {
        NSRange r = [att.string rangeOfString:keyword options:NSCaseInsensitiveSearch range:search];
        if (r.location == NSNotFound) { break; }
        [att addAttributes:@{ NSBackgroundColorAttributeName: IMTheme.accentSoft,
                              NSForegroundColorAttributeName: IMTheme.accent } range:r];
        search = NSMakeRange(NSMaxRange(r), att.length - NSMaxRange(r));
    }
    return att;
}

#pragma mark - 全局搜索 VC

@interface IMGlobalSearchViewController () <UITableViewDataSource, UITableViewDelegate, IMLiquidNavigationBarDelegate>
@end

@implementation IMGlobalSearchViewController {
    NSString *_host;
    NSString *_userID;
    NSArray<IMConversation *> *_allConversations;
    NSArray<IMUserCard *> *_allFriends;
    UISearchTextField *_searchField;   // 标题行内搜索框（自持 IMLiquidNavigationBar searchMode）
    UITableView *_tableView;
    UILabel *_emptyLabel;

    NSString *_keyword;
    NSArray<IMConversation *> *_convHits;
    NSArray<IMUserCard *> *_friendHits;
    NSArray<NSDictionary *> *_recordGroups;  // 聊天记录命中（**不聚合**，一条命中一行）：{convID,conv,title,snippet,seq}
    NSArray<NSNumber *> *_sections;            // 非空分组，按 会话/联系人/聊天记录 顺序
}

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _host = [host copy]; _userID = [userID copy];
        _allConversations = [IMDatabase.sharedDatabase cachedConversations] ?: @[];
        _allFriends = [IMDatabase.sharedDatabase cachedFriends] ?: @[];
        _convHits = @[]; _friendHits = @[]; _recordGroups = @[]; _sections = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"搜索";
    self.view.backgroundColor = IMTheme.groupedBackground;

    // 搜索框在标题行：自持 IMLiquidNavigationBar 的 searchMode（复用 titleGlass 得 24 圆角+玻璃）。
    // ⚠️ 几何契约：导航容器对「自持栏页面」（controllerOwnsBar 白名单）会**强制重置
    // additionalSafeAreaInsets.top = 0**（IMMainTabBarController syncBarForController:）——在 viewDidLoad
    // 里自己撑 56/72 会被每次转场同步清零，栏内按「安全区-hostExtraTopInset」算出负值钳 0，搜索框顶进
    // 状态栏（2026-08-20 踩坑）。正确做法：不碰 additionalSafeAreaInsets、hostExtraTopInset 保持 0，
    // 栏高改为显式「真实安全区 + 56」（bottom = safeArea.top + 56），内容行自然落在标准标题行位置。
    IMLiquidNavigationBar *bar = [[IMLiquidNavigationBar alloc] initWithTitle:@"" subtitle:@"" actionTitle:@"取消"];
    bar.delegate = self;
    // 关掉栏的磨砂底带（仿 IMFilePickerViewController）：本页自带纯色 groupedBackground，磨砂带叠上去
    // 在 iOS 26 呈现为「搜索框所在条带比页面白一截」（26 的 ultraThin 材质更透白；18 差异不可见）。
    // 页面静态无滚动穿透，无需磨砂——去掉后栏区与页面同色，玻璃只留搜索胶囊/取消钮本体。
    bar.backgroundEffectProgress = 0;
    bar.tintColor = IMTheme.accent;
    bar.searchPlaceholder = @"搜索会话、联系人、聊天记录";
    bar.searchModeActive = YES;
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar];
    _searchField = bar.searchTextField;
    _searchField.tintColor = IMTheme.accent;
    [_searchField addTarget:self action:@selector(searchFieldChanged) forControlEvents:UIControlEventEditingChanged];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = IMTheme.groupedBackground;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 64;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    // 单一背景面：表格铺满全屏（含状态栏/搜索栏区），内容用 contentInset 给栏让位。
    // 曾把表顶钉在栏下方——栏区显裸 view 的 groupedBackground、表区显 grouped 表格自己渲染的背景，
    // iOS 26 两者有肉眼可见的色差（浅色明显、深色同黑不可见）；整页统一由表格渲染后由构造保证同色。
    _tableView.contentInset = UIEdgeInsetsMake(kIMLiquidBarHeight + 4, 0, 0, 0);
    _tableView.verticalScrollIndicatorInsets = UIEdgeInsetsMake(kIMLiquidBarHeight + 4, 0, 0, 0);
    [_tableView registerClass:IMSearchResultCell.class forCellReuseIdentifier:@"r"];
    [self.view addSubview:_tableView];

    _emptyLabel = [UILabel new];
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.font = [UIFont systemFontOfSize:15];
    _emptyLabel.textColor = IMTheme.textSecondary;
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.hidden = YES;
    [self.view addSubview:_emptyLabel];
    [self.view bringSubviewToFront:bar]; // 表格铺满全屏后与栏区重叠：栏（搜索框/取消）必须浮在表格之上

    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        // 栏高 = 真实安全区 + 56（容器把自持页 additionalSafeAreaInsets 清 0，此处显式补栏行高）。
        [bar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:kIMLiquidBarHeight],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],   // 铺满全屏（单一背景面，见上）
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [_emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 每次出现重读会话/好友快照（作底部搜索 tab 根页长驻，切走再回来数据要最新；也顺带解决快照陈旧）。
    _allConversations = [IMDatabase.sharedDatabase cachedConversations] ?: @[];
    _allFriends = [IMDatabase.sharedDatabase cachedFriends] ?: @[];
    if (_keyword.length > 0) { [self recomputeForKeyword:_keyword]; }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_searchField becomeFirstResponder];
}

#pragma mark - IMLiquidNavigationBarDelegate

- (void)searchFieldChanged { [self recomputeForKeyword:(_searchField.text ?: @"")]; }
// 「取消」：作为**独立页**（会话列表下钻）→ pop 返回；作为**底部搜索 tab 根页**（无处可退）→ 清空+收键盘。
- (void)liquidNavigationBarDidTapAction:(IMLiquidNavigationBar *)bar { [self cancelTapped]; }
- (void)liquidNavigationBarDidTapLeft:(IMLiquidNavigationBar *)bar { [self cancelTapped]; }
- (void)liquidNavigationBarDidTapBack:(IMLiquidNavigationBar *)bar { [self cancelTapped]; }

- (void)cancelTapped {
    if (self.navigationController.viewControllers.firstObject != self) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        _searchField.text = @"";
        [_searchField resignFirstResponder];
        [self recomputeForKeyword:@""];
    }
}

#pragma mark - 搜索

- (NSString *)titleForConversation:(IMConversation *)c {
    if (c.isGroup) { return c.name.length > 0 ? c.name : @"群聊"; }
    return c.peerNickname.length > 0 ? c.peerNickname : (c.peer ?: @"");
}

- (void)recomputeForKeyword:(NSString *)kw {
    _keyword = [kw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (_keyword.length == 0) {
        _convHits = @[]; _friendHits = @[]; _recordGroups = @[]; _sections = @[];
        [self reloadSectionsAndTable];
        return;
    }
    NSString *needle = _keyword.lowercaseString;

    // 会话/群：标题命中
    NSMutableArray<IMConversation *> *convs = [NSMutableArray array];
    for (IMConversation *c in _allConversations) {
        if ([[self titleForConversation:c].lowercaseString containsString:needle]) { [convs addObject:c]; }
    }
    _convHits = convs;

    // 联系人：备注/昵称/uid 命中
    NSMutableArray<IMUserCard *> *friends = [NSMutableArray array];
    for (IMUserCard *f in _allFriends) {
        NSString *name = f.displayName.lowercaseString ?: @"";
        if ([name containsString:needle] || [f.userID.lowercaseString containsString:needle]) { [friends addObject:f]; }
    }
    _friendHits = friends;

    // 聊天记录：本地 DB 全局搜索。**不聚合**：一条命中一行（同会话可出现多行，预期内；2026-08-21 拍板，
    // Web 同口径）。仅保留当前会话列表里存在的会话——本地库可能残留已退群/已删会话的历史消息
    // （删会话只删摘要、消息保留），它们没有可打开的落点。时间倒序（新在前）。
    NSArray<IMMessageModel *> *msgs = [IMDatabase.sharedDatabase searchMessagesMatching:_keyword inConv:nil limit:500];
    NSMutableArray<NSDictionary *> *hits = [NSMutableArray array];
    NSMutableDictionary<NSString *, IMConversation *> *convCache = [NSMutableDictionary dictionary];
    for (IMMessageModel *m in msgs) {
        NSString *cid = m.convID ?: @"";
        if (cid.length == 0) { continue; }
        IMConversation *conv = convCache[cid] ?: [self conversationForID:cid];
        if (!conv) { continue; }  // 残留会话：跳过
        convCache[cid] = conv;
        // 摘要：优先展示**真正命中 needle 的字段**（否则文件名命中却显 caption → 副行无高亮、像误命中，
        // 2026-08-21 /code-review #3）。口径同 searchMessagesMatching：text 的 content / 任意 caption / file_name。
        NSString *snippet = [self snippetForMessage:m needle:needle];
        [hits addObject:@{ @"convID": cid, @"conv": conv,
                           @"title": [self titleForConversation:conv],
                           @"snippet": snippet,
                           @"seq": @(m.convSeq) }];
    }
    _recordGroups = hits;

    [self reloadSectionsAndTable];
}

/// 命中摘要 = 真正含 needle 的字段（needle 已 lowercased）。口径同 searchMessagesMatching:：
/// text 的 content / 任意 caption / file_name；都不含（理论不该发生）时回退 caption>文件名>content。
- (NSString *)snippetForMessage:(IMMessageModel *)m needle:(NSString *)needle {
    BOOL isText = [m.contentType isEqualToString:@"text"];
    if (needle.length > 0) {
        if (m.caption.length > 0 && [m.caption.lowercaseString containsString:needle]) { return m.caption; }
        if (isText && m.content.length > 0 && [m.content.lowercaseString containsString:needle]) { return m.content; }
        if (m.fileName.length > 0 && [m.fileName.lowercaseString containsString:needle]) { return m.fileName; }
    }
    return m.caption.length > 0 ? m.caption : (m.fileName.length > 0 ? m.fileName : (m.content ?: @""));
}

- (nullable IMConversation *)conversationForID:(NSString *)cid {
    for (IMConversation *c in _allConversations) { if ([c.convID isEqualToString:cid]) { return c; } }
    return nil;
}

- (void)reloadSectionsAndTable {
    NSMutableArray<NSNumber *> *secs = [NSMutableArray array];
    if (_convHits.count > 0) { [secs addObject:@(IMSearchGroupConversation)]; }
    if (_friendHits.count > 0) { [secs addObject:@(IMSearchGroupContact)]; }
    if (_recordGroups.count > 0) { [secs addObject:@(IMSearchGroupRecord)]; }
    // 有关键词就恒显「搜索用户「x」」入口（在线找人/加好友）——本地无匹配时它就是唯一结果，替代原找人页。
    if (_keyword.length > 0) { [secs addObject:@(IMSearchGroupUser)]; }
    _sections = secs;
    _emptyLabel.hidden = YES;  // 用户入口恒在，不再有「未找到相关内容」空态
    [_tableView reloadData];
}


#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return (NSInteger)_sections.count; }

- (IMSearchGroup)groupForSection:(NSInteger)section { return (IMSearchGroup)_sections[section].integerValue; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ([self groupForSection:section]) {
        case IMSearchGroupConversation: return (NSInteger)_convHits.count;
        case IMSearchGroupContact:      return (NSInteger)_friendHits.count;
        case IMSearchGroupRecord:       return (NSInteger)_recordGroups.count;
        case IMSearchGroupUser:         return 1;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch ([self groupForSection:section]) {
        case IMSearchGroupConversation: return @"会话";
        case IMSearchGroupContact:      return @"联系人";
        case IMSearchGroupRecord:       return @"聊天记录";
        case IMSearchGroupUser:         return @"用户";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    IMSearchResultCell *cell = [tableView dequeueReusableCellWithIdentifier:@"r" forIndexPath:ip];
    switch ([self groupForSection:ip.section]) {
        case IMSearchGroupConversation: {
            IMConversation *c = _convHits[(NSUInteger)ip.row];
            NSString *title = [self titleForConversation:c];
            [cell configureAvatarURL:(c.isGroup ? c.avatarURL : c.peerAvatarURL)
                                seed:(c.isGroup ? c.convID : (c.peer ?: c.convID))
                         displayName:title title:title
                            subtitle:c.isGroup ? [NSString stringWithFormat:@"%ld 人", (long)c.memberCount] : nil
                             keyword:_keyword];
            break;
        }
        case IMSearchGroupContact: {
            IMUserCard *f = _friendHits[(NSUInteger)ip.row];
            [cell configureAvatarURL:f.avatarURL seed:f.userID displayName:f.displayName
                               title:f.displayName subtitle:@"联系人" keyword:_keyword];
            break;
        }
        case IMSearchGroupRecord: {
            NSDictionary *g = _recordGroups[(NSUInteger)ip.row];
            IMConversation *c = g[@"conv"];
            NSString *title = g[@"title"];
            // 不聚合：副行 = 该条命中的内容摘要（命中词高亮）。
            [cell configureAvatarURL:(c.isGroup ? c.avatarURL : c.peerAvatarURL)
                                seed:(c.isGroup ? c.convID : (c.peer ?: c.convID))
                         displayName:title title:title
                            subtitle:(g[@"snippet"] ?: @"") keyword:_keyword];
            break;
        }
        case IMSearchGroupUser: {
            [cell configureAvatarURL:nil seed:@"__user_search__" displayName:@"搜"
                               title:[NSString stringWithFormat:@"搜索用户「%@」", _keyword]
                            subtitle:@"按 uid / 手机号精确查找、加好友" keyword:nil];
            break;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    switch ([self groupForSection:ip.section]) {
        case IMSearchGroupConversation: [self openConversation:_convHits[(NSUInteger)ip.row] jumpToSeq:0]; break;
        case IMSearchGroupContact: {
            IMUserCard *f = _friendHits[(NSUInteger)ip.row];
            if (f.userID.length == 0 || [f.userID isEqualToString:_userID]) { return; }
            [IMChatViewController openInNavigationController:self.navigationController host:_host userID:_userID
                                                     peerID:f.userID readSeq:0 unread:0 peerReadSeq:0
                                               peerNickname:f.displayName peerAvatarURL:f.avatarURL];
            break;
        }
        case IMSearchGroupRecord: {
            NSDictionary *g = _recordGroups[(NSUInteger)ip.row];
            IMConversation *conv = g[@"conv"];
            // 直接定位到最近命中那条（不开聊天页的搜索模式，2026-08-20 拍板；Web 同口径）。
            if (conv) { [self openConversation:conv jumpToSeq:[g[@"seq"] longLongValue]]; }
            break;
        }
        case IMSearchGroupUser: {
            [self.navigationController pushViewController:
                [[IMUserSearchViewController alloc] initWithHost:_host userID:_userID initialQuery:_keyword] animated:YES];
            break;
        }
    }
}

/// 打开会话（单聊/群聊）；jumpSeq>0 则打开后直接定位到该 conv_seq（居中高亮，不进搜索模式）。
- (void)openConversation:(IMConversation *)c jumpToSeq:(int64_t)jumpSeq {
    IMChatViewController *chat;
    if (c.isGroup) {
        chat = [IMChatViewController openInNavigationController:self.navigationController host:_host userID:_userID
                                                   groupConvID:c.convID groupName:c.name
                                                       readSeq:c.readSeq unread:c.unread
                                                  groupReadSeq:c.groupReadSeq groupAvatarURL:c.avatarURL];
    } else {
        if (c.peer.length == 0 || [c.peer isEqualToString:_userID]) { return; }
        chat = [IMChatViewController openInNavigationController:self.navigationController host:_host userID:_userID
                                                        peerID:c.peer readSeq:c.readSeq unread:c.unread
                                                   peerReadSeq:c.peerReadSeq
                                                  peerNickname:c.peerNickname peerAvatarURL:c.peerAvatarURL];
    }
    if (jumpSeq > 0 && chat) {
        // 定位必须**晚于聊天页的全部进场定位**（positionInitialIfNeeded 钉底/未读位 + viewDidAppear 落定校正），
        // 否则跳完被拉回底部——固定 0.45s 曾与之撞车（时序随设备浮动）。改挂 push 转场完成块（晚于目标页
        // viewDidAppear）再延 0.35s 让开落定校正与首次 sync 合并，然后 jumpToConvSeq:（居中+闪烁高亮）。
        void (^jump)(void) = ^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [chat jumpToConvSeq:jumpSeq];
            });
        };
        id<UIViewControllerTransitionCoordinator> tc = self.navigationController.transitionCoordinator;
        if (tc) {
            [tc animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) { jump(); }];
        } else {
            jump();
        }
    }
}

@end
