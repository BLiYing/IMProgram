//  IMChatDetailViewController+Peer.m
//  单聊资料页的**对端权威资料**：进页拉一次 GET /users/{id} 覆盖 init 传入的快照，
//  404（200001 用户不存在）时显「该用户不存在或已注销」空态。
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

/// 「用户不存在」的业务码（errcode.UserNotFound）。
static const NSInteger kIMErrUserNotFound = 200001;

/// 「该用户不存在或已注销」覆盖层的 view tag（幂等判定用）。
static const NSInteger kIMPeerNotFoundOverlayTag = 91001;

@implementation IMChatDetailViewController (Peer)

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
