//  IMCallHistoryViewController.m

#import "IMCallHistoryViewController.h"
#import "IMCallHistoryRecord.h"
#import "IMCallHistoryPaginator.h"
#import "IMCallRecord.h"
#import "IMRtcCall.h"
#import "IMTheme.h"
#import "IMLocalization.h"
#import "IMLiquidSegmentedControl.h"
#import "UILabel+IMAvatar.h"
#import "IMUserProfileCache.h"
#import "IMUserCard.h"
#import "IMDatabase.h"
#import "IMDatabase+RosterCache.h"
#import "IMGroupInfo.h"
#import "IMChatViewController.h"
#import "UIViewController+IMToast.h"
@import IMCallEngine;

static const NSInteger kIMCallHistoryPageSize = 20;
/// 「未接」筛选自动续页的目标行数（设计文档 §3.5「凑够一屏」，取一屏大致能装下的行数，非精确视口计算）。
static const NSInteger kIMCallHistoryMinVisiblePerScreen = 10;
/// 距底部还剩这么多点时触发下一页（对齐 IMFavoritesViewController 的 300pt 阈值）。
static const CGFloat kIMCallHistoryLoadMoreThreshold = 300;

#pragma mark - 行 cell

@interface IMCallHistoryRowCell : UITableViewCell
- (void)configureWithRecord:(IMCallHistoryRecord *)record
                     selfUID:(NSString *)selfUID
                 displayName:(nullable NSString *)displayName
                   avatarURL:(nullable NSString *)avatarURL
                        seed:(NSString *)seed
                     isGroup:(BOOL)isGroup
               groupSubtitle:(nullable NSString *)groupSubtitle;
@end

@implementation IMCallHistoryRowCell {
    UILabel *_avatar;
    UIImageView *_groupGlyph;
    UILabel *_nameLabel;
    UIImageView *_kindIcon;
    UILabel *_subtitleLabel;
    UILabel *_timeLabel;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleDefault;

        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.textColor = UIColor.whiteColor;
        _avatar.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _avatar.clipsToBounds = YES;
        _avatar.layer.cornerRadius = 20;
        [self.contentView addSubview:_avatar];

        _groupGlyph = [UIImageView new];
        _groupGlyph.translatesAutoresizingMaskIntoConstraints = NO;
        _groupGlyph.tintColor = UIColor.whiteColor;
        _groupGlyph.contentMode = UIViewContentModeScaleAspectFit;
        _groupGlyph.image = [UIImage systemImageNamed:@"person.3.fill"];
        [_avatar addSubview:_groupGlyph];

        _nameLabel = [UILabel new];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightSemibold];
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_nameLabel];

        _kindIcon = [UIImageView new];
        _kindIcon.translatesAutoresizingMaskIntoConstraints = NO;
        _kindIcon.contentMode = UIViewContentModeScaleAspectFit;
        _kindIcon.tintColor = IMTheme.textSecondary;
        [self.contentView addSubview:_kindIcon];

        _subtitleLabel = [UILabel new];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [UIFont systemFontOfSize:12.5];
        _subtitleLabel.textColor = IMTheme.textSecondary;
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_subtitleLabel];

        _timeLabel = [UILabel new];
        _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _timeLabel.font = [UIFont systemFontOfSize:12.5];
        _timeLabel.textColor = IMTheme.textSecondary;
        [_timeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_timeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentView addSubview:_timeLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:40],
            [_avatar.heightAnchor constraintEqualToConstant:40],
            [_groupGlyph.centerXAnchor constraintEqualToAnchor:_avatar.centerXAnchor],
            [_groupGlyph.centerYAnchor constraintEqualToAnchor:_avatar.centerYAnchor],
            [_groupGlyph.widthAnchor constraintEqualToConstant:16],
            [_groupGlyph.heightAnchor constraintEqualToConstant:16],

            [_nameLabel.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:10],
            [_nameLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:9],
            [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_timeLabel.leadingAnchor constant:-8],

            [_kindIcon.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_kindIcon.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:2],
            [_kindIcon.widthAnchor constraintEqualToConstant:12],
            [_kindIcon.heightAnchor constraintEqualToConstant:12],
            [_kindIcon.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-9],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_kindIcon.trailingAnchor constant:5],
            [_subtitleLabel.centerYAnchor constraintEqualToAnchor:_kindIcon.centerYAnchor],
            [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16],

            [_timeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_timeLabel.topAnchor constraintEqualToAnchor:_nameLabel.topAnchor],
        ]];
    }
    return self;
}

- (void)configureWithRecord:(IMCallHistoryRecord *)record selfUID:(NSString *)selfUID
                 displayName:(NSString *)displayName avatarURL:(NSString *)avatarURL seed:(NSString *)seed
                     isGroup:(BOOL)isGroup groupSubtitle:(NSString *)groupSubtitle {
    BOOL missed = IMCallHistoryRecordIsMissed(record, selfUID);
    BOOL outgoing = [record.caller isEqualToString:selfUID];
    UIColor *nameColor = missed ? IMTheme.danger : IMTheme.textPrimary;

    NSString *arrow = outgoing ? @"↗ " : @"↙ "; // ↗ / ↙
    NSMutableAttributedString *name = [[NSMutableAttributedString alloc] initWithString:arrow
                                        attributes:@{ NSForegroundColorAttributeName: nameColor }];
    [name appendAttributedString:[[NSAttributedString alloc] initWithString:(displayName ?: @"")
                                        attributes:@{ NSForegroundColorAttributeName: nameColor }]];
    _nameLabel.attributedText = name;

    if (isGroup) {
        _avatar.text = nil;
        _avatar.backgroundColor = [IMTheme avatarColorForSeed:@"im-call-history-group"];
        _groupGlyph.hidden = NO;
        [_avatar im_clearAvatarImage];
        _subtitleLabel.text = groupSubtitle;
    } else {
        _groupGlyph.hidden = YES;
        [_avatar im_setAvatarURL:avatarURL seed:seed displayName:displayName];
        NSString *content = IMCallRecordBuild(record.callID, record.video, record.reason, record.durationSec, NO);
        IMCallRecordDisplay *d = IMCallRecordRender(content, outgoing, NO, nil);
        _subtitleLabel.text = d.text;
    }
    _kindIcon.image = [UIImage systemImageNamed:record.video ? @"video.fill" : @"phone.fill"];
    _timeLabel.text = [IMTheme timeStringFromMillis:record.startedAtMs];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [_avatar im_clearAvatarImage];
    _avatar.text = nil;
    _groupGlyph.hidden = YES;
}

@end

#pragma mark - 空态 / 错误态

@interface IMCallHistoryStateView : UIView
@property (nonatomic, copy) void (^onRetry)(void);
- (void)showLoading;
- (void)showEmpty;
- (void)showErrorWithMessage:(NSString *)message;
- (void)hide;
@end

@implementation IMCallHistoryStateView {
    UIImageView *_icon;
    UIActivityIndicatorView *_spinner;
    UILabel *_label;
    UIButton *_retryButton;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.hidden = YES;
        self.backgroundColor = UIColor.clearColor;

        _icon = [UIImageView new];
        _icon.translatesAutoresizingMaskIntoConstraints = NO;
        _icon.tintColor = IMTheme.textTertiary;
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_icon];

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        _spinner.translatesAutoresizingMaskIntoConstraints = NO;
        _spinner.hidesWhenStopped = YES;
        [self addSubview:_spinner];

        _label = [UILabel new];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = [UIFont systemFontOfSize:13.5];
        _label.textColor = IMTheme.textSecondary;
        _label.textAlignment = NSTextAlignmentCenter;
        _label.numberOfLines = 0;
        [self addSubview:_label];

        _retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _retryButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_retryButton setTitle:IMLocalized(@"common.retry") forState:UIControlStateNormal];
        [_retryButton addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];
        _retryButton.hidden = YES;
        [self addSubview:_retryButton];

        [NSLayoutConstraint activateConstraints:@[
            [_icon.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_icon.topAnchor constraintEqualToAnchor:self.topAnchor constant:70],
            [_icon.widthAnchor constraintEqualToConstant:44],
            [_icon.heightAnchor constraintEqualToConstant:44],
            [_spinner.centerXAnchor constraintEqualToAnchor:_icon.centerXAnchor],
            [_spinner.centerYAnchor constraintEqualToAnchor:_icon.centerYAnchor],
            [_label.topAnchor constraintEqualToAnchor:_icon.bottomAnchor constant:14],
            [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:32],
            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-32],
            [_retryButton.topAnchor constraintEqualToAnchor:_label.bottomAnchor constant:10],
            [_retryButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        ]];
    }
    return self;
}

- (void)retryTapped { if (self.onRetry) { self.onRetry(); } }

- (void)showLoading {
    self.hidden = NO;
    _icon.hidden = YES;
    [_spinner startAnimating];
    _label.text = IMLocalized(@"common.loading");
    _retryButton.hidden = YES;
}

- (void)showEmpty {
    self.hidden = NO;
    _icon.hidden = NO;
    [_spinner stopAnimating];
    _icon.image = [UIImage systemImageNamed:@"phone.slash"];
    _label.text = IMLocalized(@"call.history.empty");
    _retryButton.hidden = YES;
}

- (void)showErrorWithMessage:(NSString *)message {
    self.hidden = NO;
    _icon.hidden = NO;
    [_spinner stopAnimating];
    _icon.image = [UIImage systemImageNamed:@"wifi.slash"];
    _label.text = message.length > 0 ? message : IMLocalized(@"common.load_failed");
    _retryButton.hidden = NO;
}

- (void)hide {
    self.hidden = YES;
    [_spinner stopAnimating];
}

@end

#pragma mark - 主页

@interface IMCallHistoryViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@end

@implementation IMCallHistoryViewController {
    IMCallHistoryPaginator *_paginator;
    UITableView *_tableView;
    IMLiquidSegmentedControl *_segmented;
    IMCallHistoryStateView *_stateView;
    UIActivityIndicatorView *_footerSpinner;
    UILabel *_footerLabel;
    UIView *_footerView;
    NSArray<IMCallHistorySection *> *_sections;
    NSDictionary<NSString *, IMGroupInfo *> *_groupsByConvID;
    NSUUID *_rtcEventToken;
    BOOL _didLoadOnce;
    /// 翻页（非首次加载）失败时记一笔，供底部「加载失败，点击重试」态用；成功/新请求发出时清空。
    /// 首次加载失败改走 `_stateView`（见 `applyLoadResult:`），两者不会同时非空。
    NSError *_footerError;
}

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _host = [host copy];
        _userID = [userID copy];
        _sections = @[];
    }
    return self;
}

- (void)dealloc {
    if (_rtcEventToken) { [IMRtcCall.shared removeEventObserver:_rtcEventToken]; }
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"ios.settings.row.recent_calls");
    self.view.backgroundColor = IMTheme.groupedBackground;

    __weak typeof(self) ws = self;
    _paginator = [[IMCallHistoryPaginator alloc] initWithSelfUID:self.userID pageSize:kIMCallHistoryPageSize
        fetcher:^(id cursor, NSInteger limit, IMCallHistoryFetchCompletion completion) {
        [IMRtcCall.shared fetchCallHistoryWithLimit:limit cursor:cursor
            completion:^(NSArray<IMCallHistoryRecord *> *records, NSNumber *nextCursor, NSError *error) {
            completion(records, nextCursor, error);
        }];
    }];

    _segmented = [[IMLiquidSegmentedControl alloc] initWithFrame:CGRectZero];
    _segmented.translatesAutoresizingMaskIntoConstraints = NO;
    _segmented.titles = @[IMLocalized(@"call.history.tab_all"), IMLocalized(@"call.history.tab_missed")];
    _segmented.selectedIndex = 0;
    [_segmented addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_segmented];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = IMTheme.groupedBackground;
    _tableView.separatorInset = UIEdgeInsetsMake(0, 66, 0, 0);
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 58;
    [_tableView registerClass:IMCallHistoryRowCell.class forCellReuseIdentifier:@"row"];
    [self.view addSubview:_tableView];

    _stateView = [[IMCallHistoryStateView alloc] initWithFrame:CGRectZero];
    _stateView.translatesAutoresizingMaskIntoConstraints = NO;
    _stateView.onRetry = ^{ [ws reload]; };
    [self.view addSubview:_stateView];

    [self setupFooterView];

    [NSLayoutConstraint activateConstraints:@[
        [_segmented.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:6],
        [_segmented.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_segmented.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [_segmented.heightAnchor constraintEqualToConstant:34],
        [_tableView.topAnchor constraintEqualToAnchor:_segmented.bottomAnchor constant:4],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_stateView.topAnchor constraintEqualToAnchor:_tableView.topAnchor],
        [_stateView.leadingAnchor constraintEqualToAnchor:_tableView.leadingAnchor],
        [_stateView.trailingAnchor constraintEqualToAnchor:_tableView.trailingAnchor],
        [_stateView.bottomAnchor constraintEqualToAnchor:_tableView.bottomAnchor],
    ]];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(profilesResolved:)
                                                name:IMUserProfileCacheDidResolveNotification object:nil];
    // `callEnd`：本页仍存活期间通话结束，重拉首页并作废在途旧翻页请求（设计文档 §3）。
    _rtcEventToken = [IMRtcCall.shared addEventObserver:^(IMCallEvent *event) {
        if (event.name == IMCallEventNameCallEnd) { [ws reload]; }
    }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!_didLoadOnce) {
        _didLoadOnce = YES;
        [self reload];
    }
}

- (void)setupFooterView {
    _footerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 44)];
    _footerSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _footerSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    [_footerView addSubview:_footerSpinner];
    _footerLabel = [UILabel new];
    _footerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _footerLabel.font = [UIFont systemFontOfSize:12.5];
    _footerLabel.textColor = IMTheme.textSecondary;
    _footerLabel.textAlignment = NSTextAlignmentCenter;
    [_footerView addSubview:_footerLabel];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(footerTapped)];
    [_footerView addGestureRecognizer:tap];
    [NSLayoutConstraint activateConstraints:@[
        [_footerSpinner.centerYAnchor constraintEqualToAnchor:_footerView.centerYAnchor],
        [_footerLabel.centerXAnchor constraintEqualToAnchor:_footerView.centerXAnchor],
        [_footerLabel.centerYAnchor constraintEqualToAnchor:_footerView.centerYAnchor],
        [_footerSpinner.trailingAnchor constraintEqualToAnchor:_footerLabel.leadingAnchor constant:-8],
    ]];
    _footerView.hidden = YES;
}

#pragma mark - 数据

/// 首次进页 / 切换筛选凑不够一屏 / `callEnd` 触发都走这里。已有数据在屏（如 callEnd 时用户仍停留在本页）
/// 就不盖一个满屏 loading——只在**完全没数据可看**时才用 `_stateView` 的「加载中」态挡一下。
- (void)reload {
    if (_sections.count == 0) { [_stateView showLoading]; } else { [_stateView hide]; }
    __weak typeof(self) ws = self;
    [_paginator reloadWithMinVisible:kIMCallHistoryMinVisiblePerScreen completion:^(NSError *error) {
        [ws applyLoadResult:error];
    }];
    [self updateFooter]; // paginator 已在上面同步置 loading=YES，这里紧接着反映到底部指示器
}

- (void)loadMoreIfNeeded {
    if (_paginator.loading || _paginator.reachedEnd) { return; }
    __weak typeof(self) ws = self;
    [_paginator loadMoreWithMinVisible:kIMCallHistoryMinVisiblePerScreen completion:^(NSError *error) {
        [ws applyLoadResult:error];
    }];
    [self updateFooter];
}

- (void)applyLoadResult:(NSError *)error {
    _groupsByConvID = [self buildGroupsIndex];
    _sections = IMCallHistoryGroupByDate(_paginator.filteredRecords);
    [_tableView reloadData];
    if (_sections.count == 0) {
        // 完全没数据可看：满屏态（空 / 出错），下面 updateFooter 会因 sections.count==0 保持无底部条。
        _footerError = nil;
        if (error) {
            NSString *message = [error.domain isEqualToString:IMRTCErrorInfo.domain] ? IMLocalized(@"common.login_expired")
                                                                                       : (error.localizedDescription ?: IMLocalized(@"common.load_failed"));
            [_stateView showErrorWithMessage:message];
        } else {
            [_stateView showEmpty];
        }
    } else {
        // 已有数据在屏：出错不打断已加载的部分（UX 稿 §04-B），只在底部条提示，整页不切空/错态。
        [_stateView hide];
        _footerError = error;
    }
    [self updateFooter];
}

- (NSDictionary<NSString *, IMGroupInfo *> *)buildGroupsIndex {
    NSMutableDictionary<NSString *, IMGroupInfo *> *m = [NSMutableDictionary dictionary];
    for (IMGroupInfo *g in [IMDatabase.sharedDatabase cachedGroups]) {
        if (g.convID.length > 0) { m[g.convID] = g; }
    }
    return m;
}

/// 底部条只在**已有数据在屏**时出现（首次加载/切筛选无数据走满屏 `_stateView`）：翻页中显 spinner；
/// 翻页失败显红字「加载失败，点击重试」（UX 稿 §04-B，已加载部分保留、不清空整页）；否则不显示。
- (void)updateFooter {
    if (_paginator.loading && _sections.count > 0) {
        _footerSpinner.hidden = NO;
        [_footerSpinner startAnimating];
        _footerLabel.textColor = IMTheme.textSecondary;
        _footerLabel.text = IMLocalized(@"common.loading");
        _tableView.tableFooterView = _footerView;
    } else if (_footerError && _sections.count > 0) {
        _footerSpinner.hidden = YES;
        [_footerSpinner stopAnimating];
        _footerLabel.textColor = IMTheme.danger;
        _footerLabel.text = IMLocalized(@"call.history.load_failed");
        _tableView.tableFooterView = _footerView;
    } else {
        _tableView.tableFooterView = nil;
    }
}

- (void)footerTapped {
    if (_footerError && !_paginator.loading) {
        _footerError = nil;
        [self loadMoreIfNeeded];
    }
}

- (void)profilesResolved:(NSNotification *)note {
    if (_sections.count > 0) { [_tableView reloadData]; }
}

/// 「全部/未接」是同一份已加载数据的两种呈现（设计文档 §3.5），切换本身不发请求：按新筛选重建
/// `_sections`；数据不够一屏且没到底时先显「加载中」（避免闪一下「暂无记录」又变加载中），交给
/// `loadMoreIfNeeded` 续拉——真到底了才是「暂无未接来电」。
- (void)filterChanged:(IMLiquidSegmentedControl *)seg {
    _paginator.filter = seg.selectedIndex == 1 ? IMCallHistoryFilterMissed : IMCallHistoryFilterAll;
    _sections = IMCallHistoryGroupByDate(_paginator.filteredRecords);
    [_tableView reloadData];
    if (_sections.count > 0) {
        [_stateView hide];
    } else if (_paginator.reachedEnd) {
        [_stateView showEmpty];
    } else {
        [_stateView showLoading];
    }
    [self loadMoreIfNeeded];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return (NSInteger)_sections.count; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_sections[(NSUInteger)section].records.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return _sections[(NSUInteger)section].title;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMCallHistoryRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];
    IMCallHistoryRecord *record = _sections[(NSUInteger)indexPath.section].records[(NSUInteger)indexPath.row];
    if (record.group) {
        IMGroupInfo *group = _groupsByConvID[record.chatGroupID ?: @""];
        NSString *name = group.name.length > 0 ? group.name : IMLocalized(@"common.unnamed_group");
        NSInteger peerCount = IMCallHistoryGroupPeerCount(record.memberUIDs, record.caller);
        NSString *kind = IMLocalized(record.video ? @"call.record.kind_video" : @"call.record.kind_voice");
        NSString *subtitle = IMLocalizedFormat(@"call.history.group_subtitle", kind, (long)peerCount);
        [cell configureWithRecord:record selfUID:self.userID displayName:name avatarURL:nil seed:record.chatGroupID ?: @""
                           isGroup:YES groupSubtitle:subtitle];
    } else {
        NSString *peerUID = IMCallHistoryRecordPeerUID(record, self.userID);
        IMUserCard *card = peerUID.length > 0 ? [IMUserProfileCache.sharedCache cardForUserID:peerUID] : nil;
        NSString *name = card.displayName.length > 0 ? card.displayName : IMLocalized(@"common.unnamed_user");
        [cell configureWithRecord:record selfUID:self.userID displayName:name avatarURL:card.avatarURL
                              seed:peerUID ?: @"" isGroup:NO groupSubtitle:nil];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    IMCallHistoryRecord *record = _sections[(NSUInteger)indexPath.section].records[(NSUInteger)indexPath.row];
    if (record.group) {
        IMGroupInfo *group = _groupsByConvID[record.chatGroupID ?: @""];
        if (record.chatGroupID.length == 0) { return; }
        [IMChatViewController openInNavigationController:self.navigationController host:self.host userID:self.userID
                                               groupConvID:record.chatGroupID groupName:group.name
                                                   readSeq:0 unread:0 groupReadSeq:0 groupAvatarURL:group.avatarURL];
        return;
    }
    NSString *peerUID = IMCallHistoryRecordPeerUID(record, self.userID);
    if (peerUID.length == 0) { return; }
    NSString *reason = [IMRtcCall.shared placeSingleCallToPeer:peerUID video:record.video];
    if (reason.length > 0) { [self im_showToast:reason]; }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != _tableView) { return; }
    CGFloat remaining = scrollView.contentSize.height - scrollView.contentOffset.y - scrollView.bounds.size.height;
    if (remaining < kIMCallHistoryLoadMoreThreshold) { [self loadMoreIfNeeded]; }
}

@end
