//  IMChatViewController+Mention.m
//  聊天页「@提及」分文件实现（M4-8，仅群聊）：输入 @ 弹内联成员选择卡、候选维护、发送时按
//  文本里是否仍留着 `@显示名` 复核收件人。从 IMChatViewController.m 平移，未改行为。

#import "IMChatViewController+Private.h"
#import "IMChatMessageLogic.h"   // IMChatTextContainsMentionToken
#import "IMMessageModel.h"
#import "IMDatabase.h"
#import "IMGroupInfo.h"
#import "IMMentionPickerViewController.h"
#import "IMTheme.h"

@implementation IMChatViewController (Mention)

#pragma mark - @提及（M4-8）

/// 输入框「正在输入的 @查询词」：光标前最近一个 `@` 到光标之间、且不含空白的片段。
/// 返回 nil 表示当前不在 @ 输入态。半角 `@` 与中文键盘的全角 `＠` 都认。
- (nullable NSString *)activeMentionQuery {
    NSString *text = self.inputField.text ?: @"";
    if (text.length == 0) { return nil; }
    // UITextField 单行，取光标位置；拿不到就按整串末尾算。
    NSInteger caret = (NSInteger)text.length;
    UITextRange *sel = self.inputField.selectedTextRange;
    if (sel) {
        caret = [self.inputField offsetFromPosition:self.inputField.beginningOfDocument toPosition:sel.end];
    }
    if (caret <= 0 || caret > (NSInteger)text.length) { return nil; }
    NSString *head = [text substringToIndex:(NSUInteger)caret];
    NSRange at = [head rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"@＠"]
                                       options:NSBackwardsSearch];
    if (at.location == NSNotFound) { return nil; }
    NSString *q = [head substringFromIndex:at.location + at.length];
    // @ 后出现空白即视为这次提及已结束（用户在正常打字，不该再弹卡）。
    if ([q rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) { return nil; }
    return q;
}

/// 群聊里键入 `@` 时在**输入栏上方**内联一个成员下拉面板（child VC，不弹 sheet、不遮挡输入框）。
/// 面板顶部自带搜索框并自动聚焦：焦点从聊天输入框转到搜索框（键盘不收），过滤由搜索框驱动；
/// 选中后焦点交还聊天输入框、回填 token 并移除面板。删掉 `@`/点取消/发送/退出会话都会移除面板。
- (void)maybePresentMentionPicker {
    if (!self.isGroupChat || !self.groupInfo) { [self dismissMentionPanel]; return; }
    NSString *q = [self activeMentionQuery];
    if (!q) { [self dismissMentionPanel]; return; }
    if (self.mentionPanel) {
        // 已开：聊天输入框里 @后的文字**实时驱动**面板过滤（任务1，微信/Telegram 式）。
        [self.mentionPanel updateQuery:q];
        [self updateMentionPanelHeight];
        return;
    }
    __weak typeof(self) ws = self;
    // 首次打开即按当前 @查询词过滤（刚敲下 @、后面还没字时 q 为空串 → 列表显全部成员）。
    IMMentionPickerViewController *panel = [[IMMentionPickerViewController alloc]
        initInlineWithGroup:self.groupInfo
               initialQuery:q
               onPickMember:^(IMGroupMember *m) { [ws pickMentionInsert:m.displayName uid:m.userID]; }
                  onPickAll:^{ [ws pickMentionInsert:@"所有人" uid:nil]; }];
    panel.onInlineFilterChanged = ^{ [ws updateMentionPanelHeight]; };
    panel.onInlineCancel = ^{ [ws dismissMentionPanel]; [ws.inputField becomeFirstResponder]; };
    [self addChildViewController:panel];
    panel.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:panel.view];
    // 底边贴输入区栈顶（replyBar.top）→ 浮在消息区底部、输入栏之上；键盘弹起时随约束链一起上移。
    self.mentionPanelHeight = [panel.view.heightAnchor constraintEqualToConstant:[panel preferredInlineHeight]];
    [NSLayoutConstraint activateConstraints:@[
        [panel.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [panel.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [panel.view.bottomAnchor constraintEqualToAnchor:self.replyBar.topAnchor],
        self.mentionPanelHeight,
    ]];
    [panel didMoveToParentViewController:self];
    self.mentionPanel = panel;
    // 刻意**不**聚焦搜索框：焦点留在聊天输入框，用户想搜再点搜索框（对齐用户要求）。
}

/// 面板选中某成员/@所有人：焦点先回聊天输入框（保证 caret 有效）→ 回填 token → 移除面板。
- (void)pickMentionInsert:(NSString *)displayName uid:(nullable NSString *)uid {
    [self.inputField becomeFirstResponder];
    [self insertMentionToken:displayName forUID:uid];
    [self dismissMentionPanel];
}

- (void)updateMentionPanelHeight {
    if (!self.mentionPanel || !self.mentionPanelHeight) { return; }
    self.mentionPanelHeight.constant = [self.mentionPanel preferredInlineHeight];
    [self.view layoutIfNeeded];
}

/// 移除内联 @面板（选中 / 离开 @ 输入态 / 发送 / 退出会话）。
- (void)dismissMentionPanel {
    if (!self.mentionPanel) { return; }
    IMMentionPickerViewController *p = self.mentionPanel;
    self.mentionPanel = nil;
    self.mentionPanelHeight = nil;
    [p willMoveToParentViewController:nil];
    [p.view removeFromSuperview];
    [p removeFromParentViewController];
}

/// 回填 token：把输入框里"正在输入的 @query"整体替换为 `@显示名 `（尾随空格便于继续打字）。
/// uid 为 nil 表示 @所有人。被 @ 者记入 mentionCandidates，发送时按文本里是否还留着该 token 复核。
- (void)insertMentionToken:(NSString *)displayName forUID:(nullable NSString *)uid {
    NSString *text = self.inputField.text ?: @"";
    NSInteger caret = (NSInteger)text.length;
    UITextRange *sel = self.inputField.selectedTextRange;
    if (sel) {
        caret = [self.inputField offsetFromPosition:self.inputField.beginningOfDocument toPosition:sel.end];
    }
    caret = MAX(0, MIN(caret, (NSInteger)text.length));
    NSString *head = [text substringToIndex:(NSUInteger)caret];
    NSString *after = [text substringFromIndex:(NSUInteger)caret];
    NSRange at = [head rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"@＠"]
                                       options:NSBackwardsSearch];
    // 尾随空格便于继续打字；但光标后本就以空白开头时不再补，否则会留下双空格（与 Web mention.ts 一致）。
    BOOL afterStartsBlank = after.length > 0 &&
        [NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:[after characterAtIndex:0]];
    NSString *token = [NSString stringWithFormat:@"@%@%@", displayName, afterStartsBlank ? @"" : @" "];
    NSUInteger caretAfterInsert = 0;
    if (at.location == NSNotFound) {
        self.inputField.text = [NSString stringWithFormat:@"%@%@%@", head, token, after]; // 兜底：光标处插入
        caretAfterInsert = head.length + token.length;
    } else {
        NSString *before = [text substringToIndex:at.location];
        self.inputField.text = [NSString stringWithFormat:@"%@%@%@", before, token, after];
        caretAfterInsert = before.length + token.length;
    }
    if (uid.length > 0) {
        if (!self.mentionCandidates) { self.mentionCandidates = [NSMutableDictionary dictionary]; }
        self.mentionCandidates[uid] = displayName;
    } else {
        self.mentionAllPending = YES;
    }
    [self updateSendButtonVisibility];
    [self.inputField becomeFirstResponder];
    // 光标落回 token 之后（UITextField 被程序化赋值后默认停在末尾，token 后若还有正文就错位了）。
    UITextPosition *pos = [self.inputField positionFromPosition:self.inputField.beginningOfDocument
                                                         offset:(NSInteger)caretAfterInsert];
    if (pos) { self.inputField.selectedTextRange = [self.inputField textRangeFromPosition:pos toPosition:pos]; }
}

/// 发送前把输入框文本还原成 mentions uid 列表：只保留**文本里仍存在完整 token** 的候选，
/// 用户手动删掉 token 即自动不再 @ 他（草图 §07-06）。
- (NSArray<NSString *> *)resolvedMentionsInText:(NSString *)text {
    if (self.mentionCandidates.count == 0 || text.length == 0) { return @[]; }
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    [self.mentionCandidates enumerateKeysAndObjectsUsingBlock:^(NSString *uid, NSString *name, BOOL *stop) {
        if (IMChatTextContainsMentionToken(text, name)) { [out addObject:uid]; }
    }];
    return out;
}

/// @所有人 是否仍生效：既要标记在、文本里也要还留着完整的 `@所有人` token。
/// 发送前算出 @ 片段（与 resolvedMentionsInText: 同源同规则，只是多记了每个 token 的位置）。
/// 收端有片段就不必反查群成员表——超级群不下发成员表，老路在那里对普通成员必然失效。
/// 协议见 IMServer/docs/PROTOCOL.md §4.1；与 Web 的 resolveMentionSpans 逐条对齐。
- (NSArray<IMMentionSpan *> *)resolvedMentionSpansInText:(NSString *)text {
    if (!self.isGroupChat || text.length == 0) { return @[]; }
    NSMutableDictionary<NSString *, NSString *> *nameToUID = [NSMutableDictionary dictionary];
    [self.mentionCandidates enumerateKeysAndObjectsUsingBlock:^(NSString *uid, NSString *name, BOOL *stop) {
        if (name.length > 0 && !nameToUID[name]) { nameToUID[name] = uid; }
    }];
    // 「所有人」放在成员之后覆盖：同名成员碰上字面「所有人」时以 @所有人 为准——与服务端校验一致
    //（空 uid 只在 mention_all 时合法；反过来记成员 uid 会因不在 mentions 里而被服务端丢弃）。
    if ([self resolvedMentionAllInText:text]) { nameToUID[@"所有人"] = @""; }
    return IMChatScanMentionSpans(text, nameToUID);
}

- (BOOL)resolvedMentionAllInText:(NSString *)text {
    return self.mentionAllPending && IMChatTextContainsMentionToken(text, @"所有人");
}

/// 清空本条待发的 @提及态（输入框已清空，候选表与 @所有人 标记一并复位）。
- (void)clearPendingMentions {
    [self.mentionCandidates removeAllObjects];
    self.mentionAllPending = NO;
    [self dismissMentionPanel]; // 发出后输入框已清空（编程式清空不触发 editingChanged），显式收面板
}

@end
