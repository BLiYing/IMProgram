//  IMForwardPickerViewController.m

#import "IMForwardPickerViewController.h"
#import "IMHTTPService.h"
#import "IMConversation.h"
#import "IMAccountIdentity.h"
#import "IMListSearch.h"
#import "UIViewController+IMToast.h"
#import "UILabel+IMAvatar.h"
#import "IMTheme.h"
#import "IMCircleCheckbox.h"

static const NSUInteger kIMForwardMaxSelection = 9;

#pragma mark - Cell（头像圈 + 名字，对齐 Web 转发选择器 / 复用 IMReadReceipt 同款布局）

@interface IMForwardPickerCell : UITableViewCell
- (void)configureWithConversation:(IMConversation *)c multiSelect:(BOOL)multiSelect selected:(BOOL)selected;
@end

@implementation IMForwardPickerCell {
    IMCircleCheckbox *_checkbox;   // 行首圆形勾选框（仅多选态显示，对齐 Web/微信）
    UILabel *_avatar;
    UILabel *_nameLabel;
    NSLayoutConstraint *_checkboxWidth;   // 22 多选 / 0 单选（连同 avatar 前距收起）
    NSLayoutConstraint *_avatarLeading;   // = checkbox.trailing + (多选 12 / 单选 0)
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        _checkbox = [IMCircleCheckbox new];
        _checkbox.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_checkbox];

        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        _avatar.textColor = UIColor.whiteColor;
        _avatar.layer.cornerRadius = 17;
        _avatar.layer.masksToBounds = YES;
        [self.contentView addSubview:_avatar];

        _nameLabel = [UILabel new];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = [UIFont systemFontOfSize:15.5];
        _nameLabel.textColor = IMTheme.textPrimary;
        [self.contentView addSubview:_nameLabel];

        UILayoutGuide *g = self.contentView.layoutMarginsGuide;
        _checkboxWidth = [_checkbox.widthAnchor constraintEqualToConstant:0];
        _avatarLeading = [_avatar.leadingAnchor constraintEqualToAnchor:_checkbox.trailingAnchor constant:0];
        [NSLayoutConstraint activateConstraints:@[
            [_checkbox.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
            [_checkbox.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
            [_checkbox.heightAnchor constraintEqualToConstant:22],
            _checkboxWidth,
            _avatarLeading,
            [_avatar.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:34],
            [_avatar.heightAnchor constraintEqualToConstant:34],
            [_nameLabel.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:12],
            [_nameLabel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_nameLabel.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
            [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:50],
        ]];
    }
    return self;
}

/// 群聊用 name/avatarURL、seed=convID；单聊用 peerNickname/peerAvatarURL、seed=peer（对齐 Web convAvatarUrl）。
/// im_setAvatarURL 内部自动解析相对 URL 并做 cell 复用防错，故直接传原始 avatar_url。
/// 多选态在行首显圆形勾选框（选中 checkmark.circle.fill / 未选 circle）；单选态收起为 0 宽，avatar 顶到行首。
- (void)configureWithConversation:(IMConversation *)c multiSelect:(BOOL)multiSelect selected:(BOOL)selected {
    NSString *name = c.displayName; // 群名/会话备注、单聊备注名 > 昵称 > uid（全端统一口径）
    NSString *url = c.isGroup ? c.avatarURL : c.peerAvatarURL;
    NSString *seed = c.isGroup ? (c.convID ?: name) : (c.peer ?: name);
    [_avatar im_setAvatarURL:url seed:seed displayName:name];
    _nameLabel.text = name;

    _checkbox.hidden = !multiSelect;
    _checkboxWidth.constant = multiSelect ? 22 : 0;
    _avatarLeading.constant = multiSelect ? 12 : 0; // 与 IMContactCell 统一（共享 IMCircleCheckbox）
    if (multiSelect) { _checkbox.checked = selected; }
}

@end

@interface IMForwardPickerViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@end

@implementation IMForwardPickerViewController {
    NSString *_host;
    NSString *_token;
    void (^_onDone)(NSArray<IMConversation *> *);
    NSArray<IMConversation *> *_convs;
    NSArray<IMConversation *> *_filtered;        // 当前搜索词下的可见行；**所有按 row 取会话的地方都读它**
    NSMutableArray<IMConversation *> *_selected; // 多选顺序集（存的是会话对象，与过滤无关：搜完再搜也不丢已选）
    BOOL _multiSelect;
    UITableView *_tableView;
    UISearchBar *_searchBar;
}

- (instancetype)initWithHost:(NSString *)host token:(NSString *)token onDone:(void (^)(NSArray<IMConversation *> *))onDone {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _host = [host copy];
        _token = [token copy];
        _onDone = [onDone copy];
        _selected = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"转发到";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTapped)];
    [self updateRightButton];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:IMForwardPickerCell.class forCellReuseIdentifier:@"conv"];

    // 搜索框（会话多了以后必需）：外观与匹配口径走 IMListSearch，与选好友页/@面板同一套。
    // 放 tableHeaderView 而非 UISearchController：本页是 modal + 自带导航栏，
    // UISearchController 会再叠一层导航态，交互与「取消/多选」两个 bar button 打架。
    _searchBar = IMListSearchBarMake(self.view.bounds.size.width, @"搜索会话", self);
    _tableView.tableHeaderView = _searchBar;
    [self.view addSubview:_tableView];

    [self loadConversations];
}

- (void)loadConversations {
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService conversationsWithToken:_token completion:^(NSArray<IMConversation *> *convs, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) {
            [self im_showToast:@"加载会话失败"];
            return;
        }
        // 剔除「系统通知」单聊：那是只读会话，服务端直接拒 send_msg to=system（护栏见
        // IMServer/docs/design/SYSTEM_NOTICE_SESSION_DESIGN.md §2.2），列出来只会点了报错。
        // 群聊不看 peer（群会话的 peer 无意义），故先判 isGroup。
        NSMutableArray<IMConversation *> *forwardable = [NSMutableArray arrayWithCapacity:convs.count];
        for (IMConversation *c in convs) {
            if (!c.isGroup && IMIsSystemUserID(c.peer)) { continue; }
            [forwardable addObject:c];
        }
        if (forwardable.count == 0) {
            [self im_showToast:@"暂无可转发的会话"];
            return;
        }
        self->_convs = forwardable;
        [self applyFilter];
    }];
}

#pragma mark - 搜索

/// 重算可见行。匹配会话显示名（会话备注 > 好友备注 > 昵称 > 群名）与单聊对端 uid，大小写不敏感。
/// 备注参与匹配是安全的：转发选择页只在本机显示，选中后发出去的是消息本身，不含任何名字。
- (void)applyFilter {
    NSString *q = IMListSearchNormalizedQuery(_searchBar.text);
    if (q.length == 0) {
        _filtered = _convs;
    } else {
        NSMutableArray<IMConversation *> *out = [NSMutableArray array];
        for (IMConversation *c in _convs) {
            // 只有显示名 + 内部 ID（兜底，不展示）。**这里没有 @句柄维度**：搜索的是"会话"，
            // 而会话列表接口刻意不下发 username（语义是"最近聊过的"，标识无意义；且它是全端最高频接口，
            // 见 IMServer/docs/ACCOUNT_IDENTITY_REDESIGN.md §7.4）。
            if (IMListSearchMatches(q, @[[self displayNameFor:c], c.peer ?: @""])) { [out addObject:c]; }
        }
        _filtered = out;
    }
    [_tableView reloadData];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText { [self applyFilter]; }

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

#pragma mark - 单选 / 多选切换

- (void)updateRightButton {
    if (_multiSelect) {
        NSString *title = _selected.count > 0 ? [NSString stringWithFormat:@"发送(%lu)", (unsigned long)_selected.count] : @"发送";
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleDone target:self action:@selector(sendTapped)];
        self.navigationItem.rightBarButtonItem.enabled = _selected.count > 0;
    } else {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"多选" style:UIBarButtonItemStylePlain target:self action:@selector(enterMultiSelect)];
    }
}

- (void)enterMultiSelect {
    _multiSelect = YES;
    [self updateRightButton];
    [_tableView reloadData];
}

- (void)cancelTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)sendTapped {
    if (_selected.count == 0) { return; }
    NSArray<IMConversation *> *result = [_selected copy];
    void (^done)(NSArray<IMConversation *> *) = _onDone;
    [self dismissViewControllerAnimated:YES completion:^{ if (done) { done(result); } }];
}

#pragma mark - 展示

- (NSString *)displayNameFor:(IMConversation *)c { return c.displayName; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _filtered.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    IMForwardPickerCell *cell = [tableView dequeueReusableCellWithIdentifier:@"conv" forIndexPath:ip];
    IMConversation *c = _filtered[ip.row];
    BOOL selected = [_selected containsObject:c];
    [cell configureWithConversation:c multiSelect:_multiSelect selected:selected];
    // 多选态：选中态由行首圆圈承载，不再挂尾部系统 ✓；单选态保留 disclosure「>」。
    cell.accessoryType = _multiSelect ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    [_searchBar resignFirstResponder];
    IMConversation *c = _filtered[ip.row];
    if (!_multiSelect) { // 单选：确认后立即回调
        __weak typeof(self) ws = self;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"转发"
            message:[NSString stringWithFormat:@"发送给「%@」？", [self displayNameFor:c]]
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"发送" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            __strong typeof(ws) self = ws;
            void (^done)(NSArray<IMConversation *> *) = self->_onDone;
            [self dismissViewControllerAnimated:YES completion:^{ if (done) { done(@[c]); } }];
        }]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    // 多选：切换选中，上限 9。
    if ([_selected containsObject:c]) {
        [_selected removeObject:c];
    } else {
        if (_selected.count >= kIMForwardMaxSelection) {
            [self im_showToast:[NSString stringWithFormat:@"最多选择 %lu 个会话", (unsigned long)kIMForwardMaxSelection]];
            return;
        }
        [_selected addObject:c];
    }
    [tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
    [self updateRightButton];
}

@end
