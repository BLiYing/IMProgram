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
#import "IMFavoriteVoiceCell.h"   // 语音迷你播放器行（2026-08-26）
#import "IMVoicePlayer.h"         // 收藏语音就地播放（toggleEnsuringLocal 共享入口）
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
#import "IMFilePreviewPresenter.h"

static NSString *const kIMFavoritesViewModeKey = @"im.favorites.viewMode"; // 0=消息模式 1=聊天模式
static NSString *const kIMFavoritesMeBucket = @"__im_fav_me__";            // 聊天模式「我的」分组键
static CGFloat const kIMFavSegH = 40;                                        // 分段本体（同详情页 kIMDetailTabSegH）
/// pick 模式（从收藏发送）最多可选条数——独立常量，随时可调；超限点勾选框吐司提示。
/// 与 Web `FAV_PICK_MAX` 拉齐；不区分类型（媒体/文件/语音/文本/链接/记录同池）。
static NSInteger const kIMFavoritesPickMaxSelection = 9;

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
        // Links 分类走独立 IMFavoriteLinkCell（草图 §D），cellForRow 已 kind 分流后不会到这里；
        // 老兜底分支已删（死代码——若 register 失误应立刻构建期暴露，不该在此偷偷渲染个错样式）。
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
@interface IMFavoritesViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
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
    IMDatabaseAccountContext *_databaseContext;
    NSString *_selfUID;
    NSDictionary<NSString *, IMConversation *> *_convByID; // 来源会话名/头像查表
    NSDictionary<NSString *, IMUserCard *> *_friendByID;   // 好友：source_from→显示名（含备注）
    NSDictionary<NSString *, IMGroupInfo *> *_groupByID;   // 群：source_conv_id→成员（取群昵称）

    // pick 模式（Batch 2）：从聊天页加号 → 收藏调出。多选 + 底部"发送(N)"→ onPickDone(selected fav 数组)。
    // browse 模式下这些字段全默认（_pickMode=NO），不影响原有行为；模式一经初始化不再切换。
    BOOL _pickMode;
    void (^_onPickDone)(NSArray<NSDictionary *> *);
    NSMutableSet<NSNumber *> *_pickedFavIds;         // 选中集，按 favorite.id
    UIView *_pickBar;                                 // 底部工具栏容器
    UIButton *_pickCancelBtn;
    UIButton *_pickSendBtn;
    CFAbsoluteTime _suppressRowSelectionUntil;        // 勾选框刚点过的短时窗内（0.3s）压制行 didSelect
                                                       // ——保底防个别 UIKit 版本对 accessoryView UIButton
                                                       // 触发 didSelect 的历史行为把播放/预览也跟着触发。
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

/// pick 模式：多选 + 底部"发送(N)"→ onDone 回调携带选中项数组（用户"取消"回调 @[]）。
/// 聊天页加号面板 → 收藏 走这条入口；宿主拿到数组后按 forwardEchoContent: 逐条发到当前会话。
- (instancetype)initInPickModeWithDone:(void (^)(NSArray<NSDictionary *> *))onDone {
    self = [self init];
    if (self) {
        _pickMode = YES;
        _onPickDone = [onDone copy];
        _pickedFavIds = [NSMutableSet new];
        _mode = IMFavoritesViewModeMessages; // pick 模式恒消息模式（聊天模式的分组下钻在 pick 场景无意义）
        self.title = @"从收藏发送";
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
    if (_pickMode) { [self buildPickBar]; [self installPickCancelButton]; } // Batch 2：pick 模式补装底部发送栏 + 右上取消

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
    [_tableView registerClass:IMFavoriteVoiceCell.class forCellReuseIdentifier:@"favvoice"]; // 语音迷你播放器行（2026-08-26）
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
/// pick 模式下改为"取消"（installPickCancelButton 后覆盖），本方法先行装 ⋯ 再由后者替换。
- (void)installModeButton {
    if (_sourceFilterKey || _pickMode) { return; } // 来源子页/pick 模式不显模式菜单
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis"]
                                                              style:UIBarButtonItemStylePlain target:self action:@selector(modeTapped:)];
    item.accessibilityLabel = @"查看模式";
    self.navigationItem.rightBarButtonItem = item;
    [self im_refreshNavigationBar];
}

#pragma mark pick 模式：底部发送栏 + 右上取消 + 选中态维护

/// pick 模式右上"取消"按钮：与聊天页 attach 面板一致语义——放弃发送，onDone 回调 @[]，宿主 dismiss 本页。
- (void)installPickCancelButton {
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithTitle:@"取消"
                                                             style:UIBarButtonItemStylePlain
                                                            target:self action:@selector(handlePickCancel)];
    self.navigationItem.rightBarButtonItem = item;
    [self im_refreshNavigationBar];
}

/// 底部"发送(N)"工具栏：黏在 safeArea 底，tableView contentInset.bottom 让最后一行可完整可见。
- (void)buildPickBar {
    _pickBar = [UIView new];
    _pickBar.translatesAutoresizingMaskIntoConstraints = NO;
    _pickBar.backgroundColor = IMTheme.surface;
    _pickBar.layer.borderColor = IMTheme.separator.CGColor;
    _pickBar.layer.borderWidth = 0.5; // 与 tableView 分隔
    [self.view addSubview:_pickBar];

    _pickSendBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _pickSendBtn.translatesAutoresizingMaskIntoConstraints = NO;
    _pickSendBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [_pickSendBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [_pickSendBtn setTitleColor:[UIColor.whiteColor colorWithAlphaComponent:0.5] forState:UIControlStateDisabled];
    _pickSendBtn.backgroundColor = IMTheme.accent;
    _pickSendBtn.layer.cornerRadius = 18;
    _pickSendBtn.clipsToBounds = YES;
    _pickSendBtn.enabled = NO;
    [_pickSendBtn setTitle:@"发送" forState:UIControlStateNormal];
    [_pickSendBtn addTarget:self action:@selector(handlePickSend) forControlEvents:UIControlEventTouchUpInside];
    [_pickBar addSubview:_pickSendBtn];

    [NSLayoutConstraint activateConstraints:@[
        [_pickBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_pickBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_pickBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_pickBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-52], // 52pt 内容区 + safeArea
        [_pickSendBtn.trailingAnchor constraintEqualToAnchor:_pickBar.trailingAnchor constant:-16],
        [_pickSendBtn.centerYAnchor constraintEqualToAnchor:_pickBar.safeAreaLayoutGuide.bottomAnchor constant:-26],
        [_pickSendBtn.heightAnchor constraintEqualToConstant:36],
        [_pickSendBtn.widthAnchor constraintGreaterThanOrEqualToConstant:88],
    ]];
    // tableView 底部让位给 pickBar 内容区（52pt），最后一行不被遮住。
    _tableView.contentInset = UIEdgeInsetsMake(_tableView.contentInset.top, 0, 52, 0);
    _tableView.verticalScrollIndicatorInsets = UIEdgeInsetsMake(0, 0, 52, 0);
}

/// 更新"发送"按钮：无选中→disabled 灰态；有选中→"发送 (N)"。
- (void)updatePickSendButton {
    NSUInteger n = _pickedFavIds.count;
    _pickSendBtn.enabled = n > 0;
    NSString *title = n > 0 ? [NSString stringWithFormat:@"发送 (%lu)", (unsigned long)n] : @"发送";
    [_pickSendBtn setTitle:title forState:UIControlStateNormal];
}

- (void)handlePickCancel {
    if (_onPickDone) { _onPickDone(@[]); }
}

- (void)handlePickSend {
    if (_pickedFavIds.count == 0 || !_onPickDone) { return; }
    // 按选中顺序不保序（NSSet 无序），改按 _allItems 里的原顺序过滤，收端出现顺序与收藏时间线一致。
    NSMutableArray<NSDictionary *> *picked = [NSMutableArray new];
    for (NSDictionary *f in _allItems) {
        NSNumber *fid = [f[@"id"] isKindOfClass:NSNumber.class] ? f[@"id"]
                     : ([f[@"id"] respondsToSelector:@selector(longLongValue)] ? @([f[@"id"] longLongValue]) : nil);
        if (fid && [_pickedFavIds containsObject:fid]) { [picked addObject:f]; }
    }
    _onPickDone(picked);
}

/// pick 模式勾选框点击 → 切换选中；超限吐司拒绝。**只**由勾选框调用（accessoryView UIButton /
/// 媒体格右上按钮 / 语音行勾选框），行点击/播放键/媒体格自身不再走这条路径——用户可以在选中的同时
/// 预览/播放/打开链接。返回 YES 表示已消化（保留用于外部调用签名兼容）。
- (BOOL)handlePickTapForFavorite:(NSDictionary *)f {
    if (!_pickMode) { return NO; }
    NSNumber *fid = [f[@"id"] isKindOfClass:NSNumber.class] ? f[@"id"]
                 : ([f[@"id"] respondsToSelector:@selector(longLongValue)] ? @([f[@"id"] longLongValue]) : nil);
    if (!fid) { return YES; }
    if ([_pickedFavIds containsObject:fid]) {
        [_pickedFavIds removeObject:fid];
    } else {
        if ((NSInteger)_pickedFavIds.count >= kIMFavoritesPickMaxSelection) {
            [self im_showToast:[NSString stringWithFormat:@"最多选择 %ld 项", (long)kIMFavoritesPickMaxSelection]];
            return YES;
        }
        [_pickedFavIds addObject:fid];
    }
    [self updatePickSendButton];
    [_tableView reloadData]; // 直接整表刷新（selection 影响多个 cell 的 accessory，逐格 reload 反而复杂）
    return YES;
}

/// pick 模式下按 favorite.id 判定该 cell 是否选中（accessory checkmark 用）。
- (BOOL)isPickedFavorite:(NSDictionary *)f {
    if (!_pickMode) { return NO; }
    NSNumber *fid = [f[@"id"] isKindOfClass:NSNumber.class] ? f[@"id"]
                 : ([f[@"id"] respondsToSelector:@selector(longLongValue)] ? @([f[@"id"] longLongValue]) : nil);
    return fid && [_pickedFavIds containsObject:fid];
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
    if (c) { return c.displayName; } // 会话备注 > 群名 / 好友备注 > 昵称 > uid
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
    if (c && !c.isGroup && [c.peer isEqualToString:from]) { return c.displayName; } // 单聊：备注 > 昵称 > uid
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
    m.waveform = [f[@"waveform"] isKindOfClass:NSString.class] && [f[@"waveform"] length] ? f[@"waveform"] : nil; // 语音收藏波形
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
    if (_selectedKind == IMFavoriteCategoryVoice) { return 92; } // 迷你播放器 + 来源行（2026-08-26）
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
        // 铁律（收藏 pick）：点媒体格恒开预览（图片=查看器 / 视频=播放器）——即使 pick 模式；选中只走
        // 右上角勾选框覆盖层（IMMediaTileCell.setPickMode:selected:onCheckboxTap:）。曾把 pick 模式下的
        // onPick 复用为"切换选中"，导致用户看不到预览、还以为要长按才能选。
        cell.onPick = ^(IMMediaItem *item) {
            __strong typeof(ws) self = ws;
            if (self) { [self openMediaItem:item]; }
        };
        // pick 模式勾选框：透传 pickMode / 选中查询 / 切换回调。
        cell.pickMode = _pickMode;
        cell.isItemSelectedAtIndex = ^BOOL(NSInteger i) {
            __strong typeof(ws) self = ws;
            if (!self || i < 0 || i >= (NSInteger)self->_mediaFavs.count) { return NO; }
            return [self isPickedFavorite:self->_mediaFavs[(NSUInteger)i]];
        };
        cell.onToggleSelectionAtIndex = ^(NSInteger i) {
            __strong typeof(ws) self = ws;
            if (!self || i < 0 || i >= (NSInteger)self->_mediaFavs.count) { return; }
            [self handlePickTapForFavorite:self->_mediaFavs[(NSUInteger)i]];
        };
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
        [self applyPickAccessoryForCell:fc favorite:f];
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
        [self applyPickAccessoryForCell:lc favorite:f];
        return lc;
    }
    // 语音分类：迷你波形播放器行（2026-08-26 拍板）——点播放键/点行都走 playFavoriteVoice:。
    if (_selectedKind == IMFavoriteCategoryVoice) {
        IMFavoriteVoiceCell *vc = [tableView dequeueReusableCellWithIdentifier:@"favvoice" forIndexPath:indexPath];
        IMMessageModel *m = [self modelForFavorite:f];
        int64_t createdAt = [f[@"created_at"] respondsToSelector:@selector(longLongValue)] ? [f[@"created_at"] longLongValue] : 0;
        [vc configureWithMessage:m sourceText:[self sourceNameForFavorite:f]
                        timeText:(createdAt > 0 ? IMFormatFileDateTime(createdAt) : @"")];
        __weak typeof(self) ws = self;
        NSDictionary *fav = f;
        // 铁律（收藏 pick）：▶/⏸ 键恒播放/暂停——即使 pick 模式；选中只走行右侧勾选框（accessoryView）。
        // 曾把播放键复用为"切换选中"，导致用户听不到语音、且和"点击其他位置=打开"的语义不一致。
        vc.onPlayTap = ^{
            __strong typeof(ws) self = ws;
            if (self) { [self playFavoriteVoice:fav]; }
        };
        [self applyPickAccessoryForCell:vc favorite:f];
        return vc;
    }
    IMFavoriteRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];
    [cell configureWithFavorite:f kind:_selectedKind source:[self sourceNameForFavorite:f]];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    [self applyPickAccessoryForCell:cell favorite:f];
    return cell;
}

/// pick 模式给任意 cell 挂勾选框 accessory：**UIButton** 独立触发切换（accessoryView 作为 UIControl 自吃
/// touch，行 didSelect 不会随之触发）。选中态=✓（accent），未选中=空圈（tertiary）；非 pick 模式清 accessory。
/// tag = favorite.id（int64_t）；action 里用 tag 反查再走 handlePickTapForFavorite: 走上限校验。
- (void)applyPickAccessoryForCell:(UITableViewCell *)cell favorite:(NSDictionary *)f {
    if (!_pickMode) { cell.accessoryView = nil; cell.accessoryType = UITableViewCellAccessoryNone; return; }
    BOOL on = [self isPickedFavorite:f];
    int64_t fid = [f[@"id"] respondsToSelector:@selector(longLongValue)] ? [f[@"id"] longLongValue] : 0;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *img = [UIImage systemImageNamed:(on ? @"checkmark.circle.fill" : @"circle")
                            withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular]];
    [btn setImage:[img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
    btn.tintColor = on ? IMTheme.accent : IMTheme.textTertiary;
    btn.frame = CGRectMake(0, 0, 36, 36);
    btn.tag = (NSInteger)fid; // int64_t 全部落 NSInteger（iOS 64-bit 无损）
    [btn addTarget:self action:@selector(handlePickAccessoryTap:) forControlEvents:UIControlEventTouchUpInside];
    cell.accessoryView = btn;
}

/// UIButton accessoryView action：按 tag（=favorite.id）在 _allItems 中反查并走 handlePickTapForFavorite:
/// （统一走上限校验、reloadData、更新发送按钮）。
- (void)handlePickAccessoryTap:(UIButton *)sender {
    _suppressRowSelectionUntil = CFAbsoluteTimeGetCurrent() + 0.3;
    int64_t fid = (int64_t)sender.tag;
    if (fid == 0) { return; }
    for (NSDictionary *f in _allItems) {
        if ([f[@"id"] respondsToSelector:@selector(longLongValue)] && [f[@"id"] longLongValue] == fid) {
            [self handlePickTapForFavorite:f];
            return;
        }
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    // 勾选框刚触发过（0.3s 内）→ 保底压制行 didSelect，避免个别 UIKit 版本 accessoryView UIButton
    // 触发 didSelect 时把预览/播放也一并触发。
    if (_pickMode && CFAbsoluteTimeGetCurrent() < _suppressRowSelectionUntil) { return; }
    if (_mode == IMFavoritesViewModeChats) {
        if (indexPath.row >= (NSInteger)_shownGroups.count) { return; }
        IMFavoriteSourceGroup *g = _shownGroups[(NSUInteger)indexPath.row];
        IMFavoritesViewController *sub = [[IMFavoritesViewController alloc] initWithSourceFilterKey:g.key name:g.name items:_allItems];
        [self.navigationController pushViewController:sub animated:YES];
        return;
    }
    // pick 模式行点击 = **打开该项**（预览/播放/QuickLook/Safari）——与 browse 一致；选中只走
    // accessoryView 勾选框（applyPickAccessoryForCell:）。曾在 pick 模式下把行点击=切换选中，导致
    // 用户没法预览就要盲发。媒体分类点击落在宫格里，本方法不接管。
    if (_selectedKind == IMFavoriteCategoryMedia || indexPath.row >= (NSInteger)_rows.count) { return; }
    NSDictionary *f = _rows[(NSUInteger)indexPath.row];
    NSString *content = [f[@"content"] isKindOfClass:NSString.class] ? f[@"content"] : @"";
    if (content.length == 0) { return; }
    switch (_selectedKind) {
        case IMFavoriteCategoryFiles: {
            // 与聊天页气泡口径一致：本机有原件 → QuickLook；否则点整条 = 触发下载（handleTapForMessage
            // 覆盖未下载/下载中/暂停/失败全部分支）。曾按 stateForMessage 分支导致"无 dp 又无缓存"静默无反应。
            IMMessageModel *m = [self modelForFavorite:f];
            NSURL *local = [_downloads localFileForMessage:m];
            if (local) { [IMFilePreviewPresenter presentURL:local fromViewController:self]; }
            else { [_downloads handleTapForMessage:m]; }
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
        case IMFavoriteCategoryVoice:
            // 迷你播放器（2026-08-26）：行内就地播放/暂停——曾用 SFSafari 打开裸音频文件，完全不像 IM。
            [self playFavoriteVoice:f];
            break;
        default:
            [self.navigationController pushViewController:[[IMFavoriteReaderViewController alloc] initWithText:content] animated:YES];
            break;
    }
}

/// 播放收藏语音（2026-08-26）：走 IMVoicePlayer 共享入口就地播放/暂停。
/// 播放状态经 IMVoicePlayer 通知广播回 IMFavoriteVoiceCell（波形进度 + ▶/⏸ 图标）。
- (void)playFavoriteVoice:(NSDictionary *)f {
    IMMessageModel *m = [self modelForFavorite:f];
    __weak typeof(self) ws = self;
    [[IMVoicePlayer sharedPlayer] toggleEnsuringLocal:m host:IMHTTPService.sharedService.host completion:^(NSError *err) {
        __strong typeof(ws) self = ws;
        if (self && err) { [self im_showToast:@"语音下载失败"]; } // IO 错误不吞（CODING_STYLE §5）
    }];
}

#pragma mark 长按 / 左滑

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    // pick 模式（从聊天页调出选发）：禁用左滑删除——语义混淆（本意是选发，误滑删了原始收藏且无确认）。
    if (_pickMode) { return nil; }
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
    if (_pickMode) { return nil; } // pick 模式禁上下文菜单（转发/删除/复制在 pick 场景无意义）
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
    IMMediaAttributes *attrs = [IMFavoritesViewController mediaAttributesFromFavorite:f];
    // 老路径的 fileSize 是从字典外单独传入的（收藏 forward 分支已在上面读了 file_size 到 fileSize 变量），
    // 类方法内部按 f[@"file_size"] 自读，两条口径可能微差；此处显式覆盖 file_size 以保持旧行为不变。
    if (attrs && ([ct isEqualToString:@"image"] || [ct isEqualToString:@"video"])) { attrs.fileSize = fileSize; }
    return attrs;
}

/// 类方法版本（供聊天页"从收藏发送"直接调用）：口径与实例方法 forwardAttributesFromFavorite: 一致，
/// fileSize 从 f[@"file_size"] 自读。收藏字典结构见 M4-4 API 契约。
+ (IMMediaAttributes *)mediaAttributesFromFavorite:(NSDictionary *)f {
    NSString *ct = [f[@"content_type"] isKindOfClass:NSString.class] ? f[@"content_type"] : @"text";
    BOOL isMedia = [ct isEqualToString:@"image"] || [ct isEqualToString:@"video"];
    BOOL isVoice = [ct isEqualToString:@"voice"] || [ct isEqualToString:@"audio"];
    NSString *caption = [f[@"caption"] isKindOfClass:NSString.class] ? f[@"caption"] : nil;
    if (!isMedia && !isVoice && caption.length == 0) { return nil; }
    IMMediaAttributes *attrs = [IMMediaAttributes new];
    if (isVoice) {
        // 语音：duration 服务端强校验 >0（缺则整条拒发 100001）；waveform 波形保真（老收藏无此字段则收端退化条纹）。
        attrs.durationMillis = [f[@"duration"] respondsToSelector:@selector(longLongValue)] ? [f[@"duration"] longLongValue] : 0;
        attrs.waveform = [f[@"waveform"] isKindOfClass:NSString.class] && [f[@"waveform"] length] ? f[@"waveform"] : nil;
        attrs.fileSize = [f[@"file_size"] respondsToSelector:@selector(longLongValue)] ? [f[@"file_size"] longLongValue] : 0;
    }
    if (isMedia) {
        attrs.thumb = [f[@"thumb"] isKindOfClass:NSString.class] ? f[@"thumb"] : nil;
        attrs.poster = [f[@"poster"] isKindOfClass:NSString.class] ? f[@"poster"] : nil;
        attrs.durationMillis = [f[@"duration"] respondsToSelector:@selector(longLongValue)] ? [f[@"duration"] longLongValue] : 0;
        attrs.pixelWidth = [f[@"media_w"] respondsToSelector:@selector(integerValue)] ? [f[@"media_w"] integerValue] : 0;
        attrs.pixelHeight = [f[@"media_h"] respondsToSelector:@selector(integerValue)] ? [f[@"media_h"] integerValue] : 0;
        attrs.fileSize = [f[@"file_size"] respondsToSelector:@selector(longLongValue)] ? [f[@"file_size"] longLongValue] : 0;
    }
    attrs.caption = caption;
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
    m.waveform = attributes.waveform.length ? attributes.waveform : nil; // 语音：回显/落库带波形
    m.mediaW = attributes.pixelWidth;
    m.mediaH = attributes.pixelHeight;
    m.caption = attributes.caption.length ? attributes.caption : nil;
    m.status = IMMessageStatusSending; m.timestamp = sentAt;
    [self performDatabaseOperation:^(IMDatabase *database) { [database saveMessage:m]; }];
}

#pragma mark 媒体查看 / 下载回调

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

@end
