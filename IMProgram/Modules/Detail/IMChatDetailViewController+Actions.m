//  IMChatDetailViewController+Actions.m
//  详情页「动作」分文件实现：操作排/更多菜单、置顶/免打扰/编辑/拉黑、群昵称/群备注（G1）。
//  从 IMChatDetailViewController.m 平移，未改行为；私有属性/常量经 IMChatDetailViewController+Private.h 共享。

#import "IMChatDetailViewController+Private.h"
#import "IMDetailMemberCell.h"
#import "IMDetailFileCell.h"
#import "IMDetailMediaContainerCell.h"
#import "IMDetailHeaderViews.h"
#import "IMMediaUtil.h"
#import "IMHTTPService.h"
#import "IMSocketManager.h"
#import "IMProtocol.h"
#import "IMDatabase.h"
#import "IMConversation.h"
#import "IMGroupInfo.h"
#import "IMUserCard.h"
#import "IMRemarkStore.h"
#import "IMContactShare.h"
#import "IMGroupManageViewController.h"
#import "IMGroupTextViewController.h"
#import "IMQRCardViewController.h"
#import "IMChatViewController.h"
#import "IMPopoverCard.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import "IMTimeUtil.h"
#import "IMLog.h"
#import "IMMessageModel.h"    // playVoiceRow: 读 content（Private.h 只有 @class 前向声明）
#import "IMVoicePlayer.h"     // 语音 tab：点行就地播放/暂停（toggleEnsuringLocal 共享入口）
#import "IMVoiceMiniPlayerView.h" // 三行 cell 第 2 行：迷你波形播放器
#import "IMTimeUtil.h"        // decorateVoiceRow3Cell: IMFormatVoiceDuration
#import "IMGroupInfo.h"       // decorateVoiceRow3Cell: 群成员昵称
#import "IMAccountIdentity.h"

@implementation IMChatDetailViewController (Actions)

#pragma mark - 语音 tab：三行 cell 装配 + 点行播放

/// 三行（sketch §10 拍板）：发送者 / <IMVoiceMiniPlayerView 迷你播放器带波形进度> / 年月日时:分。
/// 用一个自定义 stack 装到 cell.contentView（避开 UITableViewCellStyleDefault 的 textLabel 限制）。
- (void)decorateVoiceRow3Cell:(UITableViewCell *)cell message:(IMMessageModel *)m {
    UIStackView *stack = (UIStackView *)[cell.contentView viewWithTag:8801];
    IMVoiceMiniPlayerView *mini = (IMVoiceMiniPlayerView *)[cell.contentView viewWithTag:8802];
    UILabel *sender = (UILabel *)[cell.contentView viewWithTag:8803];
    UILabel *time = (UILabel *)[cell.contentView viewWithTag:8804];
    if (!stack) {
        // 首次装：cell 复用后子视图保留，configure 只更新内容。
        sender = [UILabel new];
        sender.tag = 8803;
        sender.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        sender.textColor = IMTheme.textPrimary;
        mini = [IMVoiceMiniPlayerView new];
        mini.tag = 8802;
        time = [UILabel new];
        time.tag = 8804;
        time.font = [UIFont systemFontOfSize:11];
        time.textColor = IMTheme.textSecondary;
        stack = [[UIStackView alloc] initWithArrangedSubviews:@[sender, mini, time]];
        stack.tag = 8801;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 6;
        stack.alignment = UIStackViewAlignmentFill;
        [cell.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10],
            [stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10],
        ]];
        // 默认 textLabel/imageView 不要，改用 stack 承载三行。
        cell.textLabel.text = @"";
        cell.imageView.image = nil;
    }
    NSString *senderUID = m.from ?: @"";
    NSString *senderText;
    if ([senderUID isEqualToString:self.userID]) {
        senderText = @"你自己";
    } else if (self.isGroup) {
        NSString *nick = [self.group nicknameOfMember:senderUID] ?: senderUID;
        senderText = [IMRemarkStore.sharedStore displayNameForUser:senderUID fallback:nick]; // 备注优先（本机显示）
    } else {
        senderText = [IMRemarkStore.sharedStore displayNameForUser:senderUID
                                                          fallback:(self.peerNickname.length ? self.peerNickname : senderUID)];
    }
    sender.text = senderText;
    [mini configureWithMessage:m];
    time.text = IMFormatFileDateTime(m.timestamp);
    // 点 ▶ / 波形：走共享入口 toggleEnsuringLocal（缓存命中直接播；未缓存直连下载）。
    __weak typeof(self) ws = self;
    IMMessageModel *msg = m;
    mini.onPlayTap = ^{
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        [[IMVoicePlayer sharedPlayer] toggleEnsuringLocal:msg host:self.host completion:^(NSError *err) {
            if (err) { [self im_showToast:@"语音下载失败"]; } // CODING_STYLE §5 不吞错
        }];
    };
}


/// 语音行点击（2026-08-26）：走 IMVoicePlayer 共享入口就地播放/暂停。
/// 主文件 didSelect 调用；放本 category 是体量门禁拆分（主文件曾 1508 行超 1500 红线）。
- (void)playVoiceRow:(IMMessageModel *)m {
    __weak typeof(self) ws = self;
    [[IMVoicePlayer sharedPlayer] toggleEnsuringLocal:m host:self.host completion:^(NSError *err) {
        __strong typeof(ws) self = ws;
        if (self && err) { [self im_showToast:@"语音下载失败"]; } // IO 错误不吞（CODING_STYLE §5）
    }];
}

#pragma mark - 动作：操作排 / 更多菜单

- (void)pillTapped:(UIButton *)b {
    NSString *a = b.accessibilityLabel;
    if ([a isEqualToString:@"search"]) {
        // 会话内搜索：pop 回本会话的聊天页，转场落定后进入搜索态（设计见 SEARCH_DESIGN §4）。
        IMChatViewController *chat = [IMChatViewController existingChatForConvID:self.convID
                                                          inNavigationController:self.navigationController];
        if (!chat) { [self im_showToast:@"请返回聊天页后再搜索"]; return; }
        [self.navigationController popToViewController:chat animated:YES];
        id<UIViewControllerTransitionCoordinator> tc = self.navigationController.transitionCoordinator;
        if (tc) {
            [tc animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) { [chat beginInChatSearch]; }];
        } else {
            [chat beginInChatSearch];
        }
    }
    else if ([a isEqualToString:@"call"]) { [self im_showToast:@"语音通话即将上线"]; }
    else if ([a isEqualToString:@"video"]) { [self im_showToast:@"视频通话即将上线"]; }
    else if ([a isEqualToString:@"message"]) { [self openChatWithPeerID:self.peerID nickname:self.peerNickname avatarURL:self.peerAvatarURL]; }
    else if ([a isEqualToString:@"addfriend"]) { [self requestAddPeerFriend]; }
}

/// 单聊「加好友」：向对端发好友申请（微信式，任务一 P0）。
- (void)requestAddPeerFriend { [self requestAddFriendUID:self.peerID]; }

/// 向指定 uid 发好友申请（单聊 pill 与群成员菜单共用）。
/// 两种结果分别对待：
///  - **已直接成为好友**（对方仍视我为好友，典型于我曾单向删除对方后加回）：**不吐司**——
///    说「已发送好友申请」会让用户误以为还要等对方通过；直接刷新界面（操作排/卡片立即恢复）即可。
///  - 已发出申请（待对方同意）：吐司告知，界面暂不变（仍是 requested 非 accepted）。
- (void)requestAddFriendUID:(NSString *)uid {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0 || uid.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService requestFriendWithToken:token peerID:uid
                                             completion:^(BOOL becameFriend, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) { [self im_showToast:error.localizedDescription ?: @"好友申请发送失败"]; return; }
        // 重拉关系：单聊校正 peerIsFriend 并重建操作排/卡片；群聊刷新成员菜单依据。
        // 两种结果都要刷——即使只是发出申请，我侧也已从「无关系」变 requested。
        if (self.isGroup) { [self loadFriendUIDs]; } else { [self loadPeerBlockState]; }
        if (!becameFriend) { [self im_showToast:@"已发送好友申请"]; }
    }];
}

/// 与某人开始/回到单聊（操作排「消息」）。
- (void)openChatWithPeerID:(NSString *)peerID nickname:(NSString *)nickname avatarURL:(NSString *)avatarURL {
    if (peerID.length == 0 || [peerID isEqualToString:self.userID]) { return; }
    [IMChatViewController openInNavigationController:self.navigationController
                                                host:self.host userID:self.userID
                                              peerID:peerID readSeq:0 unread:0 peerReadSeq:0
                                        peerNickname:nickname peerAvatarURL:avatarURL];
}

/// 「更多」Telegram 式锚点菜单：清空记录=普通色；退出/删除群/拉黑=红。
- (void)moreTapped:(UIButton *)anchor {
    NSMutableArray<IMPopoverCardItem *> *items = [NSMutableArray array];
    __weak typeof(self) ws = self;
    if (self.isGroup) {
        [items addObject:[IMPopoverCardItem itemWithTitle:@"清空聊天记录" symbol:@"trash" destructive:NO handler:^{ [ws confirmClearHistory]; }]];
        [items addObject:[IMPopoverCardItem itemWithTitle:@"退出群组" symbol:@"rectangle.portrait.and.arrow.right" destructive:YES handler:^{ [ws confirmLeaveGroup]; }]];
        if (self.group && self.group.myRole == IMGroupRoleOwner) {
            [items addObject:[IMPopoverCardItem itemWithTitle:@"删除群组" symbol:@"trash.fill" destructive:YES handler:^{ [ws confirmDissolve]; }]];
        }
    } else if (IMIsSystemUserID(self.peerID)) {
        // 系统通知会话：只保留清空聊天记录（拉黑/举报 不适用；护栏也会拒）。
        [items addObject:[IMPopoverCardItem itemWithTitle:@"清空聊天记录" symbol:@"trash" destructive:NO handler:^{ [ws confirmClearHistory]; }]];
    } else {
        // 入口 ②「推荐给朋友」（CONTACT_CARD_DESIGN §4.3）：把**当前正在看的这个人**推给别的会话。
        // 微信里比"聊天页发名片"更高频（我正在看这个人 → 推给谁），且零新组件：选会话复用转发选择页。
        [items addObject:[IMPopoverCardItem itemWithTitle:@"推荐给朋友" symbol:@"person.crop.square" destructive:NO handler:^{
            [ws shareThisPeerAsContactCard];
        }]];
        [items addObject:[IMPopoverCardItem itemWithTitle:(self.peerBlocked ? @"取消拉黑" : @"拉黑") symbol:@"hand.raised"
                                             destructive:!self.peerBlocked handler:^{ [ws toggleBlock]; }]];
        [items addObject:[IMPopoverCardItem itemWithTitle:@"清空聊天记录" symbol:@"trash" destructive:NO handler:^{ [ws confirmClearHistory]; }]];
        // 删除好友（2026-08-30 补齐；此前只有通讯录左滑有这个动作，资料页里找不到）。
        // 破坏性最重 → 放末位（destructive-last，与消息/会话菜单同约定）。非好友根本看不到「更多」，
        // 这里的判定只是兜底：好友态是异步校正的，别在旧值下摆一个必然 4xx 的按钮。
        if (self.peerIsFriend) {
            [items addObject:[IMPopoverCardItem itemWithTitle:@"删除好友" symbol:@"person.badge.minus"
                                                 destructive:YES handler:^{ [ws confirmRemoveFriend]; }]];
        }
    }
    [IMPopoverCard presentFromAnchor:anchor inHostView:self.view items:items];
}

/// 入口 ②：把当前单聊对端做成名片，选会话发出去。
///
/// 昵称取 `self.peerNickname` 而**不是**页面标题——后者备注优先，发出去就泄露"我给你起的外号"（§2.4）。
/// 但 `peerNickname` 只有在 `peerProfileLoaded` 为 YES（+Peer.m 拉过权威资料）后才可信：init 传入值
/// 依入口而异，从群成员行进来是**群昵称**、从找人搜索进来是 nil，两者冻进名片都是错的
/// （/code-review 2026-08-29）。未加载则先拉一次再弹选会话页。
- (void)shareThisPeerAsContactCard {
    if (self.peerID.length == 0) { return; }
    if (self.peerProfileLoaded) {
        [IMContactShare presentPickerFrom:self selfUID:self.userID userID:self.peerID
                                 username:self.peerUsername
                                 nickname:self.peerNickname avatarURL:self.peerAvatarURL];
        return;
    }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:@"请先登录"]; return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService userProfileWithToken:token userID:self.peerID
                                          completion:^(IMUserCard *card, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) {
            // 200001 用户不存在 → 没有可分享的名片；其余（网络）也不该冻一个可能错的名字进去。
            [self im_showToast:(error.code == 200001 ? @"该用户不存在或已注销" : @"拉取资料失败，请重试")];
            return;
        }
        self.peerNickname = card.nickname.length ? card.nickname : self.peerNickname;
        self.peerUsername = card.username.length ? card.username : self.peerUsername;
        self.peerAvatarURL = card.avatarURL.length ? card.avatarURL : self.peerAvatarURL;
        self.peerProfileLoaded = YES;
        [IMContactShare presentPickerFrom:self selfUID:self.userID userID:self.peerID
                                 username:self.peerUsername
                                 nickname:self.peerNickname avatarURL:self.peerAvatarURL];
    }];
}

/// 「更多」→ 删除好友（二次确认）。删完**不退页**：重拉关系后本页自然切成非好友视图
/// （只剩「加好友」+ 隐藏三张卡），用户当场就能看到关系已变；弹回上一页反而让人怀疑到底删没删。
- (void)confirmRemoveFriend {
    if (self.isGroup || self.peerID.length == 0) { return; }
    __weak typeof(self) ws = self;
    [self confirmDestructive:[NSString stringWithFormat:@"删除好友「%@」？", self.displayTitle]
                     message:@"将从通讯录移除，聊天记录仍保留在本机。" action:@"删除" handler:^{
        NSString *token = IMHTTPService.sharedService.currentToken; if (token.length == 0) { return; }
        NSString *peer = ws.peerID; if (peer.length == 0) { return; }
        [IMHTTPService.sharedService removeFriendWithToken:token peerID:peer completion:^(NSError *error) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (error) { [self im_showToast:error.localizedDescription ?: @"删除失败"]; return; }
            [self im_showToast:@"已删除好友"];
            // 重拉关系：校正 peerIsFriend → 重建操作排 + 隐藏备注名/设置/页签三张卡。
            // 同一次 /friends 也会刷新 IMFriendStateStore，故下次再进本页起步值就是"非好友"。
            [self loadPeerBlockState];
        }];
    }];
}

- (void)confirmDissolve {
    [self confirmDestructive:[NSString stringWithFormat:@"删除并解散「%@」？", self.displayTitle]
                     message:@"所有成员将被移出，聊天记录无法恢复，此操作不可撤销。" action:@"删除" handler:^{
        NSString *token = IMHTTPService.sharedService.currentToken; if (token.length == 0) { return; }
        __weak typeof(self) ws = self;
        [IMHTTPService.sharedService dissolveGroupWithToken:token convID:self.convID completion:^(NSError *error) {
            if (error) { [ws im_showToast:error.localizedDescription]; return; }
            // 连退两级（详情 + 聊天页）回列表；dissolve 群事件也会触发各页自退（幂等）。
            NSArray *vcs = ws.navigationController.viewControllers;
            NSInteger idx = (NSInteger)vcs.count - 3;
            if (idx >= 0) { [ws.navigationController popToViewController:vcs[idx] animated:YES]; }
            else { [ws.navigationController popViewControllerAnimated:YES]; }
        }];
    }];
}

- (void)confirmClearHistory {
    NSString *msg = self.isGroup ? @"仅清空本机记录，不影响其他成员。" : @"将删除此会话在本机的全部消息，且无法恢复。";
    [self confirmDestructive:@"清空聊天记录？" message:msg action:@"清空" handler:^{
        if (![self performDatabaseOperation:^(IMDatabase *database) {
            [database clearMessagesForConv:self.convID];
        }]) { return; }
        [self rebuildTabs];
        [self.tableView reloadData];
        // 通知底层聊天页清空内存并刷新（否则返回聊天页仍显旧消息）。
        [NSNotificationCenter.defaultCenter postNotificationName:IMChatConversationClearedNotification
                                                          object:nil userInfo:@{kIMConvIDKey: self.convID}];
        [self im_showToast:@"聊天记录已清空"];
    }];
}

- (void)confirmLeaveGroup {
    [self confirmDestructive:[NSString stringWithFormat:@"退出「%@」？", self.displayTitle]
                     message:@"退出后将不再接收此群消息。" action:@"退出" handler:^{
        NSString *token = IMHTTPService.sharedService.currentToken; if (token.length == 0) { return; }
        __weak typeof(self) ws = self;
        [IMHTTPService.sharedService leaveGroupWithToken:token convID:self.convID completion:^(NSError *error) {
            if (error) { [ws im_showToast:error.localizedDescription]; return; }
            // 连退两级（详情 + 聊天页）回列表。
            NSArray *vcs = ws.navigationController.viewControllers;
            NSInteger idx = (NSInteger)vcs.count - 3;
            if (idx >= 0) { [ws.navigationController popToViewController:vcs[idx] animated:YES]; }
            else { [ws.navigationController popViewControllerAnimated:YES]; }
        }];
    }];
}

/// 通用二次确认（红色破坏性）。
- (void)confirmDestructive:(NSString *)title message:(NSString *)message action:(NSString *)action handler:(void (^)(void))handler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:action style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        if (handler) { handler(); }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 动作：设置 / 编辑 / 拉黑

- (void)switchChanged:(UISwitch *)sw {
    if (sw.tag == 1) { self.pinnedAt = sw.on ? IMNowMillis() : 0; }
    else if (sw.tag == 2) { self.muted = sw.on; }
    [self commitConversationSettings];
}
- (void)commitConversationSettings {
    NSString *token = IMHTTPService.sharedService.currentToken; if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    // markedUnread 必须回传当前值（PUT 整体替换）：原来硬编码 NO，在详情页拨置顶/免打扰会
    // 顺手清掉列表页设的手动标未读红点。
    [IMHTTPService.sharedService updateConversationSettingsWithToken:token convID:self.convID
        pinnedAt:self.pinnedAt muted:self.muted markedUnread:self.markedUnread completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || !error) { return; }
        [self im_showToast:error.localizedDescription ?: @"设置失败"];
        // 提交失败：重拉权威值并刷新开关，不让 UI 停留在"看起来成功"的失败态。
        [self loadConversationSettings];
    }];
}

/// 好友备注名长度上限（Unicode 码点），与服务端 friend.MaxRemarkRunes 对齐。
static NSInteger const kIMFriendRemarkMaxRunes = 32;

/// 按 Unicode 码点数长度（与 Go 的 len([]rune(s)) 同口径）：NSString 是 UTF-16 存储，
/// 一个增补平面字符（emoji 等）占两个单元，跳过低代理项即得码点数。
static NSInteger IMRuneCount(NSString *s) {
    NSInteger n = 0;
    for (NSUInteger i = 0; i < s.length; i++) {
        if (!CFStringIsSurrogateLowCharacter([s characterAtIndex:i])) { n++; }
    }
    return n;
}

/// 好友备注名（仅本人可见）：**服务端多端同步**（POST /friends/remark，存 im_friend.remark）。
/// 2026-08-28 从本地 NSUserDefaults 改到服务端——旧实现只有本页读得到，会话列表/通讯录/选人页
/// 全都还显真实昵称，换台设备更是完全看不到。成功后本端乐观刷新 + 落缓存，服务端把
/// friend(event=remark) 帧推给本人其它设备；本机各页由 IMRemarkStore 的变更通知刷新。
- (void)editRemark {
    if (self.peerID.length == 0) { return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置备注名"
        message:@"备注名仅自己可见，将替代对方昵称显示，多端同步。" preferredStyle:UIAlertControllerStyleAlert];
    NSString *current = self.peerRemark ?: @"";
    NSString *placeholder = self.peerNickname.length ? self.peerNickname : (self.peerID ?: @"");
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = current; tf.placeholder = placeholder; }];
    __weak typeof(self) ws = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *v = [alert.textFields.firstObject.text
                       stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        if ([v isEqualToString:current]) { return; } // 没改就别打服务端（清空也走这里：""=="" 直接返回）
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        // 与服务端 friend.MaxRemarkRunes（32）对齐：本地先拦，省一次注定 100001 的往返。
        // 按 Unicode 码点数，与服务端 len([]rune(..)) 同口径——NSString.length 是 UTF-16 单元数，
        // 一个 emoji 占 2，用它会把「32 字」提前拦成 16 个 emoji。
        if (IMRuneCount(v) > kIMFriendRemarkMaxRunes) {
            [self im_showToast:[NSString stringWithFormat:@"备注名最多 %ld 字", (long)kIMFriendRemarkMaxRunes]];
            return;
        }
        NSString *token = IMHTTPService.sharedService.currentToken;
        if (token.length == 0) { [self im_showToast:@"未登录"]; return; }
        NSString *peerID = self.peerID;
        [IMHTTPService.sharedService setFriendRemarkWithToken:token peerID:peerID remark:v
                                                  completion:^(NSError *error) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            // 业务码文案已在 IMHTTPService 按码映射（如 200103 →「对方不是你的好友」），直接透出。
            if (error) { [self im_showToast:error.localizedDescription ?: @"保存失败"]; return; }
            IMLog(@"好友备注已更新 peer=%@ len=%lu", peerID, (unsigned long)v.length);
            self.peerRemark = v.length ? v : nil;
            // 乐观落缓存 + 更新全局显示名：本机各页当场跟着变。服务端那帧也会回到本端，
            // 但那是一个网络往返之后的事，等它标题会明显滞后一拍。
            [self performDatabaseOperation:^(IMDatabase *database) {
                [database applyCachedRemark:v forPeer:peerID];
            }];
            [IMRemarkStore.sharedStore applyRemark:v forUser:peerID];
            [self refreshHeaderTexts];
            [self.tableView reloadData];
            [self im_showToast:v.length ? @"备注已更新" : @"备注已清除"];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 群昵称 / 群备注（G1）

/// 会话备注（G1，仅本人可见、多端同步）：值由 loadConversationSettings 从 GET …/settings 读入
/// self.convRemark，编辑走 PUT …/remark，变更经 conv_update 同步全端。
/// 与上面的**好友备注**（POST /friends/remark，跟人走、通讯录也变）是两件事，别混。
- (NSString *)currentConvRemark { return self.convRemark ?: @""; }

/// 我在本群的昵称（G1，任意成员）：走后端 → 成功后刷新群资料（气泡回退名随之更新）。
- (void)editMyGroupNickname {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"我在本群的昵称"
        message:@"群内所有人可见，最多 20 字；留空恢复默认昵称。" preferredStyle:UIAlertControllerStyleAlert];
    NSString *current = self.group.myNickname ?: @"";
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = current; }];
    __weak typeof(self) ws = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *v = [alert.textFields.firstObject.text
                       stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        if ([v isEqualToString:current]) { return; }
        NSString *token = IMHTTPService.sharedService.currentToken;
        if (token.length == 0) { [ws im_showToast:@"未登录"]; return; }
        [IMHTTPService.sharedService setGroupMyNicknameWithToken:token convID:ws.convID nickname:v
                                                     completion:^(NSError *error) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (error) { [self im_showToast:error.localizedDescription ?: @"保存失败"]; return; }
            self.group.myNickname = v.length ? v : nil;
            [self loadGroupInfo]; // 成员表 group_nickname 变了，重拉刷新
            [self im_showToast:@"已更新"];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

/// 群备注（G1，仅本人可见）：改我看到的群名，**服务端多端同步**（PUT …/remark）。
/// 成功后本端乐观刷新 + 落缓存；conv_update 会把变更同步到本人其它端与本机的会话列表/聊天页标题。
- (void)editGroupRemark {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"群备注"
        message:@"仅自己可见，将替代群名显示，多端同步。" preferredStyle:UIAlertControllerStyleAlert];
    NSString *current = [self currentConvRemark];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = current; tf.placeholder = self.group.name; }];
    __weak typeof(self) ws = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *v = [alert.textFields.firstObject.text
                       stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        if ([v isEqualToString:current]) { return; }
        NSString *token = IMHTTPService.sharedService.currentToken;
        if (token.length == 0) { [ws im_showToast:@"未登录"]; return; }
        [IMHTTPService.sharedService setConversationRemarkWithToken:token convID:ws.convID remark:v
                                                        completion:^(NSError *error) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (error) { [self im_showToast:error.localizedDescription ?: @"保存失败"]; return; }
            IMLog(@"群备注已更新 conv=%@ len=%lu", self.convID, (unsigned long)v.length);
            self.convRemark = v.length ? v : nil;
            // 乐观落缓存：本机会话列表下次刷新（含 conv_update 前）即显新备注，不必等 HTTP 重拉。
            [self performDatabaseOperation:^(IMDatabase *database) {
                [database applyCachedRemarkForConversation:self.convID remark:self.convRemark];
            }];
            [self refreshHeaderTexts];
            [self.tableView reloadData];
            [self im_showToast:v.length ? @"备注已更新" : @"备注已清除"];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)toggleBlock {
    NSString *token = IMHTTPService.sharedService.currentToken; if (token.length == 0) { return; }
    BOOL toBlock = !self.peerBlocked;
    void (^commit)(void) = ^{
        __weak typeof(self) ws = self;
        [IMHTTPService.sharedService friendActionWithToken:token action:(toBlock ? @"block" : @"unblock") peerID:self.peerID
                                                completion:^(NSError *error) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (error) { [self im_showToast:error.localizedDescription ?: @"操作失败"]; return; }
            self.peerBlocked = toBlock;
            [self im_showToast:toBlock ? @"已拉黑" : @"已取消拉黑"];
        }];
    };
    if (toBlock) {
        [self confirmDestructive:[NSString stringWithFormat:@"拉黑「%@」？", self.displayTitle]
                         message:@"拉黑后将不再收到对方消息。" action:@"拉黑" handler:commit];
    } else { commit(); }
}

@end
