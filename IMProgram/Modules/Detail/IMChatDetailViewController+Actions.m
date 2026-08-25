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
#import "IMGroupManageViewController.h"
#import "IMGroupTextViewController.h"
#import "IMQRCardViewController.h"
#import "IMChatViewController.h"
#import "IMPopoverCard.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import "IMTimeUtil.h"
#import "IMLog.h"

@implementation IMChatDetailViewController (Actions)

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
    } else if ([self.peerID isEqualToString:@"system"]) {
        // 系统通知会话：只保留清空聊天记录（拉黑/举报 不适用；护栏也会拒）。
        [items addObject:[IMPopoverCardItem itemWithTitle:@"清空聊天记录" symbol:@"trash" destructive:NO handler:^{ [ws confirmClearHistory]; }]];
    } else {
        [items addObject:[IMPopoverCardItem itemWithTitle:(self.peerBlocked ? @"取消拉黑" : @"拉黑") symbol:@"hand.raised"
                                             destructive:!self.peerBlocked handler:^{ [ws toggleBlock]; }]];
        [items addObject:[IMPopoverCardItem itemWithTitle:@"清空聊天记录" symbol:@"trash" destructive:NO handler:^{ [ws confirmClearHistory]; }]];
    }
    [IMPopoverCard presentFromAnchor:anchor inHostView:self.view items:items];
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

- (void)editRemark {
    // 单聊备注名：本地私有（NSUserDefaults，未签名装机 Keychain 不可用），仅自己可见，替代显示名。
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置备注名"
        message:@"备注名仅自己可见，将替代对方昵称显示。" preferredStyle:UIAlertControllerStyleAlert];
    NSString *current = self.displayTitle;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = current; }];
    __weak typeof(self) ws = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *v = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        __strong typeof(ws) self = ws;
        if (!self || v.length == 0) { return; }
        [NSUserDefaults.standardUserDefaults setObject:v forKey:[self remarkKey]];
        self.peerNickname = v;
        [self.avatarView setAvatarURL:[self headerAvatarURL] seed:(self.peerID ?: @"") name:v];
        [self refreshHeaderTexts];
        [self.tableView reloadData];
        [self im_showToast:@"备注已更新"];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (NSString *)remarkKey { return [NSString stringWithFormat:@"im_remark_%@_%@", self.userID, self.peerID]; }

#pragma mark - 群昵称 / 群备注（G1）

/// 群备注本地键（仅本人可见；沿用单聊备注的本地存储范式，keyed by convID）。
/// 说明：后端已有会话级 remark 字段（随 conv_update 多端同步），iOS 现用本地存储，多端同步为后续项。
/// 群备注（G1，仅本人可见）：改为服务端多端同步（旧版本地 NSUserDefaults 已弃用）。值由 loadConversationSettings
/// 从 GET …/settings 读入 self.convRemark，编辑走 PUT …/remark，变更经 conv_update 同步全端。
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
