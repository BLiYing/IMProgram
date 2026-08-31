//  IMChatViewController+DataSource.m
//  聊天页「列表渲染」分文件实现：UITableViewDataSource（numberOfRows/cellForRow 全类型装配）
//  + 相册聚簇（同 group_id 宫格）+ 行高/估高/日期分隔。从 IMChatViewController.m 平移，未改行为。

#import "IMChatViewController+Private.h"
#import "IMChatSearchState.h"   // 搜索态命中词（cell 高亮）
#import "IMChatSelectionState.h" // 多选态逐格勾选集（selectedMediaSeqs）
#import "IMMediaDownloadCoordinator.h"
#import "IMMediaSendService.h"
#import "IMMessageModel.h"
#import "IMTheme.h"
#import "IMGroupInfo.h"
#import "IMDatabase.h"
#import "IMMenuAction.h"
#import "IMMediaUtil.h"
#import "IMMediaPlaceholder.h"
#import "IMPendingMediaStore.h"
#import "IMUploadProgress.h"
#import "IMDownloadProgress.h"
#import "IMBubbleCell.h"
#import "IMSystemCell.h"
#import "IMRemarkStore.h"
#import "IMImageCell.h"
#import "IMAlbumCell.h"
#import "IMLinkCardCell.h"
#import "IMChatRecordCell.h"
#import "IMContactCardCell.h"
#import "IMContactCard.h"
#import "IMRemarkStore.h"
#import "Voice/IMVoiceBubbleCell.h" // voice P0
#import "Voice/IMVoicePlayer.h"
#import "IMChatViewController+Voice.h"

@implementation IMChatViewController (DataSource)

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.windowState.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMMessageModel *m = self.windowState.messages[indexPath.row];
    // 首条未读行只算一次（firstUnreadRow 是 O(k) 扫描且各 cell 分支都要用），各分支复用。
    // 相册部分已读：首条未读可能落在被折叠的 follower 行，映射到其 leader 行，保证分割线画在可见行上。
    NSInteger firstUnread = [self firstUnreadRow];
    if (firstUnread >= 0) {
        NSUInteger vis = [self visibleRowForMessage:self.windowState.messages[firstUnread]];
        if (vis != NSNotFound) { firstUnread = (NSInteger)vis; }
    }
    BOOL rowIsFirstUnread = (indexPath.row == firstUnread);
    // 系统消息（群邀请/移除/转让/禁言等留痕）：独立居中灰字行，无气泡/头像/时间勾。
    if ([m.contentType isEqualToString:@"system"]) {
        IMSystemCell *sys = [tableView dequeueReusableCellWithIdentifier:@"system" forIndexPath:indexPath];
        __weak typeof(self) wsSys = self;
        [sys configureWithSegments:m.sysSegments
                      fallbackText:m.content
                 displayNameForUID:^NSString *(NSString *uid, NSString *fallbackName) {
            // 本机显示名：**是我自己 → 「我」** > 我给他起的备注 > 他在本群的昵称 > 服务端字面。
            // 口径收在 IMSysSegment，会话列表预览读同一个方法——同一句话两处必须一致。
            __strong typeof(wsSys) self = wsSys;
            return [IMSysSegment localNameForUID:uid selfUID:self.userID
                                   groupNickname:[self.groupInfo nicknameOfMember:uid]
                                        fallback:fallbackName];
        }
                          onTapUID:^(NSString *uid) { [wsSys openMemberProfileForUID:uid]; }];
        return sys;
    }
    // 撤回消息（M4-1）：居中系统行"你/对方撤回了一条消息"，隐藏原气泡；本人文本可"重新编辑"回填输入框。
    if (m.recalledAt > 0) {
        BOOL mineR = [m.from isEqualToString:self.userID];
        IMSystemCell *sys = [tableView dequeueReusableCellWithIdentifier:@"system" forIndexPath:indexPath];
        NSString *who = mineR ? @"你" : (self.isGroupChat ? [self senderNameForMessage:m] : @"对方");
        NSString *text = [NSString stringWithFormat:@"%@撤回了一条消息", who];
        BOOL canReedit = mineR && [m.contentType isEqualToString:@"text"] && m.content.length > 0;
        __weak typeof(self) ws = self;
        NSString *original = m.content ?: @"";
        [sys configureWithText:text reeditHandler:canReedit ? ^{
            ws.inputField.text = original;
            [ws updateSendButtonVisibility];
            [ws.inputField becomeFirstResponder];
        } : nil];
        return sys;
    }
    // 合并转发（#3）：聊天记录卡片，点击进详情页看全部。
    if ([m.contentType isEqualToString:@"chat_record"]) {
        IMChatRecordCell *rec = [tableView dequeueReusableCellWithIdentifier:@"record" forIndexPath:indexPath];
        BOOL mineR = [m.from isEqualToString:self.userID];
        BOOL grpR = self.isGroupChat && !mineR;                              // 群聊对方
        BOOL firstR = grpR && [self isFirstInSenderRun:indexPath.row];       // 连续段首条→显示名
        BOOL lastR = grpR && [self isLastInSenderRun:indexPath.row];         // 连续段末条→显示头像
        [rec configureWithMessage:m mine:mineR senderName:(firstR ? [self senderNameForMessage:m] : nil)
                       senderRole:(firstR ? [self senderRoleForMessage:m] : IMGroupRoleMember)];
        [rec applyGroupAvatarURL:(grpR ? [self senderAvatarURLForMessage:m] : nil)
                            seed:(m.from ?: @"") name:(grpR ? [self senderNameForMessage:m] : nil)
                      showAvatar:lastR gutter:grpR];
        [rec applyUnreadDivider:rowIsFirstUnread]; // 首条未读为聊天记录卡片时也显分割线
        __weak typeof(self) ws = self;
        rec.onTap = ^{ [ws openChatRecord:m]; };
        // 被拒收系统行的恢复入口（非好友 200103 → 发好友申请；合并转发发给非好友会命中）。
        __weak typeof(self) wsNote = self;
        rec.onNoteActionTap = ^{ [wsNote sendFriendRequestFromRejectedNote]; };
        // 群聊对方头像点击 → 该成员资料页（单聊/自己不挂）。
        if (grpR) {
            NSString *memberUID = m.from;
            __weak typeof(self) wsAvatar = self;
            rec.onAvatarTap = ^{ [wsAvatar openMemberProfileForUID:memberUID]; };
        }
        __weak typeof(self) wsRetry_rec = self;
        rec.onRetryTap = ^{ [wsRetry_rec im_resendMessage:m]; }; // 发送失败红❗ → 重发
        return rec;
    }
    // 个人名片（contact）：240pt 定宽卡片气泡，点击进名片里那个人的资料页。
    if ([m.contentType isEqualToString:IMContentTypeContact]) {
        IMContactCardCell *cc = [tableView dequeueReusableCellWithIdentifier:@"contact" forIndexPath:indexPath];
        BOOL mineC = [m.from isEqualToString:self.userID];
        BOOL grpC = self.isGroupChat && !mineC;
        BOOL firstC = grpC && [self isFirstInSenderRun:indexPath.row];
        BOOL lastC = grpC && [self isLastInSenderRun:indexPath.row];
        // 卡片主标题走**收方本地**显示名（备注 > 快照昵称）：VC 解析、cell 只渲染，与其它 cell 分工一致。
        IMContactCard *card = IMContactCardParse(m.content);
        NSString *shown = card ? [IMRemarkStore.sharedStore displayNameForUser:card.userID fallback:card.nickname] : nil;
        [cc configureWithMessage:m mine:mineC displayName:shown peerReadSeq:self.peerReadSeq
                      senderName:(firstC ? [self senderNameForMessage:m] : nil)
                      senderRole:(firstC ? [self senderRoleForMessage:m] : IMGroupRoleMember)];
        [cc applyGroupAvatarURL:(grpC ? [self senderAvatarURLForMessage:m] : nil)
                           seed:(m.from ?: @"") name:(grpC ? [self senderNameForMessage:m] : nil)
                     showAvatar:lastC gutter:grpC];
        [cc applyUnreadDivider:rowIsFirstUnread];
        if (card) {
            __weak typeof(self) wsCard = self;
            NSString *cardUID = card.userID;
            NSString *cardNick = card.nickname;
            NSString *cardAvatar = card.avatarURL;
            cc.onTap = ^{ [wsCard openContactProfileForUID:cardUID nickname:cardNick avatarURL:cardAvatar]; };
        }
        if (grpC) {
            NSString *memberUID = m.from;
            __weak typeof(self) wsAvatar = self;
            cc.onAvatarTap = ^{ [wsAvatar openMemberProfileForUID:memberUID]; };
        }
        __weak typeof(self) wsRetry_cc = self;
        cc.onRetryTap = ^{ [wsRetry_cc im_resendMessage:m]; }; // 发送失败红❗ → 重发
        return cc;
    }
    // 纯 URL 文本消息：URL 文本 + 链接富预览卡片（OG），点击应用内打开（带引用时也显示引用行+卡片）。
    if ([m.contentType isEqualToString:@"text"] && m.recalledAt == 0 && m.translation.length == 0 && IMMediaLooksLikeURL(m.content)) {
        IMLinkCardCell *link = [tableView dequeueReusableCellWithIdentifier:@"link" forIndexPath:indexPath];
        BOOL mineL = [m.from isEqualToString:self.userID];
        BOOL grpL = self.isGroupChat && !mineL;
        BOOL firstL = grpL && [self isFirstInSenderRun:indexPath.row];
        BOOL lastL = grpL && [self isLastInSenderRun:indexPath.row];
        [link configureWithMessage:m mine:mineL senderName:(firstL ? [self senderNameForMessage:m] : nil)
                        senderRole:(firstL ? [self senderRoleForMessage:m] : IMGroupRoleMember)];
        [link applyGroupAvatarURL:(grpL ? [self senderAvatarURLForMessage:m] : nil)
                             seed:(m.from ?: @"") name:(grpL ? [self senderNameForMessage:m] : nil)
                       showAvatar:lastL gutter:grpL];
        [link applyUnreadDivider:rowIsFirstUnread]; // 首条未读为链接卡片时也显分割线
        // 群聊对方头像点击 → 该成员资料页（单聊/自己不挂；与文本气泡/图片/相册统一）。
        if (grpL) {
            NSString *memberUID = m.from;
            __weak typeof(self) wsAvatar = self;
            link.onAvatarTap = ^{ [wsAvatar openMemberProfileForUID:memberUID]; };
        }
        __weak typeof(self) ws = self;
        link.onTap = ^(NSString *url) { [ws openLink:url]; };
        // OG 预览异步展开 → 刷行高（滚动中延迟到停止；与 IMImageCell.onMediaSizeResolved 同守卫）。
        link.onContentSizeResolved = ^{
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (self.tableView.isDragging || self.tableView.isDecelerating) {
                self.needsRowHeightSettle = YES;
                return;
            }
            BOOL wasNearBottom = [self isNearBottom];
            [self refreshRowHeightsWithoutAnimation];
            if (wasNearBottom) { [self scrollToAbsoluteBottom]; }
        };
        __weak typeof(self) wsRetry_link = self;
        link.onRetryTap = ^{ [wsRetry_link im_resendMessage:m]; }; // 发送失败红❗ → 重发
        return link;
    }
    // 相册宫格（M4+）：同 group_id 的多图/视频合并为一个 cell（leader 行渲染宫格，从行零高）。
    if ([self isAlbumMember:m]) {
        if ([self isAlbumFollowerAtRow:indexPath.row]) {
            UITableViewCell *pad = [tableView dequeueReusableCellWithIdentifier:@"albumPad" forIndexPath:indexPath];
            pad.hidden = YES;
            pad.selectionStyle = UITableViewCellSelectionStyleNone;
            return pad;
        }
        IMAlbumCell *alb = [tableView dequeueReusableCellWithIdentifier:@"album" forIndexPath:indexPath];
        NSArray<IMMessageModel *> *members = [self albumMembersForGroupID:m.groupID];
        BOOL mineAlb = [m.from isEqualToString:self.userID];
        BOOL grpAlb = self.isGroupChat && !mineAlb;                                  // 群聊对方
        BOOL firstAlb = grpAlb && [self isFirstInSenderRun:indexPath.row];           // 连续段首条→显示名
        BOOL lastAlb = grpAlb && [self isLastInSenderRun:indexPath.row];             // 连续段末条→显示头像
        NSString *senderNameAlb = firstAlb ? [self senderNameForMessage:m] : nil;
        IMGroupRole senderRoleAlb = firstAlb ? [self senderRoleForMessage:m] : IMGroupRoleMember;
        // 逐格下载门控（M4-7）：必须在 configure **前**挂好——bind 每一格时会回调查询该格的门控态。
        __weak typeof(self) wsAlbDl = self;
        alb.downloadStateForItem = ^IMDownloadProgress *(IMMessageModel *mm) {
            __strong typeof(wsAlbDl) self = wsAlbDl;
            return self ? [self.downloads stateForMessage:mm] : nil;
        };
        alb.onDownloadItem = ^(IMMessageModel *mm) {
            __strong typeof(wsAlbDl) self = wsAlbDl;
            if (self) { [self.downloads handleTapForMessage:mm]; }
        };
        // 多选态逐格勾选（2a）：查询/切换单格选中；整组全选态由 didSelect/didDeselect 与 toggle 同步到左侧系统圈。
        __weak typeof(self) wsAlbSel = self;
        alb.isMemberSelected = ^BOOL(IMMessageModel *mm) {
            __strong typeof(wsAlbSel) self = wsAlbSel;
            return self && mm.convSeq > 0 && [self.selectionState.selectedMediaSeqs containsObject:@(mm.convSeq)];
        };
        alb.onToggleMember = ^(IMMessageModel *mm) {
            __strong typeof(wsAlbSel) self = wsAlbSel;
            if (self) { [self toggleAlbumMemberSelection:mm]; }
        };
        [alb configureWithMembers:members mine:mineAlb host:self.host
                         previews:self.outboxPreviews progress:self.outboxProgress senderName:senderNameAlb
                       senderRole:senderRoleAlb];
        [alb applyGroupAvatarURL:(grpAlb ? [self senderAvatarURLForMessage:m] : nil)
                            seed:(m.from ?: @"") name:(grpAlb ? [self senderNameForMessage:m] : nil)
                      showAvatar:lastAlb gutter:grpAlb];
        [alb applyUnreadDivider:rowIsFirstUnread]; // 首条未读为相册宫格时也显分割线
        // 群聊对方头像点击 → 该成员资料页（单聊/自己不挂；与文本气泡/图片/链接统一）。
        if (grpAlb) {
            NSString *memberUID = m.from;
            __weak typeof(self) wsAvatar = self;
            alb.onAvatarTap = ^{ [wsAvatar openMemberProfileForUID:memberUID]; };
        }
        __weak typeof(self) wsAlbNote = self;
        alb.onNoteActionTap = ^{ [wsAlbNote sendFriendRequestFromRejectedNote]; };
        __weak typeof(self) ws = self;
        alb.onTapItem = ^(IMMessageModel *mm) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            // 待发格（排队/压缩/上传/失败）：走与单张气泡同一状态机——⏸↔↑ 暂停恢复、↻ 重试、✕ 确认取消。
            BOOL pendingTile = [IMPendingMediaStore isLocalRef:mm.content]
                || (mm.convSeq <= 0 && mm.content.length == 0
                    && (mm.status == IMMessageStatusSending || mm.status == IMMessageStatusFailed));
            if (pendingTile) { [self handlePendingMediaTap:mm]; return; }
            if (mm.content.length > 0) { [self presentMediaViewerForMessage:mm preloaded:nil]; }
        };
        alb.menuForItem = ^UIMenu *(IMMessageModel *mm) {
            __strong typeof(ws) self = ws;
            if (!self) { return nil; }
            // 待发格也给长按菜单（含「取消发送」——可单独取消宫格里的某一项）。
            return [IMMenuAction menuWithActions:[self messageActionsForMessage:mm
                                                                           mine:[mm.from isEqualToString:self.userID]]];
        };
        __weak typeof(self) wsRetry_alb = self;
        alb.onRetryTap = ^{ [wsRetry_alb im_resendMessage:m]; }; // 发送失败红❗ → 重发
        return alb;
    }
    // 语音消息（voice P0）：波形气泡 + 播放键 + 未播红点；长按走通用菜单（禁复制/编辑）。
    if ([m.contentType isEqualToString:@"voice"]) {
        IMVoiceBubbleCell *vc = [tableView dequeueReusableCellWithIdentifier:@"voice" forIndexPath:indexPath];
        BOOL mineV = [m.from isEqualToString:self.userID];
        BOOL grpV = self.isGroupChat && !mineV;
        BOOL firstV = grpV && [self isFirstInSenderRun:indexPath.row];
        BOOL lastV = grpV && [self isLastInSenderRun:indexPath.row];
        NSString *midV = IMVoicePlayerPlayableIDForMessage(m);
        BOOL played = mineV || [[IMVoicePlayer sharedPlayer] hasPlayed:midV inConv:m.convID owner:self.userID];
        [vc configureWithMessage:m mine:mineV
                       dayHeader:[self dayHeaderForRow:indexPath.row]
              showsUnreadDivider:rowIsFirstUnread
                      senderName:(firstV ? [self senderNameForMessage:m] : nil)
                      senderRole:(firstV ? [self senderRoleForMessage:m] : IMGroupRoleMember)
                       hasPlayed:played
                     peerReadSeq:self.peerReadSeq
                  isGroupContext:self.isGroupChat];
        [vc applyGroupAvatarURL:(grpV ? [self senderAvatarURLForMessage:m] : nil)
                           seed:(m.from ?: @"")
                           name:(grpV ? [self senderNameForMessage:m] : nil)
                     showAvatar:lastV gutter:grpV];
        NSString *fullURL = [self fullMediaURL:m.content];
        __weak typeof(self) ws = self;
        __weak IMMessageModel *wm = m;
        vc.onPlayTap = ^{
            __strong typeof(ws) self = ws; IMMessageModel *sm = wm;
            if (!self || !sm) { return; }
            [self im_playVoiceMessage:sm fullURL:fullURL];
        };
        vc.onRetryTap = ^{ // 发送失败红❗：统一入口按 IMResendPolicy 分派（语音上传失败→重传；send_msg 失败→原 cid 重发）
            __strong typeof(ws) self = ws; IMMessageModel *sm = wm;
            if (!self || !sm) { return; }
            [self im_resendMessage:sm];
        };
        if (grpV) {
            NSString *memberUID = m.from;
            __weak typeof(self) wsAvatar = self;
            vc.onAvatarTap = ^{ [wsAvatar openMemberProfileForUID:memberUID]; };
        }
        return vc;
    }
    // 图片/视频消息（M4-6）：独立媒体 cell。图片显缩略图、视频显首帧+播放角标（不自动播放）；点击进全屏查看器。
    // 上传中的乐观气泡：content 为空 → 显本地预览 + 居中进度（批量发送 UX）。
    if ([m.contentType isEqualToString:@"image"] || [m.contentType isEqualToString:@"video"]) {
        IMImageCell *img = [tableView dequeueReusableCellWithIdentifier:@"image" forIndexPath:indexPath];
        BOOL mineI = [m.from isEqualToString:self.userID];
        NSString *key = m.clientMsgID ?: @"";
        BOOL grpI = self.isGroupChat && !mineI;
        BOOL firstI = grpI && [self isFirstInSenderRun:indexPath.row];
        BOOL lastI = grpI && [self isLastInSenderRun:indexPath.row];
        NSString *senderNameI = firstI ? [self senderNameForMessage:m] : nil;
        IMGroupRole senderRoleI = firstI ? [self senderRoleForMessage:m] : IMGroupRoleMember;
        // 本地待发（im-pending://）不是网络地址：只显本地缩略图，绝不拿它去拼 URL 发请求。
        // 本地待发件 = content 已是 im-pending:// 引用，**或**还没走到落盘那步（排队/压缩期 content 为空）。
        // 后者漏掉的话，排队期点中心 ✕ 会被当成"打开查看器"（URL 为空 → 看起来没反应）。
        BOOL pendingLocal = [IMPendingMediaStore isLocalRef:m.content]
            || (m.convSeq <= 0 && m.content.length == 0
                && (m.status == IMMessageStatusSending || m.status == IMMessageStatusFailed));
        UIImage *previewI = pendingLocal ? [self pendingPreviewForMessage:m] : self.outboxPreviews[key];
        NSString *imgFullURL = ((m.content.length > 0 && !pendingLocal) ? [self fullMediaURL:m.content] : @"");
        // 门控（M4-7）：收到的图片/视频按策略"未下载" → 显 ↓（下载中为环形进度）+ 尺寸角标，不加载原图/不放行播放。
        // 视频封面仍照显（poster 只有几十 KB），门控挡的是**整段视频**。
        IMDownloadProgress *gate = pendingLocal ? nil : [self.downloads stateForMessage:m];
        img.gated = gate != nil;
        img.downloadProgress = gate;
        img.captionMentionMap = [self mentionMapForCaption:m]; // 图说 caption 的 @高亮（configure 前置）
        img.searchHighlightKeyword = self.searchState.searchKeyword; // 搜索态命中词高亮（非搜索态为 nil）
        [img configureWithMessage:m
                          fullURL:imgFullURL
                        posterURL:(m.poster.length > 0 ? [self fullMediaURL:m.poster] : nil)
                             mine:mineI peerReadSeq:self.peerReadSeq
                     previewImage:previewI senderName:senderNameI senderRole:senderRoleI];
        [img applyGroupAvatarURL:(grpI ? [self senderAvatarURLForMessage:m] : nil)
                            seed:(m.from ?: @"") name:(grpI ? [self senderNameForMessage:m] : nil)
                      showAvatar:lastI gutter:grpI];
        [img applyUnreadDivider:rowIsFirstUnread]; // 首条未读为图片/视频时也显分割线
        // 群聊对方头像点击 → 该成员资料页（单聊/自己不挂；与文本气泡/相册/链接统一）。
        if (grpI) {
            NSString *memberUID = m.from;
            __weak typeof(self) wsAvatar = self;
            img.onAvatarTap = ^{ [wsAvatar openMemberProfileForUID:memberUID]; };
        }
        // 失败的本地待发件：进度角标显"发送失败"（内存里的进度在重进会话后是空的，按状态补上）。
        IMUploadProgress *progI = self.outboxProgress[key];
        if (!progI && pendingLocal && m.status == IMMessageStatusFailed) { progI = [IMUploadProgress failedProgress]; }
        [img setUploadProgress:progI];
        __weak typeof(self) ws = self;
        img.onNoteActionTap = ^{ [ws sendFriendRequestFromRejectedNote]; };
        img.onDownloadTap = ^{ // 门控点 ↓：图片=解除门控重载；视频=下载状态机（M4-7）
            __strong typeof(ws) self = ws;
            if (self) { [self.downloads handleTapForMessage:m]; }
        };
        img.onTap = ^(UIImage *image) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (pendingLocal) { [self handlePendingMediaTap:m]; return; } // 中心按钮状态机：⏸/↑/↻/✕
            [self presentMediaViewerForMessage:m preloaded:image];
        };
        // 老消息无 media_w/h：异步出图后才知比例 → 刷一次行高（无动画，不打断滚动）。
        // 行高变化会把底部偏移顶走——若此刻本就贴底（典型：刚进会话），必须重新贴底，
        // 否则用户看到的是"进来没停在最新消息"。上滚读历史时不动（wasNearBottom=NO）。
        IMMessageModel *mediaMsg = m;
        img.onMediaSizeResolved = ^(CGSize pixelSize) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            // 量出的尺寸写回模型 + 落库（一次性成本）：此后 estimatedHeight 首帧即正确，
            // 同一条消息不会每次滚过/重进会话都触发一遍行高跳变（上滑弹跳的主根因）。
            if (mediaMsg.mediaW <= 0 && pixelSize.width > 0 && pixelSize.height > 0) {
                mediaMsg.mediaW = (NSInteger)round(pixelSize.width);
                mediaMsg.mediaH = (NSInteger)round(pixelSize.height);
                if (mediaMsg.convSeq > 0) {
                    [self performDatabaseOperation:^(IMDatabase *database) { [database saveMessage:mediaMsg]; }];
                }
            }
            // 拖拽/惯性滚动中不做 begin/endUpdates（行高瞬变 + offset 修正 = 肉眼可见的卡顿弹跳），
            // 记脏、滚动停止后统一补一次。
            if (self.tableView.isDragging || self.tableView.isDecelerating) {
                self.needsRowHeightSettle = YES;
                return;
            }
            BOOL wasNearBottom = [self isNearBottom];
            [self refreshRowHeightsWithoutAnimation];
            if (wasNearBottom) { [self scrollToAbsoluteBottom]; }
        };
        __weak typeof(self) wsRetry_img = self;
        img.onRetryTap = ^{ [wsRetry_img im_resendMessage:m]; }; // 发送失败红❗ → 重发
        return img;
    }
    IMBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"bubble" forIndexPath:indexPath];
    BOOL mine = [m.from isEqualToString:self.userID];
    BOOL showsDivider = rowIsFirstUnread;
    // 群聊：对方气泡带发送者昵称（自己/单聊不带）；连续同发送者只首条显名、末条显头像（Telegram 式）。
    BOOL grp = self.isGroupChat && !mine;
    BOOL firstInRun = grp && [self isFirstInSenderRun:indexPath.row];
    BOOL lastInRun = grp && [self isLastInSenderRun:indexPath.row];
    NSString *senderName = firstInRun ? [self senderNameForMessage:m] : nil;
    // 引用的是图片/视频：把原消息的媒体 URL 传给 cell，引用条内显示真缩略图（#4）。
    // 引用的是图片/视频：把完整媒体地址 + 内嵌 thumb 交给 cell，由 IMMediaPlaceholder 统一决定
    // 真帧(仅已下载)/thumb 磨砂/占位图标（门控一致 M4-7）。绝不为一张 24px 引用小图联网拉原件/抽远端帧。
    NSString *replyThumbURL = nil;   // 完整媒体地址（有媒体引用目标即置）
    NSString *replyThumbData = nil;  // 内嵌 thumb dataURI
    BOOL replyThumbIsVideo = NO;
    if (m.replyToConvSeq > 0) {
        IMMessageModel *target = [self messageWithConvSeq:m.replyToConvSeq];
        // 图说消息（带 caption）：引用**只显文本**（快照即 caption），不挂媒体缩略图——与 Web 一致，简化少出错。
        if (target && target.caption.length == 0
            && ([target.contentType isEqualToString:@"image"] || [target.contentType isEqualToString:@"video"])
            && target.recalledAt == 0 && target.content.length > 0) {
            replyThumbIsVideo = [target.contentType isEqualToString:@"video"];
            replyThumbURL = [self fullMediaURL:target.content];
            replyThumbData = target.thumb;
        }
    }
    // 文件上传中/失败：左侧图标位显圆环状态机、第二行显进度（必须在 configure 之前设，整条一次性布好）。
    NSString *bubbleKey = m.clientMsgID ?: @"";
    IMUploadProgress *fileProgress = self.outboxProgress[bubbleKey];
    if (!fileProgress && [m.contentType isEqualToString:@"file"] && m.status == IMMessageStatusFailed
        && [IMPendingMediaStore isLocalRef:m.content]) {
        fileProgress = [IMUploadProgress failedProgress]; // 重进会话：内存进度已空，按落库状态补
    }
    cell.uploadProgress = fileProgress;
    // 文件下载态（M4-7 / 1d）：自己发的与收到的同款——本机有原件即无门控（点开 QuickLook），
    // 清缓存后回落 ↓/下载。上传态优先、二者互斥（有上传态时不叠加下载态）。
    cell.downloadProgress = (!fileProgress && [m.contentType isEqualToString:@"file"])
        ? [self.downloads stateForMessage:m] : nil;
    // 图标位点击：上传态=发送状态机（⏸/↑/↻/✕）；下载态=下载状态机（↓/⏸/↻）；就绪/完成态不挂（点整条气泡打开）。
    if (fileProgress && [m.contentType isEqualToString:@"file"]) {
        __weak typeof(self) wsFile = self;
        cell.onFileControlTap = ^{
            __strong typeof(wsFile) self = wsFile;
            if (self) { [self handlePendingMediaTap:m]; }
        };
    } else if (cell.downloadProgress && [m.contentType isEqualToString:@"file"]) {
        __weak typeof(self) wsDl = self;
        cell.onFileControlTap = ^{
            __strong typeof(wsDl) self = wsDl;
            if (self) { [self.downloads handleTapForMessage:m]; }
        };
    } else {
        cell.onFileControlTap = nil;
    }
    // 群聊对方头像点击 → 该成员资料页（单聊/自己不挂）。
    if (self.isGroupChat && ![m.from isEqualToString:self.userID]) {
        NSString *memberUID = m.from;
        __weak typeof(self) wsAvatar = self;
        cell.onAvatarTap = ^{ [wsAvatar openMemberProfileForUID:memberUID]; };
    } else {
        cell.onAvatarTap = nil;
    }
    // 拒收系统行的恢复入口（非好友 200103 → 发好友申请）。cell 内部据 noteCode 判定是否可点。
    __weak typeof(self) wsNote = self;
    cell.onNoteActionTap = ^{ [wsNote sendFriendRequestFromRejectedNote]; };
    // 文本气泡里首个 URL 的 og 预览卡片：卡片被点→打开链接；卡片异步展开→按 IMLinkCardCell 同款守卫刷行高。
    __weak typeof(self) wsLink = self;
    cell.onLinkTap = ^(NSString *url) { [wsLink openLink:url]; };
    cell.onLinkPreviewResolved = ^{
        __strong typeof(wsLink) self = wsLink;
        if (!self) { return; }
        if (self.tableView.isDragging || self.tableView.isDecelerating) {
            self.needsRowHeightSettle = YES;
            return;
        }
        BOOL wasNearBottom = [self isNearBottom];
        [self refreshRowHeightsWithoutAnimation];
        if (wasNearBottom) { [self scrollToAbsoluteBottom]; }
    };
    NSString *replyFromName = (self.isGroupChat && m.replyToConvSeq > 0 && m.replyToFrom.length > 0)
        ? [self replyFromNameForUID:m.replyToFrom] : nil;
    cell.textExpanded = [self isTextExpandedForMessage:m]; // 中长文本"展开全文"记忆（configure 前置）
    cell.mentionMap = [self mentionMapForMessage:m];       // 气泡内 @昵称 高亮+跳资料映射（configure 前置）
    cell.captionMentionMap = [self mentionMapForCaption:m]; // 文件文 caption 的 @高亮（configure 前置）
    cell.searchHighlightKeyword = self.searchState.searchKeyword; // 搜索态命中词高亮（非搜索态为 nil）
    [cell configureWithMessage:m mine:mine peerReadSeq:self.peerReadSeq
                     dayHeader:[self dayHeaderForRow:indexPath.row]
            showsUnreadDivider:showsDivider
                    senderName:senderName
                    senderRole:(firstInRun ? [self senderRoleForMessage:m] : IMGroupRoleMember)
                 replyThumbURL:replyThumbURL
                replyThumbData:replyThumbData
             replyThumbIsVideo:replyThumbIsVideo
                 replyFromName:replyFromName];
    [cell applyGroupAvatarURL:(grp ? [self senderAvatarURLForMessage:m] : nil)
                         seed:(m.from ?: @"") name:(grp ? [self senderNameForMessage:m] : nil)
                   showAvatar:lastInRun gutter:grp];
    __weak typeof(self) wsRetryBubble = self;
    cell.onRetryTap = ^{ [wsRetryBubble im_resendMessage:m]; }; // 发送失败红❗ → 重发
    return cell;
}

#pragma mark - 相册聚簇（M4+：同 group_id 的多图/视频渲染为一个宫格）

/// 相册成员判定：有 group_id 的图片/视频且未撤回。**多选态同样聚簇**（整组作为一个勾选单位，不再拆成
/// 独立行——勾选宫格 leader 行即选中整组，见 Selection 的 selectedMessages 展开）。
- (BOOL)isAlbumMember:(IMMessageModel *)m {
    return m.groupID.length > 0 && m.recalledAt == 0
        && ([m.contentType isEqualToString:@"image"] || [m.contentType isEqualToString:@"video"]);
}

/// 该行是否相册"从行"：同组首个成员为主行（渲染整个宫格），其余成员行零高隐藏。
/// 同批消息相邻发送，向前找通常 1~2 步即命中。
- (BOOL)isAlbumFollowerAtRow:(NSInteger)row {
    IMMessageModel *m = self.windowState.messages[(NSUInteger)row];
    if (![self isAlbumMember:m]) { return NO; }
    for (NSInteger i = row - 1; i >= 0; i--) {
        IMMessageModel *p = self.windowState.messages[(NSUInteger)i];
        if (p.groupID.length > 0 && [p.groupID isEqualToString:m.groupID] && [self isAlbumMember:p]) { return YES; }
    }
    return NO;
}

/// 同组全部成员（按消息顺序）。
- (NSArray<IMMessageModel *> *)albumMembersForGroupID:(NSString *)gid {
    NSMutableArray<IMMessageModel *> *out = [NSMutableArray array];
    for (IMMessageModel *m in self.windowState.messages) {
        if (m.groupID.length > 0 && [m.groupID isEqualToString:gid] && [self isAlbumMember:m]) { [out addObject:m]; }
    }
    return out;
}

/// 消息所属的"可见行"：相册成员 → 该组 leader 行；普通消息 → 自身行。NSNotFound=不在列表。
- (NSUInteger)visibleRowForMessage:(IMMessageModel *)m {
    NSUInteger own = [self.windowState.messages indexOfObjectIdenticalTo:m];
    if (own == NSNotFound || ![self isAlbumMember:m]) { return own; }
    for (NSUInteger i = 0; i <= own; i++) {
        IMMessageModel *p = self.windowState.messages[i];
        if (p.groupID.length > 0 && [p.groupID isEqualToString:m.groupID] && [self isAlbumMember:p]) { return i; }
    }
    return own;
}

/// 从行零高（宫格已在 leader 行整体渲染）；其余行自适应。
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row < (NSInteger)self.windowState.messages.count && [self isAlbumFollowerAtRow:indexPath.row]) { return 0; }
    return UITableViewAutomaticDimension;
}

/// 按消息类型精确估高：估算与真实行高差得越远，上滑实体化行时系统的 offset 修正越猛
///（=「滚到某处突然卡一下/弹跳」的另一半根因；主因是媒体尺寸此前不落库，见 onMediaSizeResolved）。
- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= (NSInteger)self.windowState.messages.count) { return 56; }
    IMMessageModel *m = self.windowState.messages[(NSUInteger)indexPath.row];
    if ([self isAlbumFollowerAtRow:indexPath.row]) { return 0; }
    if ([self isAlbumMember:m]) { return 240; } // 宫格 leader：整格粗估
    if ([m.contentType isEqualToString:@"image"] || [m.contentType isEqualToString:@"video"]) {
        // 已知 media_w/h → 与 cell 同一套缩放规则精确估；未知 → 方形占位边长（cell 首帧同款）。
        // 图说 caption 粗估加一行（self-sizing 会自撑到实际多行高，估准只为减少上滑 offset 修正）。
        return [IMImageCell displayHeightForPixelWidth:m.mediaW pixelHeight:m.mediaH] + 8 + (m.caption.length > 0 ? 26 : 0);
    }
    if ([m.contentType isEqualToString:@"file"]) { return m.caption.length > 0 ? 110 : 84; }
    // 语音：气泡固定 75pt + 上下间距 ≈ 81；群聊对方连续段首条多一行昵称。
    // 2026-08-27 修：此前落到兜底 56，与真实高度差 25pt+，语音密集会话上滑时系统反复修正
    // contentOffset —— 是"滑动不流畅"的另一半（另一半是 configure 里的 beginUpdates/endUpdates）。
    if ([m.contentType isEqualToString:@"voice"]) {
        BOOL grpNameVoice = self.isGroupChat && ![m.from isEqualToString:self.userID]
            && [self isFirstInSenderRun:indexPath.row];
        return grpNameVoice ? 103 : 81;
    }
    // 名片卡：卡片本体 ≈93pt（10+44+8+0.5+6+~14+10）+ 上下间距 6 ≈ 99；群聊段首多一行昵称 ~22。
    if ([m.contentType isEqualToString:IMContentTypeContact]) {
        BOOL grpNameCard = self.isGroupChat && ![m.from isEqualToString:self.userID]
            && [self isFirstInSenderRun:indexPath.row];
        return grpNameCard ? 121 : 99;
    }
    if ([m.contentType isEqualToString:@"chat_record"]) {
        // 群聊对方连续段首条多一行发送者昵称（~22pt），估高相应加高，减少上滑实体化时的 offset 修正。
        BOOL grpNameRec = self.isGroupChat && ![m.from isEqualToString:self.userID]
            && [self isFirstInSenderRun:indexPath.row];
        return grpNameRec ? 142 : 120;
    }
    return 56;
}

/// 按 conv_seq 找已加载的消息（引用缩略图解析用；不在窗口内返回 nil）。
- (IMMessageModel *)messageWithConvSeq:(int64_t)convSeq {
    for (IMMessageModel *x in self.windowState.messages) {
        if (x.convSeq == convSeq) { return x; }
    }
    return nil;
}

/// 按时间分组：每自然日首条消息上方显示日期分隔胶囊（今天/昨天/M月d日）。无效时间或同日返回 nil。
- (NSString *)dayHeaderForRow:(NSInteger)row {
    IMMessageModel *m = self.windowState.messages[row];
    if (m.timestamp <= 0) { return nil; } // 发送中（未拿到服务端时间）不显示日期
    if (row == 0) { return [IMTheme dayHeaderStringFromMillis:m.timestamp]; }
    IMMessageModel *prev = self.windowState.messages[row - 1];
    if ([IMTheme isMillis:m.timestamp sameDayAsMillis:prev.timestamp]) { return nil; }
    return [IMTheme dayHeaderStringFromMillis:m.timestamp];
}

#pragma mark - Telegram 式连续消息分组（同发送者连续段：名字只显首条、头像贴末条）

/// 上一「可见行」（跳过相册零高从行）；无则 -1。
- (NSInteger)prevVisibleRow:(NSInteger)row {
    for (NSInteger j = row - 1; j >= 0; j--) {
        if ([self isAlbumFollowerAtRow:j]) { continue; }
        return j;
    }
    return -1;
}

/// 下一「可见行」（跳过相册零高从行）；无则 messages.count。
- (NSInteger)nextVisibleRow:(NSInteger)row {
    for (NSInteger j = row + 1; j < (NSInteger)self.windowState.messages.count; j++) {
        if ([self isAlbumFollowerAtRow:j]) { continue; }
        return j;
    }
    return (NSInteger)self.windowState.messages.count;
}

/// 两条消息是否属于同一「连续段」：同发送者、都是普通气泡（非系统/撤回）、同一天。
- (BOOL)message:(IMMessageModel *)a sameSenderRunAs:(IMMessageModel *)b {
    if (![a.from isEqualToString:b.from]) { return NO; }
    if ([a.contentType isEqualToString:@"system"] || [b.contentType isEqualToString:@"system"]) { return NO; }
    if (a.recalledAt != 0 || b.recalledAt != 0) { return NO; }
    if (a.timestamp > 0 && b.timestamp > 0 && ![IMTheme isMillis:a.timestamp sameDayAsMillis:b.timestamp]) { return NO; }
    return YES;
}

/// 该行是否为连续段首条（对方群消息用；决定是否显示发送者名）。
- (BOOL)isFirstInSenderRun:(NSInteger)row {
    NSInteger p = [self prevVisibleRow:row];
    if (p < 0) { return YES; }
    return ![self message:self.windowState.messages[(NSUInteger)p] sameSenderRunAs:self.windowState.messages[(NSUInteger)row]];
}

/// 该行是否为连续段末条（对方群消息用；决定是否显示头像）。
- (BOOL)isLastInSenderRun:(NSInteger)row {
    NSInteger n = [self nextVisibleRow:row];
    if (n >= (NSInteger)self.windowState.messages.count) { return YES; }
    return ![self message:self.windowState.messages[(NSUInteger)n] sameSenderRunAs:self.windowState.messages[(NSUInteger)row]];
}

@end
