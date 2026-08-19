//  IMChatViewController+Selection.m
//  聊天页「多选态」分文件实现（#2：转发/收藏/删除 + 合并转发）。
//  从 IMChatViewController.m 平移，未改行为；私有属性经 IMChatViewController+Private.h 共享。

#import "IMChatViewController+Private.h"
#import "IMMessageModel.h"
#import "IMConversation.h"
#import "IMForwardPickerViewController.h"
#import "IMHTTPService.h"
#import "IMDatabase.h"
#import "IMProtocol.h"
#import "IMMediaUtil.h"
#import "IMMediaExpiryRegistry.h"
#import "IMTheme.h"
#import "IMTimeUtil.h"
#import "UIViewController+IMToast.h"

@implementation IMChatViewController (Selection)

#pragma mark - 多选态（#2：转发/收藏/删除）

/// 进入多选：表格进入编辑多选态，隐藏输入栏、显示底部工具栏，并默认选中触发的那条。
/// 列表**锚定长按的那条消息不动**：宫格展开为独立行会让行结构/总高度剧变，不锚定就会跳到别处。
- (void)enterSelectionWithMessage:(IMMessageModel *)message {
    if (self.selecting) { return; }
    self.selecting = YES;
    [self showAttachPanel:NO];
    [self cancelReply];
    [self.inputField resignFirstResponder];

    NSUInteger row = [self.messages indexOfObject:message];
    [self preserveScreenPositionOfRow:row during:^{
        self.tableView.allowsMultipleSelectionDuringEditing = YES;
        [self.tableView setEditing:YES animated:NO];
        [self.tableView reloadData]; // 相册宫格展开为独立行（逐条可勾选）；isAlbumMember 在多选态恒 NO
        // 已在屏上的 cell 不会再走 willDisplay，就地改 selectionStyle 让勾选态可见（#5）。
        for (UITableViewCell *c in self.tableView.visibleCells) { [self applySelectionStyleForCell:c]; }
    }];

    [self buildSelectionBarIfNeeded];
    self.selectionBar.hidden = NO;
    self.inputBar.hidden = YES;

    self.savedTitle = self.title;
    self.savedRightItem = self.navigationItem.rightBarButtonItem;
    self.navigationItem.rightBarButtonItem = nil;
    // 必须用**带标题**的 item：统一 Liquid 标题栏按 leftTitle 渲染左位文字并把点击路由到本 item；
    // 系统 Cancel item 无标题 → 被回落成返回箭头、点击直接 pop 出聊天页（"没有取消按钮"的根因）。
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(exitSelection)];

    if (row != NSNotFound) {
        [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]
                                    animated:NO scrollPosition:UITableViewScrollPositionNone];
    }
    [self updateSelectionUI];
}

- (void)exitSelection {
    if (!self.selecting) { return; }
    self.selecting = NO;
    // 退出同样锚定：以当前视口第一条可见消息为锚（宫格收拢后上方内容变矮，不锚定视口会漂移）。
    NSIndexPath *anchor = self.tableView.indexPathsForVisibleRows.firstObject;
    [self preserveScreenPositionOfRow:(anchor ? (NSUInteger)anchor.row : NSNotFound) during:^{
        [self.tableView setEditing:NO animated:NO];
        [self.tableView reloadData]; // 相册宫格恢复聚簇渲染
        for (UITableViewCell *c in self.tableView.visibleCells) { [self applySelectionStyleForCell:c]; }
    }];
    self.selectionBar.hidden = YES;
    self.inputBar.hidden = NO;
    self.title = self.savedTitle;
    self.navigationItem.leftBarButtonItem = nil; // 恢复默认返回
    self.navigationItem.rightBarButtonItem = self.savedRightItem;
    [self refreshUnifiedNavigationBar]; // 标题/左右钮改动要立刻刷进 Liquid 标题栏
}

/// 在表格 mutation（编辑态切换 + reloadData）前后保持某行的屏幕位置不变（多选进出时列表不跳）。
/// reload 后行高全部回到估算值，先落一次布局再对齐、两轮收敛（与 anchorRowToTop: 同思路）。
- (void)preserveScreenPositionOfRow:(NSUInteger)row during:(void (NS_NOESCAPE ^)(void))mutation {
    if (row == NSNotFound || row >= self.messages.count) { mutation(); return; }
    NSIndexPath *ip = [NSIndexPath indexPathForRow:(NSInteger)row inSection:0];
    CGFloat screenY = [self.tableView rectForRowAtIndexPath:ip].origin.y - self.tableView.contentOffset.y;
    mutation();
    for (int pass = 0; pass < 2; pass++) {
        [self.tableView layoutIfNeeded];
        CGFloat topInset = self.tableView.adjustedContentInset.top;
        CGFloat maxY = self.tableView.contentSize.height - self.tableView.bounds.size.height
                     + self.tableView.adjustedContentInset.bottom;
        CGFloat y = [self.tableView rectForRowAtIndexPath:ip].origin.y - screenY;
        y = MAX(-topInset, MIN(y, MAX(-topInset, maxY)));
        [self.tableView setContentOffset:CGPointMake(0, y) animated:NO];
    }
}

- (void)buildSelectionBarIfNeeded {
    if (self.selectionBar) { return; }
    UIView *bar = [UIView new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = UIColor.secondarySystemBackgroundColor;
    [self.view addSubview:bar];
    self.selectionBar = bar;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self selectionBarButton:@"转发" image:@"arrowshape.turn.up.right" action:@selector(forwardSelected)],
        [self selectionBarButton:@"收藏" image:@"bookmark" action:@selector(favoriteSelected)],
        [self selectionBarButton:@"删除" image:@"trash" action:@selector(deleteSelected)],
    ]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [bar.topAnchor constraintEqualToAnchor:self.inputBar.topAnchor],
        [row.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [row.topAnchor constraintEqualToAnchor:bar.topAnchor],
        [row.heightAnchor constraintEqualToConstant:56],
    ]];
}

- (UIButton *)selectionBarButton:(NSString *)title image:(NSString *)image action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
    cfg.image = [UIImage systemImageNamed:image];
    cfg.title = title;
    cfg.imagePlacement = NSDirectionalRectEdgeTop;
    cfg.imagePadding = 3;
    cfg.baseForegroundColor = IMTheme.textPrimary;
    b.configuration = cfg;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

/// 已选消息（按行序）。
- (NSArray<IMMessageModel *> *)selectedMessages {
    NSArray<NSIndexPath *> *ips = [self.tableView.indexPathsForSelectedRows sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<IMMessageModel *> *out = [NSMutableArray array];
    for (NSIndexPath *ip in ips) {
        if (ip.row < (NSInteger)self.messages.count) { [out addObject:self.messages[(NSUInteger)ip.row]]; }
    }
    return out;
}

- (void)updateSelectionUI {
    NSUInteger n = self.tableView.indexPathsForSelectedRows.count;
    self.title = n > 0 ? [NSString stringWithFormat:@"已选择 %lu 条", (unsigned long)n] : @"选择消息";
    [self refreshUnifiedNavigationBar]; // 标题与「取消」左钮由统一 Liquid 栏渲染，改完必须刷一次
}

#pragma mark 多选工具栏动作

- (void)forwardSelected {
    NSArray<IMMessageModel *> *msgs = [self selectedMessages];
    if (msgs.count == 0) { [self im_showToast:@"请先选择消息"]; return; }
    __weak typeof(self) ws = self;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"逐条转发" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [ws pickConversationsThen:^(NSArray<IMConversation *> *convs) { [ws forwardMessages:msgs perMessageToConversations:convs]; }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"合并转发" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        __strong typeof(ws) self = ws; if (!self) { return; }
        NSUInteger expiredCount = 0;
        for (IMMessageModel *m in msgs) { if ([self isMediaExpiredForForward:m]) { expiredCount++; } }
        if (expiredCount >= msgs.count) { [self im_showToast:@"所选均已失效，无法合并转发"]; return; } // 失效项会被剔出记录，全失效则整条无意义
        NSString *json = [self mergedForwardJSONForMessages:msgs];
        [self pickConversationsThen:^(NSArray<IMConversation *> *convs) { [self forwardMergedRecord:json toConversations:convs]; }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    // iPad/regular 宽度下走 popover：sourceRect 必须在 sourceView 自身坐标系内，否则锚点跑到屏幕外（原用 self.view 坐标）。
    UIView *anchor = self.selectionBar ?: self.view;
    sheet.popoverPresentationController.sourceView = anchor;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(anchor.bounds), CGRectGetMinY(anchor.bounds), 1, 1);
    sheet.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionDown;
    [self presentViewController:sheet animated:YES completion:nil];
}

/// 弹出整页会话选择器，回调选中的会话。
/// 转发的发送方本地回显（用户反馈 #2）：服务端不回显自己发的消息，转发若不落库/上屏，
/// 发送方在目标会话里看不到这条转发。与普通发送一致：乐观消息落库（目标是当前会话则上屏），
/// ACK 后按 clientMsgID upsert 状态/conv_seq（页面已退出也能改到库，重进会话读到正确状态）。
- (void)forwardEchoContent:(NSString *)content contentType:(NSString *)ct forwardFrom:(NSString *)origin fileName:(NSString *)fileName fileSize:(int64_t)fileSize
                    toConv:(NSString *)convID toUser:(NSString *)toUser {
    [self forwardEchoContent:content contentType:ct forwardFrom:origin fileName:fileName fileSize:fileSize
                  attributes:nil toConv:convID toUser:toUser];
}

/// 从源消息取出转发要一并带走的媒体元数据（封面/尺寸/时长）；非媒体消息返回 nil。
- (IMMediaAttributes *)forwardAttributesForMessage:(IMMessageModel *)message {
    BOOL isMedia = [message.contentType isEqualToString:@"image"] || [message.contentType isEqualToString:@"video"];
    BOOL hasCaption = message.caption.length > 0; // 图说：文件文也可能带 caption，需建 attrs 承载
    if (!isMedia && !hasCaption) { return nil; }
    IMMediaAttributes *attrs = [IMMediaAttributes new];
    if (isMedia) {
        attrs.poster = message.poster;          // 视频封面（不带的话 Web 收端解不了 HEVC 就只剩空白）
        attrs.thumb = message.thumb;            // 极小模糊预览：不带的话收端未下载态只有空磨砂、没内容轮廓
        attrs.pixelWidth = message.mediaW;
        attrs.pixelHeight = message.mediaH;
        attrs.durationMillis = message.duration;
        attrs.fileSize = message.fileSize;
    }
    // 图说整体转发（Telegram 模型）：caption + mentions 随转发跟随——收端 @ 高亮可点、被@者强提醒
    // （服务端按目标群成员再过滤，非成员自动落普通文字）。**不带 mentionAll**：@所有人 需目标群
    // 群主/管理员权限，无权会整条拒发 300204，且转发不该再次全员强提醒（与 Web 同取舍）。
    attrs.caption = message.caption;
    attrs.mentions = message.mentions;
    return attrs;
}

/// attributes：原消息的封面/尺寸/时长。转发不带就等于把这些信息丢了（收端只能按未知渲染，事后补不回）。
- (void)forwardEchoContent:(NSString *)content contentType:(NSString *)ct forwardFrom:(NSString *)origin fileName:(NSString *)fileName fileSize:(int64_t)fileSize
                attributes:(IMMediaAttributes *)attributes toConv:(NSString *)convID toUser:(NSString *)toUser {
    IMMessageModel *m = [IMMessageModel new];
    int64_t sentAt = IMNowMillis();
    __weak typeof(self) ws = self;
    NSString *clientMsgID = [IMSocketManager.sharedManager forwardContent:content contentType:ct
                                                                   toConv:convID toUser:toUser forwardFrom:origin
                                                                 fileName:fileName
                                                                 fileSize:fileSize
                                                               attributes:attributes
                                                               completion:^(BOOL success, NSError *error, int64_t convSeq) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        m.status = success ? IMMessageStatusSent : IMMessageStatusFailed;
        m.convSeq = convSeq;
        if (![self performDatabaseOperation:^(IMDatabase *database) {
            [database saveMessage:m];
        }]) { return; }
        if (success && [ct isEqualToString:@"file"] && fileName.length > 0) {
            [self performDatabaseOperation:^(IMDatabase *database) {
                [database cacheSentFiles:@[@{
                    @"server_msg_id": m.clientMsgID ?: @"", @"url": content,
                    @"name": fileName, @"size": @(fileSize), @"timestamp": @(sentAt),
                }]];
            }];
        }
        if ([convID isEqualToString:self.convID]) {
            if (convSeq > 0) { [self.seenConvSeqs addObject:@(convSeq)]; } // 防 sync 重复回显
            [self.tableView reloadData];
        }
    }];
    m.clientMsgID = clientMsgID;
    m.convID = convID; m.to = toUser; m.from = self.userID;
    m.content = content; m.contentType = ct;
    m.fileName = fileName;
    m.fileSize = fileSize;
    m.poster = attributes.poster.length > 0 ? attributes.poster : nil;
    m.thumb = attributes.thumb.length > 0 ? attributes.thumb : nil;
    m.mediaW = attributes.pixelWidth;
    m.mediaH = attributes.pixelHeight;
    m.duration = attributes.durationMillis;
    m.caption = attributes.caption.length > 0 ? attributes.caption : nil; // 图说随转发跟随（本端气泡即时显）
    m.mentions = attributes.mentions; // 配文 @ 落到本端回显行：再次转发这条时才能继续重发 mentions（强提醒链不断）
    m.forwardFrom = origin.length > 0 ? origin : nil;
    m.status = IMMessageStatusSending;
    m.timestamp = sentAt;
    [self performDatabaseOperation:^(IMDatabase *database) {
        [database saveMessage:m];
    }];
    if ([convID isEqualToString:self.convID]) {
        [self.messages addObject:m];
        [self appendReloadAndScroll];
    }
}

- (void)pickConversationsThen:(void (^)(NSArray<IMConversation *> *convs))block {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    IMForwardPickerViewController *picker = [[IMForwardPickerViewController alloc]
        initWithHost:self.host token:token onDone:^(NSArray<IMConversation *> *selected) {
        if (selected.count > 0) { block(selected); }
    }];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)forwardMessages:(NSArray<IMMessageModel *> *)msgs perMessageToConversations:(NSArray<IMConversation *> *)convs {
    // 失效媒体跳过（转出去对端必 404）：先数一次，避免在会话外层循环里重复计数。
    NSUInteger expiredCount = 0;
    for (IMMessageModel *m in msgs) { if ([self isMediaExpiredForForward:m]) { expiredCount++; } }
    for (IMConversation *c in convs) {
        NSString *toUser = c.isGroup ? @"" : (c.peer ?: @"");
        for (IMMessageModel *m in msgs) {
            if (m.recalledAt > 0 || m.content.length == 0 || [m.contentType isEqualToString:@"system"]) { continue; }
            if (m.convSeq <= 0) { continue; } // 防御：发送中/失败的本地件（多选已拦，此处兜底）
            if ([self isMediaExpiredForForward:m]) { continue; } // 失效媒体跳过
            NSString *origin = m.forwardFrom.length > 0 ? m.forwardFrom
                : (m.fromNickname.length > 0 ? m.fromNickname : (m.from ?: @""));
            [self forwardEchoContent:m.content contentType:(m.contentType ?: @"text") forwardFrom:origin fileName:m.fileName fileSize:m.fileSize
                          attributes:[self forwardAttributesForMessage:m] toConv:c.convID toUser:toUser];
        }
    }
    [self exitSelection];
    if (expiredCount >= msgs.count) { // 所选可选消息均为失效媒体（系统/撤回件多选态本就不可选）
        [self im_showToast:@"所选均已失效，未转发"];
        return;
    }
    NSString *base = convs.count == 1 ? @"已转发" : [NSString stringWithFormat:@"已转发到 %lu 个会话", (unsigned long)convs.count];
    [self im_showToast:expiredCount > 0
        ? [NSString stringWithFormat:@"%@（%lu 条已失效未转发）", base, (unsigned long)expiredCount]
        : base];
}

- (void)forwardMergedRecord:(NSString *)json toConversations:(NSArray<IMConversation *> *)convs {
    if (json.length == 0) { return; }
    for (IMConversation *c in convs) {
        NSString *toUser = c.isGroup ? @"" : (c.peer ?: @"");
        [self forwardEchoContent:json contentType:@"chat_record" forwardFrom:@"" fileName:nil fileSize:0
                          toConv:c.convID toUser:toUser];
    }
    [self exitSelection];
    [self im_showToast:@"已合并转发"];
}

- (void)favoriteSelected {
    NSArray<IMMessageModel *> *msgs = [self selectedMessages];
    if (msgs.count == 0) { [self im_showToast:@"请先选择消息"]; return; }
    for (IMMessageModel *m in msgs) {
        if (m.recalledAt > 0 || m.content.length == 0 || [m.contentType isEqualToString:@"system"]) { continue; }
        [self favoriteMessage:m];
    }
    [self exitSelection];
}

- (void)deleteSelected {
    NSArray<IMMessageModel *> *msgs = [self selectedMessages];
    if (msgs.count == 0) { [self im_showToast:@"请先选择消息"]; return; }
    __weak typeof(self) ws = self;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:nil
        message:[NSString stringWithFormat:@"删除所选 %lu 条消息？", (unsigned long)msgs.count]
        preferredStyle:UIAlertControllerStyleActionSheet];
    [ac addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        __strong typeof(ws) self = ws;
        for (IMMessageModel *m in msgs) {
            [self performDatabaseOperation:^(IMDatabase *database) {
                [database deleteMessage:m];
            }];
            [self.messages removeObject:m];
            if (m.convSeq > 0) { [self.seenConvSeqs removeObject:@(m.convSeq)]; }
        }
        [self.tableView reloadData];
        [self exitSelection];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    ac.popoverPresentationController.sourceView = self.selectionBar ?: self.view;
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark 合并转发数据

/// 发送方显示名：自己→uid，群聊→成员昵称，单聊→标题（对端显示名）。
- (NSString *)displayNameForMessage:(IMMessageModel *)m {
    if ([m.from isEqualToString:self.userID]) { return self.userID ?: @"我"; }
    if (self.isGroupChat) { return [self senderNameForMessage:m]; }
    return (self.savedTitle.length ? self.savedTitle : (self.title.length ? self.title : (self.peerID ?: @"")));
}

/// 合并转发内容：JSON（t=标题，items=[{n:发送者, ct:类型, c:内容/URL, 文件另带 fn:文件名/fs:字节数}]），
/// content_type=chat_record。fn/fs 与 Web 同约定；老记录无 fn 时读端从 URL 反推原名兜底。
- (NSString *)mergedForwardJSONForMessages:(NSArray<IMMessageModel *> *)msgs {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (IMMessageModel *m in msgs) {
        if (m.recalledAt > 0 || [m.contentType isEqualToString:@"system"] || m.content.length == 0) { continue; }
        if (m.convSeq <= 0) { continue; } // 防御：发送中/失败的本地件（多选已拦，此处兜底）
        if ([self isMediaExpiredForForward:m]) { continue; } // 失效媒体剔出合并记录（收端点开必 404）
        NSMutableDictionary *item = [@{ @"n": [self displayNameForMessage:m] ?: @"",
                                        @"ct": m.contentType ?: @"text",
                                        @"c": m.content ?: @"" } mutableCopy];
        if ([m.contentType isEqualToString:@"file"]) {
            NSString *fname = m.fileName.length > 0 ? m.fileName : IMMediaFileName(m.content);
            if (fname.length > 0) { item[@"fn"] = fname; }
            if (m.fileSize > 0) { item[@"fs"] = @(m.fileSize); }
        }
        if (m.caption.length > 0) { item[@"cap"] = m.caption; } // 图说条目携带 caption（cap，与 Web 同 key）→ 记录卡「有字显字」
        [items addObject:item];
    }
    // 多选态下 self.title 已被替换为"已选择 N 条"，用 savedTitle 取真实会话名。
    NSString *base = self.savedTitle.length ? self.savedTitle : (self.title.length ? self.title : (self.peerID ?: @"聊天"));
    NSDictionary *dict = @{ @"t": [NSString stringWithFormat:@"%@ 的聊天记录", base], @"items": items };
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:NULL];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
}

#pragma mark - 编辑/选择 delegate（tableView）

/// 多选态下该消息是否可勾选：系统提示/撤回墓碑/发送中·失败的本地件（无服务端内容，转出去是空的）不可选。
- (BOOL)isSelectableMessage:(IMMessageModel *)m {
    return ![m.contentType isEqualToString:@"system"] && m.recalledAt == 0 && m.convSeq > 0;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.selecting) { return NO; } // 仅多选态可选中
    // 不可选的行不显示勾选圈（系统编辑态对 canEdit=NO 的行自动不画圈，无需额外 UI）。
    if (indexPath.row >= (NSInteger)self.messages.count) { return NO; }
    return [self isSelectableMessage:self.messages[indexPath.row]];
}

/// 多选态勾选填充（#5）：selectionStyle=None 会让编辑圈选永远不显示"已勾选"态，
/// 进入多选须临时改回 Default（配 clear 的 multipleSelectionBackgroundView 保持气泡外观）。
- (void)applySelectionStyleForCell:(UITableViewCell *)cell {
    cell.selectionStyle = self.selecting ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    if (self.selecting && !cell.multipleSelectionBackgroundView) {
        UIView *bg = [UIView new];
        bg.backgroundColor = UIColor.clearColor;
        cell.multipleSelectionBackgroundView = bg;
    }
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    [self applySelectionStyleForCell:cell];
    // 长按菜单交互统一在此挂（单一咽喉点，取代原先在 cellForRow 各类型分支各补一行——漏接一种即静默无菜单）。
    // 幂等；system/albumPad 等不实现 previewTargetView 的 cell 自动跳过；相册宫格每格自带交互不受影响。
    [self attachMessageContextMenuToCell:cell];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.selecting) { [self updateSelectionUI]; return; }
    // 上传中/失败的文件气泡不再响应整条点击：暂停/继续/重试/取消收敛到左侧图标位的圆环状态机
    //（cell.onFileControlTap → handlePendingMediaTap:），气泡其余区域仅在发送完成后点击打开文件。
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.selecting) { [self updateSelectionUI]; }
}

@end
