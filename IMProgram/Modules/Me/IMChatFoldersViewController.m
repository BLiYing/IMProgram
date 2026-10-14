//  IMChatFoldersViewController.m

#import "IMChatFoldersViewController.h"
#import "IMChatFolderEditViewController.h"
#import "IMChatFolderStore.h"
#import "IMHTTPService.h"
#import "IMLocalization.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"
#import "IMMainTabBarController.h" // im_refreshNavigationBar（注入的液态标题栏按 navigationItem 渲染，改完须显式刷新）

@interface IMChatFoldersViewController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation IMChatFoldersViewController {
    NSString *_host, *_userID;
    UITableView *_tableView;
    NSArray<NSString *> *_recommendNames; // 空态推荐（本地化后的名称）
}

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) { _host = [host copy]; _userID = [userID copy]; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"settings.row.folders");
    self.view.backgroundColor = IMTheme.groupedBackground;
    _recommendNames = @[IMLocalized(@"folder.recommend.work"), IMLocalized(@"folder.recommend.personal"),
                        IMLocalized(@"folder.recommend.groups")];
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onStoreChanged)
                                               name:IMChatFoldersDidChangeNotification object:nil];
    [self updateNavButtons];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_userID.length > 0) { [IMChatFolderStore.shared adoptUserID:_userID]; }
    [IMChatFolderStore.shared refresh];
    [_tableView reloadData];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (NSArray<IMChatFolder *> *)folders { return IMChatFolderStore.shared.folders; }
- (BOOL)isEmptyState { return [self folders].count == 0; }

- (void)onStoreChanged {
    [_tableView reloadData];
    [self updateNavButtons];
}

- (void)updateNavButtons {
    if ([self isEmptyState]) {
        self.navigationItem.rightBarButtonItem = nil;
        _tableView.editing = NO;
        [self im_refreshNavigationBar];
        return;
    }
    // 「编辑」进入拖动排序；左滑删除始终可用。
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:IMLocalized(_tableView.editing ? @"common.done" : @"common.edit")
        style:UIBarButtonItemStylePlain target:self action:@selector(toggleEditing)];
    [self im_refreshNavigationBar];
}

- (void)toggleEditing {
    [_tableView setEditing:!_tableView.editing animated:YES];
    [self updateNavButtons];
}

#pragma mark - 表格结构

// 有文件夹：0 = 文件夹，1 = 创建；无文件夹：0 = 创建，1 = 推荐（头部另有空态说明）。
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self isEmptyState]) { return section == 0 ? 1 : (NSInteger)_recommendNames.count; }
    return section == 0 ? (NSInteger)[self folders].count : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    IMChatFolderStore *store = IMChatFolderStore.shared;
    if ([self isEmptyState]) { return section == 1 ? IMLocalized(@"folder.manage.recommended") : nil; }
    if (section == 0) {
        return IMLocalizedFormat(@"folder.manage.section_mine", (long)[self folders].count, (long)store.maxFolders);
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    IMChatFolderStore *store = IMChatFolderStore.shared;
    BOOL maxed = (NSInteger)[self folders].count >= store.maxFolders;
    if ([self isEmptyState]) { return nil; }
    if (section == 1) {
        return maxed ? IMLocalizedFormat(@"folder.manage.max_reached", (long)store.maxFolders)
                     : IMLocalized(@"folder.manage.footer");
    }
    return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (![self isEmptyState] || section != 0) { return nil; }
    // 空态说明放在「创建」行之上：图标 + 标题 + 一句话。
    UIView *v = [UIView new];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"folder"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:44 weight:UIImageSymbolWeightLight]]];
    icon.tintColor = IMTheme.textSecondary;
    UILabel *title = [UILabel new];
    title.text = IMLocalized(@"folder.manage.empty_title");
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    title.textColor = IMTheme.textPrimary;
    UILabel *desc = [UILabel new];
    desc.text = IMLocalized(@"folder.manage.empty_desc");
    desc.font = [UIFont systemFontOfSize:14];
    desc.textColor = IMTheme.textSecondary;
    desc.textAlignment = NSTextAlignmentCenter;
    desc.numberOfLines = 0;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, title, desc]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:v.topAnchor constant:24],
        [stack.bottomAnchor constraintEqualToAnchor:v.bottomAnchor constant:-12],
        [stack.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:32],
        [stack.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-32],
    ]];
    return v;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if ([self isEmptyState] && section == 0) { return 150; }
    return UITableViewAutomaticDimension;
}

- (UITableViewCell *)iconCellWithTitle:(NSString *)title symbol:(NSString *)symbol color:(UIColor *)color {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.text = title;
    UIImage *img = [UIImage systemImageNamed:symbol
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightMedium]];
    UIImageView *iv = [[UIImageView alloc] initWithImage:img];
    iv.tintColor = UIColor.whiteColor;
    iv.contentMode = UIViewContentModeCenter;
    iv.backgroundColor = color;
    iv.layer.cornerRadius = 7;
    iv.layer.cornerCurve = kCACornerCurveContinuous;
    iv.frame = CGRectMake(0, 0, 30, 30);
    // 用 UIGraphicsImageRenderer 把方块画成一张图塞进 imageView：系统 cell 的左图标列才会按它撑开并对齐分隔线。
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:iv.bounds.size];
    UIImage *tile = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) { [iv.layer renderInContext:ctx.CGContext]; }];
    cell.imageView.image = tile;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    IMChatFolderStore *store = IMChatFolderStore.shared;
    BOOL maxed = (NSInteger)[self folders].count >= store.maxFolders;
    if ([self isEmptyState]) {
        if (ip.section == 0) { return [self createCell:NO]; }
        NSString *name = _recommendNames[(NSUInteger)ip.row];
        UITableViewCell *cell = [self iconCellWithTitle:name
                                                 symbol:(ip.row == 0 ? @"briefcase.fill" : (ip.row == 1 ? @"face.smiling.fill" : @"person.2.fill"))
                                                  color:(ip.row == 0 ? UIColor.systemGreenColor : (ip.row == 1 ? UIColor.systemOrangeColor : UIColor.systemPurpleColor))];
        cell.detailTextLabel.text = IMLocalized(@"folder.manage.recommended_add");
        cell.detailTextLabel.textColor = IMTheme.accent;
        return cell;
    }
    if (ip.section == 1) { return [self createCell:maxed]; }
    IMChatFolder *f = [self folders][(NSUInteger)ip.row];
    UITableViewCell *cell = [self iconCellWithTitle:f.name symbol:@"folder.fill" color:UIColor.systemBlueColor];
    cell.detailTextLabel.text = IMLocalizedFormat(@"folder.manage.chats_count", (long)f.convIDs.count);
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)createCell:(BOOL)disabled {
    UITableViewCell *cell = [UITableViewCell new];
    cell.textLabel.text = IMLocalized(@"folder.manage.create");
    cell.textLabel.textColor = disabled ? IMTheme.textSecondary : IMTheme.accent;
    cell.selectionStyle = disabled ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
    return cell;
}

#pragma mark - 交互

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    IMChatFolderStore *store = IMChatFolderStore.shared;
    BOOL maxed = (NSInteger)[self folders].count >= store.maxFolders;
    BOOL empty = [self isEmptyState];
    if (empty && ip.section == 1) { // 推荐：以该名称进创建页（不预填会话）
        [self pushCreateWithName:_recommendNames[(NSUInteger)ip.row]];
    } else if ((empty && ip.section == 0) || (!empty && ip.section == 1)) {
        if (maxed) { [self im_showToast:IMLocalized(@"err.300301")]; return; }
        [self pushCreateWithName:nil];
    } else {
        IMChatFolder *f = [self folders][(NSUInteger)ip.row];
        IMChatFolderEditViewController *vc = [[IMChatFolderEditViewController alloc]
            initWithFolderID:f.folderID host:_host token:IMHTTPService.sharedService.currentToken userID:_userID];
        [self.navigationController pushViewController:vc animated:YES];
    }
}

- (void)pushCreateWithName:(NSString *)name {
    IMChatFolderEditViewController *vc = [[IMChatFolderEditViewController alloc]
        initWithFolderID:nil host:_host token:IMHTTPService.sharedService.currentToken userID:_userID];
    vc.initialName = name;
    [self.navigationController pushViewController:vc animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)ip {
    return ![self isEmptyState] && ip.section == 0;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)ip {
    return ![self isEmptyState] && ip.section == 0;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from
       toProposedIndexPath:(NSIndexPath *)to {
    return to.section == 0 ? to : [NSIndexPath indexPathForRow:(NSInteger)[self folders].count - 1 inSection:0];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (IMChatFolder *f in [self folders]) { [ids addObject:f.folderID]; }
    NSString *moved = ids[(NSUInteger)from.row];
    [ids removeObjectAtIndex:(NSUInteger)from.row];
    [ids insertObject:moved atIndex:(NSUInteger)to.row];
    __weak typeof(self) ws = self;
    [IMChatFolderStore.shared reorderFolderIDs:ids completion:^(NSError *error) {
        if (error) {
            [ws im_showToast:[IMChatFolderStore userMessageForError:error]];
            [ws.tableView reloadData]; // 失败：回到服务端顺序
        }
    }];
}

- (UITableView *)tableView { return _tableView; }

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    if ([self isEmptyState] || ip.section != 0) { return nil; }
    IMChatFolder *f = [self folders][(NSUInteger)ip.row];
    __weak typeof(self) ws = self;
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:IMLocalized(@"folder.tab.menu_delete") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            [ws confirmDelete:f completion:done];
        }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

- (void)confirmDelete:(IMChatFolder *)f completion:(void (^)(BOOL))done {
    __weak typeof(self) ws = self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
        message:IMLocalizedFormat(@"folder.edit.delete_confirm", f.name) preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *a) { done(NO); }]];
    [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [IMChatFolderStore.shared deleteFolder:f.folderID completion:^(NSError *error) {
            if (error) { [ws im_showToast:[IMChatFolderStore userMessageForError:error]]; }
            done(error == nil);
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
