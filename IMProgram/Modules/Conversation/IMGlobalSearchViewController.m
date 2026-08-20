//  IMGlobalSearchViewController.m

#import "IMGlobalSearchViewController.h"
#import "IMDatabase.h"
#import "IMConversation.h"
#import "IMUserCard.h"
#import "IMMessageModel.h"
#import "IMChatViewController.h"
#import "IMTheme.h"
#import "IMMainTabBarController.h" // kIMLiquidBarHeight
#import "IMProgram-Swift.h"        // IMLiquidNavigationBar（searchMode）

typedef NS_ENUM(NSInteger, IMSearchGroup) {
    IMSearchGroupConversation = 0,
    IMSearchGroupContact,
    IMSearchGroupRecord,
};

#pragma mark - 结果行 cell（自持，不复用会话列表私有 cell）

@interface IMSearchResultCell : UITableViewCell
@property (nonatomic, strong) UILabel *avatarLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
- (void)configureSeed:(NSString *)seed initial:(NSString *)initial title:(NSString *)title subtitle:(nullable NSString *)subtitle;
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

- (void)configureSeed:(NSString *)seed initial:(NSString *)initial title:(NSString *)title subtitle:(nullable NSString *)subtitle {
    self.avatarLabel.backgroundColor = [IMTheme avatarColorForSeed:seed];
    self.avatarLabel.text = initial.length > 0 ? [[initial substringToIndex:1] uppercaseString] : @"?";
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    self.subtitleLabel.hidden = (subtitle.length == 0);
}

@end

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
    NSArray<NSDictionary *> *_recordGroups;  // {@"convID",@"title",@"count",@"snippet",@"conv"?}
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

    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        // 栏高 = 真实安全区 + 56（容器把自持页 additionalSafeAreaInsets 清 0，此处显式补栏行高）。
        [bar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:kIMLiquidBarHeight],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:kIMLiquidBarHeight + 4],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [_emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_searchField becomeFirstResponder];
}

#pragma mark - IMLiquidNavigationBarDelegate

- (void)searchFieldChanged { [self recomputeForKeyword:(_searchField.text ?: @"")]; }
- (void)liquidNavigationBarDidTapAction:(IMLiquidNavigationBar *)bar { [self.navigationController popViewControllerAnimated:YES]; }
- (void)liquidNavigationBarDidTapLeft:(IMLiquidNavigationBar *)bar { [self.navigationController popViewControllerAnimated:YES]; }
- (void)liquidNavigationBarDidTapBack:(IMLiquidNavigationBar *)bar { [self.navigationController popViewControllerAnimated:YES]; }

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

    // 聊天记录：本地 DB 全局搜索，按会话聚合
    NSArray<IMMessageModel *> *msgs = [IMDatabase.sharedDatabase searchMessagesMatching:_keyword inConv:nil limit:500];
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableDictionary *> *byConv = [NSMutableDictionary dictionary];
    for (IMMessageModel *m in msgs) {
        NSString *cid = m.convID ?: @"";
        if (cid.length == 0) { continue; }
        NSMutableDictionary *g = byConv[cid];
        if (!g) {
            g = [@{ @"convID": cid, @"count": @0 } mutableCopy];
            NSString *snippet = m.caption.length > 0 ? m.caption : (m.content ?: @"");
            g[@"snippet"] = snippet;  // msgs 已按时间倒序 → 首条=最新命中
            byConv[cid] = g; [order addObject:cid];
        }
        g[@"count"] = @([g[@"count"] integerValue] + 1);
    }
    NSMutableArray<NSDictionary *> *groups = [NSMutableArray array];
    for (NSString *cid in order) {
        NSMutableDictionary *g = byConv[cid];
        IMConversation *conv = [self conversationForID:cid];
        g[@"title"] = conv ? [self titleForConversation:conv] : cid;
        if (conv) { g[@"conv"] = conv; }
        [groups addObject:g];
    }
    _recordGroups = groups;

    [self reloadSectionsAndTable];
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
    _sections = secs;
    BOOL empty = (_keyword.length > 0 && secs.count == 0);
    _emptyLabel.hidden = !empty;
    _emptyLabel.text = empty ? @"未找到相关内容" : nil;
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
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch ([self groupForSection:section]) {
        case IMSearchGroupConversation: return @"会话";
        case IMSearchGroupContact:      return @"联系人";
        case IMSearchGroupRecord:       return @"聊天记录";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    IMSearchResultCell *cell = [tableView dequeueReusableCellWithIdentifier:@"r" forIndexPath:ip];
    switch ([self groupForSection:ip.section]) {
        case IMSearchGroupConversation: {
            IMConversation *c = _convHits[(NSUInteger)ip.row];
            NSString *title = [self titleForConversation:c];
            [cell configureSeed:c.convID initial:title title:title
                       subtitle:c.isGroup ? [NSString stringWithFormat:@"%ld 人", (long)c.memberCount] : nil];
            break;
        }
        case IMSearchGroupContact: {
            IMUserCard *f = _friendHits[(NSUInteger)ip.row];
            [cell configureSeed:f.userID initial:f.displayName title:f.displayName subtitle:@"联系人"];
            break;
        }
        case IMSearchGroupRecord: {
            NSDictionary *g = _recordGroups[(NSUInteger)ip.row];
            NSString *title = g[@"title"];
            NSInteger count = [g[@"count"] integerValue];
            NSString *sub = [NSString stringWithFormat:@"%ld 条相关消息 · %@", (long)count, g[@"snippet"] ?: @""];
            [cell configureSeed:g[@"convID"] initial:title title:title subtitle:sub];
            break;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    switch ([self groupForSection:ip.section]) {
        case IMSearchGroupConversation: [self openConversation:_convHits[(NSUInteger)ip.row] withSearch:nil]; break;
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
            if (conv) { [self openConversation:conv withSearch:_keyword]; }
            break;
        }
    }
}

/// 打开会话（单聊/群聊）；withSearch 非空则打开后进「会话内搜索」预填同词。
- (void)openConversation:(IMConversation *)c withSearch:(nullable NSString *)kw {
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
    if (kw.length > 0 && chat) {
        // 等消息从本地库载入后再进搜索态（预填同词、跳最新命中）。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [chat beginInChatSearchWithKeyword:kw];
        });
    }
}

@end
