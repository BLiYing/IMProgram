#import "IMChatRecordCell.h"
#import "IMMessageModel.h"
#import "IMMediaUtil.h"
#import "UILabel+IMAvatar.h"
#import "IMTheme.h"

static void IMParseChatRecord(NSString *content, NSString **outTitle, NSArray<NSString *> **outLines) {
    *outTitle = @"聊天记录"; *outLines = @[];
    NSData *d = [content dataUsingEncoding:NSUTF8StringEncoding];
    if (!d) { return; }
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
    if (![dict isKindOfClass:NSDictionary.class]) { return; }
    if ([dict[@"t"] isKindOfClass:NSString.class]) { *outTitle = dict[@"t"]; }
    NSArray *items = [dict[@"items"] isKindOfClass:NSArray.class] ? dict[@"items"] : @[];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSDictionary *it in items) {
        if (![it isKindOfClass:NSDictionary.class]) { continue; }
        NSString *n = [it[@"n"] isKindOfClass:NSString.class] ? it[@"n"] : @"";
        NSString *ct = [it[@"ct"] isKindOfClass:NSString.class] ? it[@"ct"] : @"text";
        NSString *c = [it[@"c"] isKindOfClass:NSString.class] ? it[@"c"] : @"";
        // 文件行带原始文件名（新记录读 fn 字段；老记录从 URL 反推 <随机>__<原名>，与 Web 同逻辑）。
        NSString *fn = [it[@"fn"] isKindOfClass:NSString.class] ? it[@"fn"] : IMMediaFileName(c);
        NSString *preview = [ct isEqualToString:@"image"] ? @"[图片]"
            : [ct isEqualToString:@"video"] ? @"[视频]"
            : [ct isEqualToString:@"file"] ? (fn.length > 0 ? [@"[文件] " stringByAppendingString:fn] : @"[文件]") : c;
        [lines addObject:[NSString stringWithFormat:@"%@: %@", n, preview]];
        if (lines.count >= 4) { break; }
    }
    *outLines = lines;
}

/// 合并转发消息气泡：卡片（标题 + 前几条预览 + 「聊天记录」脚注），点击进详情页。
@implementation IMChatRecordCell {
    UIView  *_card;
    UILabel *_title;
    UILabel *_preview;
    UILabel *_footer;
    NSLayoutConstraint *_leading;
    NSLayoutConstraint *_trailing;
    UILabel *_senderLabel;         // 群聊对方消息：发送者昵称（连续段首条显示，主色小字，卡片上方）
    UILabel *_avatar;              // 群聊对方消息：头像（连续段末条显示，贴卡片底左侧）
    NSLayoutConstraint *_cardTop;          // 无昵称：卡片贴 cell 顶
    NSLayoutConstraint *_cardTopUnderName; // 有昵称：卡片接昵称底
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

        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textColor = UIColor.whiteColor;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _avatar.layer.cornerRadius = 15;
        _avatar.layer.masksToBounds = YES;
        _avatar.hidden = YES;
        _avatar.userInteractionEnabled = YES; // 点头像 → 进该成员资料页（onAvatarTap，微信式）
        [_avatar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(avatarTapped)]];
        [self.contentView addSubview:_avatar];

        _leading = [_card.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12];
        _trailing = [_card.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
        // 卡片顶：无昵称贴 cell 顶，有昵称接昵称底（群聊连续段首条）——二选一。
        _cardTop = [_card.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:3];
        _cardTopUnderName = [_card.topAnchor constraintEqualToAnchor:_senderLabel.bottomAnchor constant:4];
        _cardTop.active = YES;
        [NSLayoutConstraint activateConstraints:@[
            [_card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3],
            [_card.widthAnchor constraintEqualToConstant:240],
            // 昵称：顶贴 cell、左对齐卡片（卡片左移时随之右移）。
            [_senderLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
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
    NSString *title; NSArray<NSString *> *lines;
    IMParseChatRecord(message.content, &title, &lines);
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
- (void)avatarTapped { if (_onAvatarTap) { _onAvatarTap(); } }
- (void)prepareForReuse {
    [super prepareForReuse];
    _onTap = nil; _onAvatarTap = nil;
    _senderLabel.hidden = YES; _senderLabel.text = nil;
    _avatar.hidden = YES; _leading.constant = 12;
}
- (UIView *)previewTargetView { return _card; }

@end
