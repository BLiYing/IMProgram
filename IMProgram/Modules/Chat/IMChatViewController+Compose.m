//  IMChatViewController+Compose.m
//  聊天页「文本发送 / 引用回复（M4-2）/ 收藏（M4-4）/ 编辑·翻译（M4-5）」分文件实现：发送按钮的完整
//  发送流水线、输入栏上方引用条的进入与取消、消息收藏、就地编辑与译文切换。从 IMChatViewController.m
//  平移，未改行为。@提及的 token 解析仍在 +Mention.m，sendTapped 经 (Private) 声明调用它们。

#import "IMChatViewController+Private.h"
#import "IMMessageModel.h"
#import "IMDatabase.h"
#import "IMHTTPService.h"
#import "IMTheme.h"
#import "IMTimeUtil.h"
#import "IMImageLoader.h"
#import "IMMediaUtil.h"          // IMReplySnippet
#import "IMMediaPlaceholder.h"
#import "UIViewController+IMToast.h"

@implementation IMChatViewController (Compose)

#pragma mark - 文本发送

- (void)sendTapped {
    NSString *text = [self.inputField.text stringByTrimmingCharactersInSet:
                      NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // 先发预览条里攒的粘贴图（≥2 张共享 group_id 成宫格）。
    if (self.pendingPasteImages.count > 0) {
        NSArray<UIImage *> *images = [self.pendingPasteImages copy];
        [self.pendingPasteImages removeAllObjects];
        [self refreshPasteBar];
        BOOL editing = self.editingMessage && self.editingMessage.convSeq > 0;
        BOOL replying = self.replyingTo.convSeq > 0;
        // 图说合并（Telegram 模型）：**恰好单张 + 有文字 + 非编辑/非引用** → 文字作为 caption 与图**同发一条**，
        // 配文 @ 一并解析随媒体上行；不再补发独立文本。多张（宫格）/编辑/引用走原有「图+文各发」路径
        //（宫格不带 caption；iOS 媒体发送不带 replyTo，引用态保持文本单发以免丢引用）。
        if (images.count == 1 && text.length > 0 && !editing && !replying) {
            NSArray<NSString *> *mentions = self.isGroupChat ? [self resolvedMentionsInText:text] : @[];
            BOOL mentionAll = self.isGroupChat && [self resolvedMentionAllInText:text];
            [self uploadAndSendPastedImage:images.firstObject groupID:nil caption:text mentions:mentions mentionAll:mentionAll];
            self.inputField.text = @"";
            [self clearPendingMentions];
            [self updateSendButtonVisibility];
            return; // 文字已作为 caption 随图发出，不再走下面的独立文本发送
        }
        NSString *gid = images.count > 1 ? [@"alb-" stringByAppendingString:NSUUID.UUID.UUIDString] : nil;
        for (UIImage *img in images) { [self uploadAndSendPastedImage:img groupID:gid]; }
        [self updateSendButtonVisibility];
    }
    if (text.length == 0) { return; }

    // 编辑态（M4-5）：发 msg_op edit 而非新消息；内容由服务端广播回 onMsgOpApplied 更新。
    if (self.editingMessage && self.editingMessage.convSeq > 0) {
        [IMSocketManager.sharedManager editMessageInConv:(self.editingMessage.convID ?: @"")
                                           targetConvSeq:self.editingMessage.convSeq content:text];
        [self cancelEdit];
        return;
    }

    __block NSString *clientMsgID = nil;
    __weak typeof(self) weakSelf = self;
    IMSendCompletion completion = ^(BOOL success, NSError *error, int64_t convSeq) {
        [weakSelf handleSendResult:success convSeq:convSeq error:error forClientMsgID:clientMsgID];
    };
    int64_t replySeq = self.replyingTo.convSeq; // 引用回复（M4-2）：0=普通发送
    // @提及（M4-8）：按输入框里**仍留着**的 token 还原 uid（删了 token 就自动不 @ 他）。解析在 +Mention.m。
    NSArray<NSString *> *mentions = self.isGroupChat ? [self resolvedMentionsInText:text] : @[];
    BOOL mentionAll = self.isGroupChat && [self resolvedMentionAllInText:text];
    // @ 片段：位置随消息走，收端不必反查群成员表（超级群没那张表）。见 +Mention.m。
    NSArray<IMMentionSpan *> *mentionSpans = [self resolvedMentionSpansInText:text];
    // 群聊按 conv_id 路由（to 留空，服务端查成员写扩散）；单聊按对端 uid。
    clientMsgID = self.isGroupChat
        ? [IMSocketManager.sharedManager sendText:text toConv:self.convID replyToConvSeq:replySeq
                                         mentions:mentions mentionAll:mentionAll mentionSpans:mentionSpans completion:completion]
        : [IMSocketManager.sharedManager sendText:text toUser:self.peerID replyToConvSeq:replySeq completion:completion];

    IMMessageModel *m = [IMMessageModel new];
    m.clientMsgID = clientMsgID;
    m.convID = self.convID;
    m.to = self.peerID;
    m.content = text;
    m.from = self.userID;
    m.contentType = @"text";
    m.status = IMMessageStatusSending;
    // 本端回显也要带上 @ 信息：不带的话自己发的那条在 ack 回来前不高亮，落库后重进会话也不高亮。
    m.mentions = mentions.count > 0 ? mentions : nil;
    m.mentionAll = mentionAll;
    m.mentionSpans = mentionSpans.count > 0 ? mentionSpans : nil;
    m.timestamp = IMNowMillis(); // 本地时间，气泡尾巴即时显示时间（与 Web 一致）
    if (replySeq > 0) { // 本端即时快照（服务端会给收件方冻结权威快照；媒体用 [图片]/[视频] 占位）
        m.replyToConvSeq = replySeq;
        m.replySnapshot = IMReplySnippet(self.replyingTo);
        m.replyToFrom = self.replyingTo.from; // 被引用者 uid：本端回显需自带（服务端只发给收件方，ack 不回带、sync 已去重）
    }
    [self performDatabaseOperation:^(IMDatabase *database) {
        [database saveMessage:m]; // 落库（sending）
    }];
    [self.windowState.messages addObject:m];
    self.inputField.text = @"";
    [self clearPendingMentions]; // 发出即清，下一条重新累积（M4-8）
    [self updateSendButtonVisibility];
    [self cancelReply];
    [self appendReloadAndScroll];
}

#pragma mark - 引用回复（M4-2）

/// 构建引用/编辑预览条（两行版）。由 IMChatViewController 主构造调用；放在此 category 与引用行为同处。
/// 布局：左竖条 + 36×36 缩略图/类型图标槽 + 上行「回复X」下行内容摘要 + 右侧独立锚定的取消 ✕。
/// 条身挂 tap（跳原消息）与下滑手势（收起）。外层 leading/trailing/bottom/height 约束在主构造里随其它栏一起排。
- (void)buildReplyBar {
    self.replyBar = [UIView new];
    self.replyBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.replyBar.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.replyBar.clipsToBounds = YES;
    [self.view addSubview:self.replyBar];
    [self.replyBar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(replyBarTapped)]];
    UISwipeGestureRecognizer *replyDismiss = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(cancelReply)];
    replyDismiss.direction = UISwipeGestureRecognizerDirectionDown;
    [self.replyBar addGestureRecognizer:replyDismiss];

    UIView *replyStripe = [UIView new];
    replyStripe.translatesAutoresizingMaskIntoConstraints = NO;
    replyStripe.backgroundColor = IMTheme.accent;
    replyStripe.layer.cornerRadius = 1.5;
    [self.replyBar addSubview:replyStripe];
    self.replyThumb = [UIImageView new];
    self.replyThumb.translatesAutoresizingMaskIntoConstraints = NO;
    self.replyThumb.contentMode = UIViewContentModeScaleAspectFill;
    self.replyThumb.clipsToBounds = YES;
    self.replyThumb.layer.cornerRadius = 4;
    self.replyThumb.hidden = YES;
    [self.replyBar addSubview:self.replyThumb];

    self.replyTitleLabel = [UILabel new];
    self.replyTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.replyTitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.replyTitleLabel.textColor = IMTheme.accent;
    self.replyTitleLabel.numberOfLines = 1;
    [self.replyTitleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    self.replySnippetLabel = [UILabel new];
    self.replySnippetLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.replySnippetLabel.font = [UIFont systemFontOfSize:13];
    self.replySnippetLabel.textColor = UIColor.secondaryLabelColor;
    self.replySnippetLabel.numberOfLines = 1;
    [self.replySnippetLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *replyText = [[UIStackView alloc] initWithArrangedSubviews:@[self.replyTitleLabel, self.replySnippetLabel]];
    replyText.translatesAutoresizingMaskIntoConstraints = NO;
    replyText.axis = UILayoutConstraintAxisVertical;
    replyText.alignment = UIStackViewAlignmentLeading;
    replyText.spacing = 2;
    [self.replyBar addSubview:replyText];

    UIButton *replyCancel = [UIButton buttonWithType:UIButtonTypeSystem];
    replyCancel.translatesAutoresizingMaskIntoConstraints = NO;
    [replyCancel setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    replyCancel.tintColor = UIColor.tertiaryLabelColor;
    [replyCancel addTarget:self action:@selector(cancelReply) forControlEvents:UIControlEventTouchUpInside];
    // ✕ 独立锚到条右端、优先级拉满永不让位 → 文件名再长也不会把它挤出屏幕（旧版 ✕ 位置链在 label.trailing 上是 bug 根因）。
    [replyCancel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [replyCancel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.replyBar addSubview:replyCancel];
    // 引用条收起时 height 压到 0（replyBarHeight），竖条 top(8)+bottom(-8) 若都是要求约束会与之冲突刷
    // "Unable to satisfy"。bottom 降到 999：收起时静默让开，展开时（默认高度）仍严格贴底。
    NSLayoutConstraint *stripeBottom = [replyStripe.bottomAnchor constraintEqualToAnchor:self.replyBar.bottomAnchor constant:-8];
    stripeBottom.priority = UILayoutPriorityRequired - 1;
    [NSLayoutConstraint activateConstraints:@[
        [replyStripe.leadingAnchor constraintEqualToAnchor:self.replyBar.leadingAnchor constant:12],
        [replyStripe.widthAnchor constraintEqualToConstant:3],
        [replyStripe.topAnchor constraintEqualToAnchor:self.replyBar.topAnchor constant:8],
        stripeBottom,
        [self.replyThumb.leadingAnchor constraintEqualToAnchor:replyStripe.trailingAnchor constant:8],
        [self.replyThumb.centerYAnchor constraintEqualToAnchor:self.replyBar.centerYAnchor],
        [self.replyThumb.widthAnchor constraintEqualToConstant:36],
        [self.replyThumb.heightAnchor constraintEqualToConstant:36],
        [replyText.centerYAnchor constraintEqualToAnchor:self.replyBar.centerYAnchor],
        // 文本堆只给「上限」到 ✕ 左侧，配合两 label 低压缩抵抗 → 内容超长时各行各自截断，绝不外推 ✕。
        [replyText.trailingAnchor constraintLessThanOrEqualToAnchor:replyCancel.leadingAnchor constant:-8],
        [replyCancel.trailingAnchor constraintEqualToAnchor:self.replyBar.trailingAnchor constant:-12],
        [replyCancel.centerYAnchor constraintEqualToAnchor:self.replyBar.centerYAnchor],
    ]];
    // 文本堆前导：无缩略图/图标时贴竖条、有则贴槽位（setReplyPreviewForMessage 切换）。
    self.replyTextLeadingNoThumb = [replyText.leadingAnchor constraintEqualToAnchor:replyStripe.trailingAnchor constant:8];
    self.replyTextLeadingThumb = [replyText.leadingAnchor constraintEqualToAnchor:self.replyThumb.trailingAnchor constant:8];
    self.replyTextLeadingNoThumb.active = YES;
}

/// 进入引用态：展开引用条显示预览，聚焦输入框。
- (void)beginReplyTo:(IMMessageModel *)message {
    self.editingMessage = nil; // 引用与编辑互斥（共用引用条）
    self.replyingTo = message;
    NSString *who = [message.from isEqualToString:self.userID] ? @"自己"
        : (self.isGroupChat ? [self senderNameForMessage:message] : (self.peerID ?: @""));
    self.replyTitleLabel.text = [NSString stringWithFormat:@"回复 %@", who];
    [self setReplyPreviewForMessage:message];
    [self setReplyBarExpanded:YES];
    [self.inputField becomeFirstResponder];
}

/// 依被引用消息类型配预览：左侧缩略图/类型图标 + 下行内容摘要（含截断策略）。
/// 图片/视频=异步缩略图；文件=doc 图标 + 中间截断文件名（保住扩展名，item B）；语音=waveform；
/// 聊天记录=列表图标；其余（文本/链接）=无图标、末尾截断。
- (void)setReplyPreviewForMessage:(IMMessageModel *)message {
    NSString *ct = message.contentType ?: @"text";
    BOOL isImage = [ct isEqualToString:@"image"];
    BOOL isVideo = [ct isEqualToString:@"video"];
    // 图说消息（带 caption）：引用预览**只显文本**（=caption，IMReplySnippet），不挂缩略图/图标——与 Web 一致，简化少出错。
    if (message.caption.length > 0 && (isImage || isVideo || [ct isEqualToString:@"file"])) {
        self.replySnippetLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.replySnippetLabel.text = IMReplySnippet(message);
        [self showReplyIconSymbol:nil];
        return;
    }
    if ([ct isEqualToString:@"file"]) {
        NSString *fn = message.fileName.length > 0 ? message.fileName : IMMediaFileName(message.content);
        self.replySnippetLabel.text = fn.length > 0 ? fn : @"[文件]";
        self.replySnippetLabel.lineBreakMode = NSLineBreakByTruncatingMiddle; // 文件名中间截断：报告…final.pdf
        // 按扩展名分型的共用文件图标（与文件气泡/详情文件行/收藏同款），而非所有文件一个 doc 图标。
        [self showReplySlotImage:IMFileTypeIconForName(fn, 30)];
        return;
    }
    self.replySnippetLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    if (isImage || isVideo) {
        self.replySnippetLabel.text = isImage ? @"图片" : @"视频";
        [self showReplyThumbForMediaMessage:message isVideo:isVideo];
    } else if ([ct isEqualToString:@"audio"]) {
        self.replySnippetLabel.text = @"语音";
        [self showReplyIconSymbol:@"waveform"];
    } else if ([ct isEqualToString:@"chat_record"]) {
        self.replySnippetLabel.text = IMReplySnippet(message);
        [self showReplyIconSymbol:@"list.bullet.rectangle"];
    } else {
        self.replySnippetLabel.text = IMReplySnippet(message);
        [self showReplyIconSymbol:nil];
    }
}

/// 媒体引用：左槽异步缩略图（门控一致 M4-7：真帧仅已下载 > thumb 磨砂 > 类型图标）。切换/取消目标后丢弃过期图防串图。
- (void)showReplyThumbForMediaMessage:(IMMessageModel *)message isVideo:(BOOL)isVideo {
    self.replyThumb.contentMode = UIViewContentModeScaleAspectFill;
    self.replyThumb.hidden = NO;
    self.replyThumb.image = nil;
    self.replyTextLeadingNoThumb.active = NO;
    self.replyTextLeadingThumb.active = YES;
    NSString *url = [self fullMediaURL:message.content];
    __weak typeof(self) ws = self;
    [IMMediaPlaceholder previewForURL:url isVideo:isVideo thumb:message.thumb completion:^(UIImage *img) {
        __strong typeof(ws) self = ws;
        if (!self || self.replyingTo != message) { return; }
        if (img) {
            self.replyThumb.contentMode = UIViewContentModeScaleAspectFill;
            self.replyThumb.image = img;
        } else { // 取不到帧/缩略 → 退化成媒体类型图标居中显示
            self.replyThumb.contentMode = UIViewContentModeCenter;
            self.replyThumb.image = [[UIImage systemImageNamed:(isVideo ? @"video.fill" : @"photo.fill")]
                imageWithTintColor:IMTheme.textSecondary renderingMode:UIImageRenderingModeAlwaysOriginal];
        }
    }];
}

/// 左槽放一张已渲染好的图（居中，如文件类型图标）。image=nil → 隐藏槽位、文本堆贴竖条（纯文本/编辑态）。
- (void)showReplySlotImage:(nullable UIImage *)image {
    if (!image) {
        self.replyThumb.hidden = YES;
        self.replyThumb.image = nil;
        self.replyTextLeadingThumb.active = NO;
        self.replyTextLeadingNoThumb.active = YES;
        return;
    }
    self.replyThumb.contentMode = UIViewContentModeCenter;
    self.replyThumb.image = image;
    self.replyThumb.hidden = NO;
    self.replyTextLeadingNoThumb.active = NO;
    self.replyTextLeadingThumb.active = YES;
}

/// 非媒体、非文件引用：左槽显示类型 SF 图标（语音/聊天记录）。symbol=nil → 隐藏槽位。
- (void)showReplyIconSymbol:(nullable NSString *)symbol {
    if (symbol.length == 0) { [self showReplySlotImage:nil]; return; }
    [self showReplySlotImage:[[UIImage systemImageNamed:symbol
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular]]
        imageWithTintColor:IMTheme.textSecondary renderingMode:UIImageRenderingModeAlwaysOriginal]];
}

/// 展开/收起引用条（动画，item F）；高度 0↔54（两行）。
- (void)setReplyBarExpanded:(BOOL)expanded {
    CGFloat h = expanded ? 54 : 0;
    if (self.replyBarHeight.constant == h) { return; }
    self.replyBarHeight.constant = h;
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{ [self.view layoutIfNeeded]; } completion:nil];
}

/// 点引用条 → 跳到被引用 / 正在编辑的原消息并高亮一闪（item A）。✕ 按钮自身吃点击，不会误触。
- (void)replyBarTapped {
    IMMessageModel *target = self.replyingTo ?: self.editingMessage;
    if (target.convSeq > 0) { [self jumpToConvSeq:target.convSeq]; }
}

/// 退出引用态（或编辑态，引用条为二者共用）：收起条。
- (void)cancelReply {
    if (self.editingMessage) { [self cancelEdit]; return; }
    self.replyingTo = nil;
    [self setReplyBarExpanded:NO];
    self.replyTitleLabel.text = nil;
    self.replySnippetLabel.text = nil;
    [self showReplyIconSymbol:nil];
}

#pragma mark - 收藏（M4-4）

/// 收藏一条消息（内容快照到服务端，原消息撤回/删除后仍在）。
- (void)favoriteMessage:(IMMessageModel *)message {
    if (message.content.length == 0) { return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    [IMHTTPService.sharedService addFavoriteWithToken:token contentType:(message.contentType ?: @"text")
                                              content:message.content caption:message.caption
                                             fileName:message.fileName fileSize:message.fileSize
                                             duration:message.duration waveform:message.waveform thumb:message.thumb poster:message.poster
                                               mediaW:message.mediaW mediaH:message.mediaH
                                         sourceConvID:message.convID
                                        sourceConvSeq:message.convSeq sourceFrom:(message.from ?: @"")
                                           completion:^(NSError *error) {
        // toast 吐在当前可见页（从全屏媒体库的查看器收藏时，本页不可见，吐在自己身上等于没提示）。
        [UIViewController im_showGlobalToast:error ? [NSString stringWithFormat:@"收藏失败：%@", error.localizedDescription] : @"已收藏"];
    }];
}

#pragma mark - 编辑 / 翻译（M4-5）

/// 进入编辑态：引用条复用为"编辑消息"预览，输入框回填原文。
- (void)beginEditMessage:(IMMessageModel *)message {
    self.replyingTo = nil;
    self.editingMessage = message;
    [self showReplyIconSymbol:nil]; // 编辑仅文本，无图标
    self.replyTitleLabel.text = @"编辑消息";
    self.replySnippetLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.replySnippetLabel.text = message.content.length > 60
        ? [[message.content substringToIndex:60] stringByAppendingString:@"…"] : (message.content ?: @"");
    [self setReplyBarExpanded:YES];
    self.inputField.text = message.content;
    [self updateSendButtonVisibility];
    [self.inputField becomeFirstResponder];
}

/// 退出编辑态。
- (void)cancelEdit {
    self.editingMessage = nil;
    [self setReplyBarExpanded:NO];
    self.replyTitleLabel.text = nil;
    self.replySnippetLabel.text = nil;
    self.inputField.text = @"";
    [self updateSendButtonVisibility];
}

/// 翻译一条消息：调服务端翻译，译文挂气泡下方（内存态）。
- (void)translateMessage:(IMMessageModel *)message {
    if (message.content.length == 0) { return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService translateWithToken:token text:message.content targetLang:@"zh"
                                         completion:^(NSString *translation, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) { [self im_showToast:[NSString stringWithFormat:@"翻译失败：%@", error.localizedDescription]]; return; }
        message.translation = translation;
        [self.tableView reloadData];
    }];
}

@end
