//  IMFavoritesViewController.m
//  收藏页（Browse）：GET /api/v1/favorites 展示内容快照。
//  分类（全部+动态，仿会话详情页 tab，口径复用 IMFavoritesCategories）+ 范围搜索（UISearchToken 跟随分段）
//  + 统一左图标列（媒体缩略 / 文件折角图标 / 文本引号色块 / 链接色块，无空占位）
//  + 长按菜单（转发/复制/删除）+ 左滑删除 + 点文本进阅读器 + 转发复用 IMForwardPickerViewController。
//  规格（字体/颜色/尺寸）严格照 IMServer/docs/FAVORITES_DESIGN.md §12（全走 IMTheme 语义 token，禁硬编码 hex）。
//
//  注：聊天页「从收藏发送」（Pick 模式）入口当前暂屏蔽/暂不支持（设计保留，FAVORITES_DESIGN §5.5 标 ⏸），
//  故本类只实现 Browse。

#import "IMFavoritesViewController.h"
#import "IMFavoritesCategories.h"
#import "IMHTTPService.h"
#import "IMMediaUtil.h"
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMediaViewerViewController.h"
#import "IMForwardPickerViewController.h"
#import "IMChatRecordViewController.h"
#import "IMSocketManager.h"
#import "IMDatabase.h"
#import "IMConversation.h"
#import "IMMessageModel.h"
#import "IMMediaDownloadCoordinator.h"
#import "IMDownloadProgress.h"
#import "IMLiquidSegmentedControl.h"
#import "IMTheme.h"
#import "IMTimeUtil.h"
#import "UIViewController+IMToast.h"
#import <SafariServices/SafariServices.h>
#import <QuickLook/QuickLook.h>

#pragma mark - 收藏阅读器（点文本 → 全文只读详情页，FAVORITES_DESIGN §5.6）

/// 只读全文页：大字号、可选中复制、可滚动。顶部液态标题栏由导航容器注入（title=「收藏」）。
@interface IMFavoriteReaderViewController : UIViewController
- (instancetype)initWithText:(NSString *)text;
@end

@implementation IMFavoriteReaderViewController {
    NSString *_text;
}
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
    tv.editable = NO;
    tv.selectable = YES;
    tv.backgroundColor = UIColor.clearColor;
    tv.textColor = IMTheme.textPrimary;
    tv.font = [UIFont systemFontOfSize:IMTheme.chatFontSize]; // §12.2 阅读器正文=chatFontSize（默认 17，夹 14-22）
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

#pragma mark - 收藏 Cell（统一左图标列：媒体缩略 / 文件折角图标 / 文本引号色块 / 链接色块）

@interface IMFavoriteCell : UITableViewCell
- (void)configureWithFavorite:(NSDictionary *)fav host:(NSString *)host;
/// 文件下载中：把副行就地替换为进度文案（不 reload；下载完成由 VC reload 该行恢复大小）。
- (void)applyDownloadMeta:(NSString *)text;
@end

@implementation IMFavoriteCell {
    UIView *_tile;          // 52×52 圆角图标位（§12.3）
    UIImageView *_thumb;    // 媒体缩略（铺满 tile）
    UIImageView *_glyph;    // 文件折角图标 / 文本·链接 SF Symbol（居中）
    UIImageView *_playBadge;// 视频角标
    UILabel *_title;
    UILabel *_meta;
    NSString *_thumbURL;    // 复用安全：异步缩略回来时比对
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _tile = [UIView new];
        _tile.translatesAutoresizingMaskIntoConstraints = NO;
        _tile.layer.cornerRadius = 10; // §12.3
        _tile.clipsToBounds = YES;
        [self.contentView addSubview:_tile];

        _thumb = [UIImageView new];
        _thumb.translatesAutoresizingMaskIntoConstraints = NO;
        _thumb.contentMode = UIViewContentModeScaleAspectFill;
        _thumb.clipsToBounds = YES;
        [_tile addSubview:_thumb];

        _glyph = [UIImageView new];
        _glyph.translatesAutoresizingMaskIntoConstraints = NO;
        _glyph.contentMode = UIViewContentModeScaleAspectFit;
        [_tile addSubview:_glyph];

        _playBadge = [[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:@"play.circle.fill"
                    withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular]]];
        _playBadge.tintColor = UIColor.whiteColor;
        _playBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _playBadge.hidden = YES;
        [_tile addSubview:_playBadge];

        _title = [UILabel new];
        _title.font = [UIFont systemFontOfSize:15]; // §12.2
        _title.textColor = IMTheme.textPrimary;
        _title.numberOfLines = 3;

        _meta = [UILabel new];
        _meta.font = [UIFont systemFontOfSize:13]; // §12.2
        _meta.textColor = IMTheme.textTertiary;
        _meta.numberOfLines = 1;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_title, _meta]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 3;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];

        [NSLayoutConstraint activateConstraints:@[
            [_tile.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16], // §12.3 leading 16
            [_tile.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_tile.widthAnchor constraintEqualToConstant:52],
            [_tile.heightAnchor constraintEqualToConstant:52],
            [_tile.topAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.topAnchor constant:12],
            [_tile.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-12],

            [_thumb.topAnchor constraintEqualToAnchor:_tile.topAnchor],
            [_thumb.bottomAnchor constraintEqualToAnchor:_tile.bottomAnchor],
            [_thumb.leadingAnchor constraintEqualToAnchor:_tile.leadingAnchor],
            [_thumb.trailingAnchor constraintEqualToAnchor:_tile.trailingAnchor],
            [_glyph.centerXAnchor constraintEqualToAnchor:_tile.centerXAnchor],
            [_glyph.centerYAnchor constraintEqualToAnchor:_tile.centerYAnchor],
            [_glyph.widthAnchor constraintEqualToConstant:28],
            [_glyph.heightAnchor constraintEqualToConstant:28],
            [_playBadge.centerXAnchor constraintEqualToAnchor:_tile.centerXAnchor],
            [_playBadge.centerYAnchor constraintEqualToAnchor:_tile.centerYAnchor],

            [stack.leadingAnchor constraintEqualToAnchor:_tile.trailingAnchor constant:12], // §12.3 gap 12
            [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16], // trailing 16
            [stack.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [stack.topAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.topAnchor constant:8],
            [stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-8],
        ]];
    }
    return self;
}

- (void)configureWithFavorite:(NSDictionary *)fav host:(NSString *)host {
    NSString *content = [fav[@"content"] isKindOfClass:NSString.class] ? fav[@"content"] : @"";
    NSString *ct = [fav[@"content_type"] isKindOfClass:NSString.class] ? fav[@"content_type"] : @"text";
    NSString *caption = [fav[@"caption"] isKindOfClass:NSString.class] ? fav[@"caption"] : @"";
    NSString *fileName = [fav[@"file_name"] isKindOfClass:NSString.class] ? fav[@"file_name"] : @"";
    int64_t fileSize = [fav[@"file_size"] respondsToSelector:@selector(longLongValue)] ? [fav[@"file_size"] longLongValue] : 0;
    int64_t createdAt = [fav[@"created_at"] respondsToSelector:@selector(longLongValue)] ? [fav[@"created_at"] longLongValue] : 0;

    BOOL isImage = [ct isEqualToString:@"image"];
    BOOL isVideo = [ct isEqualToString:@"video"];
    BOOL isMedia = isImage || isVideo;
    BOOL isFile = [ct isEqualToString:@"file"];
    BOOL isRecord = [ct isEqualToString:@"chat_record"] || IMLooksLikeChatRecordJSON(content);
    BOOL isLink = !isRecord && ([ct isEqualToString:@"link"] || ([ct isEqualToString:@"text"] && IMMediaLooksLikeURL(content)));

    // 复位
    _thumb.hidden = YES; _thumb.image = nil;
    _glyph.hidden = YES; _glyph.image = nil;
    _playBadge.hidden = YES;
    _thumbURL = nil;
    _title.textColor = IMTheme.textPrimary;
    _title.lineBreakMode = NSLineBreakByTruncatingTail;

    if (isMedia) {
        _tile.backgroundColor = UIColor.tertiarySystemFillColor;
        _thumb.hidden = NO;
        _playBadge.hidden = !isVideo;
        _title.numberOfLines = 2;
        _title.text = caption.length > 0 ? caption : (isVideo ? @"视频" : @"图片");
        NSString *full = IMMediaFullURL(content, host);
        _thumbURL = full;
        __weak typeof(self) ws = self;
        NSString *want = full;
        void (^apply)(UIImage *) = ^(UIImage *img) {
            __strong typeof(ws) self = ws;
            if (self && [self->_thumbURL isEqualToString:want]) { self->_thumb.image = img; }
        };
        if (isVideo) { [[IMVideoThumbnailLoader shared] loadPosterForVideoURL:full completion:apply]; }
        else { [[IMImageLoader shared] loadImageURL:full completion:apply]; }
    } else if (isFile) {
        _tile.backgroundColor = UIColor.tertiarySystemFillColor;
        _glyph.hidden = NO;
        NSString *fname = fileName.length > 0 ? fileName : IMMediaFileName(content);
        _glyph.image = [IMFileTypeIconForName(fname, 28) imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        _title.numberOfLines = 1;
        _title.lineBreakMode = NSLineBreakByTruncatingMiddle; // 文件名尾部是扩展名，中间截断更可读
        _title.text = fname;
    } else if (isRecord) {
        // 合并转发「聊天记录」卡：图标 + 摘要（IMChatRecordSnippet），点击进 IMChatRecordViewController。不显 JSON。
        _tile.backgroundColor = IMTheme.accentSoft;
        _glyph.hidden = NO;
        _glyph.image = [[UIImage systemImageNamed:@"bubble.left.and.bubble.right"
            withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold]]
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        _glyph.tintColor = IMTheme.accent;
        _title.numberOfLines = 2;
        NSString *snippet = IMChatRecordSnippet(content);
        _title.text = snippet.length > 0 ? snippet : @"聊天记录";
    } else if (isLink) {
        _tile.backgroundColor = IMTheme.accentSoft; // §12.1 文本·链接图标底
        _glyph.hidden = NO;
        _glyph.image = [[UIImage systemImageNamed:@"link"
            withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold]]
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        _glyph.tintColor = IMTheme.accent;
        _title.numberOfLines = 2;
        _title.textColor = IMTheme.accent;
        _title.text = content;
    } else { // 文本
        _tile.backgroundColor = IMTheme.accentSoft;
        _glyph.hidden = NO;
        _glyph.image = [[UIImage systemImageNamed:@"text.quote"
            withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold]]
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        _glyph.tintColor = IMTheme.accent;
        _title.numberOfLines = 3;
        _title.text = content;
    }

    // 副行：日期（+ 文件大小）。§12.2 13pt tertiary。
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSString *day = createdAt > 0 ? [IMTheme dayHeaderStringFromMillis:createdAt] : @"";
    if (day.length > 0) { [parts addObject:day]; }
    if (isFile && fileSize > 0) {
        NSString *size = IMFormatFileSize(fileSize);
        if (size.length > 0) { [parts addObject:size]; }
    }
    _meta.text = [parts componentsJoinedByString:@" · "];
}

- (void)applyDownloadMeta:(NSString *)text {
    if (text.length > 0) { _meta.text = text; }
}
@end

#pragma mark - 收藏页

// ⚠️ 必须普通 UIViewController + 内嵌 UITableView（非 UITableViewController）：导航容器注入的液态标题栏
// 若挂在滚动 tableView 的 topAnchor 会随负 contentOffset 下移（血泪三次）。顶部搜索/分段做成静止 headerBar
// 挂在 self.view，tableView 在其下。
@interface IMFavoritesViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, QLPreviewControllerDataSource>
@end

@implementation IMFavoritesViewController {
    UITableView *_tableView;
    UISearchBar *_searchBar;
    IMLiquidSegmentedControl *_segmented;
    UIView *_headerBar;
    UIView *_emptyView;
    UIImageView *_emptyIcon;
    UILabel *_emptyTitle;
    UILabel *_emptySub;

    NSArray<NSDictionary *> *_allItems;
    NSArray<IMFavoriteCategoryTab *> *_categories;
    IMFavoriteCategory _selectedCategory;
    NSArray<NSDictionary *> *_displayItems;
    NSString *_searchText;
    BOOL _loadFailed;
    BOOL _syncingToken; // 防程序化设 token 触发的 textDidChange 误判为"用户删 token"

    IMDatabaseAccountContext *_databaseContext;
    NSString *_selfUID;

    // 文件下载：复用聊天页同款 IMMediaDownloadCoordinator（下载→QuickLook，与聊天页文件点击一致）。
    IMMediaDownloadCoordinator *_downloads;
    NSMutableDictionary<NSString *, IMMessageModel *> *_fileModels; // favId(string) → 文件消息模型（供编排器跟踪同一实例）
    NSURL *_quickLookURL;
}

- (instancetype)init {
    self = [super init];
    if (self) { self.title = @"收藏消息"; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _allItems = @[];
    _displayItems = @[];
    _categories = @[];
    _selectedCategory = IMFavoriteCategoryAll;
    _searchText = @"";
    self.view.backgroundColor = IMTheme.groupedBackground;

    IMDatabaseAccountContext *ctx = IMDatabase.sharedDatabase.currentAccountContext;
    _databaseContext = ctx;
    _selfUID = ctx.ownerUserID ?: @"";

    // 下载编排器：myUserID 传哨兵值（收藏文件不分"我发/收到"，一律走下载→QuickLook，与聊天页收到文件一致）；
    // autoPrefetch 关闭（浏览收藏不该顺手把文件全拉下来，一律用户点触发）。
    _fileModels = [NSMutableDictionary dictionary];
    _downloads = [[IMMediaDownloadCoordinator alloc] initWithHost:(IMHTTPService.sharedService.host ?: @"")
                                                         myUserID:@"__im_fav_no_owner__" isGroup:NO];
    _downloads.autoPrefetchEnabled = NO;
    __weak typeof(self) ws = self;
    _downloads.onProgress = ^(IMMessageModel *message, IMDownloadProgress *state) {
        [ws updateDownloadMetaForModel:message state:state];
    };
    _downloads.onStateChanged = ^(IMMessageModel *message) {
        [ws reloadRowForModel:message]; // 下载完成→就绪：整行重配（副行恢复大小）。不自动打开（编排器铁律）。
    };

    [self buildHeaderBar];
    [self buildTableView];
    [self buildEmptyView];

    [self reload];
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
    _searchBar.placeholder = @"搜索收藏";
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.tintColor = IMTheme.accent; // 范围 token 着色
    [_headerBar addSubview:_searchBar];

    _segmented = [IMLiquidSegmentedControl new];
    _segmented.translatesAutoresizingMaskIntoConstraints = NO;
    _segmented.titles = @[@"全部"];
    [_segmented addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    [_headerBar addSubview:_segmented];

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
        [_segmented.heightAnchor constraintEqualToConstant:40], // §12.3 分段本体 40
        [_segmented.bottomAnchor constraintEqualToAnchor:_headerBar.bottomAnchor constant:-8],
    ]];
}

- (void)buildTableView {
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = IMTheme.groupedBackground;
    _tableView.rowHeight = 76; // §12.3
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [_tableView registerClass:IMFavoriteCell.class forCellReuseIdentifier:@"fav"];
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

    _emptyIcon = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"bookmark"
                withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:44 weight:UIImageSymbolWeightRegular]]];
    _emptyIcon.tintColor = IMTheme.accent;
    _emptyIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [_emptyView addSubview:_emptyIcon];

    _emptyTitle = [UILabel new];
    _emptyTitle.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _emptyTitle.textColor = IMTheme.textPrimary;
    _emptyTitle.textAlignment = NSTextAlignmentCenter;
    _emptyTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [_emptyView addSubview:_emptyTitle];

    _emptySub = [UILabel new];
    _emptySub.font = [UIFont systemFontOfSize:13];
    _emptySub.textColor = IMTheme.textTertiary;
    _emptySub.textAlignment = NSTextAlignmentCenter;
    _emptySub.numberOfLines = 0;
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

#pragma mark 数据

- (BOOL)performDatabaseOperation:(void (^)(IMDatabase *database))operation {
    return [IMDatabase.sharedDatabase performWithAccountContext:_databaseContext block:operation];
}

- (void)pullToRefresh:(UIRefreshControl *)rc {
    [self reload];
}

- (void)reload {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [_tableView.refreshControl endRefreshing]; return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService favoritesWithToken:token completion:^(NSArray<NSDictionary *> *favorites, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        [self->_tableView.refreshControl endRefreshing];
        if (error) {
            self->_loadFailed = YES; // 失败**保留旧数据**，不抹空（§7）
        } else {
            self->_loadFailed = NO;
            self->_allItems = favorites ?: @[];
        }
        [self recomputeCategories];
        [self applyFilter];
    }];
}

- (void)recomputeCategories {
    _categories = [IMFavoritesCategories categoriesForFavorites:_allItems];
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    NSInteger selIdx = 0;
    BOOL found = NO;
    for (NSInteger i = 0; i < (NSInteger)_categories.count; i++) {
        [titles addObject:_categories[(NSUInteger)i].title ?: @""];
        if (_categories[(NSUInteger)i].kind == _selectedCategory) { selIdx = i; found = YES; }
    }
    if (!found) { _selectedCategory = IMFavoriteCategoryAll; selIdx = 0; } // 原选中分类被删空 → 收敛到「全部」
    _segmented.titles = titles;
    _segmented.selectedIndex = selIdx;
    [self syncSearchScopeToken];
}

/// 过滤 = 当前分类 ∩ 搜索关键词（在当前分类范围内）。
- (void)applyFilter {
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    NSString *q = [_searchText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    for (NSDictionary *f in _allItems) {
        if (![IMFavoritesCategories favorite:f matchesCategory:_selectedCategory]) { continue; }
        if (q.length > 0 && ![self favorite:f matchesQuery:q]) { continue; }
        [out addObject:f];
    }
    _displayItems = out;
    [_tableView reloadData];
    [self updateEmptyState];
}

/// 搜索命中：content / caption / 文件名 任一包含关键词（忽略大小写）。
- (BOOL)favorite:(NSDictionary *)f matchesQuery:(NSString *)q {
    NSString *content = [f[@"content"] isKindOfClass:NSString.class] ? f[@"content"] : @"";
    NSString *caption = [f[@"caption"] isKindOfClass:NSString.class] ? f[@"caption"] : @"";
    NSString *fileName = [f[@"file_name"] isKindOfClass:NSString.class] ? f[@"file_name"] : @"";
    NSString *ct = [f[@"content_type"] isKindOfClass:NSString.class] ? f[@"content_type"] : @"text";
    if ([ct isEqualToString:@"file"] && fileName.length == 0) { fileName = IMMediaFileName(content); }
    NSStringCompareOptions opt = NSCaseInsensitiveSearch;
    return (content.length > 0 && [content rangeOfString:q options:opt].location != NSNotFound)
        || (caption.length > 0 && [caption rangeOfString:q options:opt].location != NSNotFound)
        || (fileName.length > 0 && [fileName rangeOfString:q options:opt].location != NSNotFound);
}

- (void)updateEmptyState {
    BOOL empty = _displayItems.count == 0;
    _emptyView.hidden = !empty;
    if (!empty) { return; }
    NSString *q = [_searchText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (_loadFailed && _allItems.count == 0) {
        _emptyIcon.image = [UIImage systemImageNamed:@"exclamationmark.arrow.circlepath"];
        _emptyTitle.text = @"加载失败";
        _emptySub.text = @"下拉重试";
    } else if (q.length > 0) {
        _emptyIcon.image = [UIImage systemImageNamed:@"magnifyingglass"];
        _emptyTitle.text = @"未找到相关收藏";
        _emptySub.text = @"";
    } else if (_selectedCategory != IMFavoriteCategoryAll) {
        _emptyIcon.image = [UIImage systemImageNamed:@"bookmark"];
        _emptyTitle.text = @"该分类暂无收藏";
        _emptySub.text = @"";
    } else {
        _emptyIcon.image = [UIImage systemImageNamed:@"bookmark"];
        _emptyTitle.text = @"还没有收藏";
        _emptySub.text = @"长按聊天里的任意消息 → 收藏，就会出现在这里";
    }
}

#pragma mark 分段 / 搜索范围

- (void)segmentChanged:(IMLiquidSegmentedControl *)seg {
    NSInteger i = seg.selectedIndex;
    if (i < 0 || i >= (NSInteger)_categories.count) { return; }
    _selectedCategory = _categories[(NSUInteger)i].kind;
    [self syncSearchScopeToken];
    [self applyFilter];
}

/// 范围 token 跟随当前分段：非「全部」时框首挂一枚 category token，占位改「在X中搜索」；「全部」清空。
- (void)syncSearchScopeToken {
    _syncingToken = YES;
    UISearchTextField *field = _searchBar.searchTextField;
    if (_selectedCategory == IMFavoriteCategoryAll) {
        field.tokens = @[];
        _searchBar.placeholder = @"搜索收藏";
    } else {
        NSString *title = [IMFavoritesCategories titleForCategory:_selectedCategory];
        UISearchToken *tok = [UISearchToken tokenWithIcon:nil text:title];
        field.tokens = @[tok];
        _searchBar.placeholder = [NSString stringWithFormat:@"在%@中搜索", title];
    }
    _syncingToken = NO;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    _searchText = searchText ?: @"";
    // 用户删掉范围 token（框内已无 token 但当前非「全部」）→ 等价切回「全部」。
    if (!_syncingToken && _selectedCategory != IMFavoriteCategoryAll && searchBar.searchTextField.tokens.count == 0) {
        _selectedCategory = IMFavoriteCategoryAll;
        [self recomputeCategories]; // 把分段选回「全部」并同步占位
    }
    [self applyFilter];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_displayItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMFavoriteCell *cell = [tableView dequeueReusableCellWithIdentifier:@"fav" forIndexPath:indexPath];
    [cell configureWithFavorite:_displayItems[(NSUInteger)indexPath.row] host:IMHTTPService.sharedService.host];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

/// 点一行 = 打开它的"自然全貌"（§5.1）：媒体→查看器；链接/文件→站内浏览器；文本→阅读器。
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    if (indexPath.row >= (NSInteger)_displayItems.count) { return; }
    NSDictionary *f = _displayItems[(NSUInteger)indexPath.row];
    NSString *content = [f[@"content"] isKindOfClass:NSString.class] ? f[@"content"] : @"";
    NSString *ct = [f[@"content_type"] isKindOfClass:NSString.class] ? f[@"content_type"] : @"text";
    if (content.length == 0) { return; }
    BOOL isVideo = [ct isEqualToString:@"video"];
    BOOL isImage = [ct isEqualToString:@"image"];
    if (isImage || isVideo) {
        IMMediaViewerViewController *viewer = [IMMediaViewerViewController
            viewerWithURL:IMMediaFullURL(content, IMHTTPService.sharedService.host) isVideo:isVideo preloadedImage:nil onOpenGallery:nil];
        [self presentViewController:viewer animated:YES completion:nil];
        return;
    }
    // 合并转发「聊天记录」→ 复用聊天页记录查看器（与 openChatRecord: 同款），不显 JSON。
    if ([ct isEqualToString:@"chat_record"] || IMLooksLikeChatRecordJSON(content)) {
        IMChatRecordViewController *vc = [[IMChatRecordViewController alloc]
            initWithHost:IMHTTPService.sharedService.host recordJSON:content];
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }
    // 文件 → 与聊天页收到文件一致：已下载=本地 QuickLook 预览；未下载=触发下载（副行显进度），完成后再点开。
    if ([ct isEqualToString:@"file"]) {
        IMMessageModel *m = [self fileModelForFavorite:f];
        NSURL *local = [_downloads localFileForMessage:m];
        if (local) { [self openQuickLook:local]; }
        else { [_downloads handleTapForMessage:m]; }
        return;
    }
    // 链接 → 站内浏览器
    BOOL isLink = [ct isEqualToString:@"link"] || ([ct isEqualToString:@"text"] && IMMediaLooksLikeURL(content));
    if (isLink) {
        NSURL *url = [NSURL URLWithString:IMMediaFullURL(content, IMHTTPService.sharedService.host)];
        if (url && ([url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"https"])) {
            SFSafariViewController *sf = [[SFSafariViewController alloc] initWithURL:url];
            [self presentViewController:sf animated:YES completion:nil];
        }
        return;
    }
    // 纯文本 → 阅读器
    [self.navigationController pushViewController:[[IMFavoriteReaderViewController alloc] initWithText:content] animated:YES];
}

#pragma mark 长按菜单 / 左滑

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    __weak typeof(self) ws = self;
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:@"删除" handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [ws deleteAt:indexPath done:completionHandler];
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
    contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    if (indexPath.row >= (NSInteger)_displayItems.count) { return nil; }
    NSDictionary *f = _displayItems[(NSUInteger)indexPath.row];
    NSString *content = [f[@"content"] isKindOfClass:NSString.class] ? f[@"content"] : @"";
    NSString *ct = [f[@"content_type"] isKindOfClass:NSString.class] ? f[@"content_type"] : @"text";
    BOOL isText = [ct isEqualToString:@"text"] && !IMMediaLooksLikeURL(content);
    BOOL isLink = [ct isEqualToString:@"link"] || ([ct isEqualToString:@"text"] && IMMediaLooksLikeURL(content));
    __weak typeof(self) ws = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        NSMutableArray<UIMenuElement *> *acts = [NSMutableArray array];
        [acts addObject:[UIAction actionWithTitle:@"转发"
            image:[UIImage systemImageNamed:@"arrowshape.turn.up.right"] identifier:nil
            handler:^(UIAction *a) { [ws forwardFavorite:f]; }]];
        if (isText || isLink) {
            [acts addObject:[UIAction actionWithTitle:@"复制"
                image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil
                handler:^(UIAction *a) {
                UIPasteboard.generalPasteboard.string = content;
                [ws im_showToast:@"已复制"];
            }]];
        }
        UIAction *del = [UIAction actionWithTitle:@"删除"
            image:[UIImage systemImageNamed:@"trash"] identifier:nil
            handler:^(UIAction *a) { [ws deleteAt:indexPath done:nil]; }];
        del.attributes = UIMenuElementAttributesDestructive;
        [acts addObject:del];
        return [UIMenu menuWithTitle:@"" children:acts];
    }];
}

#pragma mark 删除 / 转发

- (void)deleteAt:(NSIndexPath *)indexPath done:(void (^)(BOOL))done {
    if (indexPath.row >= (NSInteger)_displayItems.count) { if (done) { done(NO); } return; }
    NSDictionary *f = _displayItems[(NSUInteger)indexPath.row];
    int64_t fid = [f[@"id"] respondsToSelector:@selector(longLongValue)] ? [f[@"id"] longLongValue] : 0;
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (fid <= 0 || token.length == 0) { if (done) { done(NO); } return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService deleteFavoriteWithToken:token favoriteID:fid completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { if (done) { done(NO); } return; }
        if (error) { if (done) { done(NO); } [self im_showToast:@"删除失败"]; return; }
        // 从 _allItems 移除该 id，重推分类 + 过滤（分类可能因此收缩）。
        NSMutableArray *m = [self->_allItems mutableCopy];
        NSUInteger idx = [m indexOfObjectPassingTest:^BOOL(NSDictionary *x, NSUInteger i, BOOL *stop) {
            return [x[@"id"] respondsToSelector:@selector(longLongValue)] && [x[@"id"] longLongValue] == fid;
        }];
        if (idx != NSNotFound) { [m removeObjectAtIndex:idx]; }
        self->_allItems = m;
        [self recomputeCategories];
        [self applyFilter];
        if (done) { done(YES); }
    }];
}

/// 转发一条收藏到任意会话（复用 IMForwardPickerViewController；发送走 IMSocketManager forwardContent: + 本地落库）。
- (void)forwardFavorite:(NSDictionary *)f {
    NSString *content = [f[@"content"] isKindOfClass:NSString.class] ? f[@"content"] : @"";
    if (content.length == 0) { return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    NSString *ct = [f[@"content_type"] isKindOfClass:NSString.class] ? f[@"content_type"] : @"text";
    NSString *fileName = [f[@"file_name"] isKindOfClass:NSString.class] ? f[@"file_name"] : nil;
    int64_t fileSize = [f[@"file_size"] respondsToSelector:@selector(longLongValue)] ? [f[@"file_size"] longLongValue] : 0;
    NSString *origin = [f[@"source_from"] isKindOfClass:NSString.class] ? f[@"source_from"] : @"";
    __weak typeof(self) ws = self;
    IMForwardPickerViewController *picker = [[IMForwardPickerViewController alloc]
        initWithHost:IMHTTPService.sharedService.host token:token onDone:^(NSArray<IMConversation *> *selected) {
        __strong typeof(ws) self = ws;
        if (!self || selected.count == 0) { return; }
        for (IMConversation *c in selected) {
            NSString *toUser = c.isGroup ? @"" : (c.peer ?: @"");
            [self sendFavoriteContent:content contentType:ct fileName:fileName fileSize:fileSize
                          forwardFrom:origin toConv:c.convID toUser:toUser];
        }
        [self im_showToast:selected.count == 1 ? @"已转发" : [NSString stringWithFormat:@"已转发到 %lu 个会话", (unsigned long)selected.count]];
    }];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    [self presentViewController:nav animated:YES completion:nil];
}

/// 发一条转发消息并本地落库（无聊天上下文，故不做 tableView 回显；打开该会话即从 DB 见到）。
- (void)sendFavoriteContent:(NSString *)content contentType:(NSString *)ct
                   fileName:(NSString *)fileName fileSize:(int64_t)fileSize
                forwardFrom:(NSString *)origin toConv:(NSString *)convID toUser:(NSString *)toUser {
    IMMessageModel *m = [IMMessageModel new];
    int64_t sentAt = IMNowMillis();
    __weak typeof(self) ws = self;
    NSString *cmid = [IMSocketManager.sharedManager forwardContent:content contentType:ct
                                                            toConv:convID toUser:toUser forwardFrom:origin
                                                          fileName:fileName fileSize:fileSize
                                                        completion:^(BOOL success, NSError *error, int64_t convSeq) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        m.status = success ? IMMessageStatusSent : IMMessageStatusFailed;
        m.convSeq = convSeq;
        [self performDatabaseOperation:^(IMDatabase *database) { [database saveMessage:m]; }];
    }];
    m.clientMsgID = cmid;
    m.convID = convID; m.to = toUser; m.from = _selfUID;
    m.content = content; m.contentType = ct;
    m.fileName = fileName.length > 0 ? fileName : nil;
    m.fileSize = fileSize;
    m.forwardFrom = origin.length > 0 ? origin : nil;
    m.status = IMMessageStatusSending;
    m.timestamp = sentAt;
    [self performDatabaseOperation:^(IMDatabase *database) { [database saveMessage:m]; }];
}

#pragma mark 文件下载（与聊天页同源：IMMediaDownloadCoordinator + QuickLook）

/// 收藏字典 → 文件消息模型（按 favId 缓存同一实例，供下载编排器跟踪进度/门控）。
- (IMMessageModel *)fileModelForFavorite:(NSDictionary *)f {
    int64_t fid = [f[@"id"] respondsToSelector:@selector(longLongValue)] ? [f[@"id"] longLongValue] : 0;
    NSString *key = [NSString stringWithFormat:@"%lld", fid];
    IMMessageModel *m = _fileModels[key];
    if (m) { return m; }
    m = [IMMessageModel new];
    m.clientMsgID = [@"fav-file-" stringByAppendingString:key];
    m.contentType = @"file";
    m.content = [f[@"content"] isKindOfClass:NSString.class] ? f[@"content"] : @"";
    m.fileName = [f[@"file_name"] isKindOfClass:NSString.class] ? f[@"file_name"] : nil;
    m.fileSize = [f[@"file_size"] respondsToSelector:@selector(longLongValue)] ? [f[@"file_size"] longLongValue] : 0;
    m.from = [f[@"source_from"] isKindOfClass:NSString.class] ? f[@"source_from"] : @""; // myUserID 为哨兵，恒不判为"我发"
    if (fid > 0) { _fileModels[key] = m; }
    return m;
}

- (NSInteger)rowForFavId:(int64_t)favId {
    for (NSInteger i = 0; i < (NSInteger)_displayItems.count; i++) {
        NSDictionary *f = _displayItems[(NSUInteger)i];
        if ([f[@"id"] respondsToSelector:@selector(longLongValue)] && [f[@"id"] longLongValue] == favId) { return i; }
    }
    return NSNotFound;
}

/// 高频进度：就地改可见行副行文案（不 reload）。
- (void)updateDownloadMetaForModel:(IMMessageModel *)message state:(IMDownloadProgress *)state {
    __block int64_t favId = 0;
    [_fileModels enumerateKeysAndObjectsUsingBlock:^(NSString *k, IMMessageModel *v, BOOL *stop) {
        if (v == message) { favId = k.longLongValue; *stop = YES; }
    }];
    if (favId == 0) { return; }
    NSInteger row = [self rowForFavId:favId];
    if (row == NSNotFound) { return; }
    UITableViewCell *cell = [_tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
    if ([cell isKindOfClass:IMFavoriteCell.class]) { [(IMFavoriteCell *)cell applyDownloadMeta:[state accessibilityText]]; }
}

/// 低频状态切换（下载完成→就绪）：整行重配，副行恢复大小。
- (void)reloadRowForModel:(IMMessageModel *)message {
    __block int64_t favId = 0;
    [_fileModels enumerateKeysAndObjectsUsingBlock:^(NSString *k, IMMessageModel *v, BOOL *stop) {
        if (v == message) { favId = k.longLongValue; *stop = YES; }
    }];
    if (favId == 0) { return; }
    NSInteger row = [self rowForFavId:favId];
    if (row == NSNotFound || row >= [_tableView numberOfRowsInSection:0]) { return; }
    [_tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:0]]
                     withRowAnimation:UITableViewRowAnimationNone];
}

/// 已下载文件 → 本地 QuickLook 预览（站内、离线、原生文档预览，与聊天页 openCachedFile: 一致）。
- (void)openQuickLook:(NSURL *)local {
    if (!local) { return; }
    _quickLookURL = local;
    QLPreviewController *ql = [QLPreviewController new];
    ql.dataSource = self;
    [self presentViewController:ql animated:YES completion:nil];
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return _quickLookURL ? 1 : 0;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    return _quickLookURL;
}

@end
