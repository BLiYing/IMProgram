//  IMChatDetailViewController+Peer.m
//  单聊资料页的**对端权威资料**：进页拉一次 GET /users/{id} 覆盖 init 传入的快照，
//  404（200001 用户不存在）时显「该用户不存在或已注销」空态。
//
//  另外承载：进页那一刻的**好友态起步值**（initialPeerIsFriendGuess:）与单聊「备注名 / 用户名」两行
//  （infoCell:row:，含用户名长按复制）——都是"单聊对端"这件事，且主实现文件贴着 1500 行红线。
//
//  为什么单开这个文件：① IMChatDetailViewController.m 已 1489 行 / 门禁 1500，塞不进去；
//  ② 这件事此前**根本没做**——init 传什么就显示什么，永不刷新（/code-review 2026-08-29 抓到）。
//  以前不明显，是因为进资料页的入口（会话列表/通讯录/群成员）传的都是刚从服务端拿到的新鲜值；
//  个人名片把「冻结快照」变成了常态入口，这个洞才致命：
//  设计 §6 的「先用快照填首屏、再拉最新覆盖」与第四分支「已注销 → 空态」全依赖它。

#import "IMChatDetailViewController+Private.h"
#import "IMHTTPService.h"
#import "IMUserCard.h"
#import "IMRemarkStore.h"
#import "IMTheme.h"
#import "IMDetailHeaderViews.h"   // IMDetailAvatarView（setAvatarURL:seed:name:）
#import "IMFriendStateStore.h"   // 进页那一刻的好友态起步值
#import "IMDatabase.h"           // cachedFriends（本地好友全量快照）
#import "UIViewController+IMToast.h"

/// 「用户不存在」的业务码（errcode.UserNotFound）。
static const NSInteger kIMErrUserNotFound = 200001;

/// 「该用户不存在或已注销」覆盖层的 view tag（幂等判定用）。
static const NSInteger kIMPeerNotFoundOverlayTag = 91001;

@implementation IMChatDetailViewController (Peer)

#pragma mark - 好友态起步值

/// 进页那一刻的好友态。**没有网络也要答一个**：界面在 init 就要定型（好友＝消息/呼叫/视频 + 三张卡；
/// 非好友＝只有「加好友」），等 /friends 回来再改就是肉眼可见的闪烁。
/// 顺序：内存快照 → 本地 im_friend_local 全量快照（现场播种一次）→ 都不知道则乐观 YES
/// （绝大多数单聊入口本来就是好友；反过来把好友先显示成陌生人更难看）。
- (BOOL)initialPeerIsFriendGuess:(NSString *)peerID {
    if (peerID.length == 0) { return YES; }
    NSNumber *known = [IMFriendStateStore.sharedStore friendStateForUser:peerID];
    if (known) { return known.boolValue; }
    // 冷启动首次进资料页：内存表还没被任何 /friends 拉取喂过 → 读一次本地快照顺路播种。
    [self performDatabaseOperation:^(IMDatabase *database) { (void)database.cachedFriends; }];
    known = [IMFriendStateStore.sharedStore friendStateForUser:peerID];
    return known ? known.boolValue : YES;
}

#pragma mark - 单聊信息行（备注名 / 用户名）

- (UITableViewCell *)infoCell:(UITableView *)tv row:(NSInteger)row {
    // 两行分开出池：用户名行挂了长按复制手势，与备注名行共用一个复用池会让手势跟着 cell 串到备注行上。
    UITableViewCell *cell = [self dequeueStyledCell:UITableViewCellStyleSubtitle
                                            reuseID:(row == 0 ? @"dRemark" : @"dUsername") inTable:tv];
    if (row == 0) {
        // 只显**备注本身**（不是 displayTitle）：这一行是"备注名"的编辑入口，没设过就该显"未设置"，
        // 否则会把对方昵称显示成"我给他起的备注"，用户点进去还以为已经设过了。
        BOOL hasRemark = self.peerRemark.length > 0;
        cell.textLabel.text = hasRemark ? self.peerRemark : @"未设置";
        cell.textLabel.textColor = hasRemark ? IMTheme.textPrimary : IMTheme.textSecondary;
        cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        cell.detailTextLabel.text = @"备注名 · 点击修改";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        // 显示**公开句柄** @xxx，不是 peerID——后者是 10 位随机数字内部 ID，
        // 标签写着"用户名"却显示一串 ID 是明显的错配（docs/UI.md「用户标识」）。
        // 拿不到时（资料尚未拉回 / 对方无 username）显灰字占位，绝不回退到 ID。
        BOOL hasHandle = self.peerUsername.length > 0;
        cell.textLabel.text = hasHandle ? [@"@" stringByAppendingString:self.peerUsername] : @"未设置";
        cell.textLabel.textColor = hasHandle ? IMTheme.accent : IMTheme.textSecondary;
        cell.detailTextLabel.text = @"用户名";
        cell.accessoryType = UITableViewCellAccessoryNone;
        // 长按复制句柄：用户名是拿去搜人/发给别人的东西，看得见却复制不走等于没有。
        // 手势只装一次（cell 复用后保留），文案在触发时现取，故不怕装配时机。
        if (cell.gestureRecognizers.count == 0) {
            [cell addGestureRecognizer:[[UILongPressGestureRecognizer alloc]
                initWithTarget:self action:@selector(copyPeerUsername:)]];
        }
    }
    return cell;
}

/// 长按「用户名」行 → 复制**裸句柄**（不带 @，粘到搜索框即可用）+ 轻触感 + 吐司。
- (void)copyPeerUsername:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) { return; } // 只在按下达阈值那一刻响应一次
    if (self.peerUsername.length == 0) { [self im_showToast:@"该用户未设置用户名"]; return; }
    UIPasteboard.generalPasteboard.string = self.peerUsername;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [self im_showToast:@"已复制用户名"];
}

#pragma mark - 对端权威资料

/// 拉对端权威资料并覆盖首屏快照。单聊专用；群聊不调。
/// **失败不清空**：网络抖动时保持快照可读，只有明确的「用户不存在」才转空态
/// （fail-open 对显示，fail-closed 只对"确认不存在"这一种情况）。
- (void)loadPeerProfile {
    if (self.isGroup || self.peerID.length == 0) { return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService userProfileWithToken:token userID:self.peerID
                                          completion:^(IMUserCard *card, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) {
            if (error.code == kIMErrUserNotFound) { [self showPeerNotFoundState]; }
            return; // 其余错误（离线/超时/5xx）保持快照，不打扰
        }
        if (card.nickname.length > 0) { self.peerNickname = card.nickname; }   // 真实昵称，非备注
        self.peerUsername = card.username;                                     // 公开句柄，供「用户名」行显示 @xxx
        self.peerPresence = card.presence;                                     // 头部副标题（在线/最近在线）
        self.peerProfileLoaded = YES;                                          // 此后 peerNickname 可用于名片快照
        if (card.avatarURL.length > 0) { self.peerAvatarURL = card.avatarURL; }
        // 服务端的备注是权威值，喂回全局表让各页一起收敛（本页标题随 displayTitle 自然生效）。
        if (card.remark) { [IMRemarkStore.sharedStore applyRemark:card.remark forUser:self.peerID]; }
        [self.avatarView setAvatarURL:[self headerAvatarURL] seed:(self.peerID ?: @"") name:self.displayTitle];
        [self refreshHeaderTexts];
    }];
}

/// 「该用户不存在或已注销」空态：盖住内容区，导航栏与返回保留。
/// 不动 tableView 的 section 组装（那在 1489 行的主文件里，碰不得），用一层覆盖视图实现。
- (void)showPeerNotFoundState {
    if ([self.view viewWithTag:kIMPeerNotFoundOverlayTag]) { return; } // 幂等
    UIView *overlay = [UIView new];
    overlay.tag = kIMPeerNotFoundOverlayTag;
    overlay.backgroundColor = IMTheme.groupedBackground;
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:overlay];

    UIImageView *icon = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"person.crop.circle.badge.questionmark"
                withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:48]]];
    icon.tintColor = IMTheme.textTertiary;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [overlay addSubview:icon];

    UILabel *label = [UILabel new];
    label.text = @"该用户不存在或已注销";
    label.font = [UIFont systemFontOfSize:15];
    label.textColor = IMTheme.textSecondary;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 2;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [overlay addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [overlay.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [overlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [icon.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor constant:-24],
        [label.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:12],
        [label.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:32],
        [label.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-32],
    ]];
}

@end
