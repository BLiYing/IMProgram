//  IMChatBannerStack.m

#import "IMChatBannerStack.h"
#import "IMPinnedBannerView.h"
#import "IMPinnedMessage.h"

@interface IMChatBannerStack ()
@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy) NSString *convID;

@property (nonatomic, strong) IMPinnedBannerView *pinnedBanner;
@property (nonatomic, strong) IMPinnedBannerView *announcementBanner;
@property (nonatomic, strong) IMPinnedBannerView *approvalBanner;
@property (nonatomic, strong) NSLayoutConstraint *pinnedBannerHeight;
@property (nonatomic, strong) NSLayoutConstraint *announcementBannerHeight;
@property (nonatomic, strong) NSLayoutConstraint *approvalBannerHeight;

@property (nonatomic, assign) NSInteger pinnedIndex;   ///< 横幅当前显示第几条（点条轮转）
@property (nonatomic, assign) NSInteger approvalPending; ///< 最近一次 applyApprovalPending 的原始人数（收起持久化用）
@end

@implementation IMChatBannerStack

- (instancetype)initWithHostView:(UIView *)hostView
                       topAnchor:(NSLayoutYAxisAnchor *)topAnchor
                        delegate:(nullable id<IMChatBannerStackDelegate>)delegate
                         isGroup:(BOOL)isGroup
                          userID:(NSString *)userID
                          convID:(NSString *)convID {
    self = [super init];
    if (self) {
        _delegate = delegate;   // 先于任何内容 setter 绑定，保证首次 notifyHeightChanged 能送达
        _isGroup = isGroup;
        _userID = [userID copy];
        _convID = [convID copy];
        _pinnedItems = @[];
        [self buildBannersInHostView:hostView topAnchor:topAnchor];
    }
    return self;
}

// 三条自上而下叠放：申请 > 公告 > 置顶。浮在消息表之上、紧贴 topAnchor（Glass 导航栏正下方）。
// 不改 tableView 约束（它刻意铺到状态栏下），改用 contentInset.top 顶开内容——走 additionalSafeAreaInsets
// 会反过来推动横幅自身约束，形成循环。
- (void)buildBannersInHostView:(UIView *)hostView topAnchor:(NSLayoutYAxisAnchor *)topAnchor {
    __weak typeof(self) ws = self;

    // 入群申请横幅（G3，蓝条，仅群主/管理员）：贴顶，排在公告/置顶之上。点=进审批列表。
    self.approvalBanner = [[IMPinnedBannerView alloc] initWithStyle:IMBannerStyleApproval];
    self.approvalBanner.translatesAutoresizingMaskIntoConstraints = NO;
    self.approvalBanner.hidden = YES;
    self.approvalBanner.onTap = ^{ [ws.delegate bannerStackDidTapApproval:ws]; };
    self.approvalBanner.onClose = ^{
        __strong typeof(ws) self = ws; if (!self) { return; }
        [NSUserDefaults.standardUserDefaults setInteger:self.approvalPending forKey:[self bannerDismissKey:@"approval"]];
        [self applyApprovalPending:self.approvalPending];
    };
    [hostView addSubview:self.approvalBanner];

    // 群公告横幅（G1，黄条）：接在申请横幅下方。点条=开公告全文视图。
    self.announcementBanner = [[IMPinnedBannerView alloc] initWithStyle:IMBannerStyleAnnouncement];
    self.announcementBanner.translatesAutoresizingMaskIntoConstraints = NO;
    self.announcementBanner.hidden = YES;
    self.announcementBanner.onTap = ^{ [ws.delegate bannerStackDidTapAnnouncement:ws]; };
    self.announcementBanner.onClose = ^{
        __strong typeof(ws) self = ws; if (!self) { return; }
        if (self.announcementText.length > 0) {
            [NSUserDefaults.standardUserDefaults setObject:self.announcementText forKey:[self bannerDismissKey:@"ann"]];
        }
        [self applyAnnouncementBanner];
    };
    [hostView addSubview:self.announcementBanner];

    // 置顶消息横幅（G0，蓝条）：接在公告横幅下方。
    self.pinnedBanner = [[IMPinnedBannerView alloc] initWithStyle:IMBannerStylePinned];
    self.pinnedBanner.translatesAutoresizingMaskIntoConstraints = NO;
    self.pinnedBanner.hidden = YES;
    self.pinnedBanner.onTap = ^{
        __strong typeof(ws) self = ws; if (!self) { return; }
        NSInteger total = (NSInteger)self.pinnedItems.count;
        if (total == 0) { return; }
        IMPinnedMessage *shown = self.pinnedItems[MIN(MAX(self.pinnedIndex, 0), total - 1)];
        [self.delegate bannerStack:self didRequestJumpToConvSeq:shown.convSeq];
        [self advancePinnedIndex];
    };
    self.pinnedBanner.onList = ^{ [ws.delegate bannerStackDidTapPinnedList:ws]; };
    self.pinnedBanner.onClose = ^{
        __strong typeof(ws) self = ws; if (!self) { return; }
        NSString *sig = [self currentPinnedSig];
        if (sig.length > 0) { [NSUserDefaults.standardUserDefaults setObject:sig forKey:[self bannerDismissKey:@"pin"]]; }
        [self applyPinnedBanner];
    };
    [hostView addSubview:self.pinnedBanner];

    [NSLayoutConstraint activateConstraints:@[
        [self.approvalBanner.topAnchor constraintEqualToAnchor:topAnchor],
        [self.approvalBanner.leadingAnchor constraintEqualToAnchor:hostView.leadingAnchor],
        [self.approvalBanner.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor],
        (self.approvalBannerHeight = [self.approvalBanner.heightAnchor constraintEqualToConstant:0]),

        [self.announcementBanner.topAnchor constraintEqualToAnchor:self.approvalBanner.bottomAnchor],
        [self.announcementBanner.leadingAnchor constraintEqualToAnchor:hostView.leadingAnchor],
        [self.announcementBanner.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor],
        (self.announcementBannerHeight = [self.announcementBanner.heightAnchor constraintEqualToConstant:0]),

        [self.pinnedBanner.topAnchor constraintEqualToAnchor:self.announcementBanner.bottomAnchor],
        [self.pinnedBanner.leadingAnchor constraintEqualToAnchor:hostView.leadingAnchor],
        [self.pinnedBanner.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor],
        (self.pinnedBannerHeight = [self.pinnedBanner.heightAnchor constraintEqualToConstant:0]),
    ]];
}

#pragma mark - 收起态持久化

/// 置顶横幅「内容签名」（条数 + 首条 conv_seq）：收起态按此记忆，签名变化即视为新内容、自动复现。
/// 收起处与刷新处共用同一算法，避免两处格式串分叉。
- (nullable NSString *)currentPinnedSig {
    NSInteger total = (NSInteger)self.pinnedItems.count;
    return total > 0 ? [NSString stringWithFormat:@"%ld:%lld", (long)total, (long long)self.pinnedItems.firstObject.convSeq] : nil;
}

/// 横幅收起状态的 NSUserDefaults 键：含 userID + convID，换账号/换会话互不影响。
- (NSString *)bannerDismissKey:(NSString *)kind {
    return [NSString stringWithFormat:@"im_banner_dismiss_%@_%@_%@", kind, self.userID ?: @"", self.convID ?: @""];
}

#pragma mark - 置顶（G0）

- (void)setPinnedItems:(NSArray<IMPinnedMessage *> *)pinnedItems {
    _pinnedItems = [pinnedItems copy] ?: @[];
    [self applyPinnedBanner];
}

- (nullable IMPinnedMessage *)currentPinnedItem {
    NSInteger total = (NSInteger)self.pinnedItems.count;
    if (total == 0) { return nil; }
    return self.pinnedItems[MIN(MAX(self.pinnedIndex, 0), total - 1)];
}

- (void)advancePinnedIndex {
    NSInteger total = (NSInteger)self.pinnedItems.count;
    if (total == 0) { return; }
    self.pinnedIndex = (self.pinnedIndex + 1) % total;
    [self applyPinnedBanner];
}

- (UIView *)pinnedBannerView {
    return self.pinnedBanner;
}

/// 把当前 pinnedItems/pinnedIndex 应用到横幅，并同步顶部内边距。
- (void)applyPinnedBanner {
    NSInteger total = (NSInteger)self.pinnedItems.count;
    // 别人取消置顶会让列表变短，旧索引可能越界（横幅空白）→ 夹紧回 0。
    if (self.pinnedIndex < 0 || self.pinnedIndex >= total) { self.pinnedIndex = 0; }
    IMPinnedMessage *shown = total > 0 ? self.pinnedItems[self.pinnedIndex] : nil;
    // 收起态持久化：仅当当前内容签名与"收起时记下的签名"一致才隐藏；新置顶签名不同 → 自动复现。
    NSString *sig = [self currentPinnedSig];
    NSString *dismissedSig = [NSUserDefaults.standardUserDefaults stringForKey:[self bannerDismissKey:@"pin"]];
    if (sig.length > 0 && [sig isEqualToString:dismissedSig]) { shown = nil; }
    [self.pinnedBanner applyItem:shown index:self.pinnedIndex total:total isGroup:self.isGroup];
    self.pinnedBannerHeight.constant = shown ? [IMPinnedBannerView bannerHeight] : 0;
    [self notifyHeightChanged];
}

#pragma mark - 公告（G1）

- (void)setAnnouncementText:(nullable NSString *)announcementText {
    _announcementText = [announcementText copy];
    [self applyAnnouncementBanner];
}

/// 应用群公告横幅：文本非空则显黄条。
- (void)applyAnnouncementBanner {
    NSString *text = self.announcementText;
    NSString *dismissedText = [NSUserDefaults.standardUserDefaults stringForKey:[self bannerDismissKey:@"ann"]];
    NSString *shownText = (text.length > 0 && [text isEqualToString:dismissedText]) ? nil : text; // 公告改了→签名不同→复现
    [self.announcementBanner applyAnnouncement:shownText];
    self.announcementBannerHeight.constant = shownText.length ? [IMPinnedBannerView bannerHeight] : 0;
    [self notifyHeightChanged];
}

#pragma mark - 入群申请（G3）

- (void)applyApprovalPending:(NSInteger)pending {
    self.approvalPending = pending;
    NSInteger dismissedCount = [NSUserDefaults.standardUserDefaults integerForKey:[self bannerDismissKey:@"approval"]];
    NSInteger shownPending = (pending > 0 && pending == dismissedCount) ? 0 : pending; // 申请数变→复现
    [self.approvalBanner applyApprovalCount:shownPending];
    self.approvalBannerHeight.constant = shownPending > 0 ? [IMPinnedBannerView bannerHeight] : 0;
    [self notifyHeightChanged];
}

#pragma mark - 高度

- (CGFloat)totalHeight {
    return self.approvalBannerHeight.constant + self.announcementBannerHeight.constant + self.pinnedBannerHeight.constant;
}

- (void)notifyHeightChanged {
    [self.delegate bannerStackDidChangeHeight:self];
}

@end
