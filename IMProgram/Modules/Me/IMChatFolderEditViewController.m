//  IMChatFolderEditViewController.m

#import "IMChatFolderEditViewController.h"
#import "IMChatFolderConvPickerViewController.h"
#import "IMChatFolderConvCell.h"
#import "IMChatFolderStore.h"
#import "IMConversation.h"
#import "IMHTTPService.h"
#import "IMLocalization.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"
#import "IMMainTabBarController.h" // im_refreshNavigationBar

typedef NS_ENUM(NSInteger, IMFolderEditSection) {
    IMFolderEditSectionName = 0,
    IMFolderEditSectionChats,
    IMFolderEditSectionAdd,
    IMFolderEditSectionDelete,
    IMFolderEditSectionCount,
};

@interface IMChatFolderEditViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@end

@implementation IMChatFolderEditViewController {
    NSString *_folderID;            // nil = 创建模式
    NSString *_host, *_token, *_userID;
    NSString *_name;
    NSMutableArray<NSString *> *_convIDs;                     // 该文件夹的成员（创建模式下为待提交集合）
    NSArray<IMConversation *> *_allConvs;                     // 选择器数据源 + 行显示信息
    NSMutableDictionary<NSString *, IMConversation *> *_convByID;
    UITableView *_tableView;
    UITextField *_nameField;
    UILabel *_counterLabel;
}

- (instancetype)initWithFolderID:(NSString *)folderID host:(NSString *)host token:(NSString *)token userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _folderID = [folderID copy];
        _host = [host copy]; _token = [token copy]; _userID = [userID copy];
        _convIDs = [NSMutableArray array];
        _convByID = [NSMutableDictionary dictionary];
        _allConvs = @[];
    }
    return self;
}

- (BOOL)isCreating { return _folderID.length == 0; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = IMTheme.groupedBackground;
    self.title = [self isCreating] ? IMLocalized(@"folder.edit.title_create") : IMLocalized(@"folder.edit.title_edit");
    if ([self isCreating]) {
        _name = self.initialName ?: @"";
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:IMLocalized(@"common.cancel")
            style:UIBarButtonItemStylePlain target:self action:@selector(cancelTapped)];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:IMLocalized(@"common.create")
            style:UIBarButtonItemStyleDone target:self action:@selector(createTapped)];
        [self im_refreshNavigationBar];
    } else {
        [self syncFromStore];
    }

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [_tableView registerClass:IMChatFolderConvCell.class forCellReuseIdentifier:@"conv"];
    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
    [self updateCreateEnabled];
    [self loadConversations];
    if (![self isCreating]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onStoreChanged)
                                                   name:IMChatFoldersDidChangeNotification object:nil];
    }
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self commitNameIfNeeded]; // 返回时未失焦的名称也存下
}

#pragma mark - 数据

- (void)syncFromStore {
    IMChatFolder *f = [IMChatFolderStore.shared folderWithID:_folderID];
    if (!f) { return; }
    _name = f.name;
    [_convIDs setArray:f.convIDs];
}

- (void)onStoreChanged {
    IMChatFolder *f = [IMChatFolderStore.shared folderWithID:_folderID];
    if (!f) { // 在别的设备上被删了：退出本页
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    if (!_nameField.isFirstResponder) { _name = f.name; }
    [_convIDs setArray:f.convIDs];
    [_tableView reloadData];
}

- (void)loadConversations {
    NSString *token = _token.length > 0 ? _token : IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService conversationsWithToken:token completion:^(NSArray<IMConversation *> *convs, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || error) { return; }
        self->_allConvs = convs ?: @[];
        for (IMConversation *c in self->_allConvs) { if (c.convID.length > 0) { self->_convByID[c.convID] = c; } }
        [self->_tableView reloadData];
    }];
}

/// 已添加的会话里能解析出显示信息的那些（解析不到的——如已隐藏的会话——仍占成员数，但不列出）。
- (NSArray<IMConversation *> *)listedConversations {
    NSMutableArray<IMConversation *> *out = [NSMutableArray array];
    for (NSString *cid in _convIDs) {
        IMConversation *c = _convByID[cid];
        if (c) { [out addObject:c]; }
    }
    return out;
}

#pragma mark - 名称

- (NSInteger)runeCount:(NSString *)s { return (NSInteger)([s lengthOfBytesUsingEncoding:NSUTF32StringEncoding] / 4); }

- (NSString *)trimmedName {
    return [_name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

- (void)updateCreateEnabled {
    self.navigationItem.rightBarButtonItem.enabled = [self trimmedName].length > 0;
    [self im_refreshNavigationBar];
}

- (void)nameChanged:(UITextField *)tf {
    _name = tf.text ?: @"";
    _counterLabel.text = [NSString stringWithFormat:@"%ld / %ld", (long)[self runeCount:_name], (long)IMChatFolderStore.shared.maxNameLength];
    [self updateCreateEnabled];
}

- (BOOL)textField:(UITextField *)tf shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *next = [tf.text stringByReplacingCharactersInRange:range withString:string];
    return [self runeCount:next] <= IMChatFolderStore.shared.maxNameLength; // 不超过服务端上限（字符数）
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }
- (void)textFieldDidEndEditing:(UITextField *)tf { [self commitNameIfNeeded]; }

/// 编辑模式：名称变了且合法就提交；失败回滚显示并提示。
- (void)commitNameIfNeeded {
    if ([self isCreating]) { return; }
    IMChatFolder *f = [IMChatFolderStore.shared folderWithID:_folderID];
    NSString *name = [self trimmedName];
    if (!f || [f.name isEqualToString:name]) { return; }
    if (name.length == 0) { _name = f.name; _nameField.text = f.name; return; }
    __weak typeof(self) ws = self;
    [IMChatFolderStore.shared renameFolder:_folderID to:name completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || !error) { return; }
        [self im_showToast:[IMChatFolderStore userMessageForError:error]];
        IMChatFolder *cur = [IMChatFolderStore.shared folderWithID:self->_folderID];
        self->_name = cur.name ?: self->_name;
        self->_nameField.text = self->_name;
    }];
}

#pragma mark - 动作

/// 取消 / 创建成功后的收起：从管理页 push 进来的要 pop（此前一律 dismiss，对 push 页无效 → 「取消」点了没反应）；
/// 作为导航栈根被 present 出来的才 dismiss。
- (void)cancelTapped {
    UINavigationController *nav = self.navigationController;
    if (nav && nav.viewControllers.firstObject != self) {
        [nav popViewControllerAnimated:YES];
    } else {
        [(self.presentingViewController ?: nav) dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)createTapped {
    [self.view endEditing:YES];
    NSString *name = [self trimmedName];
    if (name.length == 0) { [self im_showToast:IMLocalized(@"err.300303")]; return; }
    self.navigationItem.rightBarButtonItem.enabled = NO;
    __weak typeof(self) ws = self;
    [IMChatFolderStore.shared createFolderNamed:name convIDs:[_convIDs copy] completion:^(IMChatFolder *folder, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) {
            [self updateCreateEnabled];
            [self im_showToast:[IMChatFolderStore userMessageForError:error]];
            return;
        }
        [self cancelTapped]; // push / present 两种进法都能收起（见 cancelTapped）
    }];
}

- (void)presentPicker {
    [self.view endEditing:YES];
    __weak typeof(self) ws = self;
    NSArray<NSString *> *current = [_convIDs copy];
    IMChatFolderConvPickerViewController *picker = [[IMChatFolderConvPickerViewController alloc]
        initWithConversations:_allConvs selectedIDs:current maxCount:IMChatFolderStore.shared.maxConvs
        onDone:^(NSArray<NSString *> *selected) { [ws applySelection:selected previous:current]; }];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)applySelection:(NSArray<NSString *> *)selected previous:(NSArray<NSString *> *)previous {
    if ([self isCreating]) {
        [_convIDs setArray:selected];
        [_tableView reloadData];
        return;
    }
    NSMutableArray<NSString *> *add = [NSMutableArray array], *remove = [NSMutableArray array];
    for (NSString *c in selected) { if (![previous containsObject:c]) { [add addObject:c]; } }
    for (NSString *c in previous) { if (![selected containsObject:c]) { [remove addObject:c]; } }
    if (add.count == 0 && remove.count == 0) { return; }
    __weak typeof(self) ws = self;
    [IMChatFolderStore.shared changeConvsInFolder:_folderID add:add remove:remove completion:^(NSError *error) {
        if (error) { [ws im_showToast:[IMChatFolderStore userMessageForError:error]]; }
    }];
}

- (void)removeConv:(IMConversation *)c {
    if ([self isCreating]) {
        [_convIDs removeObject:c.convID];
        [_tableView reloadData];
        return;
    }
    __weak typeof(self) ws = self;
    [IMChatFolderStore.shared changeConvsInFolder:_folderID add:@[] remove:@[c.convID] completion:^(NSError *error) {
        if (error) { [ws im_showToast:[IMChatFolderStore userMessageForError:error]]; }
    }];
}

- (void)confirmDelete {
    __weak typeof(self) ws = self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
        message:IMLocalizedFormat(@"folder.edit.delete_confirm", [self trimmedName]) preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        __strong typeof(ws) self = ws;
        [IMChatFolderStore.shared deleteFolder:self->_folderID completion:^(NSError *error) {
            if (error) { [self im_showToast:[IMChatFolderStore userMessageForError:error]]; return; }
            // 回包整表替换时 onStoreChanged 已发现「它没了」并 pop 过一次；这里再无条件 pop 会连管理页一起弹掉。
            if (self.navigationController.topViewController == self) {
                [self.navigationController popViewControllerAnimated:YES];
            }
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self isCreating] ? IMFolderEditSectionDelete : IMFolderEditSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == IMFolderEditSectionChats) { return (NSInteger)[self listedConversations].count; }
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == IMFolderEditSectionName) { return IMLocalized(@"folder.edit.name"); }
    if (section == IMFolderEditSectionChats) {
        return IMLocalizedFormat(@"folder.edit.chats_section", (long)[self listedConversations].count);
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == IMFolderEditSectionAdd) { return IMLocalized(@"folder.edit.remove_hint"); }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    switch (ip.section) {
        case IMFolderEditSectionName: {
            UITableViewCell *cell = [UITableViewCell new];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            if (!_nameField) {
                _nameField = [UITextField new];
                _nameField.placeholder = IMLocalized(@"folder.edit.name_placeholder");
                _nameField.font = [UIFont systemFontOfSize:16];
                _nameField.returnKeyType = UIReturnKeyDone;
                _nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
                _nameField.delegate = self;
                [_nameField addTarget:self action:@selector(nameChanged:) forControlEvents:UIControlEventEditingChanged];
                _counterLabel = [UILabel new];
                _counterLabel.font = [UIFont systemFontOfSize:13];
                _counterLabel.textColor = IMTheme.textSecondary;
            }
            _nameField.text = _name;
            _counterLabel.text = [NSString stringWithFormat:@"%ld / %ld", (long)[self runeCount:_name], (long)IMChatFolderStore.shared.maxNameLength];
            _nameField.translatesAutoresizingMaskIntoConstraints = NO;
            _counterLabel.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:_nameField];
            [cell.contentView addSubview:_counterLabel];
            UILayoutGuide *g = cell.contentView.layoutMarginsGuide;
            [NSLayoutConstraint activateConstraints:@[
                [_nameField.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
                [_nameField.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
                [_nameField.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
                [_nameField.heightAnchor constraintGreaterThanOrEqualToConstant:44],
                [_counterLabel.leadingAnchor constraintEqualToAnchor:_nameField.trailingAnchor constant:8],
                [_counterLabel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
                [_counterLabel.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            ]];
            [_counterLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            return cell;
        }
        case IMFolderEditSectionChats: {
            IMChatFolderConvCell *cell = [tableView dequeueReusableCellWithIdentifier:@"conv" forIndexPath:ip];
            [cell configureWithConversation:[self listedConversations][(NSUInteger)ip.row] checked:nil];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }
        case IMFolderEditSectionAdd: {
            UITableViewCell *cell = [UITableViewCell new];
            cell.textLabel.text = IMLocalized(@"folder.edit.add_chats");
            cell.textLabel.textColor = IMTheme.accent;
            return cell;
        }
        default: {
            UITableViewCell *cell = [UITableViewCell new];
            cell.textLabel.text = IMLocalized(@"folder.edit.delete");
            cell.textLabel.textColor = IMTheme.danger;
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            return cell;
        }
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == IMFolderEditSectionAdd) { [self presentPicker]; }
    else if (ip.section == IMFolderEditSectionDelete) { [self confirmDelete]; }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section != IMFolderEditSectionChats) { return nil; }
    NSArray<IMConversation *> *listed = [self listedConversations];
    if (ip.row >= (NSInteger)listed.count) { return nil; }
    IMConversation *c = listed[(NSUInteger)ip.row];
    __weak typeof(self) ws = self;
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:IMLocalized(@"folder.edit.remove") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            [ws removeConv:c];
            done(YES);
        }];
    return [UISwipeActionsConfiguration configurationWithActions:@[remove]];
}

@end
