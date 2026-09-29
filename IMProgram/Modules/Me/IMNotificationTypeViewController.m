//  IMNotificationTypeViewController.m

#import "IMNotificationTypeViewController.h"
#import "IMNotificationSoundViewController.h"
#import "IMNotificationSettings.h"
#import "IMDatabase.h"
#import "IMConversation.h"
#import "IMHTTPService.h"
#import "IMChatViewController.h"
#import "UIViewController+IMToast.h"
#import "UILabel+IMAvatar.h"
#import "IMTheme.h"
#import "IMLocalization.h"
#import "IMLog.h"

typedef NS_ENUM(NSInteger, IMNotifTypeSection) {
    IMNotifTypeSectionToggles = 0,
    IMNotifTypeSectionSound,
    IMNotifTypeSectionExceptions,
};

#pragma mark - 开关行 Cell

@interface IMNotifSwitchCell : UITableViewCell
@property (nonatomic, copy) void (^onChange)(BOOL on);
- (void)configureWithTitle:(NSString *)title on:(BOOL)on dimmed:(BOOL)dimmed;
@end

@implementation IMNotifSwitchCell {
    UISwitch *_toggle;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _toggle = [UISwitch new];
        [_toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
        self.accessoryView = _toggle;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}
- (void)configureWithTitle:(NSString *)title on:(BOOL)on dimmed:(BOOL)dimmed {
    self.textLabel.text = title;
    self.textLabel.textColor = dimmed ? IMTheme.textSecondary : IMTheme.textPrimary; // §2.3：关掉「显示通知」后下方两行灰置但保留、可操作
    _toggle.on = on;
}
- (void)toggled:(UISwitch *)sender {
    if (self.onChange) { self.onChange(sender.on); }
}
@end

#pragma mark - 「标题 + 右值 + chevron」行 Cell（强制 Value1 样式，registerClass: 默认走 Default 样式没有 detailTextLabel）

@interface IMNotifValueCell : UITableViewCell
@end
@implementation IMNotifValueCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    return [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier];
}
@end

#pragma mark - 例外行 Cell（头像 40 / 名字 17 / 右值次要色，§4）

@interface IMNotifExceptionCell : UITableViewCell
- (void)configureWithConversation:(IMConversation *)conversation;
@end

@implementation IMNotifExceptionCell {
    UILabel *_avatar;
    UILabel *_name;
    UILabel *_value;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textColor = UIColor.whiteColor;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        _avatar.layer.cornerRadius = 20;
        _avatar.layer.masksToBounds = YES;
        [self.contentView addSubview:_avatar];

        _name = [UILabel new];
        _name.translatesAutoresizingMaskIntoConstraints = NO;
        _name.font = [UIFont systemFontOfSize:17];
        _name.textColor = IMTheme.textPrimary;
        [self.contentView addSubview:_name];

        _value = [UILabel new];
        _value.translatesAutoresizingMaskIntoConstraints = NO;
        _value.font = [UIFont systemFontOfSize:15];
        _value.textColor = IMTheme.textSecondary;
        _value.textAlignment = NSTextAlignmentRight;
        [_value setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentView addSubview:_value];

        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
            [_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:40],
            [_avatar.heightAnchor constraintEqualToConstant:40],
            [_avatar.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [_avatar.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],

            [_name.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:IMTheme.space3],
            [_name.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

            [_value.leadingAnchor constraintGreaterThanOrEqualToAnchor:_name.trailingAnchor constant:IMTheme.space2],
            [_value.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
            [_value.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}
- (void)configureWithConversation:(IMConversation *)conversation {
    NSString *display = conversation.displayName;
    NSString *avatarURL = conversation.isGroup ? conversation.avatarURL : conversation.peerAvatarURL;
    NSString *seed = conversation.isGroup ? conversation.convID : conversation.peer;
    [_avatar im_setAvatarURL:avatarURL seed:seed displayName:display];
    _name.text = display;
    _value.text = conversation.mentionUnread ? IMLocalized(@"notif.exceptions.muted_mention") : IMLocalized(@"notif.exceptions.muted");
}
@end

#pragma mark - 控制器

@interface IMNotificationTypeViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong, nullable) IMDatabaseAccountContext *databaseContext;
@property (nonatomic, copy) NSArray<IMConversation *> *exceptions; // 该类型下 muted=YES 的会话，按最后消息时间倒序
@end

@implementation IMNotificationTypeViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID isGroup:(BOOL)isGroup {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        _isGroup = isGroup;
        IMDatabaseAccountContext *context = IMDatabase.sharedDatabase.currentAccountContext;
        _databaseContext = [context.ownerUserID isEqualToString:userID] ? context : nil;
        _exceptions = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(self.isGroup ? @"notif.type.group_title" : @"notif.type.private_title");
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:IMNotifSwitchCell.class forCellReuseIdentifier:@"switch"];
    [self.tableView registerClass:IMNotifValueCell.class forCellReuseIdentifier:@"disclosure"];
    [self.tableView registerClass:IMNotifExceptionCell.class forCellReuseIdentifier:@"exception"];
    [self.view addSubview:self.tableView];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsChanged)
                                               name:IMNotificationSettingsDidChangeNotification object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadExceptions];
    [self.tableView reloadData];
}

- (void)settingsChanged {
    [self.tableView reloadData];
}

- (IMNotificationTypeSettings *)typeSettings {
    return self.isGroup ? IMNotificationSettings.shared.groupType : IMNotificationSettings.shared.privateType;
}

/// 本机会话表里该类型 muted=YES 的会话，按最后消息时间倒序（§3.5）。
- (void)reloadExceptions {
    __block NSArray<IMConversation *> *cached = @[];
    [IMDatabase.sharedDatabase performWithAccountContext:self.databaseContext block:^(IMDatabase *database) {
        cached = database.cachedConversations;
    }];
    BOOL wantGroup = self.isGroup;
    NSArray<IMConversation *> *filtered = [cached filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(IMConversation *c, NSDictionary *bindings) {
            return c.muted && c.isGroup == wantGroup;
        }]];
    self.exceptions = [filtered sortedArrayUsingComparator:^NSComparisonResult(IMConversation *a, IMConversation *b) {
        if (a.timestamp == b.timestamp) { return NSOrderedSame; }
        return a.timestamp > b.timestamp ? NSOrderedAscending : NSOrderedDescending;
    }];
}

#pragma mark - 动作

- (void)enabledChanged:(BOOL)on {
    IMNotificationTypeSettings *type = self.typeSettings;
    [IMNotificationSettings.shared setEnabled:on preview:type.preview sound:type.sound forGroup:self.isGroup];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:IMNotifTypeSectionToggles]
                   withRowAnimation:UITableViewRowAnimationNone];
}

- (void)previewChanged:(BOOL)on {
    IMNotificationTypeSettings *type = self.typeSettings;
    [IMNotificationSettings.shared setEnabled:type.enabled preview:on sound:type.sound forGroup:self.isGroup];
}

- (void)openSoundPicker {
    IMNotificationSoundViewController *vc = [[IMNotificationSoundViewController alloc] initForGroup:self.isGroup];
    [self.navigationController pushViewController:vc animated:YES];
}

/// 取消免打扰：PUT 整体替换，必须把 pinned_at / marked_unread 原样带回
/// （§3.5，iOS IMChatDetailViewController+Actions 已踩过这个坑，CODING_STYLE §8）。
- (void)unmute:(IMConversation *)conversation atIndexPath:(NSIndexPath *)indexPath {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0 || conversation.convID.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService updateConversationSettingsWithToken:token convID:conversation.convID
        pinnedAt:conversation.pinnedAt muted:NO markedUnread:conversation.markedUnread
        completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) { [self im_showToast:error.localizedDescription ?: IMLocalized(@"conv.error.settings_failed")]; return; }
        conversation.muted = NO;
        [IMDatabase.sharedDatabase performWithAccountContext:self.databaseContext block:^(IMDatabase *database) {
            [database applyCachedSettingsForConversation:conversation.convID pinnedAt:conversation.pinnedAt
                                                     muted:NO markedUnread:conversation.markedUnread];
        }];
        NSMutableArray<IMConversation *> *mutable = [self.exceptions mutableCopy];
        [mutable removeObject:conversation];
        self.exceptions = mutable;
        [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        if (mutable.count == 0) {
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:IMNotifTypeSectionExceptions]
                           withRowAnimation:UITableViewRowAnimationNone];
        }
    }];
}

- (void)openConversation:(IMConversation *)conversation {
    if (conversation.isGroup) {
        [IMChatViewController openInNavigationController:self.navigationController host:self.host userID:self.userID
                                               groupConvID:conversation.convID groupName:conversation.displayName
                                                   readSeq:conversation.readSeq unread:conversation.unread
                                              groupReadSeq:conversation.groupReadSeq groupAvatarURL:conversation.avatarURL];
    } else {
        [IMChatViewController openInNavigationController:self.navigationController host:self.host userID:self.userID
                                                    peerID:conversation.peer readSeq:conversation.readSeq
                                                    unread:conversation.unread peerReadSeq:conversation.peerReadSeq
                                              peerNickname:conversation.displayName peerAvatarURL:conversation.peerAvatarURL];
    }
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ((IMNotifTypeSection)section) {
        case IMNotifTypeSectionToggles: return 2;
        case IMNotifTypeSectionSound: return 1;
        case IMNotifTypeSectionExceptions: return MAX(self.exceptions.count, (NSUInteger)1); // 至少一行空态占位
    }
    return 0;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == IMNotifTypeSectionSound) { return IMLocalized(@"notif.sound.title"); }
    if (section == IMNotifTypeSectionExceptions) { return IMLocalized(@"notif.section.exceptions"); }
    return nil;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == IMNotifTypeSectionToggles) { return IMLocalized(@"notif.type.preview_footer"); }
    if (section == IMNotifTypeSectionExceptions && self.exceptions.count == 0) {
        return IMLocalized(self.isGroup ? @"notif.exceptions.empty_group" : @"notif.exceptions.empty_private");
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMNotificationTypeSettings *type = self.typeSettings;
    if (indexPath.section == IMNotifTypeSectionToggles) {
        IMNotifSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:@"switch" forIndexPath:indexPath];
        __weak typeof(self) ws = self;
        if (indexPath.row == 0) {
            [cell configureWithTitle:IMLocalized(@"notif.type.enabled") on:type.enabled dimmed:NO];
            cell.onChange = ^(BOOL on) { [ws enabledChanged:on]; };
        } else {
            [cell configureWithTitle:IMLocalized(@"notif.type.preview") on:type.preview dimmed:!type.enabled];
            cell.onChange = ^(BOOL on) { [ws previewChanged:on]; };
        }
        return cell;
    }
    if (indexPath.section == IMNotifTypeSectionSound) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"disclosure" forIndexPath:indexPath];
        cell.textLabel.text = IMLocalized(@"notif.type.sound");
        cell.textLabel.textColor = type.enabled ? IMTheme.textPrimary : IMTheme.textSecondary;
        cell.detailTextLabel.text = [self soundDisplayName:type.sound];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    // 例外
    if (self.exceptions.count == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"disclosure" forIndexPath:indexPath];
        cell.textLabel.text = nil;
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    IMNotifExceptionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"exception" forIndexPath:indexPath];
    [cell configureWithConversation:self.exceptions[indexPath.row]];
    return cell;
}

- (NSString *)soundDisplayName:(NSString *)soundID {
    NSDictionary<NSString *, NSString *> *names = @{
        IMNotificationSoundIDNone: IMLocalized(@"notif.sound.none"),
        IMNotificationSoundIDDefault: IMLocalized(@"notif.sound.default"),
        IMNotificationSoundIDChord: IMLocalized(@"notif.sound.chord"),
        IMNotificationSoundIDChime: IMLocalized(@"notif.sound.chime"),
        IMNotificationSoundIDRise: IMLocalized(@"notif.sound.rise"),
        IMNotificationSoundIDDrop: IMLocalized(@"notif.sound.drop"),
    };
    return names[soundID] ?: IMLocalized(@"notif.sound.default");
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == IMNotifTypeSectionSound) { [self openSoundPicker]; return; }
    if (indexPath.section == IMNotifTypeSectionExceptions && indexPath.row < (NSInteger)self.exceptions.count) {
        [self openConversation:self.exceptions[indexPath.row]];
    }
}

- (nullable UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != IMNotifTypeSectionExceptions || indexPath.row >= (NSInteger)self.exceptions.count) { return nil; }
    IMConversation *conversation = self.exceptions[indexPath.row];
    __weak typeof(self) ws = self;
    UIContextualAction *unmute = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
        title:IMLocalized(@"conv.menu.unmute") handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
            [ws unmute:conversation atIndexPath:indexPath];
            done(YES);
        }];
    unmute.backgroundColor = IMTheme.accent;
    return [UISwipeActionsConfiguration configurationWithActions:@[unmute]];
}

@end
