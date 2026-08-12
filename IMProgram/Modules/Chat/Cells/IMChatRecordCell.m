#import "IMChatRecordCell.h"
#import "IMMessageModel.h"
#import "IMMediaUtil.h"
#import "IMRejectNoteView.h"
#import "UILabel+IMAvatar.h"
#import "IMTheme.h"

// 预览/标题解析统一走 IMMediaUtil 的 IMSummarizeRecord/IMRecordItemPreview（含嵌套 chat_record→[聊天记录] 子标题），
// 与详情页共用同一 token 映射，避免各持 static 分叉。

/// 合并转发消息气泡：卡片（标题 + 前几条预览 + 「聊天记录」脚注），点击进详情页。
@implementation IMChatRecordCell {
    UIView  *_card;
    UILabel *_title;
    UILabel *_preview;
    UILabel *_footer;
    NSLayoutConstraint *_leading;
    NSLayoutConstraint *_trailing;
    UILabel *_senderLabel;         // 群聊对方消息：发送者昵称（连续段首条显示，主色小字，卡片上方）
    // _avatar 由 IMMessageCell 基类持有（贴卡片底左侧，约束在本类补）。
    NSLayoutConstraint *_cardTop;          // 无昵称：卡片贴 cell 顶
    NSLayoutConstraint *_cardTopUnderName; // 有昵称：卡片接昵称底
    IMRejectNoteView *_sysNote;            // 被拒收系统行（卡片下方居中；可恢复时带「发送好友申请」）——与三类气泡共用组件
    NSLayoutConstraint *_cardBottom;       // 无系统行：卡片贴 cell 底
    NSLayoutConstraint *_noteTop;          // 有系统行：系统行接卡片底
    NSLayoutConstraint *_noteBottom;       // 有系统行：系统行贴 cell 底
    // _unreadDivider / _unreadDividerHeight 由 IMMessageCell 基类持有。
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _card = [UIView new];
        _card.translatesAutoresizingMaskIntoConstraints = NO;
        _card.backgroundColor = IMTheme.surface;
        _card.layer.cornerRadius = IMTheme.radiusBubble;
        _card.userInteractionEnabled = YES;
        [_card addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
        [self.contentView addSubview:_card];

        _title = [UILabel new];
        _title.translatesAutoresizingMaskIntoConstraints = NO;
        _title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _title.textColor = IMTheme.textPrimary;
        _title.numberOfLines = 1;
        [_card addSubview:_title];

        _preview = [UILabel new];
        _preview.translatesAutoresizingMaskIntoConstraints = NO;
        _preview.font = [UIFont systemFontOfSize:12];
        _preview.textColor = IMTheme.textSecondary;
        _preview.numberOfLines = 3;
        [_card addSubview:_preview];

        UIView *sep = [UIView new];
        sep.translatesAutoresizingMaskIntoConstraints = NO;
        sep.backgroundColor = UIColor.separatorColor;
        [_card addSubview:sep];

        _footer = [UILabel new];
        _footer.translatesAutoresizingMaskIntoConstraints = NO;
        _footer.font = [UIFont systemFontOfSize:11];
        _footer.textColor = IMTheme.textSecondary;
        _footer.text = @"聊天记录";
        [_card addSubview:_footer];

        // 群聊对方消息（与 IMBubbleCell/IMImageCell/IMLinkCardCell 一致）：昵称在卡片上方、头像贴卡片底左侧。
        _senderLabel = [UILabel new];
        _senderLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _senderLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _senderLabel.textColor = IMTheme.accent;
        _senderLabel.hidden = YES;
        [self.contentView addSubview:_senderLabel];

        // _avatar 由 IMMessageCell 基类创建（视图 + 点击插桩）；本类只补它的 leading/bottom/size 约束。

        // 被拒收系统行（卡片下方，与 IMBubble/IMImage/IMAlbum 共用组件）：有 note 时接卡片底，否则隐藏、卡片直接贴 cell 底。
        _sysNote = [IMRejectNoteView new];
        _sysNote.translatesAutoresizingMaskIntoConstraints = NO;
        _sysNote.hidden = YES;
        __weak typeof(self) wsNote = self;
        _sysNote.onActionTap = ^{ if (wsNote.onNoteActionTap) { wsNote.onNoteActionTap(); } };
        [self.contentView addSubview:_sysNote];

        _leading = [_card.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12];
        _trailing = [_card.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
        // _unreadDivider 由 IMMessageCell 基类创建并自锚（顶/左/右 + 高 0）；本类把卡片顶改锚它的 bottom。
        // 卡片顶：无昵称贴分割线底，有昵称接昵称底（群聊连续段首条）——二选一。
        _cardTop = [_card.topAnchor constraintEqualToAnchor:_unreadDivider.bottomAnchor constant:3];
        _cardTopUnderName = [_card.topAnchor constraintEqualToAnchor:_senderLabel.bottomAnchor constant:4];
        _cardTop.active = YES;
        // 卡片底 vs 系统行：默认卡片贴 cell 底；有系统行时改由系统行贴底、卡片接系统行顶（configure 中切换）。
        _cardBottom = [_card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3];
        _noteTop = [_sysNote.topAnchor constraintEqualToAnchor:_card.bottomAnchor constant:4];
        _noteBottom = [_sysNote.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6];
        _cardBottom.active = YES;
        [NSLayoutConstraint activateConstraints:@[
            [_sysNote.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor],
            [_sysNote.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor],
            [_card.widthAnchor constraintEqualToConstant:240],
            // 昵称：顶贴 cell、左对齐卡片（卡片左移时随之右移）。
            [_senderLabel.topAnchor constraintEqualToAnchor:_unreadDivider.bottomAnchor constant:4],
            [_senderLabel.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:2],
            [_senderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            // 头像：30×30 贴 cell 左、底对齐卡片底（连续段末条才 show）。
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_avatar.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:30],
            [_avatar.heightAnchor constraintEqualToConstant:30],
            [_title.topAnchor constraintEqualToAnchor:_card.topAnchor constant:10],
            [_title.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:12],
            [_title.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-12],
            [_preview.topAnchor constraintEqualToAnchor:_title.bottomAnchor constant:6],
            [_preview.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:12],
            [_preview.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-12],
            [sep.topAnchor constraintEqualToAnchor:_preview.bottomAnchor constant:8],
            [sep.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:12],
            [sep.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-12],
            [sep.heightAnchor constraintEqualToConstant:0.5],
            [_footer.topAnchor constraintEqualToAnchor:sep.bottomAnchor constant:6],
            [_footer.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:12],
            [_footer.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor constant:-8],
        ]];
    }
    return self;
}
- (void)configureWithMessage:(IMMessageModel *)message mine:(BOOL)mine
                  senderName:(NSString *)senderName {
    _card.layer.cornerRadius = IMTheme.radiusBubble;
    _title.font = [UIFont systemFontOfSize:MAX(14, IMTheme.chatFontSize - 2) weight:UIFontWeightSemibold];
    _preview.font = [UIFont systemFontOfSize:MAX(12, IMTheme.chatFontSize - 5)];
    NSString *title = nil; NSArray<NSString *> *lines = nil;
    IMSummarizeRecord(message.content, &title, &lines, 4);   // 卡片显前 4 行预览
    _title.text = title;
    _preview.text = [lines componentsJoinedByString:@"\n"];
    _leading.active = !mine;
    _trailing.active = mine;
    // 群聊对方消息昵称（连续段首条）：显示时卡片接昵称底，否则贴 cell 顶。
    BOOL showName = senderName.length > 0;
    _senderLabel.font = [UIFont systemFontOfSize:MAX(12, IMTheme.chatFontSize - 4) weight:UIFontWeightSemibold];
    _senderLabel.text = senderName;
    _senderLabel.hidden = !showName;
    _cardTop.active = !showName;
    _cardTopUnderName.active = showName;
    // 被拒收系统行（如非好友 200103 / 内容过大 300001）：有 note 时卡片改接系统行、系统行贴 cell 底。
    [_sysNote configureWithNote:message.note code:message.noteCode];
    BOOL hasNote = _sysNote.hasContent;
    _sysNote.hidden = !hasNote;
    _cardBottom.active = !hasNote;
    _noteTop.active = hasNote;
    _noteBottom.active = hasNote;
}
- (void)applyGroupAvatarURL:(NSString *)url seed:(NSString *)seed name:(NSString *)name
                 showAvatar:(BOOL)showAvatar gutter:(BOOL)gutter {
    _leading.constant = gutter ? 48 : 12;   // 对方群消息留 30 头像列（12 + 30 + 6），与其他 cell 一致
    if (gutter && showAvatar) {
        _avatar.hidden = NO;
        [_avatar im_setAvatarURL:url seed:seed displayName:name];
    } else {
        _avatar.hidden = YES;
    }
}
- (void)tapped { if (_onTap) { _onTap(); } }
// avatarTapped/handleAvatarTap、applyUnreadDivider: 由 IMMessageCell 基类提供。

- (void)prepareForReuse {
    [super prepareForReuse];
    _onTap = nil; _onNoteActionTap = nil;
    // onAvatarTap / 头像与分割线的复位由 IMMessageCell 基类 prepareForReuse 统一处理。
    _senderLabel.hidden = YES; _senderLabel.text = nil;
    _avatar.hidden = YES; _leading.constant = 12;
}
- (UIView *)previewTargetView { return _card; }

@end
