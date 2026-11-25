//  IMWorkbenchViewController.m

#import "IMWorkbenchViewController.h"
#import "IMActionListSheet.h"
#import "IMAppStoreViewController.h"
#import "IMHTTPService.h"
#import "IMJSONValue.h"
#import "IMHTTPService+Workbench.h"
#import "IMLocalization.h"
#import "IMTheme.h"
#import "IMLog.h"
#import "IMServerConfigStore.h"
#import "IMWorkbench.h"
#import "IMWorkbenchCells.h"
#import "IMWorkbenchOpener.h"
#import "UIViewController+IMToast.h"
#import "IMMainTabBarController.h"

static NSString *const kAppCell = @"app", *const kBannerCell = @"banner", *const kEmptyCell = @"empty", *const kHeader = @"header";

typedef NS_ENUM(NSInteger, IMWorkbenchRowKind) { IMWorkbenchRowBanner, IMWorkbenchRowApps, IMWorkbenchRowEmpty };

@interface IMWorkbenchViewController () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy, nullable) NSString *unitID;
@property (nonatomic, copy) NSString *unitTitle;
@property (nonatomic, copy) NSArray<NSDictionary *> *banners;
@property (nonatomic, copy) NSArray<IMWorkbenchSection *> *sections;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) NSUInteger loadSeq;
/// 移除请求还没回来的应用：期间开始的首页加载可能读到移除前的数据，结果里先滤掉。
@property (nonatomic, strong) NSMutableSet<NSString *> *removingIDs;
@property (nonatomic, strong) UICollectionView *collectionView;
@end

@implementation IMWorkbenchViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        _banners = @[];
        _sections = @[];
        _unitTitle = @"";
        _removingIDs = [NSMutableSet set];
    }
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = IMTheme.groupedBackground;
    UIBarButtonItem *store = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"storefront"] style:UIBarButtonItemStylePlain
                                                             target:self action:@selector(openStore)];
    store.accessibilityLabel = IMLocalized(@"workbench.store");
    store.accessibilityIdentifier = @"workbench.store";
    self.navigationItem.rightBarButtonItem = store;

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:[self makeLayout]];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.collectionView.backgroundColor = UIColor.clearColor;
    self.collectionView.alwaysBounceVertical = YES;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.accessibilityIdentifier = @"workbench.grid";
    [self.collectionView registerClass:IMWorkbenchAppCell.class forCellWithReuseIdentifier:kAppCell];
    [self.collectionView registerClass:IMWorkbenchBannerCell.class forCellWithReuseIdentifier:kBannerCell];
    [self.collectionView registerClass:IMWorkbenchEmptyCell.class forCellWithReuseIdentifier:kEmptyCell];
    [self.collectionView registerClass:IMWorkbenchHeaderView.class forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:kHeader];
    UIRefreshControl *refresh = [UIRefreshControl new];
    [refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    self.collectionView.refreshControl = refresh;
    [self.view addSubview:self.collectionView];
    [NSLayoutConstraint activateConstraints:@[
        [self.collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(configChanged) name:IMServerConfigDidLoadNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(storeChanged:) name:IMWorkbenchDidChangeNotification object:nil];
    [self syncUnit];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload]; // 每次进入 Tab 拉一次（后台改动不推送）
}

#pragma mark - 公司

- (NSArray<NSDictionary<NSString *, NSString *> *> *)units { return IMServerConfigStore.shared.workbenchUnits; }

/// 按配置与本机记忆定下当前公司，并刷新标题（多家时可点）。
- (void)syncUnit {
    NSString *picked = [IMWorkbench pickUnitIDFrom:self.units saved:(self.unitID ?: [IMWorkbench savedUnitIDForUser:self.userID])];
    if (![picked isEqualToString:self.unitID]) {
        self.unitID = picked;
        self.unitTitle = @"";
        self.banners = @[];
        self.sections = @[];
        self.loaded = NO;
        [self.collectionView reloadData];
    }
    if (self.unitTitle.length == 0) {
        for (NSDictionary *u in self.units) {
            if ([u[@"unit_id"] isEqualToString:picked]) { self.unitTitle = u[@"name"] ?: @""; break; }
        }
    }
    [self applyTitle];
}

- (void)applyTitle {
    // 只设 navigationItem.title：设 self.title 会把底部 Tab 的「工作台」改成公司名
    self.navigationItem.title = self.units.count > 1 ? [self.unitTitle stringByAppendingString:@" ▾"] : self.unitTitle;
    [self im_refreshNavigationBar];
}

- (BOOL)im_navigationTitleTappable { return self.units.count > 1; }

- (void)im_navigationTitleTapped {
    if (self.units.count < 2) { return; }
    NSMutableArray<IMActionListItem *> *items = [NSMutableArray array];
    __weak typeof(self) weak = self;
    for (NSDictionary<NSString *, NSString *> *u in self.units) {
        NSString *uid = u[@"unit_id"];
        [items addObject:[IMActionListItem itemWithTitle:(u[@"name"] ?: uid) selected:[uid isEqualToString:self.unitID] handler:^{
            [weak switchToUnit:uid];
        }]];
    }
    [IMActionListSheet presentFrom:self title:IMLocalized(@"workbench.switch_unit") items:items];
}

- (void)switchToUnit:(NSString *)unitID {
    if ([unitID isEqualToString:self.unitID]) { return; }
    [IMWorkbench saveUnitID:unitID forUser:self.userID];
    self.unitID = nil; // 让 syncUnit 按刚存的选择重新定下并重置
    [self syncUnit];
    [self reload];
}

- (void)configChanged {
    [self syncUnit];
    if (!self.loaded) { [self reload]; }
}

- (void)storeChanged:(NSNotification *)note {
    // 不在屏上（商店页压在上面）不拉：回来时 viewWillAppear 会拉一次，连加几个只拉一次
    if ([note.object isEqual:self.unitID] && self.view.window) { [self reload]; }
}

#pragma mark - 加载

- (void)reload {
    NSString *token = IMHTTPService.sharedService.currentToken;
    NSString *unitID = self.unitID;
    if (token.length == 0 || unitID.length == 0) { [self.collectionView.refreshControl endRefreshing]; return; }
    NSUInteger seq = ++self.loadSeq;
    __weak typeof(self) weak = self;
    [IMHTTPService.sharedService workbenchHomeWithToken:token unitID:unitID completion:^(NSDictionary *data, NSError *error) {
        typeof(self) s = weak;
        if (!s || seq != s.loadSeq) { return; } // 切了公司：旧响应作废
        [s.collectionView.refreshControl endRefreshing];
        if (error) {
            IMLogWarnWithTag(IMLogTagHTTP, @"workbench_load_failed code=%ld", (long)error.code);
            if (error.code == IMWorkbenchErrorOrgNotVisible) { [IMServerConfigStore.shared refreshNow]; } // 这家看不到了：重拉配置，Tab / 公司列表随之更新
            [s im_showToast:error.localizedDescription ?: IMLocalized(@"common.action_failed")];
            return;
        }
        [s applyHome:data];
    }];
}

- (void)applyHome:(NSDictionary *)data {
    NSDictionary *unit = [data[@"unit"] isKindOfClass:NSDictionary.class] ? data[@"unit"] : @{};
    NSString *shortName = [unit[@"short_name"] isKindOfClass:NSString.class] ? unit[@"short_name"] : @"";
    NSString *name = [unit[@"name"] isKindOfClass:NSString.class] ? unit[@"name"] : @"";
    if (shortName.length > 0 || name.length > 0) { self.unitTitle = shortName.length > 0 ? shortName : name; }
    NSMutableArray *banners = [NSMutableArray array];
    for (id b in ([data[@"banners"] isKindOfClass:NSArray.class] ? data[@"banners"] : @[])) {
        if ([b isKindOfClass:NSDictionary.class] && [b[@"image_url"] isKindOfClass:NSString.class]) { [banners addObject:b]; }
    }
    self.banners = banners;
    NSMutableArray *groups = [NSMutableArray array];
    for (NSDictionary *g in IMJSONDicts(data[@"groups"])) { // 先滤掉移除在途的应用
        NSMutableArray *apps = [NSMutableArray array];
        for (NSDictionary *a in IMJSONDicts(g[@"apps"])) {
            if (![self.removingIDs containsObject:IMJSONString(a[@"app_id"])]) { [apps addObject:a]; }
        }
        [groups addObject:@{ @"name": IMJSONString(g[@"name"]), @"apps": apps }];
    }
    self.sections = [IMWorkbench sectionsFromGroups:groups otherTitle:IMLocalized(@"workbench.group_other")
                                           soleTitle:IMLocalized(@"workbench.my_apps")];
    self.loaded = YES;
    [self applyTitle];
    [self.collectionView reloadData];
}

#pragma mark - 布局（交互稿 I-1：轮播 350×140 r12 左右 20；宫格卡片左右 20 r10，4 列，单元 84 高）

/// 当前布局里第 index 段是什么：轮播（有展示中的才有）→ 各应用段；一个应用都没有时应用段换成空态。
- (BOOL)hasBanner { return self.banners.count > 0; }

- (IMWorkbenchRowKind)kindOfSection:(NSInteger)index {
    if (self.hasBanner && index == 0) { return IMWorkbenchRowBanner; }
    return self.sections.count == 0 ? IMWorkbenchRowEmpty : IMWorkbenchRowApps;
}

- (NSInteger)appSectionIndex:(NSInteger)section { return section - (self.hasBanner ? 1 : 0); }

/// 整行一格的段（轮播 / 空态）。
static NSCollectionLayoutSection *IMWorkbenchFullWidthSection(CGFloat height, NSDirectionalEdgeInsets insets) {
    NSCollectionLayoutSize *size = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1]
                                                                  heightDimension:[NSCollectionLayoutDimension absoluteDimension:height]];
    NSCollectionLayoutGroup *g = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:size subitems:@[[NSCollectionLayoutItem itemWithLayoutSize:size]]];
    NSCollectionLayoutSection *sec = [NSCollectionLayoutSection sectionWithGroup:g];
    sec.contentInsets = insets;
    return sec;
}

- (UICollectionViewLayout *)makeLayout {
    __weak typeof(self) weak = self;
    UICollectionViewCompositionalLayout *layout = [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:
        ^NSCollectionLayoutSection *(NSInteger index, id<NSCollectionLayoutEnvironment> env) {
        IMWorkbenchRowKind kind = [weak kindOfSection:index];
        CGFloat width = env.container.effectiveContentSize.width;
        if (kind == IMWorkbenchRowBanner) { return IMWorkbenchFullWidthSection((width - 40) * 0.4, NSDirectionalEdgeInsetsMake(4, 20, 0, 20)); }
        if (kind == IMWorkbenchRowEmpty) { return IMWorkbenchFullWidthSection(260, NSDirectionalEdgeInsetsMake(60, 0, 0, 0)); }
        NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:
            [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:0.25]
                                           heightDimension:[NSCollectionLayoutDimension absoluteDimension:84]]];
        NSCollectionLayoutGroup *row = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:
            [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1]
                                           heightDimension:[NSCollectionLayoutDimension absoluteDimension:84]] subitems:@[item, item, item, item]];
        NSCollectionLayoutSection *sec = [NSCollectionLayoutSection sectionWithGroup:row];
        sec.interGroupSpacing = 8;
        sec.contentInsets = NSDirectionalEdgeInsetsMake(16, 28, 6, 28); // 卡片左右 20 + 卡内 8
        NSCollectionLayoutBoundarySupplementaryItem *header = [NSCollectionLayoutBoundarySupplementaryItem
            boundarySupplementaryItemWithLayoutSize:[NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1]
                                                                                  heightDimension:[NSCollectionLayoutDimension absoluteDimension:38]]
                                        elementKind:UICollectionElementKindSectionHeader alignment:NSRectAlignmentTop];
        header.contentInsets = NSDirectionalEdgeInsetsMake(0, -28, 0, -28);
        sec.boundarySupplementaryItems = @[header];
        NSCollectionLayoutDecorationItem *card = [NSCollectionLayoutDecorationItem backgroundDecorationItemWithElementKind:IMWorkbenchCardBackgroundKind];
        card.contentInsets = NSDirectionalEdgeInsetsMake(38, 20, 0, 20); // 表头不在卡片里
        sec.decorationItems = @[card];
        return sec;
    }];
    [layout registerClass:IMWorkbenchCardBackground.class forDecorationViewOfKind:IMWorkbenchCardBackgroundKind];
    return layout;
}

#pragma mark - 数据源

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)cv {
    if (!self.loaded) { return 0; }
    return (self.hasBanner ? 1 : 0) + MAX((NSInteger)self.sections.count, 1);
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    switch ([self kindOfSection:section]) {
        case IMWorkbenchRowBanner:
        case IMWorkbenchRowEmpty: return 1;
        case IMWorkbenchRowApps: return (NSInteger)self.sections[[self appSectionIndex:section]].apps.count;
    }
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    __weak typeof(self) weak = self;
    switch ([self kindOfSection:ip.section]) {
        case IMWorkbenchRowBanner: {
            IMWorkbenchBannerCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kBannerCell forIndexPath:ip];
            [cell configureWithBanners:self.banners host:self.host];
            cell.onTap = ^(NSDictionary *banner) { [weak tapBanner:banner]; };
            return cell;
        }
        case IMWorkbenchRowEmpty: {
            IMWorkbenchEmptyCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kEmptyCell forIndexPath:ip];
            cell.onGoStore = ^{ [weak openStore]; };
            return cell;
        }
        case IMWorkbenchRowApps: {
            IMWorkbenchAppCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kAppCell forIndexPath:ip];
            [cell configureWithApp:[self appAt:ip] host:self.host];
            return cell;
        }
    }
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)cv viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)ip {
    IMWorkbenchHeaderView *h = [cv dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:kHeader forIndexPath:ip];
    h.label.text = [self kindOfSection:ip.section] == IMWorkbenchRowApps ? self.sections[[self appSectionIndex:ip.section]].title : @"";
    return h;
}

- (NSDictionary *)appAt:(NSIndexPath *)ip { return self.sections[[self appSectionIndex:ip.section]].apps[ip.item]; }

#pragma mark - 交互

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    if ([self kindOfSection:ip.section] != IMWorkbenchRowApps) { return; }
    NSDictionary *app = [self appAt:ip];
    __weak typeof(self) weak = self;
    [IMWorkbenchOpener openAppID:app[@"app_id"] name:IMJSONString(app[@"name"]) unitID:self.unitID from:self onUnavailable:^{ [weak reload]; }];
}

/// 交互稿 I-4：长按 → 「移除」（强制不可移除的没有菜单）。
- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)cv contextMenuConfigurationForItemsAtIndexPaths:(NSArray<NSIndexPath *> *)paths point:(CGPoint)point {
    NSIndexPath *ip = paths.firstObject;
    if (!ip || [self kindOfSection:ip.section] != IMWorkbenchRowApps) { return nil; }
    NSDictionary *app = [self appAt:ip];
    if ([app[@"install_mode"] isEqual:@"forced_fixed"]) { return nil; }
    __weak typeof(self) weak = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *suggested) {
        UIAction *remove = [UIAction actionWithTitle:IMLocalized(@"workbench.remove") image:[UIImage systemImageNamed:@"minus.circle"]
                                          identifier:nil handler:^(UIAction *a) { [weak removeApp:app]; }];
        remove.attributes = UIMenuElementAttributesDestructive;
        return [UIMenu menuWithChildren:@[remove]];
    }];
}

/// 乐观更新：先从宫格里拿掉，失败回滚（重拉）+ toast。
- (void)removeApp:(NSDictionary *)app {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    NSMutableArray<IMWorkbenchSection *> *next = [NSMutableArray array];
    for (IMWorkbenchSection *s in self.sections) {
        NSMutableArray *apps = [s.apps mutableCopy];
        [apps removeObject:app];
        if (apps.count > 0) { [next addObject:[[IMWorkbenchSection alloc] initWithTitle:s.title apps:apps]]; }
    }
    self.sections = next;
    self.loadSeq++; // 在途的首页加载是移除前的数据：作废，免得把刚移除的又带回来
    [self.collectionView.refreshControl endRefreshing];
    [self.collectionView reloadData];
    NSString *appID = IMJSONString(app[@"app_id"]);
    [self.removingIDs addObject:appID];
    __weak typeof(self) weak = self;
    [IMHTTPService.sharedService workbenchSetAppWithToken:token unitID:self.unitID appID:appID add:NO completion:^(NSDictionary *d, NSError *error) {
        [weak.removingIDs removeObject:appID];
        if (error) {
            [weak im_showToast:error.localizedDescription ?: IMLocalized(@"common.action_failed")];
            [weak reload];
        }
    }];
}

- (void)tapBanner:(NSDictionary *)banner {
    NSString *kind = IMJSONString(banner[@"link_kind"]);
    if ([kind isEqual:@"url"]) {
        [IMWorkbenchOpener openLink:IMJSONString(banner[@"link_url"]) from:self];
    } else if ([kind isEqual:@"app"] && [banner[@"link_app_id"] isKindOfClass:NSString.class]) {
        __weak typeof(self) weak = self;
        [IMWorkbenchOpener openAppID:banner[@"link_app_id"] name:@"" unitID:self.unitID from:self onUnavailable:^{ [weak reload]; }];
    }
}

- (void)openStore {
    if (self.unitID.length == 0) { return; }
    IMAppStoreViewController *vc = [[IMAppStoreViewController alloc] initWithHost:self.host unitID:self.unitID];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
