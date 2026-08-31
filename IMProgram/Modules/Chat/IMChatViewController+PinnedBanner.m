//  IMChatViewController+PinnedBanner.m
//  聊天页顶部三横幅栈（G0 置顶 / G1 公告 / G2 禁言锁 / G3 入群申请）分文件实现：拉取/刷新置顶集合、
//  横幅栈 IMChatBannerStackDelegate 回调（顶开表、跳转、公告卡、入群审批、置顶列表）与输入栏禁言锁。
//  从 IMChatViewController.m 平移，未改行为。

#import "IMChatViewController+Private.h" // 含 IMChatBannerStack / IMSocketManager / IMGroupInfo
#import "IMHTTPService.h"
#import "IMPinnedMessage.h"
#import "IMMessageModel.h"
#import "IMDatabase.h"            // 跳转前判目标是否已撤回（recalledAt）
#import "UIViewController+IMToast.h"  // im_showToast:
#import "IMJoinRequestsViewController.h"
#import "IMGroupTextViewController.h"
#import "IMTimeUtil.h"                    // IMNowMillis
#import "IMAccountIdentity.h"

NS_ASSUME_NONNULL_BEGIN

/// setComposerLocked 仅本 TU 内被 refreshComposerMuteState 调用（且在其定义之前），故只需 TU 内前置声明，
/// 不进 +Private.h（跨 TU 不可见即可）。
@interface IMChatViewController (PinnedBannerInternal)
- (void)setComposerLocked:(BOOL)locked reason:(nullable NSString *)reason;
- (void)jumpToPinnedConvSeq:(int64_t)convSeq;
@end

NS_ASSUME_NONNULL_END

@implementation IMChatViewController (PinnedBanner)

#pragma mark - 置顶消息横幅（G0）

/// 能否置顶：群内读 `perm_pin`——开(YES)=仅群主/管理员，关(NO)=全员可置顶（对齐服务端 hub.go 校验）；单聊任一方可。
- (BOOL)canPinMessages {
    if (!self.isGroupChat) { return YES; }
    if (!self.groupInfo.permPin) { return YES; } // 群主关闭「仅管理员可置顶」→ 全员可置顶
    return self.groupInfo.myRole == IMGroupRoleOwner || self.groupInfo.myRole == IMGroupRoleAdmin;
}

/// 重拉本会话置顶集合并刷新横幅。best-effort：拉不到就不显，绝不打断聊天。
- (void)reloadPinnedBanner {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0 || self.convID.length == 0) { return; }
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService pinnedMessagesWithToken:token convID:self.convID
                                             completion:^(NSArray<IMPinnedMessage *> *items, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || error) { return; }
        self.bannerStack.pinnedItems = items ?: @[]; // setter 内部夹紧索引 + 收起态判定 + 顶开 tableView
    }];
}

/// 待审批人数：仅群聊且我是群主/管理员才计，其余 0。喂给横幅栈决定是否显 G3 蓝条。
- (NSInteger)approvalPendingCount {
    BOOL canManage = self.groupInfo.myRole == IMGroupRoleOwner || self.groupInfo.myRole == IMGroupRoleAdmin;
    return (self.isGroupChat && canManage) ? self.groupInfo.pendingCount : 0;
}

#pragma mark IMChatBannerStackDelegate

/// 三横幅叠加总高变化 → 顶开消息表内容（放一处算，避免各方法各自覆盖 inset.top）。
- (void)bannerStackDidChangeHeight:(IMChatBannerStack *)stack {
    CGFloat top = stack.totalHeight;
    UIEdgeInsets inset = self.tableView.contentInset;
    if (inset.top == top) { return; }
    inset.top = top;
    self.tableView.contentInset = inset;
}

/// 点置顶横幅主体：跳到当前那条（轮转已在横幅栈内部处理）。
- (void)bannerStack:(IMChatBannerStack *)stack didRequestJumpToConvSeq:(int64_t)convSeq {
    [self jumpToPinnedConvSeq:convSeq];
}

/// 置顶跳转前的「原消息还在吗」判定（纯函数，便于回归：IMProgramTests/IMPinnedJumpTests.m）。
/// YES = 本地这条已是撤回墓碑，应提示而非跳转；NO = 正常跳（含"本地压根没有这条"，
/// 那种由 jumpToConvSeq: 自己分辨"不在本地/已被删除"）。
BOOL IMPinnedTargetRecalled(NSArray<IMMessageModel *> *messages, int64_t convSeq) {
    if (convSeq <= 0) { return NO; }
    for (IMMessageModel *m in messages) {
        if (m.convSeq == convSeq) { return m.recalledAt > 0; }
    }
    return NO;
}

/// 置顶项跳转（横幅主体 / 置顶列表行共用）：先判目标是不是**已被撤回**。
/// 服务端置顶列表本就剔除撤回消息（store.PinnedMessages 带 recalled_at = 0），但横幅是快照——
/// reloadPinnedBanner 是 best-effort（拉失败就留旧集合）、msg_op 帧还没到、半屏列表开着时对方撤回，
/// 都可能停在旧集合上。此时直接 jumpToConvSeq: 会滚到一条「撤回了一条消息」的系统行并高亮一闪，
/// 用户看不出原消息已经没了。故显式提示 + 顺手重拉一次让横幅收敛（与 Web jumpToPinned 同口径）。
- (void)jumpToPinnedConvSeq:(int64_t)convSeq {
    // 分页后内存里只有当前一窗，而**置顶消息天然是较早那条**——十有八九不在窗口里。
    // 只查内存的话这个判定基本永远返回 NO，「原消息已被撤回」这条提示等于没了。
    // 故窗口里没有就回本地库查那一条（本地也没有，才由 jumpToConvSeq: 去开窗）。
    NSArray<IMMessageModel *> *probe = self.windowState.messages;
    BOOL inWindow = NO;
    for (IMMessageModel *m in probe) { if (m.convSeq == convSeq) { inWindow = YES; break; } }
    if (!inWindow) {
        __block IMMessageModel *row = nil;
        NSString *convID = self.convID;
        [self performDatabaseOperation:^(IMDatabase *database) {
            row = [database messageInConv:convID convSeq:convSeq];
        }];
        probe = row ? @[row] : @[];
    }
    if (IMPinnedTargetRecalled(probe, convSeq)) {
        [self im_showToast:@"原消息已被撤回"];
        [self reloadPinnedBanner];
        return;
    }
    [self jumpToConvSeq:convSeq];
}

/// 点入群申请横幅：进审批列表（同意/拒绝后回调重拉，角标随之更新）。
- (void)bannerStackDidTapApproval:(IMChatBannerStack *)stack {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    IMJoinRequestsViewController *vc = [[IMJoinRequestsViewController alloc] initWithToken:token convID:self.convID
                                                                                onChanged:^{ [ws reloadGroupInfo]; }];
    [self.navigationController pushViewController:vc animated:YES];
}

/// 进群/新版本自动弹一次公告卡（sketch §02②，决策 16）：`announcementAt` 比本地记录新才弹，每版一次。
/// 本地按 convID 存 last-seen（NSUserDefaults）；弹过即记录本版，之后 reloadGroupInfo 再进来不重复弹。
- (void)maybeAutoPopAnnouncement {
    NSString *text = self.bannerStack.announcementText;
    int64_t at = self.groupInfo.announcementAt;
    if (text.length == 0 || at <= 0) { return; }
    NSString *key = [NSString stringWithFormat:@"im_ann_seen_%@", self.convID ?: @""];
    int64_t seen = (int64_t)[NSUserDefaults.standardUserDefaults doubleForKey:key];
    if (at <= seen) { return; }
    // 仅在本页可见且无其他弹层时弹（被详情页盖住/已有 sheet 时先不弹，下次可见再弹）。
    if (self.navigationController.topViewController != self || self.presentedViewController != nil) { return; }
    [NSUserDefaults.standardUserDefaults setDouble:(double)at forKey:key];
    // 自己就是本版公告的发布者（管理员/群主刚编辑）→ 不弹窗（内容自己写的、已知），仅记版本供其他版本仍能弹。
    // 与 Web 拉齐（App.tsx 同 announcement_by === uid 守卫）。
    if (self.groupInfo.announcementBy.length > 0 && [self.groupInfo.announcementBy isEqualToString:self.userID]) { return; }
    NSString *sub = [IMGroupTextViewController announceSubtitleForMillis:at];
    [IMGroupTextViewController presentFrom:self title:@"群公告" subtitle:sub body:text];
}

/// 点公告横幅：**直接开公告全文视图**（决策 16，不再跳群资料页——旧实现跳过去详情页却没公告卡，等于点了看不到）。
- (void)bannerStackDidTapAnnouncement:(IMChatBannerStack *)stack {
    NSString *text = stack.announcementText;
    if (text.length == 0) { return; }
    NSString *sub = [IMGroupTextViewController announceSubtitleForMillis:self.groupInfo.announcementAt];
    [IMGroupTextViewController presentFrom:self title:@"群公告" subtitle:sub body:text];
}

/// G2 输入栏禁言锁：成员级禁言(myMuteUntil)或全员禁言(且我是普通成员)时禁用输入并改占位文案。
/// 服务端仍是权威（发上来照样拒 300208/300206），这里只是提前告知、不给试错。
/// 系统通知会话（peerID=system）：走同一锁机制，reason="此会话不支持回复"——
/// 见 docs/design/SYSTEM_NOTICE_SESSION_DESIGN.md §5.2；服务端也会拒收（护栏 §2.2）。
- (void)refreshComposerMuteState {
    if (!self.isGroupChat && IMIsSystemUserID(self.peerID)) {
        [self setComposerLocked:YES reason:@"此会话不支持回复"];
        return;
    }
    if (!self.isGroupChat || !self.groupInfo) {
        if (self.composerMuteLocked) { [self setComposerLocked:NO reason:nil]; }
        return;
    }
    int64_t now = IMNowMillis();
    BOOL memberMuted = self.groupInfo.myMuteUntil > now;
    BOOL allMuted = self.groupInfo.muteUntil > now && self.groupInfo.myRole == IMGroupRoleMember;
    NSString *reason = memberMuted ? @"你已被管理员禁言" : (allMuted ? @"本群已开启全员禁言" : nil);
    [self setComposerLocked:(reason != nil) reason:reason];
}

- (void)setComposerLocked:(BOOL)locked reason:(nullable NSString *)reason {
    self.composerMuteLocked = locked;
    self.inputField.enabled = !locked;
    self.inputField.placeholder = locked ? reason : @"输入消息…";
    // 2026-08-25：附件面板入口也一起锁——否则被禁言时输入栏禁了但 + 键仍能点开
    // 相册/相机/文件，一路走到 upload 才被 300208 拒，且此时 iOS 不会像文本一样给可读回执。
    // 表情键不锁（发不出去，占屏而已，但保留浏览表情的能力）。若面板开着，直接收起（键盘也收）。
    self.plusButton.enabled = !locked;
    self.plusButton.alpha = locked ? 0.4 : 1.0;
    // 语音钮同锁（2026-08-26）：Telegram 布局后 🎙 是一等发送入口（长按即录即传），不锁则被禁言成员
    // 仍能录音上传、到 send_msg 才被 300208 拒且无可读回执——入口即拦与文本/附件一致
    //（+Voice.m 长按手势 Began 亦按 voiceButton.enabled 早退，双保险：disabled 不拦手势识别）。
    self.voiceButton.enabled = !locked;
    self.voiceButton.alpha = locked ? 0.4 : 1.0;
    if (locked && self.attachPanelVisible) { [self showAttachPanel:NO]; }
    if (locked) { [self.inputField resignFirstResponder]; }
}

/// 点右侧列表键：半屏列出全部置顶消息，点行跳转；有权限者可就地取消置顶。
- (void)bannerStackDidTapPinnedList:(IMChatBannerStack *)stack {
    NSArray<IMPinnedMessage *> *items = stack.pinnedItems;
    if (items.count == 0) { return; }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"置顶消息"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) ws = self;
    BOOL canPin = [self canPinMessages];
    for (IMPinnedMessage *item in items) {
        NSString *sender = [item senderLabelForGroup:self.isGroupChat];
        NSString *title = sender.length > 0
            ? [NSString stringWithFormat:@"%@：%@", sender, item.previewText]
            : item.previewText;
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [ws jumpToPinnedConvSeq:item.convSeq];
        }]];
    }
    IMPinnedMessage *shown = stack.currentPinnedItem;
    if (canPin && shown) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"取消置顶当前这条" style:UIAlertActionStyleDestructive
                                               handler:^(UIAlertAction *action) {
            [IMSocketManager.sharedManager pinMessageInConv:(ws.convID ?: @"")
                                              targetConvSeq:shown.convSeq pinned:NO];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = stack.pinnedBannerView;
    sheet.popoverPresentationController.sourceRect = stack.pinnedBannerView.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
