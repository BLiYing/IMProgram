//  IMChatViewController+Group.m
//  聊天页「群聊 M3-5」分文件实现：拉群资料（标题成员数/气泡昵称回退/资料页数据源）、群备注（G1，仅本人可见、
//  多端同步）拉取与 conv_update 就地刷新、群变更事件（被移出/解散退页）、以及气泡发送者身份解析
//  （昵称/角色/引用显示名/头像 URL）。从 IMChatViewController.m 平移，未改行为。

#import "IMChatViewController+Private.h"
#import "IMRemarkStore.h"  // 含 IMGroupInfo / IMSocketManager（kIMConvID/Group* 键、IMGroupRole）
#import "IMHTTPService.h"
#import "IMMessageModel.h"
#import "UIViewController+IMToast.h"

@implementation IMChatViewController (Group)

#pragma mark - 群聊（M3-5）

/// 拉群资料：标题成员数 / 气泡昵称回退 / 群资料页数据源。best-effort。
- (void)reloadGroupInfo {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService groupInfoWithToken:token convID:self.convID completion:^(IMGroupInfo *group, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !group) { return; }
        self.groupInfo = group;
        self.groupName = group.name;
        [self updateTitle];
        // 群头像加载后刷新右上圆按钮。
        [self installInfoAvatarButtonWithURL:group.avatarURL seed:self.convID name:group.name action:@selector(groupInfoTapped)];
        self.bannerStack.announcementText = group.announcement.length ? group.announcement : nil; // G1 公告横幅（setter 应用）
        [self.bannerStack applyApprovalPending:[self approvalPendingCount]]; // G3：群主/管理员待审入群申请横幅
        [self maybeAutoPopAnnouncement]; // 进群/新版本自动弹一次公告卡（每版一次）
        [self refreshComposerMuteState]; // G2：被禁言则锁输入栏
        [self.tableView reloadData]; // 昵称回退可能变化（老消息无 from_nickname 时用成员表）
    }];
}

/// 群备注（G1，仅本人可见、多端同步）：进页拉一次单会话设置取 remark，标题优先显备注。
- (void)loadConvRemark {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService conversationSettingsWithToken:token convID:self.convID
                                                    completion:^(NSDictionary *data, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || error) { return; }
        NSString *rmk = [data[@"remark"] isKindOfClass:[NSString class]] ? data[@"remark"] : nil;
        self.convRemark = rmk.length > 0 ? rmk : nil;
        [self updateTitle];
    }];
}

/// conv_update（本人其它端 / 本机详情页改备注）→ 就地刷新标题；remark 全值随帧带来，免再拉。
- (void)onConvUpdatedForRemark:(NSNotification *)note {
    if (![note.userInfo[kIMConvIDKey] isEqualToString:self.convID]) { return; }
    NSString *rmk = note.userInfo[kIMConvRemarkKey];
    self.convRemark = rmk.length > 0 ? rmk : nil; // 键缺失（非 settings 帧）视作无备注
    [self updateTitle];
}

/// 群变更事件：本群则刷新资料；自己被移出 → 提示并退出本页。
- (void)onGroupEvent:(NSNotification *)note {
    NSString *convID = note.userInfo[kIMConvIDKey];
    if (![convID isEqualToString:self.convID]) { return; }
    NSString *event = note.userInfo[kIMGroupEventKey];
    NSString *target = note.userInfo[kIMGroupTargetKey];
    // 被移出（remove 且 target=自己）或群被解散（dissolve，管理端处置，对全体生效）→ 提示并退出本页。
    BOOL removedMe = [event isEqualToString:@"remove"] && [target isEqualToString:self.userID];
    BOOL dissolved = [event isEqualToString:@"dissolve"];
    if (removedMe || dissolved) {
        [self im_showToast:dissolved ? @"该群已被解散" : @"你已被移出群聊"];
        // 先让吐司可见，再退出本页（随页面销毁，故略作停留）。
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf.navigationController popViewControllerAnimated:YES];
        });
        return;
    }
    [self reloadGroupInfo];
}

/// 群聊气泡发送者昵称：优先消息自带 from_nickname，其次群成员表，最后 uid。
/// 群内**公开名**：群昵称 / 全局昵称 / uid。会被写进要发出去的内容时用它（当前：合并转发条目名）。
/// 刻意不含好友备注——备注仅本人可见，进了消息内容就发给收件人了（见 docs/UI.md 隐私红线）。
- (NSString *)senderPublicNameForMessage:(IMMessageModel *)m {
    if (m.fromNickname.length > 0) { return m.fromNickname; }
    NSString *nick = [self.groupInfo nicknameOfMember:m.from];
    return nick.length > 0 ? nick : (m.from ?: @"");
}

/// 群内**本机显示名**：我给他起的备注 > 公开名。气泡上方昵称、头像首字母、系统消息里的名字都走它。
/// 只影响本机渲染，不改任何要发出去的字节。
- (NSString *)senderNameForMessage:(IMMessageModel *)m {
    return [IMRemarkStore.sharedStore displayNameForUser:m.from fallback:[self senderPublicNameForMessage:m]];
}

/// 群聊发送者在本群的角色（气泡群主/管理员徽标用）：**优先本群成员表的当前角色**（晋升/降级后老消息随之
/// 变化，微信式）；成员表里查不到该成员（未加载/发送者已退群）时，回退消息自带 `from_role`（服务端仅对
/// 群主/管理员冗余下发）兜底。都拿不到则 IMGroupRoleMember（不显徽标）。
- (IMGroupRole)senderRoleForMessage:(IMMessageModel *)m {
    for (IMGroupMember *mem in self.groupInfo.members) {
        if ([mem.userID isEqualToString:m.from]) { return mem.role; } // 成员表当前角色优先
    }
    return IMGroupRoleFromString(m.fromRole); // 兜底：发送时点角色（脏值/空→member）
}

/// 引用条被引用者显示名（群聊用）：自己→"你"，否则群成员昵称→uid。协议只下发 uid，昵称本地解析。
- (NSString *)replyFromNameForUID:(NSString *)uid {
    if (uid.length == 0) { return nil; }
    if ([uid isEqualToString:self.userID]) { return @"你"; }
    NSString *nick = [self.groupInfo nicknameOfMember:uid];
    // 备注优先（本机显示）。引用条只在本机渲染，不进消息内容——发送时冻结的是 reply_to_from(uid)。
    return [IMRemarkStore.sharedStore displayNameForUser:uid fallback:(nick.length > 0 ? nick : uid)];
}

/// 群聊发送者头像绝对 URL（无则空串——头像圈回退首字母）。相对路径补 host。
- (NSString *)senderAvatarURLForMessage:(IMMessageModel *)m {
    NSString *url = [self.groupInfo avatarURLOfMember:m.from];
    return url.length > 0 ? [self fullMediaURL:url] : @"";
}

@end
