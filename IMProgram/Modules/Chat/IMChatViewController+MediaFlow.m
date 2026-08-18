//  IMChatViewController+MediaFlow.m
//  聊天页「转发 / 长文本阅读器 / 下载编排」分文件实现（M4-3 / Q1 / M4-7）：
//  单条转发失效守卫与选择器、超长文本展开与全屏阅读器、收到媒体的下载门控/进度/落地编排。
//  从 IMChatViewController.m 平移，未改行为。

#import "IMChatViewController+Private.h"
#import "IMChatMessageLogic.h"   // IMChatTextContainsMentionToken
#import <SafariServices/SafariServices.h>
#import "IMMessageModel.h"
#import "IMTheme.h"
#import "IMDatabase.h"
#import "IMHTTPService.h"
#import "IMMediaUtil.h"
#import "IMProtocol.h"
#import "IMMediaExpiryRegistry.h"
#import "IMMediaDownloadCoordinator.h"
#import "IMDownloadProgress.h"
#import "IMForwardPickerViewController.h"
#import "IMConversation.h"
#import "IMConversationMediaViewController.h"
#import "IMTextReaderViewController.h"
#import "IMQRResultRouter.h"
#import "IMGroupInfo.h"
#import "IMBubbleCell.h"
#import "IMImageCell.h"
#import "IMAlbumCell.h"
#import "UIViewController+IMToast.h"

@implementation IMChatViewController (MediaFlow)

#pragma mark - 转发（M4-3）

/// 该消息是否为"曾可用、被服务端清理"的媒体（image/video/file）。转发透传的是 content URL 本身、不重传字节，
/// 故本机有无缓存都救不了对端——命中即拦，与保存(看铁律A)语义不同。key 必须用查看器/气泡同款 fullMediaURL: 解析。
- (BOOL)isMediaExpiredForForward:(IMMessageModel *)m {
    NSString *ct = m.contentType ?: @"";
    if (!([ct isEqualToString:@"image"] || [ct isEqualToString:@"video"] || [ct isEqualToString:@"file"])) { return NO; }
    if (m.content.length == 0) { return NO; }
    return [IMMediaExpiryRegistry.shared isExpiredURL:[self fullMediaURL:m.content]];
}

/// 失效媒体的类型名词（toast 用）：视频/文件/图片。
- (NSString *)expiredNounForMessage:(IMMessageModel *)m {
    if ([m.contentType isEqualToString:@"video"]) { return @"视频"; }
    if ([m.contentType isEqualToString:@"file"]) { return @"文件"; }
    return @"图片";
}

/// 转发一条消息（#6）：整页会话选择器（单/多选，最多 9）→ 逐条转发，保留 content_type（图片/视频不退化成文本）。
- (void)forwardMessage:(IMMessageModel *)message {
    // 从谁可见就从谁弹（查看器「更多」先关查看器再执行，栈顶可能是全屏媒体库而非本页）。
    [self presentForwardPickerForMessage:message
                      fromViewController:([UIViewController im_topVisibleViewController] ?: self)];
}

/// 转发选择页由 `presenter` 弹出（详情页文件列表复用时传自己），回声逻辑与 toast 都收敛在这里。
- (void)presentForwardPickerForMessage:(IMMessageModel *)message fromViewController:(UIViewController *)presenter {
    if (message.content.length == 0 || message.recalledAt > 0) { return; }
    // 失效守卫：曾可用媒体被服务端清理(404) → 转出去对端必 404，不给转发入口。一处拦住卡片菜单/长按菜单/详情页文件列表复用三入口。
    if ([self isMediaExpiredForForward:message]) {
        [(presenter ?: self) im_showToast:[NSString stringWithFormat:@"该%@已失效，无法转发", [self expiredNounForMessage:message]]];
        return;
    }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    NSString *origin = message.forwardFrom.length > 0 ? message.forwardFrom
        : (message.fromNickname.length > 0 ? message.fromNickname : (message.from ?: @"")); // 转发链保留最初作者
    NSString *content = message.content;
    NSString *contentType = message.contentType ?: @"text";
    NSString *fileName = message.fileName;
    int64_t fileSize = message.fileSize;
    IMMediaAttributes *attrs = [self forwardAttributesForMessage:message];
    __weak typeof(self) ws = self;
    __weak UIViewController *wp = presenter;
    IMForwardPickerViewController *picker = [[IMForwardPickerViewController alloc]
        initWithHost:self.host token:token onDone:^(NSArray<IMConversation *> *selected) {
        __strong typeof(ws) self = ws;
        if (!self || selected.count == 0) { return; }
        for (IMConversation *c in selected) {
            NSString *toUser = c.isGroup ? @"" : (c.peer ?: @"");
            [self forwardEchoContent:content contentType:contentType forwardFrom:origin fileName:fileName fileSize:fileSize
                          attributes:attrs toConv:c.convID toUser:toUser];
        }
        [(wp ?: self) im_showToast:selected.count == 1 ? @"已转发" : [NSString stringWithFormat:@"已转发到 %lu 个会话", (unsigned long)selected.count]];
    }];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    [(presenter ?: self) presentViewController:nav animated:YES completion:nil];
}

#pragma mark - 长文本展开/阅读器（Q1）

/// 消息在"展开记忆"里的 key：已落库用 convSeq，发送中退回 clientMsgID。
- (NSString *)textKeyForMessage:(IMMessageModel *)m {
    if (m.convSeq > 0) { return [NSString stringWithFormat:@"seq-%lld", (long long)m.convSeq]; }
    return m.clientMsgID.length > 0 ? m.clientMsgID : @"";
}

- (BOOL)isTextExpandedForMessage:(IMMessageModel *)m {
    return [self.expandedTextKeys containsObject:[self textKeyForMessage:m]];
}

/// 本条消息里需高亮的 `@昵称` → uid 映射（气泡内 @提及高亮 + 点击跳资料）：iOS 不落库 per-message mentions，
/// 改由**当前群成员 + 文本**推导——扫描群成员昵称在文本里是否有完整 token（与 Web 用服务端 mentions 收敛，
/// 因发送侧本就按成员昵称扫文本得出 mentions）。`@所有人` 仅在发送者是群主/管理员时高亮（对齐服务端 300204 鉴权，
/// 普通成员字面「@所有人」不误高亮），且 uid 存空串＝仅高亮不可点。非群聊/非文本/无 `@` 直接返回 nil。
- (NSDictionary<NSString *, NSString *> *)mentionMapForMessage:(IMMessageModel *)m {
    if (!self.isGroupChat || ![m.contentType isEqualToString:@"text"]) { return nil; }
    NSString *text = m.content;
    if (text.length == 0 || [text rangeOfString:@"@"].location == NSNotFound) { return nil; }
    NSArray<IMGroupMember *> *members = self.groupInfo.members;
    if (members.count == 0) { return nil; }
    NSMutableDictionary<NSString *, NSString *> *map = [NSMutableDictionary dictionary];
    for (IMGroupMember *mem in members) {
        if ([mem.userID isEqualToString:m.from]
            && (mem.role == IMGroupRoleOwner || mem.role == IMGroupRoleAdmin)
            && IMChatTextContainsMentionToken(text, @"所有人")) {
            map[@"所有人"] = @""; // 高亮但不可点
            break;
        }
    }
    for (IMGroupMember *mem in members) {
        NSString *nick = mem.displayName;
        if (nick.length > 0 && !map[nick] && IMChatTextContainsMentionToken(text, nick)) {
            map[nick] = mem.userID;
        }
    }
    return map.count > 0 ? map : nil;
}

/// 切换中长文本的展开态并就地重配该行（高度随之增减，气泡内容重排）。
- (void)toggleTextExpandedForMessage:(IMMessageModel *)m atIndexPath:(NSIndexPath *)ip {
    if (!self.expandedTextKeys) { self.expandedTextKeys = [NSMutableSet set]; }
    NSString *key = [self textKeyForMessage:m];
    if ([self.expandedTextKeys containsObject:key]) { [self.expandedTextKeys removeObject:key]; }
    else { [self.expandedTextKeys addObject:key]; }
    [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}

/// 点击文本消息的分档路由：Huge→全屏阅读器；Long→展开/收起；Short→无操作。返回 YES 表示已消费该点击。
- (BOOL)handleLongTextTapForMessage:(IMMessageModel *)m atIndexPath:(NSIndexPath *)ip {
    if (![m.contentType isEqualToString:@"text"] || m.recalledAt > 0) { return NO; }
    NSString *content = m.content ?: @"";
    if (IMMediaLooksLikeURL(content)) { return NO; } // 纯 URL 交给链接打开逻辑
    IMBubbleTextTier tier = [IMBubbleCell textTierForContent:content];
    if (tier == IMBubbleTextTierHuge) {
        __weak typeof(self) ws = self;
        IMTextReaderViewController *reader = [IMTextReaderViewController readerWithText:content mentions:[self mentionMapForMessage:m]];
        reader.onTapMentionUID = ^(NSString *uid) { [ws openMemberProfileForUID:uid]; }; // 阅读器内点 @昵称 → 关阅读器 + 跳资料
        [self presentViewController:reader animated:YES completion:nil];
        return YES;
    }
    if (tier == IMBubbleTextTierLong) {
        [self toggleTextExpandedForMessage:m atIndexPath:ip];
        return YES;
    }
    return NO;
}

/// 点击引用消息（有 replyToConvSeq）→ 跳到原消息；其余点击忽略。附件面板展开时点空白先收起面板（#3）。
- (void)handleReplyJumpTap:(UITapGestureRecognizer *)gr {
    if (self.selecting) {
        // 多选态：可选行交给表格勾选；点到发送中/失败的本地件（无勾选圈）直接提示原因，不静默。
        CGPoint sp = [gr locationInView:self.tableView];
        NSIndexPath *sip = [self.tableView indexPathForRowAtPoint:sp];
        if (sip && sip.row < (NSInteger)self.messages.count) {
            IMMessageModel *sm = self.messages[(NSUInteger)sip.row];
            if (sm.convSeq <= 0 && ![sm.contentType isEqualToString:@"system"]) {
                [self im_showToast:@"发送中/失败的消息不可选择"];
            }
        }
        return;
    }
    if (self.attachPanelVisible) { [self showAttachPanel:NO]; return; }
    // 先在「点击那一刻的稳定布局」上定位点中的消息——必须在收键盘之前：resignFirstResponder 触发的 inset
    // 变化会让坐标反查落到收起动画中间态的错行（曾表现为「跳到别的消息、高亮错行」）。
    CGPoint p = [gr locationInView:self.tableView];
    NSIndexPath *ip = [self.tableView indexPathForRowAtPoint:p];
    // @昵称 点击（气泡内）：必须在**收键盘前**用稳定布局命中——resign 会改 inset 让 cell 位移、坐标反查失准。
    // 命中某个挂了 uid 的 token → 跳该成员资料页（先于长文展开/引用跳转）。
    if (ip && ip.row < (NSInteger)self.messages.count) {
        UITableViewCell *hitCell = [self.tableView cellForRowAtIndexPath:ip];
        if ([hitCell isKindOfClass:IMBubbleCell.class]) {
            NSString *muid = [(IMBubbleCell *)hitCell mentionUIDAtPoint:[self.tableView convertPoint:p toView:hitCell]];
            if (muid.length > 0) { [self.inputField resignFirstResponder]; [self openMemberProfileForUID:muid]; return; }
        }
    }
    BOOL keyboardWasUp = self.kbInset > 0;
    [self.inputField resignFirstResponder]; // 点消息区任意处收起键盘（微信式；拖拽收起仍由 Interactive 模式负责）
    if (!ip || ip.row >= (NSInteger)self.messages.count) { return; }
    IMMessageModel *m = self.messages[(NSUInteger)ip.row];
    // 长文本（Q1）**先于**引用跳转判定：Long/Huge 文本气泡的展开/阅读器是整条点击触发，若被引用跳转抢先，
    // 作为引用发出的长文/超长文就永远点不开（内部已滤掉非文本/URL/撤回，短文本与媒体/文件引用照走下面的跳转）。
    if ([self handleLongTextTapForMessage:m atIndexPath:ip]) { return; }
    if (m.replyToConvSeq > 0) {
        int64_t target = m.replyToConvSeq;
        // 键盘正收起时，把定位滚动推迟到 inset 落定后——否则 scrollToRow 用即将失效的布局会停错位。
        if (keyboardWasUp) { [self runAfterKeyboardHidden:^{ [self jumpToConvSeq:target]; }]; }
        else { [self jumpToConvSeq:target]; }
        return;
    }
    if (m.recalledAt > 0) { return; }
    // 文件消息（M4-7）：自己发的保持应用内浏览器打开；收到的——已下载则本地 QuickLook 预览、未下载则点整条=触发下载。
    if ([m.contentType isEqualToString:@"file"]) {
        BOOL fileMine = [m.from isEqualToString:self.userID];
        if (fileMine) {
            [self openLink:[self fullMediaURL:m.content]];
        } else if ([self.downloads localFileForMessage:m]) {
            [self openCachedFile:m];
        } else {
            [self.downloads handleTapForMessage:m]; // 未下载/暂停/失败：点整条 = 点 ↓ 同效
        }
    }
}

/// 应用内浏览器打开链接（SFSafariViewController，仅接受 http/https）。
- (void)openLink:(NSString *)urlString {
    // 层3：本站邀请链接（/q/u 名片、/q/g 群码）→ 走扫码同款 resolve+路由（原生加群/名片流程），不出 App。
    if ([IMQRResultRouter routeInviteLinkIfOwn:urlString host:self.host userID:self.userID fromController:self]) { return; }
    NSURL *url = [NSURL URLWithString:urlString ?: @""];
    if (!url || !([url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"https"])) { return; }
    SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:url];
    [self presentViewController:safari animated:YES completion:nil];
}

#pragma mark - 下载编排（收到的图片 / 视频 / 文件，M4-7）
// 注：`downloads` 懒加载 getter 直接访问 _downloads ivar，留在主实现文件（category 不可见 ivar）。

/// 下载进度**就地更新**（不 reload）：镜像上传的 updateUploadProgressForMessage:。相册→只刷那一格；
/// 单图/视频/文件气泡→调 cell 自身的 updateDownloadProgress:（只改环/角标/图标，行高不变、主线程不卡）。
- (void)updateDownloadProgressForMessage:(IMMessageModel *)m state:(IMDownloadProgress *)state {
    NSUInteger row = [self visibleRowForMessage:m];
    if (row == NSNotFound || (NSInteger)row >= [self.tableView numberOfRowsInSection:0]) { return; }
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]];
    if ([cell isKindOfClass:IMAlbumCell.class]) {
        [(IMAlbumCell *)cell updateDownloadProgress:state forMessage:m];
    } else if ([cell isKindOfClass:IMImageCell.class]) {
        [(IMImageCell *)cell updateDownloadProgress:state];
    } else if ([cell isKindOfClass:IMBubbleCell.class]) {
        [(IMBubbleCell *)cell updateDownloadProgress:state];
    }
    // cell 不可见（滚出屏）：无需更新，下次滚回自然由 cellForRow 拿最新态。
}

/// 定点重配该消息的可见行（下载完成/图片解除门控）：相册成员映射到宫格 leader 行；媒体气泡行高不变。
/// 行数守卫同上传路径：消息可能刚 addObject 尚未 reloadData，此时定点 reloadRows 会触发行数断言崩溃 → 整表刷。
- (void)refreshRowForMessage:(IMMessageModel *)m {
    NSUInteger row = [self visibleRowForMessage:m];
    if (row == NSNotFound) { return; }
    if ((NSInteger)row >= [self.tableView numberOfRowsInSection:0]) { [self.tableView reloadData]; return; }
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]]
                          withRowAnimation:UITableViewRowAnimationNone];
}

/// 已下载的文件 → 本地 QuickLook 预览（不再丢给应用内浏览器）。
- (void)openCachedFile:(IMMessageModel *)m {
    NSURL *local = [self.downloads localFileForMessage:m];
    if (!local) { return; }
    self.quickLookURL = local;
    QLPreviewController *ql = [QLPreviewController new];
    ql.dataSource = self;
    [self presentViewController:ql animated:YES completion:nil];
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return self.quickLookURL ? 1 : 0;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    return self.quickLookURL;
}

/// 跳转到被引用的原消息：滚到该 conv_seq 行并高亮一闪（与 Web quoteflash 同节奏，1.2s）。
- (void)jumpToConvSeq:(int64_t)targetConvSeq {
    // 本页不在栈顶（从全屏媒体库 IMConversationMediaViewController、合并记录等 push 页里点「定位」进来，
    // 且弹层查看器已 dismiss）→ 先弹回本聊天页再滚，否则滚动发生在被覆盖的表上、用户看不到跳转（全屏库定位失效即此）。
    UINavigationController *nav = self.navigationController;
    if (nav && nav.topViewController != self && [nav.viewControllers containsObject:self]) {
        [nav popToViewController:self animated:YES];
        // pop 动画进行中滚动会落错位；挂转场协调器完成回调，等 pop 落定再跳（无协调器回落下一轮 runloop）。
        id<UIViewControllerTransitionCoordinator> tc = nav.transitionCoordinator;
        if (tc) {
            [tc animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
                [self jumpToConvSeq:targetConvSeq];
            }];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{ [self jumpToConvSeq:targetConvSeq]; });
        }
        return;
    }
    int64_t earliest = 0; // 当前已加载最早 conv_seq(>0)，用于区分"未加载到"与"已删除"
    for (NSUInteger i = 0; i < self.messages.count; i++) {
        int64_t s = self.messages[i].convSeq;
        if (s > 0 && (earliest == 0 || s < earliest)) { earliest = s; }
        if (s == targetConvSeq) {
            // 相册成员行本身零高（宫格整体画在 leader 行）：直接滚到成员下标会落在不可见行、高亮闪不出来。
            // 统一经 visibleRowForMessage 映射到该相册的 leader 行（普通消息即自身行）。
            NSUInteger visRow = [self visibleRowForMessage:self.messages[i]];
            NSInteger targetRow = (visRow == NSNotFound) ? (NSInteger)i : (NSInteger)visRow;
            NSIndexPath *ip = [NSIndexPath indexPathForRow:targetRow inSection:0];
            [self.tableView scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
            // 等滚动动画到位后再闪（已在视口时 scrollToRow 也可能微调，同样适用）。
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [self flashRowAtIndexPath:ip]; });
            return;
        }
    }
    // 跳不到分两种：落在窗口内却缺失 → 已被本地删除；目标比"已加载最早一条"还早（或全表无已确认消息，
    // earliest=0 判不出窗口）→ 本地没有。iOS 无上拉分页（全量载本地库），故不提示"上拉加载"，与 Web 文案刻意有别（CHAT_UX §3.1）。
    NSString *toast = (earliest == 0 || targetConvSeq < earliest)
        ? @"原消息不在本地" : @"原消息已被删除";
    [self im_showToast:toast];
}

/// 跳转高亮遮罩的 view tag（长按预览光栅化时据此临时隐藏它）。取一个不易与业务 tag 冲突的值。
const NSInteger kIMFlashOverlayTag = 0x1F1A5; // 跨 +Menu：光栅化预览时按此 tag 临时隐藏高亮蒙层（声明见 +Private.h）

/// 目标行高亮一闪：在气泡/卡片（previewTargetView）上盖一层强调色遮罩淡出——
/// 不动 cell 自身背景（图片 cell 改背景色看不见），对所有 cell 类型通吃。
- (void)flashRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:ip];
    if (!cell) { return; }
    UIView *target = [cell respondsToSelector:@selector(previewTargetView)]
        ? [(id)cell previewTargetView] : cell.contentView;
    if (!target) { return; }
    UIView *flash = [[UIView alloc] initWithFrame:target.bounds];
    flash.tag = kIMFlashOverlayTag; // 长按预览光栅化时按此 tag 临时隐藏，避免高亮蒙层被烘进静态预览
    flash.backgroundColor = [IMTheme.accent colorWithAlphaComponent:0.35];
    flash.layer.cornerRadius = target.layer.cornerRadius;
    flash.layer.maskedCorners = target.layer.maskedCorners; // 跟随气泡尾角（否则直角尾处露出未高亮月牙缝）
    flash.userInteractionEnabled = NO;
    flash.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [target addSubview:flash];
    [UIView animateWithDuration:0.9 delay:0.3 options:UIViewAnimationOptionCurveEaseOut
                     animations:^{ flash.alpha = 0; }
                     completion:^(BOOL finished) { [flash removeFromSuperview]; }];
}

- (void)handleSendResult:(BOOL)success convSeq:(int64_t)convSeq error:(NSError *)error forClientMsgID:(NSString *)clientMsgID {
    // 结果到来前先记录是否贴底：被拒收会给该条挂"系统行"，cell 随之变高，
    // 不重新贴底则系统行被顶出屏幕（需手动下滚才可见）。自己发的消息贴底（CHAT_UX §9）。
    BOOL wasNearBottom = [self isNearBottom];
    for (IMMessageModel *m in self.messages) {
        if ([m.clientMsgID isEqualToString:clientMsgID]) {
            m.status = success ? IMMessageStatusSent : IMMessageStatusFailed;
            // 被拒收 → 把服务端友好文案挂到 note，气泡下方居中显示（微信式系统行）；其余失败（如 ack 超时）不挂 note，仍显"未发送 ✗"。
            // 覆盖：被拉黑 200102 / 非好友 200103 / 被禁言 300004 / 非群成员 300203 / 群全员禁言 300206 / 成员级禁言 300208（G2）
            //     / 内容过大 300001（合并转发套娃膨胀超上限，后端回「消息内容过大，无法发送」，无恢复入口）。
            m.note = (!success && (error.code == 200102 || error.code == 200103 || error.code == 300004 ||
                                   error.code == 300203 || error.code == 300206 || error.code == 300208 || error.code == 300001)) ? error.localizedDescription : nil;
            m.noteCode = m.note ? error.code : 0; // 瞬态：决定系统行是否给恢复入口（200103 → 发好友申请）
            m.convSeq = convSeq;
            if (![self performDatabaseOperation:^(IMDatabase *database) {
                [database saveMessage:m]; // upsert：更新状态/conv_seq/note（含被拒文案，重进会话不丢）
            }]) { return; }
            if (convSeq > 0) { [self.seenConvSeqs addObject:@(convSeq)]; } // 防 sync 重复回显自己发的
            // 相册成员的 ACK 只定点刷宫格角标/状态胶囊（全表 reloadData 是批量发送闪屏的元凶之一）。
            if (m.groupID.length > 0) {
                [self refreshVisibleCellForMessage:m];
                return;
            }
            break;
        }
    }
    [self.tableView reloadData];
    if (wasNearBottom) { [self scrollToBottomAnimated:YES]; } // 贴底则把（变高后的）该条+系统行滚入视口
}

@end
