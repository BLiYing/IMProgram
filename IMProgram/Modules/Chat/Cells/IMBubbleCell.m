#import "IMBubbleCell.h"
#import "IMMessageModel.h"
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMediaUtil.h"
#import "UILabel+IMAvatar.h"
#import "IMAppearance.h"
#import "IMTheme.h"

static NSString *IMLocalizeSnippet(NSString *snap) {
    if ([snap isEqualToString:@"[image]"]) { return @"[图片]"; }
    if ([snap isEqualToString:@"[video]"]) { return @"[视频]"; }
    if ([snap isEqualToString:@"[file]"])  { return @"[文件]"; }
    return snap ?: @"";
}

/// 文件名/纯 URL 判定统一走 IMMediaUtil（聊天/收藏/记录共用），此处保留短别名以少改调用点。
#define IMFileNameFromContent(c) IMMediaFileName(c)
#define IMLooksLikeURL(s) IMMediaLooksLikeURL(s)

/// 若快照是媒体占位（[图片]/[视频]/[文件]），返回对应 SF Symbol 名做内嵌小图标；否则 nil。
static NSString *IMMediaGlyphForSnippet(NSString *snap) {
    if ([snap isEqualToString:@"[图片]"]) { return @"photo"; }
    if ([snap isEqualToString:@"[视频]"]) { return @"video"; }
    if ([snap isEqualToString:@"[文件]"]) { return @"doc"; }
    return nil;
}

/// 方形缩略图（aspect fill + 圆角），用于引用条内嵌真图（#4）。
static UIImage *IMSquareThumb(UIImage *src, CGFloat side) {
    if (!src) { return nil; }
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = UIScreen.mainScreen.scale;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:fmt];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:4] addClip];
        CGFloat w = src.size.width, h = src.size.height;
        if (w <= 0 || h <= 0) { return; }
        CGFloat k = MAX(side / w, side / h); // aspect fill
        CGRect dst = CGRectMake((side - w * k) / 2, (side - h * k) / 2, w * k, h * k);
        [src drawInRect:dst];
    }];
}

@implementation IMBubbleCell {
    UIView  *_datePill;       // 日期分隔胶囊（居中浮于壁纸上）
    UILabel *_dateLabel;
    NSLayoutConstraint *_datePillTop;
    NSLayoutConstraint *_datePillHeight;
    UILabel *_divider;        // 「未读消息」分割线
    NSLayoutConstraint *_dividerHeight;
    UIView *_bubble;
    UILabel *_text;
    NSLayoutConstraint *_leading;
    NSLayoutConstraint *_trailing;
    UILabel *_failBadge;      // 发送失败：气泡左侧红色❗（微信式）
    UILabel *_sysNote;        // 被拒收等系统提示：气泡下方居中灰字
    NSLayoutConstraint *_bubbleBottom;   // 无系统行时：气泡贴 cell 底
    NSLayoutConstraint *_noteTop;        // 有系统行时：系统行接气泡底
    NSLayoutConstraint *_noteBottom;     // 有系统行时：系统行贴 cell 底
    NSLayoutConstraint *_failBadgeTrailing;
    NSMutableAttributedString *_bodyText;  // 当前富文本（引用缩略图异步到达后就地更新重渲，#4）
    NSTextAttachment *_quoteThumbAtt;      // 引用媒体缩略图占位 attachment
    NSString *_quoteThumbKey;              // 复用防串图：URL 匹配才应用
    UILabel *_avatar;                      // 群聊对方头像（连续段末条，贴气泡底左侧）
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.clearColor;

        _datePill = [UIView new];
        _datePill.translatesAutoresizingMaskIntoConstraints = NO;
        _datePill.backgroundColor = IMTheme.datePillBg;
        _datePill.layer.cornerRadius = 12;
        _datePill.layer.masksToBounds = YES;
        [self.contentView addSubview:_datePill];

        _dateLabel = [UILabel new];
        _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _dateLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _dateLabel.textColor = IMTheme.datePillText;
        _dateLabel.textAlignment = NSTextAlignmentCenter;
        [_datePill addSubview:_dateLabel];

        _divider = [UILabel new];
        _divider.translatesAutoresizingMaskIntoConstraints = NO;
        _divider.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _divider.textColor = IMTheme.textSecondary;
        _divider.textAlignment = NSTextAlignmentCenter;
        _divider.text = @"未读消息";
        _divider.clipsToBounds = YES;
        [self.contentView addSubview:_divider];

        _bubble = [UIView new];
        _bubble.translatesAutoresizingMaskIntoConstraints = NO;
        _bubble.layer.cornerRadius = IMAppearance.shared.bubbleRadius;
        _bubble.layer.masksToBounds = YES;
        [self.contentView addSubview:_bubble];

        _text = [UILabel new];
        _text.translatesAutoresizingMaskIntoConstraints = NO;
        _text.numberOfLines = 0;
        _text.font = [UIFont systemFontOfSize:IMTheme.chatFontSize];
        [_bubble addSubview:_text];

        _failBadge = [UILabel new];
        _failBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _failBadge.text = @"!";
        _failBadge.textAlignment = NSTextAlignmentCenter;
        _failBadge.font = [UIFont boldSystemFontOfSize:13];
        _failBadge.textColor = UIColor.whiteColor;
        _failBadge.backgroundColor = UIColor.systemRedColor;
        _failBadge.layer.cornerRadius = 9;
        _failBadge.layer.masksToBounds = YES;
        _failBadge.hidden = YES;
        [self.contentView addSubview:_failBadge];

        _sysNote = [UILabel new];
        _sysNote.translatesAutoresizingMaskIntoConstraints = NO;
        _sysNote.font = [UIFont systemFontOfSize:12];
        _sysNote.textColor = IMTheme.textSecondary;
        _sysNote.textAlignment = NSTextAlignmentCenter;
        _sysNote.numberOfLines = 0;
        _sysNote.hidden = YES;
        [self.contentView addSubview:_sysNote];

        // 群聊对方头像（Telegram 式）：贴气泡底、位于左侧头像列；仅连续段末条显示。
        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textColor = UIColor.whiteColor;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _avatar.layer.cornerRadius = 15;
        _avatar.layer.masksToBounds = YES;
        _avatar.hidden = YES;
        [self.contentView addSubview:_avatar];

        _leading = [_bubble.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12];
        _trailing = [_bubble.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
        _datePillTop = [_datePill.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:0];
        _datePillHeight = [_datePill.heightAnchor constraintEqualToConstant:0];
        _dividerHeight = [_divider.heightAnchor constraintEqualToConstant:0];
        [NSLayoutConstraint activateConstraints:@[
            _datePillTop,
            [_datePill.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            _datePillHeight,
            [_dateLabel.leadingAnchor constraintEqualToAnchor:_datePill.leadingAnchor constant:12],
            [_dateLabel.trailingAnchor constraintEqualToAnchor:_datePill.trailingAnchor constant:-12],
            [_dateLabel.centerYAnchor constraintEqualToAnchor:_datePill.centerYAnchor],

            [_divider.topAnchor constraintEqualToAnchor:_datePill.bottomAnchor],
            [_divider.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_divider.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            _dividerHeight,

            [_bubble.topAnchor constraintEqualToAnchor:_divider.bottomAnchor constant:2],
            [_bubble.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.75],

            // 红❗：钉在气泡左侧、垂直居中（仅自己失败时显示）。
            [_failBadge.widthAnchor constraintEqualToConstant:18],
            [_failBadge.heightAnchor constraintEqualToConstant:18],
            [_failBadge.centerYAnchor constraintEqualToAnchor:_bubble.centerYAnchor],

            // 系统行：横跨内容区居中。
            [_sysNote.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:24],
            [_sysNote.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-24],

            // 气泡内文本：时间+✓/✓✓ 作为小字尾巴拼进同一段富文本（不再用独立 label 叠加+空格占位，
            // 那种做法短消息时气泡不为尾随空格变宽→ meta 溢出圆角裁剪而看不见。现在 meta 一定随文本渲染）。
            [_text.topAnchor constraintEqualToAnchor:_bubble.topAnchor constant:6],
            [_text.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:12],
            [_text.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-12],
            [_text.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:-6],

            // 头像：30×30 贴 cell 左、底对齐气泡底（连续段末条才 show）。
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_avatar.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:30],
            [_avatar.heightAnchor constraintEqualToConstant:30],
        ]];

        // 可切换约束：无系统行→气泡贴 cell 底；有系统行→气泡接系统行、系统行贴底。
        _bubbleBottom = [_bubble.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3];
        _noteTop = [_sysNote.topAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:4];
        _noteBottom = [_sysNote.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6];
        _failBadgeTrailing = [_failBadge.trailingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:-6];
        _bubbleBottom.active = YES;
    }
    return self;
}

- (void)configureWithMessage:(IMMessageModel *)message
                        mine:(BOOL)mine
                 peerReadSeq:(int64_t)peerReadSeq
                   dayHeader:(NSString *)dayHeader
          showsUnreadDivider:(BOOL)showsDivider
                  senderName:(NSString *)senderName
               replyThumbURL:(NSString *)replyThumbURL
          replyThumbIsVideo:(BOOL)replyThumbIsVideo {
    BOOL showsDate = dayHeader.length > 0;
    _datePill.hidden = !showsDate;
    _dateLabel.text = dayHeader;
    _datePillHeight.constant = showsDate ? 24 : 0;
    _datePillTop.constant = showsDate ? 8 : 0;

    _divider.hidden = !showsDivider;
    _dividerHeight.constant = showsDivider ? 28 : 0;

    _bubble.backgroundColor = mine ? IMTheme.bubbleMe : IMTheme.bubbleThem;
    _bubble.layer.cornerRadius = IMAppearance.shared.bubbleRadius;
    _text.font = [UIFont systemFontOfSize:IMTheme.chatFontSize];
    // 正文 + 小字尾巴（时间/✓/✓✓）拼成一段富文本，保证状态一定随气泡渲染。
    NSMutableAttributedString *body = [NSMutableAttributedString new];
    // 群聊：对方气泡顶部一行发送者昵称（主色小字，Telegram 式）。名字段落加 paragraphSpacing 与正文留间距。
    if (senderName.length > 0) {
        NSMutableParagraphStyle *nameStyle = [NSMutableParagraphStyle new];
        nameStyle.paragraphSpacing = 3;
        [body appendAttributedString:[[NSAttributedString alloc]
            initWithString:[senderName stringByAppendingString:@"\n"]
                attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold],
                              NSForegroundColorAttributeName: IMTheme.accent,
                              NSParagraphStyleAttributeName: nameStyle }]];
    }
    // 转发溯源（M4-3）：气泡顶部一行"转发自 X"小灰字。
    if (message.forwardFrom.length > 0) {
        [body appendAttributedString:[[NSAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"转发自 %@\n", message.forwardFrom]
                attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:12],
                              NSForegroundColorAttributeName: IMTheme.textSecondary }]];
    }
    // 引用回复（M4-2）：气泡顶部一条引用预览（竖条 + 灰字快照），点击整条气泡跳转原消息。
    // 引用的是图片/视频时优先内嵌"真缩略图"（异步加载，#4）；拿不到或文件类型则退回小图标。
    _quoteThumbAtt = nil;
    _quoteThumbKey = nil;
    if (message.replyToConvSeq > 0) {
        NSString *raw = message.replySnapshot.length > 0 ? message.replySnapshot : @"原消息";
        NSString *snap = IMLocalizeSnippet(raw);
        NSDictionary *quoteAttr = @{ NSFontAttributeName: [UIFont systemFontOfSize:13],
                                     NSForegroundColorAttributeName: IMTheme.textSecondary };
        [body appendAttributedString:[[NSAttributedString alloc] initWithString:@"▏" attributes:quoteAttr]];
        NSString *glyph = IMMediaGlyphForSnippet(snap);
        BOOL fileSnippet = [snap isEqualToString:@"[文件]"];
        if (replyThumbURL.length > 0) {
            // 真缩略图：先用占位图标撑住固定 24x24 位置（行高稳定），异步图到达后原地替换重渲。
            NSTextAttachment *att = [NSTextAttachment new];
            att.image = [[UIImage systemImageNamed:(glyph ?: @"photo")] imageWithTintColor:IMTheme.textSecondary
                                                                             renderingMode:UIImageRenderingModeAlwaysOriginal];
            att.bounds = CGRectMake(0, -6, 24, 24);
            _quoteThumbAtt = att;
            _quoteThumbKey = replyThumbURL;
            [body appendAttributedString:[NSAttributedString attributedStringWithAttachment:att]];
            [body appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:quoteAttr]];
            __weak typeof(self) ws = self;
            void (^apply)(UIImage *) = ^(UIImage *img) {
                __strong typeof(ws) self = ws;
                if (!self || !img || ![self->_quoteThumbKey isEqualToString:replyThumbURL]) { return; } // 复用防串图
                self->_quoteThumbAtt.image = IMSquareThumb(img, 24);
                self->_text.attributedText = self->_bodyText; // 重新赋值触发重渲（bounds 固定，行高不变）
            };
            if (replyThumbIsVideo) { [[IMVideoThumbnailLoader shared] loadPosterForVideoURL:replyThumbURL completion:apply]; }
            else { [[IMImageLoader shared] loadImageURL:replyThumbURL completion:apply]; }
        } else if (glyph || fileSnippet) {
            NSTextAttachment *att = [NSTextAttachment new];
            att.image = fileSnippet ? IMFileTypeIconForName(nil, 18)
                                    : [[UIImage systemImageNamed:glyph] imageWithTintColor:IMTheme.textSecondary
                                                                             renderingMode:UIImageRenderingModeAlwaysOriginal];
            att.bounds = fileSnippet ? CGRectMake(0, -4, 18, 18) : CGRectMake(0, -2, 15, 13);
            [body appendAttributedString:[NSAttributedString attributedStringWithAttachment:att]];
            [body appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:quoteAttr]];
        }
        [body appendAttributedString:[[NSAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"%@\n", snap] attributes:quoteAttr]];
    }
    // 正文：文件消息 → 跨端共用的折角文件图标 + 文件名，点击整条气泡打开；
    // 纯 URL → 链接蓝+下划线（点击打开）；其余普通文本。
    NSString *contentText = message.content ?: @"";
    NSMutableDictionary *contentAttr = [@{ NSFontAttributeName: [UIFont systemFontOfSize:IMTheme.chatFontSize],
                                           NSForegroundColorAttributeName: IMTheme.textPrimary } mutableCopy];
    if ([message.contentType isEqualToString:@"file"]) {
        NSString *fname = message.fileName.length > 0 ? message.fileName : @"文件";
        UIColor *fileColor = IMTheme.accent;
        NSTextAttachment *att = [NSTextAttachment new];
        att.image = IMFileTypeIconForName(fname, 26);
        att.bounds = CGRectMake(0, -7, 26, 26);
        [body appendAttributedString:[NSAttributedString attributedStringWithAttachment:att]];
        [body appendAttributedString:[[NSAttributedString alloc] initWithString:[@"  " stringByAppendingString:fname]
            attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:IMTheme.chatFontSize], NSForegroundColorAttributeName: fileColor }]];
        NSString *sizeText = IMFormatFileSize(message.fileSize);
        if (sizeText.length > 0) {
            [body appendAttributedString:[[NSAttributedString alloc] initWithString:[@"\n" stringByAppendingString:sizeText]
                attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:12],
                              NSForegroundColorAttributeName: IMTheme.textSecondary }]];
        }
    } else {
        if (IMLooksLikeURL(contentText)) {
            contentAttr[NSForegroundColorAttributeName] = UIColor.systemBlueColor;
            contentAttr[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
        }
        [body appendAttributedString:[[NSAttributedString alloc] initWithString:contentText attributes:contentAttr]];
    }
    // 翻译（M4-5）：译文另起一行挂气泡内（灰字小字）。
    if (message.translation.length > 0) {
        [body appendAttributedString:[[NSAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"\n%@", message.translation]
                attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:14],
                              NSForegroundColorAttributeName: IMTheme.textSecondary }]];
    }
    NSAttributedString *meta = [self attributedMetaForMessage:message mine:mine peerReadSeq:peerReadSeq];
    if (meta.length > 0) {
        [body appendAttributedString:[[NSAttributedString alloc] initWithString:@"   "
            attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:11] }]]; // 与尾巴之间留点空隙
        [body appendAttributedString:meta];
    }
    _bodyText = body;
    _text.attributedText = body;

    // 发送失败：气泡左侧红❗（仅自己）；被拒收等→气泡下方居中系统行（微信式）。
    BOOL failed = mine && message.status == IMMessageStatusFailed;
    _failBadge.hidden = !failed;
    _failBadgeTrailing.active = failed;
    BOOL hasNote = message.note.length > 0;
    _sysNote.hidden = !hasNote;
    _sysNote.text = message.note;
    _bubbleBottom.active = !hasNote;
    _noteTop.active = hasNote;
    _noteBottom.active = hasNote;

    // 尾巴：自己靠右气泡的右下角不圆（成尾），对方靠左气泡的左下角不圆。
    _bubble.layer.maskedCorners = mine
        ? (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner)
        : (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner);

    _leading.active = !mine;
    _trailing.active = mine;
}

- (void)applyGroupAvatarURL:(NSString *)url seed:(NSString *)seed name:(NSString *)name
                 showAvatar:(BOOL)showAvatar gutter:(BOOL)gutter {
    _leading.constant = gutter ? 48 : 12;   // 对方群消息留 30 头像列（12 + 30 + 6）
    if (gutter && showAvatar) {
        _avatar.hidden = NO;
        [_avatar im_setAvatarURL:url seed:seed displayName:name];
    } else {
        _avatar.hidden = YES;
    }
}

/// 气泡内右下角富文本：时间(灰)；自己消息追加状态勾——已送达 ✓(灰)/已读 ✓✓(绿)/发送中/失败。
- (NSAttributedString *)attributedMetaForMessage:(IMMessageModel *)message
                                            mine:(BOOL)mine
                                     peerReadSeq:(int64_t)peerReadSeq {
    UIFont *font = [UIFont systemFontOfSize:11];
    NSString *time = [IMTheme timeStringFromMillis:message.timestamp];
    if (message.editedAt > 0) { time = [@"已编辑 " stringByAppendingString:time ?: @""]; } // M4-5
    UIColor *timeColor = IMTheme.bubbleMetaTime;
    NSDictionary *base = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: timeColor };

    if (!mine) {
        return [[NSAttributedString alloc] initWithString:time attributes:base];
    }
    if (message.status == IMMessageStatusSending) {
        return [[NSAttributedString alloc] initWithString:@"发送中…" attributes:base];
    }
    if (message.status == IMMessageStatusFailed) {
        // 被拒收（有系统行）→ 气泡内只显时间，失败由红❗+下方系统行表达；其余失败仍显"未发送 ✗"。
        if (message.note.length > 0) {
            return [[NSAttributedString alloc] initWithString:time attributes:base];
        }
        return [[NSAttributedString alloc] initWithString:@"未发送 ✗"
            attributes:@{ NSFontAttributeName: font, NSForegroundColorAttributeName: UIColor.systemRedColor }];
    }
    // 其余（Sent，或经多端抄送/同步收到的"自己消息"——其 status 为 Received）：
    // 只要拿到了 conv_seq 即视为已送达，按对端已读位点显示 ✓/✓✓。否则只显时间。
    if (message.convSeq > 0) {
        BOOL read = message.convSeq <= peerReadSeq;
        NSString *checks = read ? @"✓✓" : @"✓";
        NSString *plain = time.length > 0 ? [NSString stringWithFormat:@"%@ %@", time, checks] : checks;
        NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:plain attributes:base];
        NSRange r = [plain rangeOfString:checks options:NSBackwardsSearch];
        [s addAttribute:NSForegroundColorAttributeName value:(read ? IMTheme.checkRead : timeColor) range:r];
        return s;
    }
    return [[NSAttributedString alloc] initWithString:time attributes:base];
}

@end
