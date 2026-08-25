//  IMFavoritesViewController.m
//  收藏页 · B 方案（FAVORITES_DESIGN §14，已拍板 2026-08-19）：保留 im_favorite、零后端，**复用会话详情页的分签展示件**。
//  · 消息模式（默认）：分段 [媒体|文件|链接|语音|文本|聊天记录]（仅存在者，口径 IMFavoritesCategories，无「全部」）。
//    媒体 = IMDetailMediaContainerCell 3 列宫格（逐格门控/进度/长按）；文件 = IMDetailFileCell 三态行（↓/环/图标/↻）；
//    链接/文本/聊天记录 = 统一图标行。下载态经合成 IMMessageModel 喂 IMMediaDownloadCoordinator（与聊天页/详情页共享）。
//  · 聊天模式：按 source_conv_id 分组的来源会话列表（自己发的/无来源归「我的」）→ 点进同一页按来源过滤。
//  · 右上玻璃 ⋯（注入式 IMLiquidNavigationBar 映射 navigationItem.rightBarButtonItem）→ IMPopoverCard 互斥菜单切换，
//    偏好 NSUserDefaults 持久化；标题副行显当前模式。
//  · 搜索范围 token 恒=当前签（无全部可回退，token 不可删，切签即换）。
//  注：聊天页「从收藏发送」（Pick）入口仍暂屏蔽（设计保留）。清缓存联动维持现状（不加通知）。

#import "IMFavoritesViewController.h"
#import "IMFavoritesCategories.h"
#import "IMHTTPService.h"
#import "IMMediaUtil.h"
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMediaViewerViewController.h"
#import "IMMediaPagerViewController.h"
#import "IMConversationMediaViewController.h" // IMMediaItem
#import "IMDetailMediaContainerCell.h"
#import "IMDetailFileCell.h"
#import "IMFavoriteLinkCell.h"
#import "IMForwardPickerViewController.h"
#import "IMChatRecordViewController.h"
#import "IMSocketManager.h"
#import "IMMediaAttributes.h"
#import "IMDatabase.h"
#import "IMConversation.h"
#import "IMUserCard.h"
#import "IMGroupInfo.h"
#import "IMMessageModel.h"
#import "IMMediaDownloadCoordinator.h"
#import "IMDownloadProgress.h"
#import "IMLiquidSegmentedControl.h"
#import "IMGlass.h"
#import "IMQRResultRouter.h"
#import "IMPopoverCard.h"
#import "IMMainTabBarController.h" // im_refreshNavigationBar
#import "UILabel+IMAvatar.h"
#import "IMTheme.h"
#import "IMTimeUtil.h"
#import "UIViewController+IMToast.h"
#import <SafariServices/SafariServices.h>
#import <QuickLook/QuickLook.h>

static NSString *const kIMFavoritesViewModeKey = @"im.favorites.viewMode"; // 0=消息模式 1=聊天模式
static NSString *const kIMFavoritesMeBucket = @"__im_fav_me__";            // 聊天模式「我的」分组键
static CGFloat const kIMFavSegH = 40;                                        // 分段本体（同详情页 kIMDetailTabSegH）

typedef NS_ENUM(NSInteger, IMFavoritesViewMode) {
    IMFavoritesViewModeMessages = 0, ///< 以消息模式查看：分签
    IMFavoritesViewModeChats,        ///< 以聊天模式查看：按来源会话分组
};

#pragma mark - 收藏阅读器（点文本 → 全文只读页，§5.6）

@interface IMFavoriteReaderViewController : UIViewController
- (instancetype)initWithText:(NSString *)text;
@end
@implementation IMFavoriteReaderViewController { NSString *_text; }
- (instancetype)initWithText:(NSString *)text {
    self = [super init];
    if (self) { _text = [text copy]; self.title = @"收藏"; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = IMTheme.groupedBackground;
    UITextView *tv = [UITextView new];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.editable = NO; tv.selectable = YES;
    tv.backgroundColor = UIColor.clearColor;
    tv.textColor = IMTheme.textPrimary;
    tv.font = [UIFont systemFontOfSize:IMTheme.chatFontSize];
    tv.text = _text;
    tv.textContainerInset = UIEdgeInsetsMake(16, 16, 16, 16);
    [self.view addSubview:tv];
    [NSLayoutConstraint activateConstraints:@[
        [tv.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [tv.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [tv.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tv.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}
@end

#pragma mark - 行 Cell（链接 / 文本 / 聊天记录 / 语音：统一 52pt 图标列，§4.1 / §12）

@interface IMFavoriteRowCell : UITableViewCell
- (void)configureWithFavorite:(NSDictionary *)fav kind:(IMFavoriteCategory)kind source:(nullable NSString *)source;
@end
@implementation IMFavoriteRowCell { UIView *_tile; UIImageView *_glyph; UILabel *_title; UILabel *_meta; }
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _tile = [UIView new];
        _tile.translatesAutoresizingMaskIntoConstraints = NO;
        _tile.layer.cornerRadius = 10; _tile.clipsToBounds = YES;
        _tile.backgroundColor = IMTheme.accentSoft;
        [self.contentView addSubview:_tile];
        _glyph = [UIImageView new];
        _glyph.translatesAutoresizingMaskIntoConstraints = NO;
        _glyph.contentMode = UIViewContentModeScaleAspectFit;
        _glyph.tintColor = IMTheme.accent;
        [_tile addSubview:_glyph];
        _title = [UILabel new];
        _title.font = [UIFont systemFontOfSize:15];
        _title.textColor = IMTheme.textPrimary;
        _title.numberOfLines = 3;
        _meta = [UILabel new];
        _meta.font = [UIFont systemFontOfSize:13];
        _meta.textColor = IMTheme.textTertiary;
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_title, _meta]];
        stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 3;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [_tile.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_tile.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_tile.widthAnchor constraintEqualToConstant:52], [_tile.heightAnchor constraintEqualToConstant:52],
            [_glyph.centerXAnchor constraintEqualToAnchor:_tile.centerXAnchor],
            [_glyph.centerYAnchor constraintEqualToAnchor:_tile.centerYAnchor],
            [_glyph.widthAnchor constraintEqualToConstant:26], [_glyph.heightAnchor constraintEqualToConstant:26],
            [stack.leadingAnchor constraintEqualToAnchor:_tile.trailingAnchor constant:12],
            [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [stack.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [stack.topAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.topAnchor constant:8],
            [stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-8],
        ]];
    }
    return self;
}
- (void)configureWithFavorite:(NSDictionary *)fav kind:(IMFavoriteCategory)kind source:(NSString *)source {
    NSString *content = [fav[@"content"] isKindOfClass:NSString.class] ? fav[@"content"] : @"";
    int64_t createdAt = [fav[@"created_at"] respondsToSelector:@selector(longLongValue)] ? [fav[@"created_at"] longLongValue] : 0;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold];
    _title.textColor = IMTheme.textPrimary;
    _title.numberOfLines = 2; // 文本封顶 2 行，给副行「来自X · 时间」留位（#1）
    NSString *symbol = @"text.quote";
    switch (kind) {
        // Links 分支已迁走：走独立 IMFavoriteLinkCell（草图 §D，36×36 favicon + 三行 + quote + source），
        // cellForRow 里已按 kind 分流。此处的老 case 保留兜底：万一新 cell 未 register 走到这里，仍能显 URL。
        case IMFavoriteCategoryLinks:
            symbol = @"link"; _title.numberOfLines = 2; _title.textColor = IMTheme.accent; _title.text = content; break;
        case IMFavoriteCategoryRecord: {
            symbol = @"bubble.left.and.bubble.right"; _title.numberOfLines = 2;
            NSString *snippet = IMChatRecordSnippet(content);
            _title.text = snippet.length > 0 ? snippet : @"聊天记录"; break;
        }
        case IMFavoriteCategoryVoice:
            symbol = @"waveform"; _title.numberOfLines = 1; _title.text = @"语音消息"; break;
        default:
            _title.text = content; break;
    }
    _glyph.image = [[UIImage systemImageNamed:symbol withConfiguration:cfg] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    NSString *when = createdAt > 0 ? IMFormatFileDateTime(createdAt) : @"";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (source.length > 0) { [parts addObject:[@"来自" stringByAppendingString:source]]; }
    if (when.length > 0) { [parts addObject:when]; }
    _meta.text = [parts componentsJoinedByString:@" · "];
}
@end

#pragma mark - 来源会话行（聊天模式）

@interface IMFavoriteSourceCell : UITableViewCell
- (void)configureWithName:(NSString *)name avatarURL:(NSString *)avatarURL seed:(NSString *)seed preview:(NSString *)preview count:(NSInteger)count;
@end
@implementation IMFavoriteSourceCell { UILabel *_avatar; UILabel *_name; UILabel *_preview; UILabel *_count; }
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        // 复用会话列表 cell 的头像视觉：im_setAvatarURL: 只设首字母文本+底色，字号/白字/居中/圆裁剪须调用方给（否则首字母黑字小号左对齐）。
        _avatar.textColor = UIColor.whiteColor;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
        _avatar.layer.cornerRadius = 23; _avatar.layer.masksToBounds = YES;
        [self.contentView addSubview:_avatar];
        _name = [UILabel new]; _name.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]; _name.textColor = IMTheme.textPrimary;
        _preview = [UILabel new]; _preview.font = [UIFont systemFontOfSize:13]; _preview.textColor = IMTheme.textSecondary; _preview.lineBreakMode = NSLineBreakByTruncatingTail;
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_name, _preview]];
        stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 2;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        _count = [UILabel new]; _count.font = [UIFont systemFontOfSize:13]; _count.textColor = IMTheme.textTertiary;
        _count.translatesAutoresizingMaskIntoConstraints = NO;
        [_count setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentView addSubview:_count];
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:46], [_avatar.heightAnchor constraintEqualToConstant:46],
            [stack.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:12],
            [stack.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_count.leadingAnchor constraintEqualToAnchor:stack.trailingAnchor constant:8],
            [_count.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
            [_count.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
    }
    return self;
}
- (void)configureWithName:(NSString *)name avatarURL:(NSString *)avatarURL seed:(NSString *)seed preview:(NSString *)preview count:(NSInteger)count {
    [_avatar im_setAvatarURL:avatarURL seed:seed displayName:name];
    _name.text = name; _preview.text = preview;
    _count.text = [NSString stringWithFormat:@"%ld", (long)count];
}
@end

#pragma mark - 来源分组值对象

@interface IMFavoriteSourceGroup : NSObject
@property (nonatomic, copy) NSString *key;          // source_conv_id 或 kIMFavoritesMeBucket
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *avatarURL;
@property (nonatomic, copy) NSString *seed;
@property (nonatomic, copy) NSString *preview;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, assign) int64_t latest;
@end
@implementation IMFavoriteSourceGroup @end

#pragma mark - 收藏页

// ⚠️ 普通 UIViewController + 内嵌 UITableView（非 UITableViewController）：导航容器注入的液态栏若挂在滚动视图上会随负
// contentOffset 下移（已踩坑三次）。顶部搜索/分段做静止 headerBar 挂 self.view。
@interface IMFavoritesViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, QLPreviewControllerDataSource>
- (NSString *)im_navigationSubtitle; // 注入栏副标题（IMMainNavigationController 经 respondsToSelector 探测）
@end

@implementation IMFavoritesViewController {
    UITableView *_tableView;
    UISearchBar *_searchBar;
    IMLiquidSegmentedControl *_segmented;
    NSLayoutConstraint *_segHeight;
    UIView *_headerBar;
    UIView *_emptyView; UIImageView *_emptyIcon; UILabel *_emptyTitle; UILabel *_emptySub;

    IMFavoritesViewMode _mode;
    NSString *_sourceFilterKey;      // nil=根页；非 nil=按来源过滤的子页（聊天模式下钻）
    NSString *_sourceFilterName;

    NSArray<NSDictionary *> *_allItems;   // 服务端全量
    NSArray<NSDictionary *> *_scoped;     // 按来源过滤后（根页=全量）
    NSArray<IMFavoriteCategoryTab *> *_categories;
    IMFavoriteCategory _selectedKind;
    NSString *_searchText;
    BOOL _loadFailed;
    BOOL _syncingToken;

    // 当前签数据（消息模式）
    NSArray<NSDictionary *> *_rows;                 // 非媒体签：过滤后的收藏
    NSArray<NSDictionary *> *_mediaFavs;            // 媒体签：过滤后的收藏（与 _mediaModels/_mediaItems 逐位对齐）
    NSArray<IMMessageModel *> *_mediaModels;
    NSArray<IMMediaItem *> *_mediaItems;
    IMDetailMediaContainerCell *_mediaContainerCell;
    CGFloat _mediaGridWidth;
    // 聊天模式
    NSArray<IMFavoriteSourceGroup *> *_groups;
    NSArray<IMFavoriteSourceGroup *> *_shownGroups;

    NSMutableDictionary<NSString *, IMMessageModel *> *_models; // favId → 合成消息模型（供编排器跟踪同一实例）
    IMMediaDownloadCoordinator *_downloads;
    NSURL *_quickLookURL;
    IMDatabaseAccountContext *_databaseContext;
    NSString *_selfUID;
    NSDictionary<NSString *, IMConversation *> *_convByID; // 来源会话名/头像查表
    NSDictionary<NSString *, IMUserCard *> *_friendByID;   // 好友：source_from→显示名（含备注）
    NSDictionary<NSString *, IMGroupInfo *> *_groupByID;   // 群：source_conv_id→成员（取群昵称）
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"收藏消息";
        _mode = (IMFavoritesViewMode)[NSUserDefaults.standardUserDefaults integerForKey:kIMFavoritesViewModeKey];
        if (_mode != IMFavoritesViewModeChats) { _mode = IMFavoritesViewModeMessages; }
    }
    return self;
}

/// 来源过滤子页（聊天模式下钻）：恒消息模式、无模式菜单。
- (instancetype)initWithSourceFilterKey:(NSString *)key name:(NSString *)name items:(NSArray<NSDictionary *> *)items {
    self = [self init];
    if (self) {
        _mode = IMFavoritesViewModeMessages;
        _sourceFilterKey = [key copy];
        _sourceFilterName = [name copy];
        _allItems = items ?: @[];
        self.title = [NSString stringWithFormat:@"来自 %@", name ?: @""];
    }
    return self;
}

- (NSString *)im_navigationSubtitle {
    if (_sourceFilterKey) { return [NSString stringWithFormat:@"%lu 条收藏", (unsigned long)_scoped.count]; }
    return _mode == IMFavoritesViewModeChats ? @"以聊天模式查看" : @"以消息模式查看";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (!_allItems) { _allItems = @[]; }
    _scoped = @[]; _categories = @[]; _rows = @[]; _mediaFavs = @[]; _mediaModels = @[]; _mediaItems = @[];
    _groups = @[]; _shownGroups = @[];
    _selectedKind = IMFavoriteCategoryMedia;
    _searchText = @"";
    _models = [NSMutableDictionary dictionary];
    self.view.backgroundColor = IMTheme.groupedBackground;

    IMDatabaseAccountContext *ctx = IMDatabase.sharedDatabase.currentAccountContext;
    _databaseContext = ctx;
    _selfUID = ctx.ownerUserID ?: @"";
    [self loadConversationIndex];

    // 下载编排器（与聊天页/详情页共享任务与缓存）：myUserID 传哨兵使收藏文件一律按"收到"门控；autoPrefetch 关（浏览收藏不自动拉）。
    _downloads = [[IMMediaDownloadCoordinator alloc] initWithHost:(IMHTTPService.sharedService.host ?: @"")
                                                         myUserID:@"__im_fav_no_owner__" isGroup:NO];
    _downloads.autoPrefetchEnabled = NO;
    __weak typeof(self) ws = self;
    _downloads.onProgress = ^(IMMessageModel *message, IMDownloadProgress *state) { [ws updateDownloadCellForModel:message state:state]; };
    _downloads.onStateChanged = ^(IMMessageModel *message) { [ws refreshDownloadRowForModel:message]; }; // 完成不自动打开（铁律②）

    [self buildHeaderBar];
    [self buildTableView];
    [self buildEmptyView];
    [self installModeButton];

    if (_sourceFilterKey) { [self rebuildAll]; } else { [self reload]; }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 回前台抢回仍在跑的下载回调（同详情页），防返回后进度冻结。
    if (_downloads) {
        NSMutableArray<IMMessageModel *> *ms = [NSMutableArray arrayWithArray:_mediaModels];
        for (NSDictionary *f in _rows) { IMMessageModel *m = _models[[self idKeyOf:f]]; if (m) { [ms addObject:m]; } }
        [_downloads reattachActiveTasksForMessages:ms];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    IMApplyUnifiedSearchFieldStyle(_searchBar);
}

#pragma mark 构建

- (void)buildHeaderBar {
    _headerBar = [UIView new];
    _headerBar.translatesAutoresizingMaskIntoConstraints = NO;
    _headerBar.backgroundColor = IMTheme.groupedBackground;
    [self.view addSubview:_headerBar];

    _searchBar = [UISearchBar new];
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    _searchBar.delegate = self;
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.tintColor = IMTheme.accent;
    IMApplyUnifiedSearchFieldStyle(_searchBar);
    [_headerBar addSubview:_searchBar];

    _segmented = [IMLiquidSegmentedControl new];
    _segmented.translatesAutoresizingMaskIntoConstraints = NO;
    [_segmented addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    [_headerBar addSubview:_segmented];
    _segHeight = [_segmented.heightAnchor constraintEqualToConstant:kIMFavSegH];

    [NSLayoutConstraint activateConstraints:@[
        [_headerBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_headerBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_headerBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_searchBar.topAnchor constraintEqualToAnchor:_headerBar.topAnchor constant:4],
        [_searchBar.leadingAnchor constraintEqualToAnchor:_headerBar.leadingAnchor constant:8],
        [_searchBar.trailingAnchor constraintEqualToAnchor:_headerBar.trailingAnchor constant:-8],
        [_segmented.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor constant:4],
        [_segmented.leadingAnchor constraintEqualToAnchor:_headerBar.leadingAnchor constant:16],
        [_segmented.trailingAnchor constraintEqualToAnchor:_headerBar.trailingAnchor constant:-16],
        _segHeight,
        [_segmented.bottomAnchor constraintEqualToAnchor:_headerBar.bottomAnchor constant:-6],
    ]];
}

- (void)buildTableView {
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = IMTheme.groupedBackground;
    _tableView.dataSource = self; _tableView.delegate = self;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _tableView.contentInset = UIEdgeInsetsMake(-14, 0, 0, 0); // 收紧 inset-grouped 顶部留白，贴近分段
    [_tableView registerClass:IMFavoriteRowCell.class forCellReuseIdentifier:@"row"];
    [_tableView registerClass:IMFavoriteLinkCell.class forCellReuseIdentifier:@"favlink"];
    _tableView.estimatedRowHeight = 90; // Links 走 auto dimension（含/无 quote 差 ~40pt），需估高避免首帧跳
    [_tableView registerClass:IMFavoriteSourceCell.class forCellReuseIdentifier:@"src"];
    [_tableView registerClass:IMDetailFileCell.class forCellReuseIdentifier:@"detailfile"];
    [_tableView registerClass:IMDetailMediaContainerCell.class forCellReuseIdentifier:@"mediagrid"];
    UIRefreshControl *rc = [UIRefreshControl new];
    [rc addTarget:self action:@selector(pullToRefresh:) forControlEvents:UIControlEventValueChanged];
    _tableView.refreshControl = rc;
    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:_headerBar.bottomAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)buildEmptyView {
    _emptyView = [UIView new];
    _emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyView.hidden = YES;
    [self.view addSubview:_emptyView];
    _emptyIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bookmark"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:44 weight:UIImageSymbolWeightRegular]]];
    _emptyIcon.tintColor = IMTheme.accent;
    _emptyIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [_emptyView addSubview:_emptyIcon];
    _emptyTitle = [UILabel new];
    _emptyTitle.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _emptyTitle.textColor = IMTheme.textPrimary; _emptyTitle.textAlignment = NSTextAlignmentCenter;
    _emptyTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [_emptyView addSubview:_emptyTitle];
    _emptySub = [UILabel new];
    _emptySub.font = [UIFont systemFontOfSize:13]; _emptySub.textColor = IMTheme.textTertiary;
    _emptySub.textAlignment = NSTextAlignmentCenter; _emptySub.numberOfLines = 0;
    _emptySub.translatesAutoresizingMaskIntoConstraints = NO;
    [_emptyView addSubview:_emptySub];
    [NSLayoutConstraint activateConstraints:@[
        [_emptyView.centerXAnchor constraintEqualToAnchor:_tableView.centerXAnchor],
        [_emptyView.centerYAnchor constraintEqualToAnchor:_tableView.centerYAnchor constant:-20],
        [_emptyView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:40],
        [_emptyView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-40],
        [_emptyIcon.topAnchor constraintEqualToAnchor:_emptyView.topAnchor],
        [_emptyIcon.centerXAnchor constraintEqualToAnchor:_emptyView.centerXAnchor],
        [_emptyTitle.topAnchor constraintEqualToAnchor:_emptyIcon.bottomAnchor constant:14],
        [_emptyTitle.leadingAnchor constraintEqualToAnchor:_emptyView.leadingAnchor],
        [_emptyTitle.trailingAnchor constraintEqualToAnchor:_emptyView.trailingAnchor],
        [_emptySub.topAnchor constraintEqualToAnchor:_emptyTitle.bottomAnchor constant:6],
        [_emptySub.leadingAnchor constraintEqualToAnchor:_emptyView.leadingAnchor],
        [_emptySub.trailingAnchor constraintEqualToAnchor:_emptyView.trailingAnchor],
        [_emptySub.bottomAnchor constraintEqualToAnchor:_emptyView.bottomAnchor],
    ]];
}

/// 右上玻璃 ⋯（注入栏把 navigationItem.rightBarButtonItem 渲染成圆形玻璃钮）。来源子页不显。
- (void)installModeButton {
    if (_sourceFilterKey) { return; }
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis"]
                                                              style:UIBarButtonItemStylePlain target:self action:@selector(modeTapped:)];
    item.accessibilityLabel = @"查看模式";
    self.navigationItem.rightBarButtonItem = item;
    [self im_refreshNavigationBar];
}

- (void)modeTapped:(UIBarButtonItem *)item {
    if ([IMPopoverCard isPresentingInHostView:self.view]) { return; }
    __weak typeof(self) ws = self;
    BOOL chats = _mode == IMFavoritesViewModeChats;
    NSArray<IMPopoverCardItem *> *items = @[
        [IMPopoverCardItem itemWithTitle:(chats ? @"以消息模式查看" : @"✓ 以消息模式查看") symbol:@"square.grid.2x2" destructive:NO
                                 handler:^{ [ws setMode:IMFavoritesViewModeMessages]; }],
        [IMPopoverCardItem itemWithTitle:(chats ? @"✓ 以聊天模式查看" : @"以聊天模式查看") symbol:@"bubble.left.and.bubble.right" destructive:NO
                                 handler:^{ [ws setMode:IMFavoritesViewModeChats]; }],
    ];
    [IMPopoverCard presentFromBarButtonItem:item inHostView:self.view items:items];
}

- (void)setMode:(IMFavoritesViewMode)mode {
    if (mode == _mode) { return; }
    _mode = mode;
    [NSUserDefaults.standardUserDefaults setInteger:mode forKey:kIMFavoritesViewModeKey];
    _searchText = @""; _searchBar.text = @"";
    [self rebuildAll];
    [self im_refreshNavigationBar]; // 副标题随模式变
}

#pragma mark 数据

- (BOOL)performDatabaseOperation:(void (^)(IMDatabase *database))operation {
    return [IMDatabase.sharedDatabase performWithAccountContext:_databaseContext block:operation];
}

- (void)loadConversationIndex {
    __block NSArray<IMConversation *> *convs = @[];
    __block NSArray<IMUserCard *> *friends = @[];
    __block NSArray<IMGroupInfo *> *groups = @[];
    [self performDatabaseOperation:^(IMDatabase *database) {
        convs = database.cachedConversations ?: @[];
        friends = database.cachedFriends ?: @[];
        groups = database.cachedGroups ?: @[];
    }];
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (IMConversation *c in convs) { if (c.convID.length) { d[c.convID] = c; } }
    _convByID = d;
    NSMutableDictionary *fd = [NSMutableDictionary dictionary];
    for (IMUserCard *u in friends) { if (u.userID.length) { fd[u.userID] = u; } }
    _friendByID = fd;
    NSMutableDictionary *gd = [NSMutableDictionary dictionary];
    for (IMGroupInfo *g in groups) { if (g.convID.length) { gd[g.convID] = g; } }
    _groupByID = gd;
}

- (void)pullToRefresh:(UIRefreshControl *)rc { [self reload]; }

- (void)reload {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [_tableView.refreshControl endRefreshing]; return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService favoritesWithToken:token completion:^(NSArray<NSDictionary *> *favorites, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        [self->_tableView.refreshControl endRefreshing];
        if (error) { self->_loadFailed = YES; } // 失败保留旧数据（§7）
        else { self->_loadFailed = NO; self->_allItems = favorites ?: @[]; }
        [self loadConversationIndex];
        [self rebuildAll];
    }];
}

- (NSString *)idKeyOf:(NSDictionary *)f {
    int64_t fid = [f[@"id"] respondsToSelector:@selector(longLongValue)] ? [f[@"id"] longLongValue] : 0;
    return [NSString stringWithFormat:@"%lld", fid];
}

/// 聊天模式分组键：自己发的 / 无来源 → 「我的」；否则 source_conv_id。
- (NSString *)groupKeyOf:(NSDictionary *)f {
    NSString *from = [f[@"source_from"] isKindOfClass:NSString.class] ? f[@"source_from"] : @"";
    NSString *conv = [f[@"source_conv_id"] isKindOfClass:NSString.class] ? f[@"source_conv_id"] : @"";
    if (conv.length == 0 || (from.length > 0 && [from isEqualToString:_selfUID])) { return kIMFavoritesMeBucket; }
    return conv;
}

/// 全量重算：来源过滤 → 分类/分组 → 当前签 → 刷表。
- (void)rebuildAll {
    if (_sourceFilterKey) {
        NSMutableArray *s = [NSMutableArray array];
        for (NSDictionary *f in _allItems) { if ([[self groupKeyOf:f] isEqualToString:_sourceFilterKey]) { [s addObject:f]; } }
        _scoped = s;
    } else {
        _scoped = _allItems;
    }
    if (_mode == IMFavoritesViewModeChats) {
        [self rebuildGroups];
        _segmented.hidden = YES; _segHeight.constant = 0;
        _searchBar.placeholder = @"搜索来源会话";
        _syncingToken = YES; _searchBar.searchTextField.tokens = @[]; _syncingToken = NO;
    } else {
        [self recomputeCategories];
        _segmented.hidden = _categories.count == 0; _segHeight.constant = _categories.count == 0 ? 0 : kIMFavSegH;
    }
    [self applyFilter];
    if (_sourceFilterKey) { [self im_refreshNavigationBar]; }
}

- (void)recomputeCategories {
    _categories = [IMFavoritesCategories categoriesForFavorites:_scoped includeAll:NO];
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    NSInteger selIdx = NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)_categories.count; i++) {
        [titles addObject:_categories[(NSUInteger)i].title ?: @""];
        if (_categories[(NSUInteger)i].kind == _selectedKind) { selIdx = i; }
    }
    if (selIdx == NSNotFound) {
        // 默认停「媒体」；无媒体则停首个存在签（已拍板②）。
        selIdx = 0;
        for (NSInteger i = 0; i < (NSInteger)_categories.count; i++) { if (_categories[(NSUInteger)i].kind == IMFavoriteCategoryMedia) { selIdx = i; break; } }
        _selectedKind = _categories.count ? _categories[(NSUInteger)selIdx].kind : IMFavoriteCategoryMedia;
    }
    _segmented.titles = titles.count ? titles : @[@"媒体"];
    _segmented.selectedIndex = selIdx;
    [self syncSearchScopeToken];
}

- (void)rebuildGroups {
    NSMutableDictionary<NSString *, IMFavoriteSourceGroup *> *map = [NSMutableDictionary dictionary];
    for (NSDictionary *f in _scoped) {
        NSString *key = [self groupKeyOf:f];
        IMFavoriteSourceGroup *g = map[key];
        int64_t created = [f[@"created_at"] respondsToSelector:@selector(longLongValue)] ? [f[@"created_at"] longLongValue] : 0;
        if (!g) {
            g = [IMFavoriteSourceGroup new];
            g.key = key;
            IMConversation *c = [key isEqualToString:kIMFavoritesMeBucket] ? nil : _convByID[key];
            g.name = [self displayNameForGroupKey:key conversation:c];
            if ([key isEqualToString:kIMFavoritesMeBucket]) { g.seed = _selfUID ?: @"me"; g.avatarURL = nil; }
            else if (c.isGroup) { g.avatarURL = IMMediaFullURL(c.avatarURL, IMHTTPService.sharedService.host); g.seed = c.convID; }
            else if (c) { g.avatarURL = IMMediaFullURL(c.peerAvatarURL, IMHTTPService.sharedService.host); g.seed = c.peer ?: key; }
            else { g.seed = key; g.avatarURL = nil; } // 来源会话已不存在：显 id 兜底、不隐藏（已拍板③）
            map[key] = g;
        }
        g.count += 1;
        if (created >= g.latest) { g.latest = created; g.preview = [self previewOf:f]; }
    }
    _groups = [map.allValues sortedArrayUsingComparator:^NSComparisonResult(IMFavoriteSourceGroup *a, IMFavoriteSourceGroup *b) {
        return a.latest > b.latest ? NSOrderedAscending : (a.latest < b.latest ? NSOrderedDescending : NSOrderedSame);
    }];
}

/// 来源分组显示名（会话备注>群名/对端昵称>id；「我的」桶=「我」）——rebuildGroups 与非媒体行「来自X」共用。
- (NSString *)displayNameForGroupKey:(NSString *)key conversation:(IMConversation *)c {
    if ([key isEqualToString:kIMFavoritesMeBucket]) { return @"我"; }
    if (c.isGroup) { return c.remark.length ? c.remark : (c.name.length ? c.name : @"群聊"); }
    if (c) { return c.remark.length ? c.remark : (c.peerNickname.length ? c.peerNickname : (c.peer ?: key)); }
    return key; // 会话不在本地缓存：显 id 兜底
}

/// 非媒体行副行「来自X」= **发送者**显示名（对齐 Web favSourceLabel：我 / 好友备注·昵称 / 群昵称 / uid）。
/// 数据全走本地缓存（会话/好友/群成员），与 Web 同口径、零额外请求。
- (NSString *)sourceNameForFavorite:(NSDictionary *)f {
    NSString *from = [f[@"source_from"] isKindOfClass:NSString.class] ? f[@"source_from"] : @"";
    if (from.length == 0) { return @""; }
    if ([from isEqualToString:_selfUID]) { return @"我"; }
    NSString *convID = [f[@"source_conv_id"] isKindOfClass:NSString.class] ? f[@"source_conv_id"] : @"";
    IMConversation *c = _convByID[convID];
    if (c && !c.isGroup && [c.peer isEqualToString:from]) { return c.peerNickname.length ? c.peerNickname : from; } // 单聊：含备注
    for (IMGroupMember *mem in _groupByID[convID].members) { if ([mem.userID isEqualToString:from]) { return mem.displayName; } } // 群昵称→全局→uid
    IMUserCard *fr = _friendByID[from];
    if (fr) { return fr.displayName; } // 好友兜底
    return from;
}

- (NSString *)previewOf:(NSDictionary *)f {
    NSString *ct = [f[@"content_type"] isKindOfClass:NSString.class] ? f[@"content_type"] : @"text";
    NSString *content = [f[@"content"] isKindOfClass:NSString.class] ? f[@"content"] : @"";
    NSString *caption = [f[@"caption"] isKindOfClass:NSString.class] ? f[@"caption"] : @"";
    if ([ct isEqualToString:@"image"]) { return caption.length ? [@"[图片] " stringByAppendingString:caption] : @"[图片]"; }
    if ([ct isEqualToString:@"video"]) { return caption.length ? [@"[视频] " stringByAppendingString:caption] : @"[视频]"; }
    if ([ct isEqualToString:@"file"]) {
        NSString *fn = [f[@"file_name"] isKindOfClass:NSString.class] && [f[@"file_name"] length] ? f[@"file_name"] : IMMediaFileName(content);
        return fn.length ? fn : @"[文件]";
    }
    if ([ct isEqualToString:@"chat_record"] || IMLooksLikeChatRecordJSON(content)) { return IMChatRecordSnippet(content) ?: @"[聊天记录]"; }
    if ([ct isEqualToString:@"audio"] || [ct isEqualToString:@"voice"]) { return @"[语音]"; }
    return content;
}

/// 过滤 = 当前签 ∩ 关键词（消息模式）/ 来源名 ∩ 关键词（聊天模式）。
- (void)applyFilter {
    NSString *q = [_searchText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (_mode == IMFavoritesViewModeChats) {
        NSMutableArray *out = [NSMutableArray array];
        for (IMFavoriteSourceGroup *g in _groups) {
            if (q.length && [g.name rangeOfString:q options:NSCaseInsensitiveSearch].location == NSNotFound) { continue; }
            [out addObject:g];
        }
        _shownGroups = out;
        _rows = @[]; _mediaFavs = @[]; _mediaModels = @[]; _mediaItems = @[];
    } else {
        NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
        for (NSDictionary *f in _scoped) {
            if (![IMFavoritesCategories favorite:f matchesCategory:_selectedKind]) { continue; }
            if (q.length > 0 && ![self favorite:f matchesQuery:q]) { continue; }
            [out addObject:f];
        }
        if (_selectedKind == IMFavoriteCategoryMedia) {
            NSMutableArray<IMMessageModel *> *models = [NSMutableArray arrayWithCapacity:out.count];
            NSMutableArray<IMMediaItem *> *items = [NSMutableArray arrayWithCapacity:out.count];
            NSString *host = IMHTTPService.sharedService.host;
            for (NSDictionary *f in out) {
                IMMessageModel *m = [self modelForFavorite:f];
                [models addObject:m];
                [items addObject:[IMMediaItem itemWithURL:IMMediaFullURL(m.content, host)
                                                  isVideo:[m.contentType isEqualToString:@"video"]
                                                timestamp:m.timestamp thumb:m.thumb durationMillis:m.duration]];
            }
            _mediaFavs = out; _mediaModels = models; _mediaItems = items; _rows = @[];
        } else {
            _rows = out; _mediaFavs = @[]; _mediaModels = @[]; _mediaItems = @[];
        }
        _shownGroups = @[];
    }
    [_tableView reloadData];
    [self updateEmptyState];
}

- (BOOL)favorite:(NSDictionary *)f matchesQuery:(NSString *)q {
    NSString *content = [f[@"content"] isKindOfClass:NSString.class] ? f[@"content"] : @"";
    NSString *caption = [f[@"caption"] isKindOfClass:NSString.class] ? f[@"caption"] : @"";
    NSString *fileName = [f[@"file_name"] isKindOfClass:NSString.class] ? f[@"file_name"] : @"";
    NSString *ct = [f[@"content_type"] isKindOfClass:NSString.class] ? f[@"content_type"] : @"text";
    if ([ct isEqualToString:@"file"] && fileName.length == 0) { fileName = IMMediaFileName(content); }
    NSStringCompareOptions opt = NSCaseInsensitiveSearch;
    return (content.length && [content rangeOfString:q options:opt].location != NSNotFound)
        || (caption.length && [caption rangeOfString:q options:opt].location != NSNotFound)
        || (fileName.length && [fileName rangeOfString:q options:opt].location != NSNotFound);
}

- (void)updateEmptyState {
    BOOL empty = _mode == IMFavoritesViewModeChats ? _shownGroups.count == 0
               : (_selectedKind == IMFavoriteCategoryMedia ? _mediaItems.count == 0 : _rows.count == 0);
    _emptyView.hidden = !empty;
    if (!empty) { return; }
    NSString *q = [_searchText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (_loadFailed && _allItems.count == 0) {
        _emptyIcon.image = [UIImage systemImageNamed:@"exclamationmark.arrow.circlepath"];
        _emptyTitle.text = @"加载失败"; _emptySub.text = @"下拉重试";
    } else if (q.length > 0) {
        _emptyIcon.image = [UIImage systemImageNamed:@"magnifyingglass"];
        _emptyTitle.text = @"未找到相关收藏"; _emptySub.text = @"";
    } else if (_scoped.count == 0) {
        _emptyIcon.image = [UIImage systemImageNamed:@"bookmark"];
        _emptyTitle.text = @"还没有收藏"; _emptySub.text = @"长按聊天里的任意消息 → 收藏，就会出现在这里";
    } else {
        _emptyIcon.image = [UIImage systemImageNamed:@"bookmark"];
        _emptyTitle.text = [NSString stringWithFormat:@"暂无%@", [IMFavoritesCategories titleForCategory:_selectedKind]]; _emptySub.text = @"";
    }
}

/// 收藏字典 → 消息模型（按 favId 缓存同一实例，供编排器跟踪进度/门控、宫格按 index 反查）。
- (IMMessageModel *)modelForFavorite:(NSDictionary *)f {
    NSString *key = [self idKeyOf:f];
    IMMessageModel *m = _models[key];
    if (m) { return m; }
    m = [IMMessageModel new];
    m.clientMsgID = [@"fav-" stringByAppendingString:key];
    m.contentType = [f[@"content_type"] isKindOfClass:NSString.class] ? f[@"content_type"] : @"text";
    m.content = [f[@"content"] isKindOfClass:NSString.class] ? f[@"content"] : @"";
    m.caption = [f[@"caption"] isKindOfClass:NSString.class] && [f[@"caption"] length] ? f[@"caption"] : nil;
    m.fileName = [f[@"file_name"] isKindOfClass:NSString.class] && [f[@"file_name"] length] ? f[@"file_name"] : nil;
    m.fileSize = [f[@"file_size"] respondsToSelector:@selector(longLongValue)] ? [f[@"file_size"] longLongValue] : 0;
    m.duration = [f[@"duration"] respondsToSelector:@selector(longLongValue)] ? [f[@"duration"] longLongValue] : 0;
    m.thumb = [f[@"thumb"] isKindOfClass:NSString.class] && [f[@"thumb"] length] ? f[@"thumb"] : nil;
    m.poster = [f[@"poster"] isKindOfClass:NSString.class] && [f[@"poster"] length] ? f[@"poster"] : nil;
    m.mediaW = [f[@"media_w"] respondsToSelector:@selector(integerValue)] ? [f[@"media_w"] integerValue] : 0;
    m.mediaH = [f[@"media_h"] respondsToSelector:@selector(integerValue)] ? [f[@"media_h"] integerValue] : 0;
    m.from = [f[@"source_from"] isKindOfClass:NSString.class] ? f[@"source_from"] : @"";
    m.timestamp = [f[@"created_at"] respondsToSelector:@selector(longLongValue)] ? [f[@"created_at"] longLongValue] : 0;
    _models[key] = m;
    return m;
}

- (nullable IMMessageModel *)mediaModelAtIndex:(NSInteger)i {
    return (i >= 0 && i < (NSInteger)_mediaModels.count) ? _mediaModels[(NSUInteger)i] : nil;
}

#pragma mark 分段 / 搜索范围

- (void)segmentChanged:(IMLiquidSegmentedControl *)seg {
    NSInteger i = seg.selectedIndex;
    if (i < 0 || i >= (NSInteger)_categories.count) { return; }
    _selectedKind = _categories[(NSUInteger)i].kind;
    [self syncSearchScopeToken];
    [self applyFilter];
}

/// 范围 token 恒=当前签（无「全部」可回退，删掉即自动补回）。
- (void)syncSearchScopeToken {
    _syncingToken = YES;
    NSString *title = [IMFavoritesCategories titleForCategory:_selectedKind];
    _searchBar.searchTextField.tokens = _categories.count ? @[[UISearchToken tokenWithIcon:nil text:title]] : @[];
    _searchBar.placeholder = [NSString stringWithFormat:@"在%@中搜索", title];
    _syncingToken = NO;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    _searchText = searchText ?: @"";
    if (!_syncingToken && _mode == IMFavoritesViewModeMessages && _categories.count && searchBar.searchTextField.tokens.count == 0) {
        [self syncSearchScopeToken]; // token 不可删：补回
    }
    [self applyFilter];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

#pragma mark UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (_mode == IMFavoritesViewModeChats) { return (NSInteger)_shownGroups.count; }
    if (_selectedKind == IMFavoriteCategoryMedia) { return _mediaItems.count > 0 ? 1 : 0; }
    return (NSInteger)_rows.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_mode == IMFavoritesViewModeChats) { return 68; }
    if (_selectedKind == IMFavoriteCategoryMedia) {
        CGFloat w = _mediaGridWidth > 0 ? _mediaGridWidth : tableView.bounds.size.width - 32;
        CGFloat h = [IMDetailMediaContainerCell heightForCount:(NSInteger)_mediaItems.count width:w];
        return h > 0 ? h : 60;
    }
    if (_selectedKind == IMFavoriteCategoryFiles) { return 74; } // 文件行 3 行：文件名+状态+来自·时间（#2/#2b）
    // Links 走 auto dimension：混排文本时多一行原文引用（~40pt），行高差异不小，固定值任一侧都会撑
    // 出空白或截断。已在 buildTableView 里设 estimatedRowHeight，自适应布局能收敛。
    if (_selectedKind == IMFavoriteCategoryLinks) { return UITableViewAutomaticDimension; }
    return 76;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_mode == IMFavoritesViewModeChats) {
        IMFavoriteSourceCell *cell = [tableView dequeueReusableCellWithIdentifier:@"src" forIndexPath:indexPath];
        IMFavoriteSourceGroup *g = _shownGroups[(NSUInteger)indexPath.row];
        [cell configureWithName:g.name avatarURL:g.avatarURL seed:g.seed preview:g.preview ?: @"" count:g.count];
        return cell;
    }
    if (_selectedKind == IMFavoriteCategoryMedia) {
        IMDetailMediaContainerCell *cell = [tableView dequeueReusableCellWithIdentifier:@"mediagrid" forIndexPath:indexPath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        __weak typeof(self) ws = self;
        cell.onPick = ^(IMMediaItem *item) { [ws openMediaItem:item]; };
        // 逐格门控：必须在 setItems: 前挂好（reloadData 会立刻回调查询每格状态）。
        cell.stateForItemIndex = ^IMDownloadProgress *(NSInteger i) {
            __strong typeof(ws) self = ws; IMMessageModel *mm = [self mediaModelAtIndex:i];
            return (self && mm) ? [self->_downloads stateForMessage:mm] : nil;
        };
        cell.thumbForItemIndex = ^NSString *(NSInteger i) { __strong typeof(ws) self = ws; return [self mediaModelAtIndex:i].thumb; }; // 收藏现存 thumb（磨砂占位）
        cell.onDownloadItemIndex = ^(NSInteger i) {
            __strong typeof(ws) self = ws; IMMessageModel *mm = [self mediaModelAtIndex:i];
            if (self && mm) { [self->_downloads handleTapForMessage:mm]; }
        };
        cell.contextMenuForItemIndex = ^UIContextMenuConfiguration *(NSInteger i) {
            __strong typeof(ws) self = ws;
            if (!self || i < 0 || i >= (NSInteger)self->_mediaFavs.count) { return nil; }
            return [self contextMenuForFavorite:self->_mediaFavs[(NSUInteger)i]];
        };
        cell.onContentWidthChanged = ^(CGFloat width) {
            __strong typeof(ws) self = ws;
            if (!self || ABS(self->_mediaGridWidth - width) < 0.5) { return; }
            self->_mediaGridWidth = width;
            dispatch_async(dispatch_get_main_queue(), ^{ [self->_tableView beginUpdates]; [self->_tableView endUpdates]; });
        };
        _mediaContainerCell = cell;
        [cell setItems:_mediaItems];
        return cell;
    }
    NSDictionary *f = _rows[(NSUInteger)indexPath.row];
    if (_selectedKind == IMFavoriteCategoryFiles) {
        IMDetailFileCell *fc = [tableView dequeueReusableCellWithIdentifier:@"detailfile" forIndexPath:indexPath];
        IMMessageModel *m = [self modelForFavorite:f];
        fc.sourceName = [self sourceNameForFavorite:f]; // 收藏页文件行显「来自X」（#2；须在 configure 前设）
        [fc configureWithMessage:m download:[_downloads stateForMessage:m]];
        return fc;
    }
    // Links 分类走独立 cell（草图 §D）：36×36 favicon + og:title/host+path/时间 + 混排文本原文引用 + 来源行。
    // 与详情页 IMDetailLinkCell 共享 IMLinkRowView，视觉基底一致；此处仅多出 quote/source 两条。
    if (_selectedKind == IMFavoriteCategoryLinks) {
        IMFavoriteLinkCell *lc = [tableView dequeueReusableCellWithIdentifier:@"favlink" forIndexPath:indexPath];
        NSString *content = [f[@"content"] isKindOfClass:NSString.class] ? f[@"content"] : @"";
        NSString *ct = [f[@"content_type"] isKindOfClass:NSString.class] ? f[@"content_type"] : @"text";
        // 抽取首个 URL：显式 link 类型时整段=URL；text 类型时可能是混排（"看看 https://xxx"），此时 content ≠ url。
        NSString *firstURL = [ct isEqualToString:@"link"] ? content : (IMFirstURLInText(content) ?: content);
        // 原文引用：仅当 URL 与原文不相等时（即混排文本）才显——纯 URL 消息展示原文就是重复 URL，冗余。
        NSString *quote = ![firstURL isEqualToString:content] ? content : nil;
        int64_t createdAt = [f[@"created_at"] respondsToSelector:@selector(longLongValue)] ? [f[@"created_at"] longLongValue] : 0;
        NSString *time = createdAt > 0 ? IMFormatFileDateTime(createdAt) : @"";
        [lc configureWithURL:firstURL quoteText:quote sourceText:[self sourceNameForFavorite:f] timeText:time];
        return lc;
    }
    IMFavoriteRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];
    [cell configureWithFavorite:f kind:_selectedKind source:[self sourceNameForFavorite:f]];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_mode == IMFavoritesViewModeChats) {
        if (indexPath.row >= (NSInteger)_shownGroups.count) { return; }
        IMFavoriteSourceGroup *g = _shownGroups[(NSUInteger)indexPath.row];
        IMFavoritesViewController *sub = [[IMFavoritesViewController alloc] initWithSourceFilterKey:g.key name:g.name items:_allItems];
        [self.navigationController pushViewController:sub animated:YES];
        return;
    }
    if (_selectedKind == IMFavoriteCategoryMedia || indexPath.row >= (NSInteger)_rows.count) { return; }
    NSDictionary *f = _rows[(NSUInteger)indexPath.row];
    NSString *content = [f[@"content"] isKindOfClass:NSString.class] ? f[@"content"] : @"";
    if (content.length == 0) { return; }
    switch (_selectedKind) {
        case IMFavoriteCategoryFiles: {
            // 与聊天页收到文件一致：已缓存→QuickLook；门控中→下载/暂停/继续（不跳页、不自动打开）。
            IMMessageModel *m = [self modelForFavorite:f];
            IMDownloadProgress *dp = [_downloads stateForMessage:m];
            if (dp) { [_downloads handleTapForMessage:m]; }
            else { NSURL *local = [_downloads localFileForMessage:m]; if (local) { [self openQuickLook:local]; } }
            break;
        }
        case IMFavoriteCategoryRecord:
            [self.navigationController pushViewController:[[IMChatRecordViewController alloc]
                initWithHost:IMHTTPService.sharedService.host recordJSON:content] animated:YES];
            break;
        case IMFavoriteCategoryLinks: {
            NSString *host = IMHTTPService.sharedService.host;
            NSString *urlStr = IMMediaFullURL(content, host);
            if ([IMQRResultRouter routeInviteLinkIfOwn:urlStr host:host userID:_selfUID fromController:self]) { return; }
            NSURL *url = [NSURL URLWithString:urlStr];
            if (url && ([url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"https"])) {
                [self presentViewController:[[SFSafariViewController alloc] initWithURL:url] animated:YES completion:nil];
            }
            break;
        }
        case IMFavoriteCategoryVoice: {
            NSURL *url = [NSURL URLWithString:IMMediaFullURL(content, IMHTTPService.sharedService.host)];
            if (url) { [self presentViewController:[[SFSafariViewController alloc] initWithURL:url] animated:YES completion:nil]; }
            break;
        }
        default:
            [self.navigationController pushViewController:[[IMFavoriteReaderViewController alloc] initWithText:content] animated:YES];
            break;
    }
}

#pragma mark 长按 / 左滑

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_mode == IMFavoritesViewModeChats || _selectedKind == IMFavoriteCategoryMedia) { return nil; }
    __weak typeof(self) ws = self;
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除"
        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        __strong typeof(ws) self = ws;
        if (!self || indexPath.row >= (NSInteger)self->_rows.count) { done(NO); return; }
        [self deleteFavorite:self->_rows[(NSUInteger)indexPath.row] done:done];
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    if (_mode == IMFavoritesViewModeChats || _selectedKind == IMFavoriteCategoryMedia) { return nil; }
    if (indexPath.row >= (NSInteger)_rows.count) { return nil; }
    return [self contextMenuForFavorite:_rows[(NSUInteger)indexPath.row]];
}

/// 转发 / 复制（文本·链接）/ 取消下载（进行中文件）/ 删除——宫格格与行共用。
- (UIContextMenuConfiguration *)contextMenuForFavorite:(NSDictionary *)f {
    NSString *content = [f[@"content"] isKindOfClass:NSString.class] ? f[@"content"] : @"";
    NSString *ct = [f[@"content_type"] isKindOfClass:NSString.class] ? f[@"content_type"] : @"text";
    BOOL copyable = [IMFavoritesCategories favorite:f matchesCategory:IMFavoriteCategoryText]
                 || [IMFavoritesCategories favorite:f matchesCategory:IMFavoriteCategoryLinks];
    BOOL downloading = NO;
    if ([ct isEqualToString:@"file"] || [ct isEqualToString:@"video"]) {
        IMDownloadProgress *dp = [_downloads stateForMessage:[self modelForFavorite:f]];
        downloading = dp && (dp.phase == IMDownloadPhaseDownloading || dp.phase == IMDownloadPhasePaused);
    }
    __weak typeof(self) ws = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *suggested) {
        NSMutableArray<UIMenuElement *> *acts = [NSMutableArray array];
        [acts addObject:[UIAction actionWithTitle:@"转发" image:[UIImage systemImageNamed:@"arrowshape.turn.up.right"] identifier:nil
                                          handler:^(UIAction *a) { [ws forwardFavorite:f]; }]];
        if (copyable) {
            [acts addObject:[UIAction actionWithTitle:@"复制" image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil
                                              handler:^(UIAction *a) { UIPasteboard.generalPasteboard.string = content; [ws im_showToast:@"已复制"]; }]];
        }
        if (downloading) {
            [acts addObject:[UIAction actionWithTitle:@"取消下载" image:[UIImage systemImageNamed:@"xmark.circle"] identifier:nil
                                              handler:^(UIAction *a) { __strong typeof(ws) self = ws; if (self) { [self->_downloads cancelDownloadForMessage:[self modelForFavorite:f]]; } }]];
        }
        UIAction *del = [UIAction actionWithTitle:@"删除" image:[UIImage systemImageNamed:@"trash"] identifier:nil
                                          handler:^(UIAction *a) { [ws deleteFavorite:f done:nil]; }];
        del.attributes = UIMenuElementAttributesDestructive;
        [acts addObject:del];
        return [UIMenu menuWithTitle:@"" children:acts];
    }];
}

#pragma mark 删除 / 转发

- (void)deleteFavorite:(NSDictionary *)f done:(void (^)(BOOL))done {
    int64_t fid = [f[@"id"] respondsToSelector:@selector(longLongValue)] ? [f[@"id"] longLongValue] : 0;
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (fid <= 0 || token.length == 0) { if (done) { done(NO); } return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService deleteFavoriteWithToken:token favoriteID:fid completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { if (done) { done(NO); } return; }
        if (error) { if (done) { done(NO); } [self im_showToast:@"删除失败"]; return; }
        NSMutableArray *m = [self->_allItems mutableCopy];
        NSUInteger idx = [m indexOfObjectPassingTest:^BOOL(NSDictionary *x, NSUInteger i, BOOL *stop) {
            return [x[@"id"] respondsToSelector:@selector(longLongValue)] && [x[@"id"] longLongValue] == fid;
        }];
        if (idx != NSNotFound) { [m removeObjectAtIndex:idx]; }
        self->_allItems = m;
        [self rebuildAll];
        if (done) { done(YES); }
    }];
}

- (void)forwardFavorite:(NSDictionary *)f {
    NSString *content = [f[@"content"] isKindOfClass:NSString.class] ? f[@"content"] : @"";
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (content.length == 0 || token.length == 0) { return; }
    NSString *ct = [f[@"content_type"] isKindOfClass:NSString.class] ? f[@"content_type"] : @"text";
    NSString *fileName = [f[@"file_name"] isKindOfClass:NSString.class] ? f[@"file_name"] : nil;
    int64_t fileSize = [f[@"file_size"] respondsToSelector:@selector(longLongValue)] ? [f[@"file_size"] longLongValue] : 0;
    NSString *origin = [f[@"source_from"] isKindOfClass:NSString.class] ? f[@"source_from"] : @"";
    // 媒体元数据随转发一并带走（磨砂缩略/封面首帧/时长/图说）——不带就等于把这些丢了：收端只能按未知
    // 渲染、事后补不回（曾漏建 attrs 致收藏转发视频收端无 thumb/封面，与聊天内转发同口径修复）。
    IMMediaAttributes *attrs = [self forwardAttributesFromFavorite:f contentType:ct fileSize:fileSize];
    __weak typeof(self) ws = self;
    IMForwardPickerViewController *picker = [[IMForwardPickerViewController alloc]
        initWithHost:IMHTTPService.sharedService.host token:token onDone:^(NSArray<IMConversation *> *selected) {
        __strong typeof(ws) self = ws;
        if (!self || selected.count == 0) { return; }
        for (IMConversation *c in selected) {
            [self sendFavoriteContent:content contentType:ct fileName:fileName fileSize:fileSize forwardFrom:origin
                           attributes:attrs toConv:c.convID toUser:(c.isGroup ? @"" : (c.peer ?: @""))];
        }
        [self im_showToast:selected.count == 1 ? @"已转发" : [NSString stringWithFormat:@"已转发到 %lu 个会话", (unsigned long)selected.count]];
    }];
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:picker] animated:YES completion:nil];
}

/// 从收藏项取出转发要一并带走的媒体元数据（磨砂缩略/封面首帧/时长/像素尺寸/图说）；非媒体且无图说时返回 nil。
- (IMMediaAttributes *)forwardAttributesFromFavorite:(NSDictionary *)f contentType:(NSString *)ct fileSize:(int64_t)fileSize {
    BOOL isMedia = [ct isEqualToString:@"image"] || [ct isEqualToString:@"video"];
    NSString *caption = [f[@"caption"] isKindOfClass:NSString.class] ? f[@"caption"] : nil;
    if (!isMedia && caption.length == 0) { return nil; }
    IMMediaAttributes *attrs = [IMMediaAttributes new];
    if (isMedia) {
        attrs.thumb = [f[@"thumb"] isKindOfClass:NSString.class] ? f[@"thumb"] : nil;   // 未下载态磨砂占位
        attrs.poster = [f[@"poster"] isKindOfClass:NSString.class] ? f[@"poster"] : nil; // 视频封面首帧（Web 解不了 HEVC 时靠它出封面）
        attrs.durationMillis = [f[@"duration"] respondsToSelector:@selector(longLongValue)] ? [f[@"duration"] longLongValue] : 0;
        attrs.pixelWidth = [f[@"media_w"] respondsToSelector:@selector(integerValue)] ? [f[@"media_w"] integerValue] : 0;   // 收端按原比例定框，免加载后重排/裁方块
        attrs.pixelHeight = [f[@"media_h"] respondsToSelector:@selector(integerValue)] ? [f[@"media_h"] integerValue] : 0;
        attrs.fileSize = fileSize;
    }
    attrs.caption = caption; // 图说随转发跟随（Telegram 模型）；仅 image/video/file 生效
    return attrs;
}

/// 发一条转发消息并本地落库（无聊天上下文不做即时回显；打开该会话即从 DB 见到）。
- (void)sendFavoriteContent:(NSString *)content contentType:(NSString *)ct fileName:(NSString *)fileName fileSize:(int64_t)fileSize
                forwardFrom:(NSString *)origin attributes:(IMMediaAttributes *)attributes toConv:(NSString *)convID toUser:(NSString *)toUser {
    IMMessageModel *m = [IMMessageModel new];
    int64_t sentAt = IMNowMillis();
    __weak typeof(self) ws = self;
    NSString *cmid = [IMSocketManager.sharedManager forwardContent:content contentType:ct toConv:convID toUser:toUser forwardFrom:origin
                                                          fileName:fileName fileSize:fileSize attributes:attributes
                                                        completion:^(BOOL success, NSError *error, int64_t convSeq) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        m.status = success ? IMMessageStatusSent : IMMessageStatusFailed;
        m.convSeq = convSeq;
        [self performDatabaseOperation:^(IMDatabase *database) { [database saveMessage:m]; }];
    }];
    m.clientMsgID = cmid; m.convID = convID; m.to = toUser; m.from = _selfUID;
    m.content = content; m.contentType = ct;
    m.fileName = fileName.length ? fileName : nil; m.fileSize = fileSize;
    m.forwardFrom = origin.length ? origin : nil;
    // 本地回显/落库也带上媒体元数据：重进会话从 DB 自愈时，缩略/封面/时长/尺寸/图说不丢。
    m.thumb = attributes.thumb.length ? attributes.thumb : nil;
    m.poster = attributes.poster.length ? attributes.poster : nil;
    if (attributes.durationMillis > 0) { m.duration = attributes.durationMillis; }
    m.mediaW = attributes.pixelWidth;
    m.mediaH = attributes.pixelHeight;
    m.caption = attributes.caption.length ? attributes.caption : nil;
    m.status = IMMessageStatusSending; m.timestamp = sentAt;
    [self performDatabaseOperation:^(IMDatabase *database) { [database saveMessage:m]; }];
}

#pragma mark 媒体查看 / 下载回调 / QuickLook

/// 点就绪格 → 分页查看器（翻页范围=本签全部媒体，无「媒体库」按钮）。
- (void)openMediaItem:(IMMediaItem *)item {
    NSArray<IMMediaItem *> *items = _mediaItems;
    NSUInteger start = [items indexOfObjectIdenticalTo:item];
    if (start == NSNotFound) {
        [self presentViewController:[IMMediaViewerViewController viewerWithURL:item.url isVideo:item.isVideo preloadedImage:nil onOpenGallery:nil]
                           animated:YES completion:nil];
        return;
    }
    IMMediaPagerViewController *pager = [IMMediaPagerViewController pagerWithCount:items.count startIndex:start
        pageProvider:^IMMediaViewerViewController *(NSUInteger index) {
            if (index >= items.count) { return nil; }
            IMMediaItem *it = items[index];
            return [IMMediaViewerViewController viewerWithURL:it.url isVideo:it.isVideo preloadedImage:nil onOpenGallery:nil];
        }];
    pager.conversationTitle = self.title;
    [self presentViewController:pager animated:YES completion:nil];
}

- (NSInteger)rowForModel:(IMMessageModel *)m {
    for (NSInteger i = 0; i < (NSInteger)_rows.count; i++) { if (_models[[self idKeyOf:_rows[(NSUInteger)i]]] == m) { return i; } }
    return NSNotFound;
}

/// 高频进度：媒体签刷那一格、文件签刷那一行（就地，不 reload）。
- (void)updateDownloadCellForModel:(IMMessageModel *)m state:(IMDownloadProgress *)state {
    if (_mode == IMFavoritesViewModeChats) { return; }
    if (_selectedKind == IMFavoriteCategoryMedia) {
        NSUInteger i = [_mediaModels indexOfObjectIdenticalTo:m];
        if (i != NSNotFound) { [_mediaContainerCell updateItemAtIndex:(NSInteger)i download:state]; }
        return;
    }
    if (_selectedKind != IMFavoriteCategoryFiles) { return; }
    NSInteger row = [self rowForModel:m];
    if (row == NSNotFound || row >= [_tableView numberOfRowsInSection:0]) { return; }
    UITableViewCell *cell = [_tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
    if ([cell isKindOfClass:IMDetailFileCell.class]) { [(IMDetailFileCell *)cell updateDownload:state]; }
}

/// 低频就绪切换：媒体签刷一格、文件签刷一行。
- (void)refreshDownloadRowForModel:(IMMessageModel *)m {
    if (_mode == IMFavoritesViewModeChats) { return; }
    if (_selectedKind == IMFavoriteCategoryMedia) {
        NSUInteger i = [_mediaModels indexOfObjectIdenticalTo:m];
        if (i != NSNotFound) { [_mediaContainerCell refreshItemAtIndex:(NSInteger)i]; }
        return;
    }
    if (_selectedKind != IMFavoriteCategoryFiles) { return; }
    NSInteger row = [self rowForModel:m];
    if (row == NSNotFound || row >= [_tableView numberOfRowsInSection:0]) { return; }
    [_tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)openQuickLook:(NSURL *)local {
    if (!local) { return; }
    _quickLookURL = local;
    QLPreviewController *ql = [QLPreviewController new];
    ql.dataSource = self;
    [self presentViewController:ql animated:YES completion:nil];
}
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller { return _quickLookURL ? 1 : 0; }
- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index { return _quickLookURL; }

@end
