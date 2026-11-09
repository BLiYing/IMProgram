//  IMGroupCreateViewController.m
//  见头文件。规格（字号/色值/尺寸）见设计稿 §07，颜色一律走 IMTheme，不写魔法值。

#import "IMGroupCreateViewController.h"
#import "IMSelectedChipStrip.h"
#import "UILabel+IMAvatar.h"   // IMAvatarInitials
#import "IMLocalization.h"
#import "IMMainTabBarController.h"   // im_refreshNavigationBar：注入式液态标题栏不监听 navigationItem
#import "IMGroupAvatarHeader.h"
#import "IMGroupNameDefault.h"
#import "IMFriendPickerViewController.h"
#import "IMAvatarCropViewController.h"
#import "IMMediaPicker.h"
#import "IMUserCard.h"
#import "IMGroupInfo.h"
#import "IMHTTPService.h"
#import "IMServerConfigStore.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"

/// 成员条最多画多少个头像：勾了几百人时不逐个建视图（滚动条也没人真去横滑几百格）。
/// 超出部分点末位「＋ 添加」回第一步取消勾选，那里有搜索与「全选」（只作用于可见行）。
static const NSUInteger kIMGroupCreateMaxChips = 30;
/// 头像上传还没回来就点了「创建」时，最多等这么久，超时就放弃头像先把群建出来。
static const NSTimeInterval kIMGroupCreateAvatarWait = 5.0;

#pragma mark - 成员横条 cell

@interface IMGroupCreateMembersCell : UITableViewCell
@property (nonatomic, copy, nullable) void (^onRemove)(NSString *userID);
@property (nonatomic, copy, nullable) void (^onAdd)(void);
- (void)configureWithMembers:(NSArray<IMUserCard *> *)members;
@end

@implementation IMGroupCreateMembersCell {
    IMSelectedChipStrip *_strip; ///< 与分享选择页底部已选栏同一个组件（Common/IMSelectedChipStrip）
    UIView *_addColumn;         ///< 「＋ 添加」固定在最右侧，**不随成员条横滚**（否则人一多就得先滑到头才能再加人）
    __weak UILabel *_addChip;   ///< 那一格的圆：深浅色切换时要重刷 CGColor 描边（见 traitCollectionDidChange:）
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _strip = [IMSelectedChipStrip new];
        _strip.maxChips = kIMGroupCreateMaxChips;
        _strip.translatesAutoresizingMaskIntoConstraints = NO;
        __weak typeof(self) ws = self;
        _strip.onRemove = ^(NSString *uid) { if (ws.onRemove) { ws.onRemove(uid); } };
        [self.contentView addSubview:_strip];

        // 固定列：一格「＋ 添加」，永远贴着右边缘。成员条只占它左边那段宽度。
        UILabel *circle = nil;
        _addColumn = [IMSelectedChipStrip addChipWithTitle:IMLocalized(@"common.add") target:self
                                                    action:@selector(addTapped) circle:&circle];
        _addChip = circle;
        _addColumn.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_addColumn];

        [NSLayoutConstraint activateConstraints:@[
            [_strip.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_strip.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_strip.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
            [_strip.trailingAnchor constraintEqualToAnchor:_addColumn.leadingAnchor constant:-IMTheme.space2],
            [_addColumn.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-IMTheme.space4],
            [_addColumn.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor constant:-2],
            [_addColumn.widthAnchor constraintEqualToConstant:46],
            [_addColumn.heightAnchor constraintEqualToConstant:68],
        ]];
    }
    return self;
}

- (void)configureWithMembers:(NSArray<IMUserCard *> *)members {
    NSMutableArray<IMSelectedChip *> *chips = [NSMutableArray arrayWithCapacity:members.count];
    for (IMUserCard *card in members) {
        NSString *label = card.displayName.length > 0 ? card.displayName : card.userID; // 成员条是本机渲染，认备注
        [chips addObject:[IMSelectedChip chipWithID:card.userID avatarURL:card.avatarURL seed:card.userID name:label]];
    }
    // 「＋ 添加」不在这条滚动内容里（它是固定列，见 initWithStyle:）。
    [_strip setChips:chips scrollToEnd:NO];
}

/// **CGColor 不随 traitCollection 自动切换**（语义色只在取 UIColor 时才解析）：
/// 用户在本页切深浅色时，「＋ 添加」那圈虚描边会停在旧色，得手动重刷。
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous]) {
        _addChip.layer.borderColor = IMTheme.separator.CGColor;
    }
}

- (void)addTapped { if (self.onAdd) { self.onAdd(); } }

@end

#pragma mark - 建群页

typedef NS_ENUM(NSInteger, IMGroupCreateSection) {
    IMGroupCreateSecName = 0,   ///< 群名称
    IMGroupCreateSecMembers,    ///< 成员横条
    IMGroupCreateSecCount,
};

@interface IMGroupCreateViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, strong) NSMutableArray<IMUserCard *> *members;
@property (nonatomic, copy) void (^onCreated)(IMGroupInfo *group);
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) IMGroupAvatarHeader *header;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UILabel *counter;
@property (nonatomic, copy) NSString *avatarURL;        ///< 已上传的群头像 URL（随建群请求发）
@property (nonatomic, assign) BOOL nameEdited;          ///< 用户手改过群名 → 增删成员不再覆盖
@property (nonatomic, assign) NSUInteger nameLastRunes;  ///< 群名框上一次观测到的 rune 数（非组合态）：只有变长才截断
@property (nonatomic, assign) BOOL avatarUploading;
@property (nonatomic, assign) BOOL createPending;       ///< 头像还在传时点了「创建」，等它回来再发
@property (nonatomic, assign) BOOL creating;            ///< 建群在途：防连点建出两个群（无幂等键）
@end

@implementation IMGroupCreateViewController

- (instancetype)initWithHost:(NSString *)host
                     members:(NSArray<IMUserCard *> *)members
                   onCreated:(void (^)(IMGroupInfo *))onCreated {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _host = [host copy];
        _members = [(members ?: @[]) mutableCopy];
        _onCreated = [onCreated copy];
        _avatarURL = @"";
    }
    return self;
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"group.create.title");
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"name"];
    [self.tableView registerClass:IMGroupCreateMembersCell.class forCellReuseIdentifier:@"members"];
    [self.view addSubview:self.tableView];

    self.header = [[IMGroupAvatarHeader alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 150)];
    [self.header addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pickAvatar)]];
    self.tableView.tableHeaderView = self.header;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:IMLocalized(@"common.create") style:UIBarButtonItemStyleDone
                                        target:self action:@selector(createTapped)];

    [self buildNameField];   // 必须在预填之前：否则 applySuggestedNameIfNeeded 写进的是 nil
    [self applySuggestedNameIfNeeded];
    [self refreshHeader];
    [self refreshCreateEnabled];
}

#pragma mark - 成员

- (void)updateMembers:(NSArray<IMUserCard *> *)members {
    self.members = [(members ?: @[]) mutableCopy];
    [self applySuggestedNameIfNeeded];
    [self.tableView reloadData];
    [self refreshCreateEnabled];
}

- (void)removeMemberWithUserID:(NSString *)userID {
    // 不允许删到 0：与第一步「一个都没选不能下一步」同口径。让用户先删空再报错，
    // 是把错误留到最后一步——这里直接拦住并说清楚。
    if (self.members.count <= 1) {
        [self im_showToast:IMLocalized(@"group.create.min_friends")];
        return;
    }
    NSUInteger idx = NSNotFound;
    for (NSUInteger i = 0; i < self.members.count; i++) {
        if ([self.members[i].userID isEqualToString:userID]) { idx = i; break; }
    }
    if (idx == NSNotFound) { return; }
    [self.members removeObjectAtIndex:idx];
    [self applySuggestedNameIfNeeded];
    [self.tableView reloadData];
}

/// 「＋ 添加」= pop 回选好友页（它还在栈上、勾选原样），不是再 push 一个选人页。
- (void)addMembersTapped {
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - 群名

/// 输入框规格照抄 IMProfileEditViewController 的 fieldWithPlaceholder:（16pt / textPrimary /
/// 随编辑显示清除键），只是嵌进 grouped cell；右侧是 12pt 三级色的 n/上限 计数（上限读 server-config，默认 30）。
/// **在 viewDidLoad 里建好**（不是 cellForRow 里懒建）：预填群名早于第一次出格。
- (void)buildNameField {
    self.nameField = [UITextField new];
    self.nameField.font = [UIFont systemFontOfSize:16];
    self.nameField.textColor = IMTheme.textPrimary;
    self.nameField.placeholder = IMLocalized(@"group.create.name_placeholder");
    self.nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.nameField.returnKeyType = UIReturnKeyDone;
    self.nameField.delegate = self;
    self.nameField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.nameField addTarget:self action:@selector(nameChanged:) forControlEvents:UIControlEventEditingChanged];

    self.counter = [UILabel new];
    self.counter.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.counter.textColor = IMTheme.textTertiary;
    self.counter.translatesAutoresizingMaskIntoConstraints = NO;
    // 长群名会把计数挤成 "25/…"：计数固定不压缩，让输入框自己截断（实测发现）。
    [self.counter setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.counter setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.nameField setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self refreshCounter];
}

/// 预填群名：**我打头**，其余按第一步的勾选顺序。一律用公开名——群名会随建群请求发出去
/// 并显示给全群，用备注等于把私下称呼广播出去（见 IMGroupNameDefault.h 的红线）。
- (void)applySuggestedNameIfNeeded {
    if (self.nameEdited) { return; }
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    // currentNickname 是登录后预热的**公开昵称**（明确允许为空；空则跳过我这一位）。
    [names addObject:IMHTTPService.sharedService.currentNickname ?: @""];
    for (IMUserCard *c in self.members) {
        [names addObject:IMPublicUserName(c.nickname, c.username, c.userID)];
    }
    NSString *suggested = IMDefaultGroupName(names, [self nameMaxLen]);
    self.nameField.text = suggested;
    [self refreshCounter];
    [self refreshHeader];
    [self refreshCreateEnabled];
}

/// 群名上限：后台「群名最大长度」（group_name_max_len；老服务端缺字段时 30）。
- (NSUInteger)nameMaxLen {
    return (NSUInteger)MAX((NSInteger)1, IMServerConfigStore.shared.groupNameMaxLen);
}

- (NSString *)trimmedName {
    return [(self.nameField.text ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (void)refreshCounter {
    // 预填群名（程序赋值不触发 EditingChanged）与手动输入都经这里，顺带记下「上一次长度」；组合态不记。
    if (!self.nameField.markedTextRange) { self.nameLastRunes = IMGroupNameRuneLength(self.nameField.text ?: @""); }
    self.counter.text = [NSString stringWithFormat:@"%lu/%lu",
                         (unsigned long)IMGroupNameRuneLength(self.nameField.text ?: @""),
                         (unsigned long)[self nameMaxLen]];
}

- (void)refreshCreateEnabled {
    self.navigationItem.rightBarButtonItem.enabled = self.trimmedName.length > 0 && !self.creating;
    // ⚠️ **必须手动刷一次注入式液态标题栏**：它只在 push/pop/present 关闭等时机从 navigationItem
    // 同步一次（IMMainNavigationController syncBarForController:），**不监听 enabled 的变化**。
    // 不刷的后果是模拟器实测抓到的 P0：进页时群名为空 → 栏里的按钮同步成 disabled；
    // 之后输入群名，UIBarButtonItem.enabled 变 YES 而栏上那颗按钮仍是灰的且点不动 —— 用户建不出群。
    [self im_refreshNavigationBar];
}

- (void)nameChanged:(UITextField *)field {
    self.nameEdited = YES;   // 手改过就再不被预填名覆盖（清空也算改过，不回填）
    // 拼音上屏后才收口超长（组合态 shouldChange 一律放行）；只在变长时截。
    if (IMGroupNameShouldTruncate(self.nameLastRunes, field.text, [self nameMaxLen], field.markedTextRange != nil)) {
        field.text = IMGroupNameTruncateForEditing(field.text, [self nameMaxLen]);
    }
    [self refreshCounter];
    [self refreshHeader];
    [self refreshCreateEnabled];
}

// 超上限（group_name_max_len）就停止输入（服务端 textguard 才是权威，这里只做体验层拦截）。
// 拼音组合态（markedTextRange 非空）直接放行：未上屏的字母也算码点，接近上限时会组不出词；超长在 nameChanged: 收口。
- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (textField.markedTextRange) { return YES; }
    NSString *currentText = textField.text ?: @"";
    NSString *next = [currentText stringByReplacingCharactersInRange:range withString:string];
    return IMGroupNameEditAllowed(currentText, next, [self nameMaxLen]);
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return NO;
}

#pragma mark - 头像

/// 无头像时圈里显示群名首字——建成后会话列表看到的正是这个样子；群名空则回到相机图标。
- (void)refreshHeader {
    NSString *name = self.trimmedName;
    [self.header applyAvatarImage:self.header.avatar.image
                      placeholder:IMAvatarInitials(name)
                          caption:(self.header.avatar.image || self.avatarURL.length > 0) ? IMLocalized(@"group.avatar.change") : IMLocalized(@"group.avatar.add")];
}

- (void)pickAvatar {
    __weak typeof(self) ws = self;
    [IMMediaPicker presentImagePickerFromViewController:self limit:1 handlesCompletion:^(NSArray<IMPickedMediaHandle *> *handles) {
        IMPickedMediaHandle *h = handles.firstObject;
        if (!h) { return; }
        [ws uploadAvatarHandle:h];
    }];
}

/// 选图 → 圆形裁切 → 头像专用上传（与群管理页设群头像同一条链）。
/// **群此刻还不存在**，所以拿到 URL 只存着，等点「创建」时随 POST 一起发。
- (void)uploadAvatarHandle:(IMPickedMediaHandle *)handle {
    IMHTTPService.sharedService.host = self.host;   // 与选好友页同一套路：发请求前对齐 host
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:IMLocalized(@"common.not_logged_in")]; return; }
    __weak typeof(self) ws = self;
    [handle loadData:^(IMPickedMedia *item) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        UIImage *img = item.data ? [UIImage imageWithData:item.data] : nil;
        if (!img) { [self im_showToast:IMLocalized(@"common.image_process_failed")]; return; }
        IMAvatarCropViewController *crop = [[IMAvatarCropViewController alloc] initWithImage:img];
        crop.onComplete = ^(NSData *jpeg) {
            __strong typeof(ws) self2 = ws;
            if (!self2 || !jpeg) { return; }   // nil = 用户取消
            [self2 startAvatarUpload:jpeg token:token];
        };
        [self presentViewController:crop animated:YES completion:nil];
    }];
}

- (void)startAvatarUpload:(NSData *)jpeg token:(NSString *)token {
    self.avatarUploading = YES;
    [self im_showToast:IMLocalized(@"common.uploading")];
    // 先把裁好的图贴上去：上传还没回来时用户也该看见自己选的那张。
    [self.header applyAvatarImage:[UIImage imageWithData:jpeg] placeholder:nil caption:IMLocalized(@"group.avatar.change")];
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService uploadAvatarData:jpeg token:token completion:^(NSString *url, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        self.avatarUploading = NO;
        if (error || url.length == 0) {
            // 头像是可选项，失败不挡建群：回到占位圈，提示一句，建完还能在群管理里补。
            self.avatarURL = @"";
            [self.header applyAvatarImage:nil placeholder:IMAvatarInitials(self.trimmedName) caption:IMLocalized(@"group.avatar.add")];
            [self im_showToast:error.localizedDescription ?: IMLocalized(@"group.create.avatar_failed")];
        } else {
            self.avatarURL = url;
        }
        if (self.createPending) { [self submitCreate]; }   // 之前点过「创建」，等的就是这一刻
    }];
}

#pragma mark - 建群

- (void)createTapped {
    if (self.creating) { return; }
    if (self.trimmedName.length == 0) { return; }          // 按钮此时本就置灰，双保险
    if (self.avatarUploading) {
        // 头像还在传：等它，但**最多等 5 秒**——不能让一张图卡住整个建群。
        self.createPending = YES;
        self.creating = YES;          // 期间按钮置灰，防连点
        [self refreshCreateEnabled];
        __weak typeof(self) ws = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kIMGroupCreateAvatarWait * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(ws) self = ws;
            if (!self || !self.createPending) { return; }
            self.avatarURL = @"";                          // 放弃这张图（上传回来也不再用）
            [self im_showToast:IMLocalized(@"group.create.avatar_slow")];
            self.creating = NO;                            // 交回 submitCreate 重新置位
            [self submitCreate];
        });
        return;
    }
    [self submitCreate];
}

- (void)submitCreate {
    if (self.creating) { return; }
    self.createPending = NO;
    IMHTTPService.sharedService.host = self.host;
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:IMLocalized(@"common.not_logged_in")]; self.creating = NO; [self refreshCreateEnabled]; return; }
    NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:self.members.count];
    for (IMUserCard *c in self.members) { [ids addObject:c.userID]; }
    self.creating = YES;
    [self refreshCreateEnabled];   // 在途置灰：建群没有幂等键，连点会真的建出两个群
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService createGroupWithToken:token name:self.trimmedName avatarURL:self.avatarURL
                                            memberIDs:ids completion:^(IMGroupInfo *group, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        self.creating = NO;
        [self refreshCreateEnabled];
        if (error || !group) {
            // 不自动重试：建群没有幂等键，重试可能真的建出两个群。
            [self im_showToast:IMLocalizedFormat(@"group.create.failed", error.localizedDescription ?: IMLocalized(@"common.unknown_error"))];
            return;
        }
        if (self.onCreated) { self.onCreated(group); }
    }];
}

#pragma mark - 入口

+ (void)startInNavigationController:(UINavigationController *)nav host:(NSString *)host userID:(NSString *)userID
                          onCreated:(void (^)(IMGroupInfo *))onCreated {
    // picker 要在自己的 onDone 里被回查（cardForUserID:），而 onDone 只能在 init 时传进去——
    // 用 __block __weak 变量在 init 之后补上引用，既拿得到又不成环。
    __block __weak IMFriendPickerViewController *weakPicker = nil;
    __weak UINavigationController *weakNav = nav;
    IMFriendPickerViewController *picker =
        [[IMFriendPickerViewController alloc] initWithHost:host userID:userID excludedIDs:nil
                                              confirmTitle:IMLocalized(@"common.next")
                                                    onDone:^(NSArray<NSString *> *selectedIDs) {
        UINavigationController *stack = weakNav;
        IMFriendPickerViewController *pk = weakPicker;
        if (!stack) { return; }
        NSMutableArray<IMUserCard *> *cards = [NSMutableArray arrayWithCapacity:selectedIDs.count];
        for (NSString *uid in selectedIDs) {
            IMUserCard *card = [pk cardForUserID:uid];
            if (!card) {                       // 回查不到也别静默丢人：至少把 uid 带过去
                card = [IMUserCard new];
                card.userID = uid;
                card.nickname = @"";
            }
            [cards addObject:card];
        }
        // 「＋ 添加」是 pop 回本页（选好友页仍在栈上）：栈里已经有建群页就更新它并 pop 回去，
        // 无脑 push 会叠出第二份一模一样的页面。
        for (UIViewController *vc in stack.viewControllers) {
            if ([vc isKindOfClass:IMGroupCreateViewController.class]) {
                [(IMGroupCreateViewController *)vc updateMembers:cards];
                [stack popToViewController:vc animated:YES];
                return;
            }
        }
        IMGroupCreateViewController *create =
            [[IMGroupCreateViewController alloc] initWithHost:host members:cards onCreated:onCreated];
        [stack pushViewController:create animated:YES];
    }];
    weakPicker = picker;
    // 仅建群入口开「全选」；群主占 1 席，故上限 = maxGroupMembers − 1。配置未加载就不截断（不按猜测值限）。
    picker.showsSelectAll = YES;
    IMServerConfigStore *cfg = IMServerConfigStore.shared;
    picker.selectAllLimit = (cfg.loaded && cfg.maxGroupMembers > 0) ? cfg.maxGroupMembers - 1 : 0;
    // 手点与全选共用这个上限；到顶给「已达本群成员上限」（与 Android 同款文案，{max} 含群主）。
    if (picker.selectAllLimit > 0) { picker.capToast = IMLocalizedFormat(@"group.create.limit_reached", (long)cfg.maxGroupMembers); }
    [nav pushViewController:picker animated:YES];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return IMGroupCreateSecCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 1; }

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == IMGroupCreateSecMembers ? 92 : 44;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section != IMGroupCreateSecMembers) { return nil; }
    return IMLocalizedFormat(@"group.create.members_summary",
            (long)self.members.count, (long)(self.members.count + 1));
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    // 上限是**部署配置**，没拉到就什么都不说——按猜测的数字提示等于误导（见 IMServerConfigStore）。
    IMServerConfigStore *cfg = IMServerConfigStore.shared;
    if (section != IMGroupCreateSecMembers || !cfg.loaded || cfg.maxGroupMembers <= 0) { return nil; }
    return IMLocalizedFormat(@"group.create.max_members", (long)(cfg.maxGroupMembers - 1)); // 群主占 1 席
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == IMGroupCreateSecMembers) {
        IMGroupCreateMembersCell *cell = [tableView dequeueReusableCellWithIdentifier:@"members" forIndexPath:indexPath];
        __weak typeof(self) ws = self;
        cell.onRemove = ^(NSString *uid) { [ws removeMemberWithUserID:uid]; };
        cell.onAdd = ^{ [ws addMembersTapped]; };
        [cell configureWithMembers:self.members];
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"name" forIndexPath:indexPath];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (self.nameField.superview != cell.contentView) {
        [self.nameField removeFromSuperview];
        [self.counter removeFromSuperview];
        [cell.contentView addSubview:self.nameField];
        [cell.contentView addSubview:self.counter];
        UILayoutGuide *g = cell.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [self.nameField.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
            [self.nameField.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
            [self.counter.leadingAnchor constraintEqualToAnchor:self.nameField.trailingAnchor constant:IMTheme.space2],
            [self.counter.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [self.counter.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
        ]];
    }
    return cell;
}

@end
