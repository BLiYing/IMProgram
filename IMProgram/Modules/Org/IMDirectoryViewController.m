//  IMDirectoryViewController.m

#import "IMDirectoryViewController.h"
#import "IMAccountIdentity.h"
#import "IMChatDetailViewController.h"
#import "IMContactCells.h"
#import "IMDirectorySearchViewController.h"
#import "IMHTTPService.h"
#import "IMHTTPService+Directory.h"
#import "IMJSONValue.h"
#import "IMSettingsIcon.h"
#import "IMLocalization.h"
#import "IMLog.h"
#import "IMSearchEntryHeader.h"
#import "IMTenantStore.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"

static NSString * const kIMDirRootDept = @"root";
static NSString * const kIMDirCellUnit = @"unit";
static NSString * const kIMDirCellMember = @"member";
static const CGFloat kIMDirMemberRowHeight = 68;
static const CGFloat kIMDirCrumbHeight = 28;


NSArray<NSArray<NSString *> *> *IMDirectoryCrumbs(NSDictionary *page) {
    NSMutableArray *out = [NSMutableArray arrayWithObject:@[kIMDirRootDept, IMJSONString(IMJSONDict(page[@"unit"])[@"name"])]];
    for (NSDictionary *item in IMJSONDicts(page[@"path"])) {
        NSString *did = IMJSONString(item[@"dept_id"]);
        if (did.length > 0) { [out addObject:@[did, IMJSONString(item[@"name"])]]; }
    }
    return out;
}

typedef NS_ENUM(NSInteger, IMDirSection) {
    IMDirSectionUnits,     // 单位列表模式
    IMDirSectionChildren,  // 下级部门
    IMDirSectionMembers,   // 直属成员
};

@interface IMDirectoryViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy, readwrite) NSString *unitID;   // 空 = 单位列表模式
@property (nonatomic, copy, readwrite) NSString *deptID;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIScrollView *crumbBar;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSArray<IMTenantUnit *> *units;
@property (nonatomic, copy) NSArray<NSDictionary *> *children;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *members;
@property (nonatomic, copy, nullable) NSString *nextCursor;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL loadedOnce;
@end

@implementation IMDirectoryViewController

- (instancetype)initRootWithHost:(NSString *)host userID:(NSString *)userID {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _host = [host copy]; _userID = [userID copy];
        _unitID = @""; _deptID = @"";
        _units = @[]; _children = @[]; _members = [NSMutableArray array];
        self.title = IMLocalized(@"contacts.entry.org");
    }
    return self;
}

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID
                      unitID:(NSString *)unitID deptID:(NSString *)deptID title:(NSString *)title {
    if ((self = [self initRootWithHost:host userID:userID])) {
        _unitID = [unitID copy];
        _deptID = deptID.length > 0 ? [deptID copy] : kIMDirRootDept;
        self.title = title.length > 0 ? title : @"";
    }
    return self;
}

- (BOOL)isUnitListMode { return self.unitID.length == 0; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = IMTheme.groupedBackground;
    UITableView *tv = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.dataSource = self;
    tv.delegate = self;
    tv.backgroundColor = IMTheme.groupedBackground;
    [tv registerClass:UITableViewCell.class forCellReuseIdentifier:kIMDirCellUnit];
    [tv registerClass:IMContactCell.class forCellReuseIdentifier:kIMDirCellMember];
    tv.tableHeaderView = [self buildHeader];
    self.tableView = tv;
    [self.view addSubview:tv];

    UILabel *empty = [UILabel new];
    empty.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    empty.textColor = IMTheme.textPrimary;
    empty.textAlignment = NSTextAlignmentCenter;
    empty.numberOfLines = 0;
    empty.text = IMLocalized(@"org.dept.empty");
    empty.hidden = YES;
    self.emptyLabel = empty;
    tv.backgroundView = empty;
    [self load];
}

/// 搜索入口（56）+ 部门页的面包屑（单位列表模式没有面包屑）。
- (UIView *)buildHeader {
    CGFloat w = self.view.bounds.size.width;
    UIView *search = IMMakeSearchEntryHeader(w, IMLocalized(@"org.search.placeholder"), self, @selector(openSearch));
    if ([self isUnitListMode]) { return search; }
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, kIMSearchEntryHeaderHeight + kIMDirCrumbHeight)];
    search.frame = CGRectMake(0, 0, w, kIMSearchEntryHeaderHeight);
    search.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [wrap addSubview:search];
    UIScrollView *bar = [[UIScrollView alloc] initWithFrame:CGRectMake(0, kIMSearchEntryHeaderHeight, w, kIMDirCrumbHeight)];
    bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    bar.showsHorizontalScrollIndicator = NO;
    self.crumbBar = bar;
    [wrap addSubview:bar];
    return wrap;
}

- (void)openSearch {
    IMDirectorySearchViewController *vc = [[IMDirectorySearchViewController alloc] initWithHost:self.host userID:self.userID];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - 加载

- (void)load {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0 || self.loading) { return; }
    self.loading = YES;
    __weak typeof(self) ws = self;
    if ([self isUnitListMode]) {
        [IMHTTPService.sharedService directoryUnitsWithToken:token completion:^(NSDictionary *data, NSError *error) {
            [ws didLoadUnits:data error:error];
        }];
        return;
    }
    [IMHTTPService.sharedService directoryDeptWithToken:token unitID:self.unitID deptID:self.deptID cursor:self.nextCursor
                                             completion:^(NSDictionary *data, NSError *error) {
        [ws didLoadPage:data error:error];
    }];
}

- (void)didLoadUnits:(NSDictionary *)data error:(NSError *)error {
    self.loading = NO;
    if (error) { [self showLoadError:error]; return; }
    self.units = [IMTenantUnit unitsFromArray:data[@"units"]];
    if (self.units.count == 1) {
        // 只有一个单位（客服、只绑一家的客户）：本页原地变成它的顶层部门页，不多点一层。
        IMTenantUnit *only = self.units.firstObject;
        self.unitID = only.unitID;
        self.deptID = kIMDirRootDept;
        self.title = only.name;
        self.tableView.tableHeaderView = [self buildHeader];
        [self load];
        return;
    }
    self.loadedOnce = YES;
    [self reloadTable];
}

- (void)didLoadPage:(NSDictionary *)data error:(NSError *)error {
    self.loading = NO;
    if (error) { [self showLoadError:error]; return; }
    BOOL firstPage = self.nextCursor.length == 0;
    if (firstPage) {
        self.children = IMJSONDicts(data[@"children"]);
        [self.members removeAllObjects];
        NSArray<NSArray<NSString *> *> *crumbs = IMDirectoryCrumbs(data);
        [self renderCrumbs:crumbs];
        if (self.title.length == 0) { self.title = crumbs.lastObject.lastObject; }
    }
    for (NSDictionary *m in IMJSONDicts(data[@"members"])) {
        if (IMJSONString(m[@"user_id"]).length > 0) { [self.members addObject:m]; }
    }
    NSString *next = IMJSONString(data[@"next_cursor"]);
    self.nextCursor = next.length > 0 ? next : nil;
    self.loadedOnce = YES;
    [self reloadTable];
}

- (void)showLoadError:(NSError *)error {
    IMLogWarnWithTag(IMLogTagHTTP, @"directory_load_failed code=%ld", (long)error.code);
    [self im_showToast:error.localizedDescription ?: IMLocalized(@"common.action_failed")];
}

- (void)reloadTable {
    BOOL empty = self.loadedOnce && ([self isUnitListMode] ? self.units.count == 0
                                                           : (self.children.count == 0 && self.members.count == 0));
    self.emptyLabel.hidden = !empty;
    [self.tableView reloadData];
}

#pragma mark - 面包屑

- (void)renderCrumbs:(NSArray<NSArray<NSString *> *> *)crumbs {
    UIScrollView *bar = self.crumbBar;
    if (!bar) { return; }
    for (UIView *v in bar.subviews) { [v removeFromSuperview]; }
    CGFloat x = 16;
    for (NSUInteger i = 0; i < crumbs.count; i++) {
        BOOL last = i + 1 == crumbs.count;
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:crumbs[i][1] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:13];
        [b setTitleColor:(last ? IMTheme.textSecondary : IMTheme.accent) forState:UIControlStateNormal];
        b.enabled = !last;
        b.tag = (NSInteger)i;
        b.accessibilityValue = crumbs[i][0];
        [b addTarget:self action:@selector(crumbTapped:) forControlEvents:UIControlEventTouchUpInside];
        [b sizeToFit];
        b.frame = CGRectMake(x, 0, b.bounds.size.width, kIMDirCrumbHeight);
        [bar addSubview:b];
        x += b.bounds.size.width;
        if (!last) {
            UILabel *sep = [UILabel new];
            sep.text = @"›";
            sep.font = [UIFont systemFontOfSize:13];
            sep.textColor = IMTheme.textTertiary;
            [sep sizeToFit];
            sep.frame = CGRectMake(x + 4, 0, sep.bounds.size.width, kIMDirCrumbHeight);
            [bar addSubview:sep];
            x += sep.bounds.size.width + 8;
        }
    }
    bar.contentSize = CGSizeMake(x + 16, kIMDirCrumbHeight);
    [bar scrollRectToVisible:CGRectMake(MAX(0, x - 1), 0, 1, 1) animated:NO]; // 当前级在最右，长路径时贴右
}

/// 点上级：导航栈里有那一级就回去，没有（从单位顶层一路 push 下来的一般都有）就新开一页。
- (void)crumbTapped:(UIButton *)sender {
    NSString *target = sender.accessibilityValue ?: kIMDirRootDept;
    for (UIViewController *vc in self.navigationController.viewControllers.reverseObjectEnumerator) {
        if (![vc isKindOfClass:IMDirectoryViewController.class]) { continue; }
        IMDirectoryViewController *d = (IMDirectoryViewController *)vc;
        if ([d.unitID isEqualToString:self.unitID] && [d.deptID isEqualToString:target]) {
            [self.navigationController popToViewController:d animated:YES];
            return;
        }
    }
    [self pushUnit:self.unitID dept:target title:[sender titleForState:UIControlStateNormal]];
}

- (void)pushUnit:(NSString *)unitID dept:(NSString *)deptID title:(NSString *)title {
    IMDirectoryViewController *vc = [[IMDirectoryViewController alloc] initWithHost:self.host userID:self.userID
                                                                             unitID:unitID deptID:deptID title:title];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - 表格

- (NSArray<NSNumber *> *)sections {
    if ([self isUnitListMode]) { return self.units.count > 0 ? @[@(IMDirSectionUnits)] : @[]; }
    NSMutableArray *s = [NSMutableArray array];
    if (self.children.count > 0) { [s addObject:@(IMDirSectionChildren)]; }
    if (self.members.count > 0) { [s addObject:@(IMDirSectionMembers)]; }
    return s;
}

- (IMDirSection)kindAt:(NSInteger)section { return (IMDirSection)[[self sections][section] integerValue]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return (NSInteger)[self sections].count; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ([self kindAt:section]) {
        case IMDirSectionUnits: return (NSInteger)self.units.count;
        case IMDirSectionChildren: return (NSInteger)self.children.count;
        case IMDirSectionMembers: return (NSInteger)self.members.count;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch ([self kindAt:section]) {
        case IMDirSectionUnits: return IMTenantStore.shared.tenantName;
        case IMDirSectionChildren: return IMLocalized(@"org.dept.sub_depts");
        case IMDirSectionMembers: return IMLocalized(@"org.dept.members");
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self kindAt:indexPath.section] == IMDirSectionMembers ? kIMDirMemberRowHeight : UITableViewAutomaticDimension;
}

/// 单位 / 部门行：SYS 44，图标 29×29（单位 = 首字，本部 systemBlue、子公司 systemPurple；部门 = folder.fill，同设置页图标）。
- (UITableViewCell *)folderCell:(UITableView *)tv indexPath:(NSIndexPath *)ip title:(NSString *)title image:(UIImage *)image {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:kIMDirCellUnit forIndexPath:ip];
    UIListContentConfiguration *cfg = UIListContentConfiguration.cellConfiguration;
    cfg.text = title;
    cfg.image = image;
    cell.contentConfiguration = cfg;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.accessoryView = nil;
    return cell;
}

/// 单位首字色块（白字 14 semibold，圆角与设置页图标一致）；按「首字 + 颜色」缓存，滚动不重画。
static UIImage *IMDirInitialTile(NSString *name, UIColor *color) {
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; });
    NSString *ch = name.length > 0 ? [name substringToIndex:[name rangeOfComposedCharacterSequenceAtIndex:0].length] : @"?";
    NSString *key = [NSString stringWithFormat:@"%@|%p", ch, color];
    UIImage *hit = [cache objectForKey:key];
    if (hit) { return hit; }
    CGFloat side = kIMSettingsIconSide;
    UIImage *img = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)]
                    imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [color setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:7] fill];
        NSDictionary *attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold],
                                 NSForegroundColorAttributeName: UIColor.whiteColor };
        CGSize ts = [ch sizeWithAttributes:attrs];
        [ch drawAtPoint:CGPointMake((side - ts.width) / 2, (side - ts.height) / 2) withAttributes:attrs];
    }];
    [cache setObject:img forKey:key];
    return img;
}

/// 客服小标：11 semibold accent，accentSoft 底 r4。
void IMDirectoryConfigureMemberCell(IMContactCell *cell, NSDictionary *m, NSString *subtitle) {
    [cell configureWithDisplayName:IMJSONString(m[@"name"]) avatarURL:IMJSONString(m[@"avatar_url"])
                        avatarSeed:IMJSONString(m[@"user_id"]) subtitle:(subtitle.length > 0 ? subtitle : nil)];
    cell.accessoryView = IMJSONBool(m[@"is_cs"]) ? IMDirectoryCSTagView() : nil;
}

UIView *IMDirectoryCSTagView(void) {
    UILabel *tag = [UILabel new];
    tag.text = IMLocalized(@"org.cs_tag");
    tag.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    tag.textColor = IMTheme.accent;
    tag.backgroundColor = IMTheme.accentSoft;
    tag.textAlignment = NSTextAlignmentCenter;
    tag.layer.cornerRadius = 4;
    tag.layer.masksToBounds = YES;
    [tag sizeToFit];
    tag.frame = CGRectMake(0, 0, tag.bounds.size.width + 10, 16);
    return tag;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch ([self kindAt:indexPath.section]) {
        case IMDirSectionUnits: {
            IMTenantUnit *u = self.units[indexPath.row];
            UIColor *bg = u.isHQ ? UIColor.systemBlueColor : UIColor.systemPurpleColor;
            return [self folderCell:tableView indexPath:indexPath title:u.name image:IMDirInitialTile(u.name, bg)];
        }
        case IMDirSectionChildren:
            return [self folderCell:tableView indexPath:indexPath title:IMJSONString(self.children[indexPath.row][@"name"])
                              image:IMSettingsIconImage(@"folder.fill", UIColor.systemBlueColor)];
        case IMDirSectionMembers: {
            NSDictionary *m = self.members[indexPath.row];
            IMContactCell *cell = [tableView dequeueReusableCellWithIdentifier:kIMDirCellMember forIndexPath:indexPath];
            IMDirectoryConfigureMemberCell(cell, m, IMJSONString(m[@"title"]));
            return cell;
        }
    }
    return [UITableViewCell new];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    // 滚到成员末尾附近续页（服务端 next_cursor）。
    if ([self kindAt:indexPath.section] == IMDirSectionMembers && self.nextCursor.length > 0
        && indexPath.row >= (NSInteger)self.members.count - 5) {
        [self load];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    switch ([self kindAt:indexPath.section]) {
        case IMDirSectionUnits: {
            IMTenantUnit *u = self.units[indexPath.row];
            [self pushUnit:u.unitID dept:kIMDirRootDept title:u.name];
            break;
        }
        case IMDirSectionChildren: {
            NSDictionary *d = self.children[indexPath.row];
            [self pushUnit:self.unitID dept:IMJSONString(d[@"dept_id"]) title:IMJSONString(d[@"name"])];
            break;
        }
        case IMDirSectionMembers:
            [self.navigationController pushViewController:IMDirectoryProfileController(self.host, self.userID, self.members[indexPath.row])
                                                 animated:YES];
            break;
    }
}

@end

UIViewController *IMDirectoryProfileController(NSString *host, NSString *userID, NSDictionary *member) {
    IMChatDetailViewController *detail =
        [[IMChatDetailViewController alloc] initSingleWithHost:host userID:userID peerID:IMJSONString(member[@"user_id"])
                                                 peerNickname:IMJSONString(member[@"name"])
                                                peerAvatarURL:IMJSONString(member[@"avatar_url"])];
    detail.showsMessagePill = YES; // 从组织架构进来：好友或免好友直聊时给进单聊的入口
    return detail;
}
