//  IMReadReceiptViewController.m

#import "IMReadReceiptViewController.h"
#import "IMGroupInfo.h"
#import "IMTheme.h"
#import "IMMediaUtil.h"                 // IMMediaFullURL
#import "UILabel+IMAvatar.h"
#import "IMLiquidSegmentedControl.h"    // 与详情页页签同款 Liquid Glass 分段
#import "IMHTTPService.h"
#import "IMMainTabBarController.h"      // kIMLiquidBarHeight
#import "IMProgram-Swift.h"             // IMLiquidNavigationBar

/// 默认展开高度占屏比（草图定「屏幕一半」；可上滑到 large 看更多成员）。
static const CGFloat kIMReadReceiptDefaultHeightRatio = 0.5;
static const CGFloat kIMReadReceiptTopPadding = 16;

/// 与文件/提及面板同款：恒按 base 外观解析分组背景，避免拖动 detent 时整卡变色。
static UIColor *IMReadReceiptBaseGroupedBackgroundColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        UITraitCollection *base = [UITraitCollection traitCollectionWithUserInterfaceLevel:UIUserInterfaceLevelBase];
        UITraitCollection *merged = [UITraitCollection traitCollectionWithTraitsFromCollections:@[tc, base]];
        return [UIColor.systemGroupedBackgroundColor resolvedColorWithTraitCollection:merged];
    }];
}

#pragma mark - 成员行

@interface IMReadReceiptRowCell : UITableViewCell
@end

@implementation IMReadReceiptRowCell {
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
        _avatar.layer.cornerRadius = 17;
        _avatar.layer.masksToBounds = YES;
        [self.contentView addSubview:_avatar];

        _name = [UILabel new];
        _name.translatesAutoresizingMaskIntoConstraints = NO;
        _name.font = [UIFont systemFontOfSize:15.5];
        _name.textColor = IMTheme.textPrimary;
        [self.contentView addSubview:_name];

        _role = [UILabel new];
        _role.translatesAutoresizingMaskIntoConstraints = NO;
        _role.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _role.textColor = IMTheme.textSecondary;
        _role.textAlignment = NSTextAlignmentCenter;
        _role.layer.cornerRadius = 4;
        _role.layer.borderWidth = 1;
        [self.contentView addSubview:_role];

        UILayoutGuide *g = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
            [_avatar.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:34],
            [_avatar.heightAnchor constraintEqualToConstant:34],
            [_name.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:12],
            [_name.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
            [_role.leadingAnchor constraintGreaterThanOrEqualToAnchor:_name.trailingAnchor constant:8],
            [_role.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_role.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
            [_role.heightAnchor constraintEqualToConstant:18],
            [_role.widthAnchor constraintGreaterThanOrEqualToConstant:44],
            [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:50],
        ]];
    }
    return self;
}

/// member 为 nil 表示群资料里查不到该 uid（刚退群等），退化为「uid + 首字母圈」。
- (void)configureWithUID:(NSString *)uid member:(IMGroupMember *)member host:(NSString *)host {
    NSString *display = member.displayName.length > 0 ? member.displayName : uid;
    [_avatar im_setAvatarURL:IMMediaFullURL(member.avatarURL, host) seed:uid displayName:display];
    _name.text = display;
    NSString *roleText = member.role == IMGroupRoleOwner ? @"群主" : (member.role == IMGroupRoleAdmin ? @"管理员" : nil);
    _role.text = roleText;
    _role.hidden = roleText == nil;
    _role.layer.borderColor = IMTheme.separator.CGColor;
}

@end

#pragma mark - 名单卡

@interface IMReadReceiptViewController () <UITableViewDataSource, UITableViewDelegate, IMLiquidNavigationBarDelegate>
@end

@implementation IMReadReceiptViewController {
    IMGroupInfo *_group;
    NSArray<NSString *> *_read;
    NSArray<NSString *> *_unread;
    void (^_onTapMember)(NSString *);
    IMLiquidSegmentedControl *_segmented;
    UITableView *_tableView;
    NSString *_host;
    NSInteger _tab; // 0=已读，1=未读
}

- (instancetype)initWithGroup:(IMGroupInfo *)group
                     readUIDs:(NSArray<NSString *> *)readUIDs
                   unreadUIDs:(NSArray<NSString *> *)unreadUIDs
                  onTapMember:(void (^)(NSString *))onTapMember {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _group = group;
        _read = readUIDs ?: @[];
        _unread = unreadUIDs ?: @[];
        _onTapMember = [onTapMember copy];
        _host = IMHTTPService.sharedService.host;
        _tab = 0;
        if (@available(iOS 15.0, *)) {
            self.modalPresentationStyle = UIModalPresentationPageSheet;
            UISheetPresentationController *sheet = self.sheetPresentationController;
            if (@available(iOS 16.0, *)) {
                UISheetPresentationControllerDetent *half =
                    [UISheetPresentationControllerDetent customDetentWithIdentifier:@"readReceiptHalf"
                        resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                            return context.maximumDetentValue * kIMReadReceiptDefaultHeightRatio;
                        }];
                sheet.detents = @[half, UISheetPresentationControllerDetent.largeDetent];
            } else {
                sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                                  UISheetPresentationControllerDetent.largeDetent];
            }
            sheet.prefersGrabberVisible = YES; // 抓手：可上滑放大看更多
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"已读详情";
    if (@available(iOS 17.0, *)) {
        self.traitOverrides.userInterfaceLevel = UIUserInterfaceLevelBase;
    }
    UIColor *sheetBackground = IMReadReceiptBaseGroupedBackgroundColor();
    self.view.backgroundColor = sheetBackground;

    _segmented = [[IMLiquidSegmentedControl alloc] initWithFrame:CGRectZero];
    _segmented.translatesAutoresizingMaskIntoConstraints = NO;
    _segmented.titles = @[[NSString stringWithFormat:@"已读 %ld", (long)_read.count],
                          [NSString stringWithFormat:@"未读 %ld", (long)_unread.count]];
    _segmented.selectedIndex = 0;
    [_segmented addTarget:self action:@selector(tabChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_segmented];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = sheetBackground;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:IMReadReceiptRowCell.class forCellReuseIdentifier:@"row"];
    [self.view addSubview:_tableView];

    [self installLiquidNavigationBar];

    [NSLayoutConstraint activateConstraints:@[
        [_segmented.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:6],
        [_segmented.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_segmented.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [_segmented.heightAnchor constraintEqualToConstant:34],
        [_tableView.topAnchor constraintEqualToAnchor:_segmented.bottomAnchor constant:6],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

/// 自持 Liquid Glass 标题栏（模态 sheet 不经导航容器注入，同文件/提及面板）。
- (void)installLiquidNavigationBar {
    UIEdgeInsets insets = self.additionalSafeAreaInsets;
    insets.top = kIMReadReceiptTopPadding + kIMLiquidBarHeight;
    self.additionalSafeAreaInsets = insets;

    IMLiquidNavigationBar *bar = [[IMLiquidNavigationBar alloc] initWithTitle:self.title subtitle:@"" actionTitle:nil];
    bar.delegate = self;
    bar.hostExtraTopInset = kIMLiquidBarHeight;
    bar.backgroundEffectProgress = 0;
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

- (void)tabChanged:(IMLiquidSegmentedControl *)seg {
    _tab = seg.selectedIndex;
    [_tableView reloadData];
}

- (NSArray<NSString *> *)currentUIDs { return _tab == 0 ? _read : _unread; }

#pragma mark - 表格

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.currentUIDs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMReadReceiptRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];
    NSArray<NSString *> *uids = self.currentUIDs;
    if (indexPath.row < (NSInteger)uids.count) {
        NSString *uid = uids[(NSUInteger)indexPath.row];
        [cell configureWithUID:uid member:[self memberForUID:uid] host:_host];
    }
    return cell;
}

/// 空态文案：已读栏"暂无人已读"，未读栏"全部已读"——后者是正面信息，不该显示为"空"。
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.currentUIDs.count > 0) { return nil; }
    return _tab == 0 ? @"还没有人读过这条消息" : @"所有人都已读";
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray<NSString *> *uids = self.currentUIDs;
    if (indexPath.row >= (NSInteger)uids.count || !_onTapMember) { return; }
    NSString *uid = uids[(NSUInteger)indexPath.row];
    void (^tap)(NSString *) = _onTapMember;
    [self dismissViewControllerAnimated:YES completion:^{ tap(uid); }];
}

- (IMGroupMember *)memberForUID:(NSString *)uid {
    for (IMGroupMember *m in _group.members) {
        if ([m.userID isEqualToString:uid]) { return m; }
    }
    return nil;
}

#pragma mark - IMLiquidNavigationBarDelegate

- (void)liquidNavigationBarDidTapLeft:(IMLiquidNavigationBar *)bar { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)liquidNavigationBarDidTapBack:(IMLiquidNavigationBar *)bar { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)liquidNavigationBarDidTapAction:(IMLiquidNavigationBar *)bar { /* 无右侧操作 */ }

@end
