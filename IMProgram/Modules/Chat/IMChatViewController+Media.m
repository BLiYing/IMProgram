//  IMChatViewController+Media.m
//  聊天页「附件面板 / 富媒体 + 复制粘贴」分文件实现（M4-6 / #2）：加号面板、相册/相机/文件选择器、
//  媒体查看器与翻页、上传编排、粘贴图预览条与批量发送。从 IMChatViewController.m 平移，未改行为。

#import "IMChatViewController+Private.h"
#import <AVFoundation/AVFoundation.h>
#import "IMMessageModel.h"
#import "IMTheme.h"
#import "IMTimeUtil.h"
#import "IMDatabase.h"
#import "IMHTTPService.h"
#import "IMMenuAction.h"
#import "IMProtocol.h"
#import "IMMediaUtil.h"
#import "IMMediaSendService.h"
#import "IMMediaViewerViewController.h"
#import "IMMediaPagerViewController.h"
#import "IMConversationMediaViewController.h"
#import "IMChatRecordViewController.h"
#import "IMChunkedUploader.h"
#import "IMFilePickerViewController.h"
#import "IMMediaPicker.h"
#import "IMPendingMediaStore.h"
#import "IMPendingMediaThumbnail.h"
#import "IMImageLoader.h"
#import "IMPopoverCard.h"
#import "IMImageCell.h"
#import "IMAlbumCell.h"
#import "IMUploadProgress.h"
#import "UIViewController+IMToast.h"
#import "UIViewController+IMDeleteSheet.h"

@implementation IMChatViewController (Media)

#pragma mark - 附件面板 / 富媒体（M4-6）

- (void)voiceTapped { [self im_showComingSoon:@"语音"]; }
- (void)emojiTapped { [self im_showComingSoon:@"表情"]; }

/// 面板项（数据驱动，M4-6）：加入口 = 数组加一条。照片接真实上传，其余占位。
- (NSArray<NSDictionary *> *)attachItems {
    return @[
        @{ @"id": @"photo", @"title": @"照片", @"image": @"photo" },
        @{ @"id": @"camera", @"title": @"拍摄", @"image": @"camera" },
        @{ @"id": @"av", @"title": @"音视频", @"image": @"video" },
        @{ @"id": @"favorite", @"title": @"收藏", @"image": @"bookmark" },
        @{ @"id": @"card", @"title": @"个人名片", @"image": @"person.crop.square" },
        @{ @"id": @"file", @"title": @"文件", @"image": @"doc" },
    ];
}

const CGFloat kIMAttachPanelHeight = 236; // 面板高度（顶起输入栏的量）；跨 +Media/主实现共享，声明见 +Private.h

/// 展开/收起附件面板（首次点击惰性构建 2×3 网格）。面板显示在输入栏「下方」（微信式）：
/// 展开时收起键盘、把输入栏上顶 kIMAttachPanelHeight，面板填充其下方空间。
- (void)toggleAttachPanel {
    if (!self.attachPanel) {
        [self buildAttachPanel];
        // 首次建面板时先解析约束，确保动画从输入栏下方的真实初始 frame 开始，
        // 而非 Auto Layout 尚未赋值时的左上角 (0,0)。
        [self.view layoutIfNeeded];
    }
    [self showAttachPanel:!self.attachPanelVisible];
}

/// 统一切换面板可见性并驱动布局（与键盘互斥，见 updateInputBottomAnimated:）。
/// 注意：方法名不能叫 setAttachPanelVisible:（那是属性 attachPanelVisible 的合成 setter，会与内部 self.attachPanelVisible= 赋值自递归）。
- (void)showAttachPanel:(BOOL)visible {
    if (visible) { [self.inputField resignFirstResponder]; } // 面板与键盘不同时占位
    self.attachPanelVisible = visible;
    self.attachPanel.hidden = !visible;
    [self updateInputBottomAnimated:YES];
}

- (void)buildAttachPanel {
    UIView *panel = [UIView new];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.backgroundColor = UIColor.secondarySystemBackgroundColor;
    panel.hidden = YES;
    [self.view addSubview:panel];
    self.attachPanel = panel;

    UIStackView *rows = [UIStackView new]; // 竖直：两行
    rows.translatesAutoresizingMaskIntoConstraints = NO;
    rows.axis = UILayoutConstraintAxisVertical;
    rows.distribution = UIStackViewDistributionFillEqually;
    rows.spacing = 16;
    [panel addSubview:rows];

    NSArray<NSDictionary *> *items = [self attachItems];
    UIStackView *currentRow = nil;
    for (NSUInteger i = 0; i < items.count; i++) {
        if (i % 3 == 0) {
            currentRow = [UIStackView new];
            currentRow.axis = UILayoutConstraintAxisHorizontal;
            currentRow.distribution = UIStackViewDistributionFillEqually;
            currentRow.spacing = 16;
            [rows addArrangedSubview:currentRow];
        }
        [currentRow addArrangedSubview:[self attachItemViewFor:items[i]]];
    }
    [NSLayoutConstraint activateConstraints:@[
        [panel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [panel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [panel.topAnchor constraintEqualToAnchor:self.inputBar.bottomAnchor], // 在输入栏「下方」展开
        [panel.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],   // 铺到屏幕底（覆盖 home 指示条区域）
        [rows.topAnchor constraintEqualToAnchor:panel.topAnchor constant:16],
        [rows.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:24],
        [rows.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-24],
        [rows.heightAnchor constraintEqualToConstant:kIMAttachPanelHeight - 40],
    ]];
}

/// 单个面板项：图标圆钮 + 标题。
- (UIView *)attachItemViewFor:(NSDictionary *)item {
    UIStackView *v = [UIStackView new];
    v.axis = UILayoutConstraintAxisVertical;
    v.alignment = UIStackViewAlignmentCenter;
    v.spacing = 6;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightRegular];
    [btn setImage:[UIImage systemImageNamed:item[@"image"] withConfiguration:c] forState:UIControlStateNormal];
    btn.tintColor = IMTheme.textPrimary;
    btn.backgroundColor = UIColor.systemBackgroundColor;
    btn.layer.cornerRadius = 12;
    NSString *itemId = item[@"id"];
    __weak typeof(self) ws = self;
    [btn addAction:[UIAction actionWithHandler:^(UIAction *a) { [ws attachItemTapped:itemId]; }]
        forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [btn.widthAnchor constraintEqualToConstant:56],
        [btn.heightAnchor constraintEqualToConstant:56],
    ]];
    UILabel *lbl = [UILabel new];
    lbl.text = item[@"title"];
    lbl.font = [UIFont systemFontOfSize:12];
    lbl.textColor = IMTheme.textSecondary;
    [v addArrangedSubview:btn];
    [v addArrangedSubview:lbl];
    return v;
}

- (void)attachItemTapped:(NSString *)itemId {
    [self showAttachPanel:NO];
    if ([itemId isEqualToString:@"photo"]) {
        [self openPhotoPicker];
        return;
    }
    if ([itemId isEqualToString:@"camera"]) {
        [self openCamera];
        return;
    }
    if ([itemId isEqualToString:@"file"]) {
        [self openFilePanel];
        return;
    }
    NSDictionary *names = @{ @"av": @"音视频",
                            @"favorite": @"从收藏发送", @"card": @"个人名片" };
    [self im_showComingSoon:names[itemId] ?: @"该功能"]; // 其余占位，后续按需接真实功能
}

/// 把消息里的相对 URL（/uploads/xxx）补成绝对地址（含 host）；已是 http/data 的原样返回。
- (NSString *)fullMediaURL:(NSString *)content {
    return IMMediaFullURL(content, self.host);
}

/// 全屏查看图片/视频（点击媒体气泡）：复用 IMMediaViewerViewController，附「媒体库」入口。
/// 任务3：在当前会话媒体时间线（口径同媒体库：image|video·未撤回·非空）里定位点中的这条，
/// 套 IMMediaPagerViewController 支持左右翻页（混排、封面待点、翻到头即停）；仅一张时退化为单开。
- (void)presentMediaViewerForMessage:(IMMessageModel *)m preloaded:(UIImage *)image {
    if (m.content.length == 0) { return; }
    NSMutableArray<IMMessageModel *> *mediaMsgs = [NSMutableArray array];
    for (IMMessageModel *x in self.messages) {
        if (x.recalledAt > 0 || x.content.length == 0) { continue; }
        if ([x.contentType isEqualToString:@"image"] || [x.contentType isEqualToString:@"video"]) {
            [mediaMsgs addObject:x];
        }
    }
    NSUInteger start = [mediaMsgs indexOfObjectIdenticalTo:m];
    if (start == NSNotFound) {
        // 不在时间线内（理论不至于，兜底）→ 单开自带全套控件的查看器。
        [self presentViewController:[self buildMediaViewerForMessage:m preloaded:image] animated:YES completion:nil];
        return;
    }
    // 恒走翻页容器（即便仅一张）：壳（✕/下载/媒体库/更多）在容器固定层、沉浸态一致。
    __weak typeof(self) ws = self;
    IMMediaPagerViewController *pager =
        [IMMediaPagerViewController pagerWithCount:mediaMsgs.count startIndex:start
                                      pageProvider:^IMMediaViewerViewController *(NSUInteger index) {
            __strong typeof(ws) self = ws;
            if (!self || index >= mediaMsgs.count) { return nil; }
            IMMessageModel *mm = mediaMsgs[index];
            // 仅初始点中的那条带气泡预载图（已解码），其余现建时自行按 URL 拉。
            return [self buildMediaViewerForMessage:mm preloaded:(mm == m ? image : nil)];
        }];
    pager.conversationTitle = [self conversationDisplayTitle];
    [self presentViewController:pager animated:YES completion:nil];
}

/// 为单条媒体消息构建一个查看器页（url/isVideo/媒体库入口/「更多」外部动作均绑定该条消息）。
/// 翻页容器按下标对每条消息各建一份，保证「更多」里的收藏/转发/删除/定位作用在正确的消息上。
- (IMMediaViewerViewController *)buildMediaViewerForMessage:(IMMessageModel *)m preloaded:(UIImage *)image {
    BOOL isVideo = [m.contentType isEqualToString:@"video"];
    __weak typeof(self) ws = self;
    IMMediaViewerViewController *viewer =
        [IMMediaViewerViewController viewerWithURL:[self fullMediaURL:m.content]
                                           isVideo:isVideo
                                    preloadedImage:image
                                     onOpenGallery:^{ [ws openConversationMediaGallery]; }];
    viewer.thumbDataURI = m.thumb; // 路线 A：未下载/加载中先显内嵌 thumb 磨砂占位 + 菊花
    viewer.moreActions = [self mediaViewerMoreActionsForMessage:m];
    return viewer;
}

/// 查看器「更多」外部动作（定位/收藏/复制/转发；内置「下载」由查看器自己加在最前）：
/// 聊天气泡查看器与全屏媒体库查看器共用。
- (NSArray<IMPopoverCardItem *> *)mediaViewerMoreActionsForMessage:(IMMessageModel *)m {
    BOOL isVideo = [m.contentType isEqualToString:@"video"];
    __weak typeof(self) ws = self;
    NSMutableArray<IMPopoverCardItem *> *acts = [NSMutableArray array];
    if (m.convSeq > 0) {
        [acts addObject:[IMPopoverCardItem itemWithTitle:@"定位到聊天位置" symbol:@"text.bubble" destructive:NO handler:^{
            [ws jumpToConvSeq:m.convSeq];
        }]];
    }
    [acts addObject:[IMPopoverCardItem itemWithTitle:@"收藏" symbol:@"bookmark" destructive:NO handler:^{ [ws favoriteMessage:m]; }]];
    // 视频不提供复制：无"复制字节"语义，复制链接意义不大，产品上禁止复制视频消息（与 Web 对齐）。
    if (!isVideo) {
        [acts addObject:[IMPopoverCardItem itemWithTitle:@"复制" symbol:@"doc.on.doc" destructive:NO handler:^{
            [ws copyMessageToPasteboard:m]; // 图片→复制图片字节（可粘贴回输入框发图）
        }]];
    }
    if (m.recalledAt == 0 && m.convSeq > 0) {
        [acts addObject:[IMPopoverCardItem itemWithTitle:@"转发" symbol:@"arrowshape.turn.up.right" destructive:NO handler:^{ [ws forwardMessage:m]; }]];
    }
    // 删除（与 Web 查看器「更多」对齐）：可为所有人删则弹两档 sheet，否则=仅删除自己 / 本地删。
    [acts addObject:[IMPopoverCardItem itemWithTitle:@"删除" symbol:@"trash" destructive:YES handler:^{ [ws confirmDeleteMediaMessage:m]; }]];
    return acts;
}

/// 查看器「更多」里的删除（IMPopoverCard 为扁平列表，用 action sheet 承载两档）：
/// 本地未发出（convSeq<=0）=本地删；可为所有人删=弹「仅删除自己 / 为所有人删除」；否则=仅删除自己。
- (void)confirmDeleteMediaMessage:(IMMessageModel *)m {
    if (!m) { return; }
    if (m.convSeq <= 0) { [self deleteMessage:m]; return; }
    if (![self canDeleteForEveryone:m]) { [self hideMessageForSelf:m]; return; }
    __weak typeof(self) ws = self;
    // 从可见页弹（查看器「更多」是先关查看器再执行，栈顶可能是全屏媒体库而非本页；
    // 挂到被覆盖的 self 上会被 UIKit 静默拒绝，曾致删除无反应）。
    UIViewController *presenter = [UIViewController im_topVisibleViewController] ?: self;
    [presenter im_presentDeleteChoiceSheetWithSelfOnly:^{ [ws hideMessageForSelf:m]; }
                                              everyone:^{ [ws deleteMessageForEveryone:m]; }];
}

/// 全屏媒体库逐格长按菜单里「消息相关」动作（转发/定位/删除，与资料 tab 一致；「取消下载」由媒体库自带）。
- (NSArray<IMMenuAction *> *)mediaContextActionsForMessage:(IMMessageModel *)m {
    __weak typeof(self) ws = self;
    NSMutableArray<IMMenuAction *> *acts = [NSMutableArray array];
    [acts addObject:[IMMenuAction actionWithId:@"forward" title:@"转发" image:@"arrowshape.turn.up.right"
                                       handler:^{ [ws forwardMessage:m]; }]];
    [acts addObject:[IMMenuAction actionWithId:@"locate" title:@"定位到聊天" image:@"text.bubble"
                                       handler:^{ [ws jumpToConvSeq:m.convSeq]; }]];
    [acts addObject:[self deleteMenuActionForMessage:m]]; // actionId=@"delete"（媒体库据此在其前插「取消下载」）
    return acts;
}

/// 媒体查看器/媒体库顶部标题（会话名）：单聊=对方昵称/uid，群聊=群名。
- (NSString *)conversationDisplayTitle {
    if (self.isGroupChat) { return self.groupName.length > 0 ? self.groupName : @"群聊"; }
    return self.peerNickname.length > 0 ? self.peerNickname : self.peerID;
}

/// 会话媒体库：汇总当前会话所有图片/视频消息，按时间序展示，点击复用同一查看器。
- (void)openConversationMediaGallery {
    NSMutableArray<IMMediaItem *> *items = [NSMutableArray array];
    NSMutableArray<IMMessageModel *> *msgs = [NSMutableArray array];
    for (IMMessageModel *m in self.messages) {
        if (m.recalledAt > 0 || m.content.length == 0) { continue; }
        BOOL isVideo = [m.contentType isEqualToString:@"video"];
        BOOL isImage = [m.contentType isEqualToString:@"image"];
        if (!isVideo && !isImage) { continue; }
        [items addObject:[IMMediaItem itemWithURL:[self fullMediaURL:m.content] isVideo:isVideo timestamp:m.timestamp thumb:m.thumb]];
        [msgs addObject:m];
    }
    __weak typeof(self) ws = self;
    IMConversationMediaViewController *gallery =
        [IMConversationMediaViewController galleryWithItems:items messages:msgs
                                                       host:self.host myUserID:self.userID isGroup:self.isGroupChat
                                                      title:[self conversationDisplayTitle]
                                     contextActionsProvider:^NSArray<IMMenuAction *> *(IMMessageModel *m) { return [ws mediaContextActionsForMessage:m]; }
                                        moreActionsProvider:^NSArray<IMPopoverCardItem *> *(IMMessageModel *m) { return [ws mediaViewerMoreActionsForMessage:m]; }];
    [self.navigationController pushViewController:gallery animated:YES];
}

/// 打开合并转发的聊天记录详情页（#3）。
- (void)openChatRecord:(IMMessageModel *)message {
    if (message.content.length == 0) { return; }
    IMChatRecordViewController *vc = [[IMChatRecordViewController alloc] initWithHost:self.host recordJSON:message.content];
    [self.navigationController pushViewController:vc animated:YES];
}

/// 相册多选（PHPicker，≤9，图片/Live 图/视频）→ **选完秒上屏**（≥2 张=一个宫格 cell，1 张=普通媒体气泡）
/// → 缩略图逐格异步补上 → 逐项 压缩/转码 + 带进度上传（每格环形进度）→ 传完一张转正式发送一张。
/// PHPicker 是进程外选择器，无需相册读权限（保存到相册的权限仍在下载路径申请）。
- (void)openPhotoPicker {
    __weak typeof(self) ws = self;
    [IMMediaPicker presentFromViewController:self limit:9
                           handlesCompletion:^(NSArray<IMPickedMediaHandle *> *handles) {
        [ws sendMediaHandles:handles];
    }];
}

/// 批量发送（相册重构，M4+）：句柄回调即上屏（不等压缩/转码），重活延后逐项进行。
- (void)sendMediaHandles:(NSArray<IMPickedMediaHandle *> *)handles {
    if (handles.count == 0) { return; }
    // ≥2 张：共享 group_id → 两端聚簇渲染宫格；1 张：普通媒体气泡（无 group_id）。
    NSString *gid = handles.count > 1 ? [@"alb-" stringByAppendingString:NSUUID.UUID.UUIDString] : nil;
    NSMutableArray<IMMessageModel *> *pending = [NSMutableArray arrayWithCapacity:handles.count];
    for (IMPickedMediaHandle *h in handles) {
        IMMessageModel *m = [IMMessageModel new];
        m.clientMsgID = [@"outbox-" stringByAppendingString:NSUUID.UUID.UUIDString]; // 临时键，转正式发送时换真 ID
        m.convID = self.convID; m.to = self.peerID; m.from = self.userID;
        m.content = @""; // 未上传：无 URL，格内显示本地预览/灰占位
        m.contentType = h.isVideo ? @"video" : @"image";
        m.groupID = gid;
        m.status = IMMessageStatusSending;
        m.timestamp = IMNowMillis();
        [self.messages addObject:m];
        [pending addObject:m];
    }
    // 转码 → 落盘 → 上传 → 发消息全程活在常驻服务（退出本页/无页面存活都不中断）；
    // enqueue 会先置好 queued 进度与缩略图加载，本页只负责上屏与渲染。
    [IMMediaSendService.shared enqueueMediaHandles:handles messages:pending
                                            toUser:(self.isGroupChat ? @"" : self.peerID)
                                         dbContext:self.databaseContext];
    [self.tableView reloadData]; // 一次性上屏：宫格只有 1 个可见 cell（从行零高），无逐条插行闪动
    [self scrollToAbsoluteBottom];
}

/// 待发/失败的乐观气泡落库（content 为 im-pending:// 本地引用）。
/// 成功发出后常驻服务会把 content 换成服务器 URL 再存一次，并删掉本地副本。
///
/// **content 为空的不落库**：那种行重进会话既显示不出内容也无法重试，只会留下一个永久的空气泡
/// （字节还没落盘就失败时会走到这里，例如未登录、句柄解码失败、磁盘写满）。
- (void)persistOutboxMessage:(IMMessageModel *)m {
    if (m.content.length == 0) { return; }
    [self performDatabaseOperation:^(IMDatabase *database) { [database saveMessage:m]; }];
}

/// 本地待发媒体的缩略图：重进会话时消息 content 是 im-pending:// 本地文件，直接出图，不走网络。
/// **解码放后台**：cellForRow 里同步解一张 4K 图或抽一帧 74MB 视频会直接卡住滚动
/// （正是 IMImageLoader 刚清掉的那种主线程解码）。首帧返回 nil，解完再刷该行。
- (UIImage *)pendingPreviewForMessage:(IMMessageModel *)m {
    NSString *key = m.clientMsgID ?: @"";
    UIImage *cached = self.outboxPreviews[key];
    if (cached) { return cached; }
    if (key.length == 0 || [self.pendingPreviewLoading containsObject:key]) { return nil; }
    NSString *path = [[IMPendingMediaStore shared] filePathForLocalRef:m.content];
    if (!path) { return nil; }
    [self.pendingPreviewLoading addObject:key];
    BOOL isVideo = [m.contentType isEqualToString:@"video"];
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIImage *thumb = isVideo ? IMPendingVideoThumbnail(path) : IMPendingImageThumbnail(path);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            [self.pendingPreviewLoading removeObject:key];
            if (!thumb) { return; }
            self.outboxPreviews[key] = thumb;
            [self refreshVisibleCellForMessage:m];
        });
    });
    return nil;
}

/// 点按待发中的图片/视频气泡（中心按钮状态机）或文件气泡的左侧图标位（同一套状态机）：
///   失败 ↻ → 重试；上传中 ⏸ ↔ 已暂停 ↑ → 切换；排队/压缩/准备中 ✕ → 确认后取消（防误触必须确认）。
- (void)handlePendingMediaTap:(IMMessageModel *)m {
    if (m.status == IMMessageStatusFailed) { [self retryPendingMessage:m]; return; }
    if ([IMMediaSendService.shared togglePauseForMessage:m]) { return; } // 分片上传：暂停↔继续
    IMUploadProgress *p = self.outboxProgress[m.clientMsgID ?: @""];
    if (p.phase == IMUploadPhaseQueued || p.phase == IMUploadPhaseTranscoding) {
        [self confirmCancelPendingMessage:m]; // 排队/压缩期无任务可暂停，点按=询问取消
    }
    // 一次性小上传进行中：无可操作，忽略点击
}

/// 取消发送前确认（长按菜单直达 cancelPendingMessage，点按走这里防误触）。
- (void)confirmCancelPendingMessage:(IMMessageModel *)m {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:@"取消发送这条消息？"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) ws = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消发送" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *a) { [ws cancelPendingMessage:m]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"继续发送" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

/// 取消发送：服务负责停任务/删副本/删库行并广播 DidCancel，本页在通知里移除该行。
- (void)cancelPendingMessage:(IMMessageModel *)m {
    [IMMediaSendService.shared cancelMessage:m dbContext:self.databaseContext];
}

/// 重试一条本地待发失败的消息（图片/视频/文件通吃）：交给常驻服务从本地副本续（文件走分片续传）。
- (void)retryPendingMessage:(IMMessageModel *)m {
    BOOL ok = [IMMediaSendService.shared retryMessage:m
                                               toUser:(self.isGroupChat ? @"" : self.peerID)
                                            dbContext:self.databaseContext];
    if (!ok) { [self im_showToast:@"本地文件已丢失，无法重试"]; return; }
    [self refreshVisibleCellForMessage:m];
}

/// 定点刷新消息的可见 cell：相册成员 → leader 行的宫格只刷格子（不 reload、不动布局）；
/// 普通消息 → reload 自身行（媒体 cell 固定高，不影响滚动位置）。
- (void)refreshVisibleCellForMessage:(IMMessageModel *)m {
    NSUInteger row = [self visibleRowForMessage:m];
    if (row == NSNotFound) { return; }
    // 行数守卫：消息可能刚 addObject 尚未 reloadData（如入列时服务同步广播初始进度），
    // 此时定点 reloadRows 会触发 UITableView 行数断言直接崩溃（真机 2026-08-04 crash 实锤）→ 整表刷。
    if ((NSInteger)row >= [self.tableView numberOfRowsInSection:0]) {
        [self.tableView reloadData];
        return;
    }
    NSIndexPath *ip = [NSIndexPath indexPathForRow:(NSInteger)row inSection:0];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:ip];
    if ([cell isKindOfClass:IMAlbumCell.class]) {
        [(IMAlbumCell *)cell refreshWithPreviews:self.outboxPreviews progress:self.outboxProgress];
        return;
    }
    [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}

/// 就地重算行高（媒体 cell 拿到真实比例后调用）：不 reload、不动画，避免打断滚动与图片闪烁。
- (void)refreshRowHeightsWithoutAnimation {
    [UIView performWithoutAnimation:^{
        [self.tableView beginUpdates];
        [self.tableView endUpdates];
    }];
}

/// 进度只改可见 cell 的覆盖层/进度环（不 reload，避免高频进度回调闪烁）。
- (void)updateUploadProgressForMessage:(IMMessageModel *)m {
    NSUInteger row = [self visibleRowForMessage:m];
    if (row == NSNotFound) { return; }
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]];
    if ([cell isKindOfClass:IMAlbumCell.class]) {
        [(IMAlbumCell *)cell refreshWithPreviews:self.outboxPreviews progress:self.outboxProgress];
    } else if ([cell isKindOfClass:IMImageCell.class]) {
        [(IMImageCell *)cell setUploadProgress:self.outboxProgress[m.clientMsgID ?: @""]];
    }
}

/// 拍摄（#4 先申请相机权限）→ 上传 → 发图片消息。
- (void)openCamera {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        [self im_showToast:@"当前设备不支持拍摄"];
        return;
    }
    __weak typeof(self) ws = self;
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (granted) { [self presentImagePickerWithSource:UIImagePickerControllerSourceTypeCamera]; }
            else { [self im_showToast:@"请在设置中允许使用相机"]; }
        });
    }];
}

/// 文件面板（Telegram 式）：从相册/从文件 入口 + 「最近发送的文件」列表（复发不再上传）。
- (void)openFilePanel {
    __weak typeof(self) ws = self;
    __block NSString *nextCursor = nil;
    __block NSArray<NSDictionary *> *cachedFiles = @[];
    [self performDatabaseOperation:^(IMDatabase *database) {
        cachedFiles = database.cachedSentFiles;
    }];
    IMFilePickerViewController *panel = [[IMFilePickerViewController alloc]
        initWithRecentFiles:cachedFiles
        onFromPhotos:^{ [ws openPhotoFilePicker]; }
        onFromFiles:^{ [ws presentDocumentPicker]; }
        onPickRecent:^(NSString *url, NSString *name, int64_t size) {
            [ws sendMediaURL:url contentType:@"file" fileName:name fileSize:size];
        }
        loadPage:^(BOOL nextPage, IMSentFilePageCompletion completion) {
            NSString *token = IMHTTPService.sharedService.currentToken;
            if (token.length == 0) {
                completion(nil, NO, [NSError errorWithDomain:@"IMFilePicker" code:-1 userInfo:nil]);
                return;
            }
            NSString *cursor = nextPage ? nextCursor : nil;
            [IMHTTPService.sharedService sentFilesWithToken:token cursor:cursor
                completion:^(NSArray<NSDictionary *> *files, NSString *cursorAfter, BOOL hasMore, NSError *error) {
                    if (!error) {
                        nextCursor = cursorAfter;
                        [ws performDatabaseOperation:^(IMDatabase *database) {
                            [database cacheSentFiles:files ?: @[]];
                        }];
                    }
                    completion(files, hasMore, error);
                }];
        }];
    // 直接 present 面板（不再包 UINavigationController）：面板自持一条 IMLiquidNavigationBar，
    // 顶部关闭按钮与全局返回按钮同款 Liquid Glass；sheet 配置在面板 init 内已设好。
    [self presentViewController:panel animated:YES completion:nil];
}

/// 文件面板中的相册入口：以 file 消息发送原始资源，不进入图片/视频气泡或相册宫格。
/// 与 Files 大文件路径同构：选完**立刻上屏**（旧实现要等整个原件拷进内存 + 一次性传完才见气泡，
/// 大视频等几分钟毫无反馈），导出/落盘/上传/发送全程活在常驻服务，≥8MB 分片可暂停续传。
- (void)openPhotoFilePicker {
    __weak typeof(self) ws = self;
    [IMMediaPicker presentFilePickerFromViewController:self limit:9
                           handlesCompletion:^(NSArray<IMPickedMediaHandle *> *handles) {
        [ws sendPhotoFileHandles:handles];
    }];
}

- (void)sendPhotoFileHandles:(NSArray<IMPickedMediaHandle *> *)handles {
    if (handles.count == 0) { return; }
    NSMutableArray<IMMessageModel *> *pending = [NSMutableArray arrayWithCapacity:handles.count];
    for (IMPickedMediaHandle *h in handles) {
        IMMessageModel *m = [IMMessageModel new];
        m.clientMsgID = [@"outbox-" stringByAppendingString:NSUUID.UUID.UUIDString]; // 临时键，转正式发送时换真 ID
        m.convID = self.convID; m.to = self.peerID; m.from = self.userID;
        m.content = @""; // 导出完成前无本地副本；服务落盘后写 im-pending:// 并落库
        m.contentType = @"file";
        m.fileName = [h suggestedFileName];
        m.fileSize = 0; // 未知，导出完成后服务补写（第二行先显「准备中…」）
        m.status = IMMessageStatusSending;
        m.timestamp = IMNowMillis();
        [self.messages addObject:m];
        [pending addObject:m];
    }
    // 先上屏再入列（与 sendLargeFileAtURL 同理：入列路径若同步广播进度，reloadRows 会撞行数断言）。
    [self.tableView reloadData];
    [self scrollToAbsoluteBottom];
    [IMMediaSendService.shared enqueuePhotoFileHandles:handles messages:pending
                                                toUser:(self.isGroupChat ? @"" : self.peerID)
                                             dbContext:self.databaseContext];
}

/// 文件面板关闭后，由聊天页直接呈现系统文件浏览器（全屏、单实例配置见 +systemDocumentPicker）。
/// 系统自行维护 Files/File Provider 的内部返回栈，选完或点叉叉都由系统关闭 picker 直接回到聊天页。
- (void)presentDocumentPicker {
    UIDocumentPickerViewController *picker = [IMFilePickerViewController systemDocumentPicker];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [self handlePickedDocumentURL:urls.firstObject];
}

/// 大文件分片发送：先把文件落到待发目录并**立刻上屏**一条 sending 气泡（带进度、可暂停），
/// 再走分片上传；中断/退出会话都不丢，重进能看到并继续。
- (void)sendLargeFileAtURL:(NSURL *)fileURL fileName:(NSString *)fileName size:(int64_t)size token:(NSString *)token {
    IMMessageModel *m = [IMMessageModel new];
    m.clientMsgID = [@"outbox-" stringByAppendingString:NSUUID.UUID.UUIDString];
    m.convID = self.convID; m.to = self.peerID; m.from = self.userID;
    m.contentType = @"file";
    m.fileName = fileName;
    m.fileSize = size;
    m.status = IMMessageStatusSending;
    m.timestamp = IMNowMillis();
    // 文件系统拷贝，不经内存：几百 MB 的文件读进 NSData 足以触发 jetsam。
    NSString *localRef = [[IMPendingMediaStore shared] storeFileAtURL:fileURL
                                                      forClientMsgID:m.clientMsgID
                                                           extension:fileName.pathExtension];
    if (!localRef) { [self im_showToast:@"本地暂存失败，请重试"]; return; }
    m.content = localRef;
    [self.messages addObject:m];
    [self persistOutboxMessage:m];
    // **先上屏再入列**：enqueue 内部会同步广播初始进度（分片作业立即标 ⏸），通知回调按 messages
    // 数组定位新行去 reloadRows——若 tableView 还不知道这行存在，行数断言直接崩（真机 2026-08-04 实锤）。
    [self appendReloadAndScroll];
    // 分片上传 + 完成后发消息活在常驻服务：退出会话、甚至所有聊天页都销毁，传完照样发出去。
    [IMMediaSendService.shared enqueueFileMessage:m
                                           toUser:(self.isGroupChat ? @"" : self.peerID)
                                        dbContext:self.databaseContext];
}

/// 进入/回到会话时合并常驻服务里仍在跑的作业：
/// - 转码/落盘尚未完成的媒体（未落库）→ 本页列表看不到，把服务实例并进来；
/// - 已落库的行（库副本）→ 换成服务实例，让后续进度/完成直接作用于同一对象。
/// 并**自动认领孤儿 sending 行**：杀进程重启后库里 status=sending 但服务无作业的行，
/// 直接续传（凭旁挂 upload_id 从服务端 offset 继续，用户无感）；本地副本丢失才降级为失败可重试。
- (void)reattachRunningUploads {
    BOOL changed = NO;
    for (IMMessageModel *serviceModel in [IMMediaSendService.shared inFlightMessagesInConv:self.convID]) {
        IMMessageModel *mine = [self messageForClientMsgID:serviceModel.clientMsgID];
        if (!mine) {
            [self.messages addObject:serviceModel];
            changed = YES;
        } else if (mine != serviceModel) {
            NSUInteger idx = [self.messages indexOfObjectIdenticalTo:mine];
            if (idx != NSNotFound) { [self.messages replaceObjectAtIndex:idx withObject:serviceModel]; }
            changed = YES;
        }
    }
    NSString *toUser = self.isGroupChat ? @"" : self.peerID;
    for (IMMessageModel *m in self.messages) {
        if (m.status != IMMessageStatusSending || m.convSeq > 0) { continue; }
        if (![IMPendingMediaStore isLocalRef:m.content]) { continue; }
        if ([IMMediaSendService.shared hasActiveJobForClientMsgID:m.clientMsgID]) { continue; }
        if (![IMMediaSendService.shared retryMessage:m toUser:toUser dbContext:self.databaseContext]) {
            m.status = IMMessageStatusFailed; // 本地副本已丢失：无法续传，标失败给出 ↻（点了会提示副本丢失）
            [self persistOutboxMessage:m];
        }
        changed = YES;
    }
    if (changed) { [self.tableView reloadData]; }
}

/// 系统 Files 返回本地副本后上传并发送。
/// 大文件走**分片上传**：气泡立刻上屏并显示进度，可点击暂停/继续，断网后从服务端 offset 续传。
- (void)handlePickedDocumentURL:(NSURL *)url {
    if (!url) { return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    NSString *originalName = url.lastPathComponent ?: @"file.bin";
    // 先 stat 再决定走哪条路：大文件绝不能为了判断大小就整包读进内存。
    int64_t size = (int64_t)[[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:NULL][NSFileSize] unsignedLongLongValue];
    if (size <= 0 || token.length == 0) { [self im_showToast:@"文件读取失败"]; return; }
    if (size >= (int64_t)IMChunkedUploader.chunkedThresholdBytes) {
        [self sendLargeFileAtURL:url fileName:originalName size:size token:token]; // 全程走文件，不进内存
        return;
    }
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data.length == 0) { [self im_showToast:@"文件读取失败"]; return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService uploadData:data fileName:originalName
                                   mimeType:@"application/octet-stream" token:token
                                 completion:^(NSString *up, NSString *contentType, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error || up.length == 0) {
            [self im_showToast:error.localizedDescription.length ? error.localizedDescription : @"文件上传失败"];
            return;
        }
        [self sendMediaURL:up contentType:@"file" fileName:originalName fileSize:(int64_t)data.length];
    }];
}

- (void)presentImagePickerWithSource:(UIImagePickerControllerSourceType)source {
    UIImagePickerController *picker = [UIImagePickerController new];
    picker.sourceType = source;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    if (!image) { return; }
    NSData *data = UIImageJPEGRepresentation(image, 0.8);
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (data.length == 0 || token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService uploadData:data fileName:@"photo.jpg" mimeType:@"image/jpeg" token:token
                                 completion:^(NSString *url, NSString *contentType, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error || url.length == 0) { [self im_showToast:@"图片上传失败"]; return; }
        [self sendMediaURL:url contentType:(contentType ?: @"image") fileName:nil fileSize:0
           mediaAttributes:[self mediaAttributesForImage:image bytes:(int64_t)data.length]];
    }];
}

/// 单图路径（相机/粘贴）的媒体元数据：像素尺寸 + 上传字节数，供收端按原比例排版。
- (IMMediaAttributes *)mediaAttributesForImage:(UIImage *)image bytes:(int64_t)bytes {
    IMMediaAttributes *attrs = [IMMediaAttributes new];
    CGFloat scale = image.scale > 0 ? image.scale : 1;
    attrs.pixelWidth = (NSInteger)round(image.size.width * scale);
    attrs.pixelHeight = (NSInteger)round(image.size.height * scale);
    attrs.fileSize = bytes;
    // 相机/粘贴图绕过 IMMediaSendService 的常驻媒体队列，过去因此漏掉了其生成 thumb 的步骤：
    // sendMedia 最终只在 attrs.thumb 非空时写入 payload，接收方就只能退回中性灰底。
    // 复用同一生成器，保证所有图片发送入口遵守 M4-7 的 ~20px data URI 契约。
    attrs.thumb = IMTinyThumbDataURI(image);
    return attrs;
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

/// 发送已上传的媒体：走 socket sendMedia，乐观上屏。
- (void)sendMediaURL:(NSString *)url contentType:(NSString *)contentType {
    [self sendMediaURL:url contentType:contentType fileName:nil fileSize:0 mediaAttributes:nil];
}

- (void)sendMediaURL:(NSString *)url contentType:(NSString *)contentType fileName:(NSString *)fileName {
    [self sendMediaURL:url contentType:contentType fileName:fileName fileSize:0 mediaAttributes:nil];
}

- (void)sendMediaURL:(NSString *)url contentType:(NSString *)contentType fileName:(NSString *)fileName fileSize:(int64_t)fileSize {
    [self sendMediaURL:url contentType:contentType fileName:fileName fileSize:fileSize mediaAttributes:nil];
}

/// mediaAttributes：图片/视频的尺寸与时长（相机/粘贴等单图路径由调用方量出）；file 消息传 nil。
- (void)sendMediaURL:(NSString *)url contentType:(NSString *)contentType fileName:(NSString *)fileName
            fileSize:(int64_t)fileSize mediaAttributes:(IMMediaAttributes *)mediaAttributes {
    __block NSString *clientMsgID = nil;
    int64_t sentAt = IMNowMillis();
    __weak typeof(self) ws = self;
    IMSendCompletion completion = ^(BOOL success, NSError *error, int64_t convSeq) {
        [ws handleSendResult:success convSeq:convSeq error:error forClientMsgID:clientMsgID];
        if (success && [contentType isEqualToString:@"file"] && fileName.length > 0) {
            [ws performDatabaseOperation:^(IMDatabase *database) {
                [database cacheSentFiles:@[@{
                    @"server_msg_id": clientMsgID ?: @"",
                    @"url": url ?: @"", @"name": fileName, @"size": @(fileSize), @"timestamp": @(sentAt),
                }]];
            }];
        }
    };
    NSString *toUser = self.isGroupChat ? @"" : self.peerID;
    if ([contentType isEqualToString:@"file"]) {
        clientMsgID = [IMSocketManager.sharedManager sendFile:url fileName:fileName ?: @"" fileSize:fileSize toConv:self.convID toUser:toUser completion:completion];
    } else {
        clientMsgID = [IMSocketManager.sharedManager sendMedia:url contentType:contentType toConv:self.convID toUser:toUser
                                                    attributes:mediaAttributes completion:completion];
    }

    IMMessageModel *m = [IMMessageModel new];
    m.clientMsgID = clientMsgID; m.convID = self.convID; m.to = self.peerID; m.from = self.userID;
    m.content = url; m.contentType = contentType; m.status = IMMessageStatusSending;
    m.fileName = fileName;
    m.fileSize = mediaAttributes.fileSize > 0 ? mediaAttributes.fileSize : fileSize;
    m.mediaW = mediaAttributes.pixelWidth;
    m.mediaH = mediaAttributes.pixelHeight;
    m.duration = mediaAttributes.durationMillis;
    m.thumb = mediaAttributes.thumb; // 回填本地 model，否则转发自发图片时 forwardAttributes 读到空 thumb→收端只剩空磨砂
    m.groupID = mediaAttributes.groupID; // 粘贴多图：本端也按宫格聚簇渲染
    m.caption = mediaAttributes.caption; // 图说：本端气泡即时显文字（重进会话仍在）
    m.mentions = mediaAttributes.mentions; // 配文 @：本端落库，转发自发消息时可重发（强提醒）
    m.mentionAll = mediaAttributes.mentionAll;
    m.timestamp = sentAt;
    [self performDatabaseOperation:^(IMDatabase *database) {
        [database saveMessage:m];
    }];
    [self.messages addObject:m];
    [self appendReloadAndScroll];
}

#pragma mark - 复制 / 粘贴图片（#2）

/// 复制消息：图片→复制真实图片字节（可粘贴回输入框直接发图）；其余→复制文本/链接。
- (void)copyMessageToPasteboard:(IMMessageModel *)message {
    if ([message.contentType isEqualToString:@"image"]) {
        __weak typeof(self) ws = self;
        [[IMImageLoader shared] loadImageURL:[self fullMediaURL:message.content] completion:^(UIImage *img) {
            if (img) {
                UIPasteboard.generalPasteboard.image = img;
                [ws im_showToast:@"已复制图片"];
            } else {
                UIPasteboard.generalPasteboard.string = [ws fullMediaURL:message.content];
                [ws im_showToast:@"已复制链接"];
            }
        }];
        return;
    }
    BOOL isMedia = [message.contentType isEqualToString:@"video"] || [message.contentType isEqualToString:@"file"];
    UIPasteboard.generalPasteboard.string = isMedia ? [self fullMediaURL:message.content] : (message.content ?: @"");
    if (isMedia) { [self im_showToast:@"已复制链接"]; }
}

/// 粘贴图片 → 预览条攒批（#2 重设计，Telegram 式）：不直接发，缩略图 chip 出现在输入栏上方，
/// 可继续粘贴/打字，逐张 ✕ 移除；发送键统一发出（≥2 张共享 group_id 成宫格，文字随后补发）。
/// 图说上传失败的配文回填：只在输入框仍为空时还原（用户已开始打新内容就不清覆），并刷新发送键可见性。
- (void)restoreCaptionToComposer:(NSString *)caption {
    if (caption.length == 0 || self.inputField.text.length > 0) { return; }
    self.inputField.text = caption;
    [self updateSendButtonVisibility];
}

- (void)appendPastedImage:(UIImage *)image {
    if (!image) { return; }
    if (!self.pendingPasteImages) { self.pendingPasteImages = [NSMutableArray array]; }
    // 粘贴限单件（2026-08-19 拍板，与 Web 对齐）：一次只留一张，后粘的替换先前的——
    // 图说 caption 只对单件消息定义；多选发图仍走媒体选择器（相册宫格），不受此限。
    if (self.pendingPasteImages.count > 0) {
        [self.pendingPasteImages removeAllObjects];
        [self im_showToast:@"一次只能粘贴一张图片，已保留最新的"];
    }
    [self.pendingPasteImages addObject:image];
    [self refreshPasteBar];
    [self updateSendButtonVisibility];
}

/// 重建预览条 chips（张数少、重建成本可忽略）：44pt 缩略图 + 右上 ✕；条高随有无内容 0↔60 切换。
- (void)refreshPasteBar {
    for (UIView *v in [self.pasteChipsStack.arrangedSubviews copy]) {
        [self.pasteChipsStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    [self.pendingPasteImages enumerateObjectsUsingBlock:^(UIImage *img, NSUInteger idx, BOOL *stop) {
        UIView *chip = [UIView new];
        chip.translatesAutoresizingMaskIntoConstraints = NO;
        UIImageView *iv = [[UIImageView alloc] initWithImage:img];
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        iv.layer.cornerRadius = 8;
        [chip addSubview:iv];
        UIButton *remove = [UIButton buttonWithType:UIButtonTypeSystem];
        remove.translatesAutoresizingMaskIntoConstraints = NO;
        [remove setImage:[UIImage systemImageNamed:@"xmark.circle.fill"
                                 withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16
                                                                                                   weight:UIImageSymbolWeightBold]]
                forState:UIControlStateNormal];
        remove.tintColor = UIColor.secondaryLabelColor;
        remove.tag = (NSInteger)idx;
        [remove addTarget:self action:@selector(removePastedImageChip:) forControlEvents:UIControlEventTouchUpInside];
        [chip addSubview:remove];
        [NSLayoutConstraint activateConstraints:@[
            [chip.widthAnchor constraintEqualToConstant:50],
            [chip.heightAnchor constraintEqualToConstant:50],
            [iv.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor],
            [iv.bottomAnchor constraintEqualToAnchor:chip.bottomAnchor],
            [iv.widthAnchor constraintEqualToConstant:44],
            [iv.heightAnchor constraintEqualToConstant:44],
            [remove.centerXAnchor constraintEqualToAnchor:iv.trailingAnchor constant:-2],
            [remove.centerYAnchor constraintEqualToAnchor:iv.topAnchor constant:2],
            [remove.widthAnchor constraintEqualToConstant:24],
            [remove.heightAnchor constraintEqualToConstant:24],
        ]];
        [self.pasteChipsStack addArrangedSubview:chip];
    }];
    self.pasteBarHeight.constant = self.pendingPasteImages.count > 0 ? 60 : 0;
    [self.view layoutIfNeeded];
}

- (void)removePastedImageChip:(UIButton *)sender {
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= (NSInteger)self.pendingPasteImages.count) { return; }
    [self.pendingPasteImages removeObjectAtIndex:(NSUInteger)idx];
    [self refreshPasteBar];
    [self updateSendButtonVisibility];
}

- (void)uploadAndSendPastedImage:(UIImage *)image groupID:(NSString *)groupID {
    [self uploadAndSendPastedImage:image groupID:groupID caption:nil mentions:nil mentionAll:NO];
}

/// 图说变体（Telegram 模型）：单张粘贴图 + 配文合并成一条 caption 消息；配文 @ 随媒体上行。
/// 失败时**必须把配文还回输入框**：sendTapped 在发起上传时已清空输入，此前失败只 toast 会把用户打的字
/// 连图一起弄丢（旧「图/文各发」路径文字必达；code-review 2026-08-19）。@token 还原成文字后重发会重新解析。
- (void)uploadAndSendPastedImage:(UIImage *)image groupID:(NSString *)groupID
                         caption:(NSString *)caption mentions:(NSArray<NSString *> *)mentions mentionAll:(BOOL)mentionAll {
    NSData *jpeg = UIImageJPEGRepresentation(image, 0.8);
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (jpeg.length == 0 || token.length == 0) {
        [self im_showToast:@"图片处理失败"];
        [self restoreCaptionToComposer:caption];
        return;
    }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService uploadData:jpeg fileName:@"pasted.jpg" mimeType:@"image/jpeg" token:token
                                 completion:^(NSString *url, NSString *contentType, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error || url.length == 0) {
            [self im_showToast:@"图片上传失败"];
            [self restoreCaptionToComposer:caption];
            return;
        }
        IMMediaAttributes *attrs = [self mediaAttributesForImage:image bytes:(int64_t)jpeg.length];
        attrs.groupID = groupID; // ≥2 张：同批共享 group_id → 两端聚簇渲染宫格
        attrs.caption = caption.length > 0 ? caption : nil;
        attrs.mentions = mentions.count > 0 ? mentions : nil;
        attrs.mentionAll = mentionAll;
        [self sendMediaURL:url contentType:(contentType ?: @"image") fileName:nil fileSize:0
           mediaAttributes:attrs];
    }];
}

@end
