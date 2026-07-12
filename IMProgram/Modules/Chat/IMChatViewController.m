//  IMChatViewController.m

#import "IMChatViewController.h"
#import "IMChatBackgroundView.h"
#import "IMSocketManager.h"
#import "IMHTTPService.h"
#import "IMConversation.h"
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMediaViewerViewController.h"
#import "IMConversationMediaViewController.h"
#import "IMForwardPickerViewController.h"
#import "IMChatRecordViewController.h"
#import "IMMediaPicker.h"
#import "IMMediaUtil.h"
#import "UILabel+IMAvatar.h"
#import "IMFilePickerViewController.h"
#import "IMRecentFiles.h"
#import "IMUserCard.h"
#import "IMGroupInfo.h"
#import "IMGroupInfoViewController.h"
#import "IMProtocol.h"
#import "IMMessageModel.h"
#import "IMDatabase.h"
#import "IMMenuAction.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import "IMLog.h"
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>
#import <SafariServices/SafariServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "IMBottomSheet.h"

#pragma mark - 引用/预览媒体占位辅助（M4-2 / #5）

/// 媒体消息在「引用/预览」场景的简短占位（本地生成，用于输入预览条与本端即时快照）。
static NSString *IMReplySnippet(IMMessageModel *m) {
    if ([m.contentType isEqualToString:@"image"]) { return @"[图片]"; }
    if ([m.contentType isEqualToString:@"video"]) { return @"[视频]"; }
    if ([m.contentType isEqualToString:@"file"])  { return @"[文件]"; }
    NSString *c = m.content ?: @"";
    return c.length > 60 ? [[c substringToIndex:60] stringByAppendingString:@"…"] : c;
}

/// 把服务端冻结的英文媒体快照（[image]/[video]/[file]）本地化为中文；其余原样返回。
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

#pragma mark - 气泡 Cell（Telegram 风格：圆角气泡 + 尾巴 + 气泡内时间/双勾）

/// 私有消息气泡 Cell：自己的消息靠右（浅绿），对方靠左（白）。
/// 顶部可选「日期分隔胶囊」+「未读消息」分割线；气泡内右下角时间，自己的消息按对端已读位点显示 ✓/✓✓（已读绿）。
@interface IMBubbleCell : UITableViewCell
- (void)configureWithMessage:(IMMessageModel *)message
                        mine:(BOOL)mine
                 peerReadSeq:(int64_t)peerReadSeq
                   dayHeader:(nullable NSString *)dayHeader
          showsUnreadDivider:(BOOL)showsDivider
                  senderName:(nullable NSString *)senderName
               replyThumbURL:(nullable NSString *)replyThumbURL
          replyThumbIsVideo:(BOOL)replyThumbIsVideo;
/// 群聊 Telegram 式头像列（对方消息）：gutter=YES 时气泡右移留头像位；showAvatar=YES（连续段末条）时显示头像。
- (void)applyGroupAvatarURL:(nullable NSString *)url seed:(NSString *)seed name:(nullable NSString *)name
                 showAvatar:(BOOL)showAvatar gutter:(BOOL)gutter;
@end

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
        _bubble.layer.cornerRadius = 18;
        _bubble.layer.masksToBounds = YES;
        [self.contentView addSubview:_bubble];

        _text = [UILabel new];
        _text.translatesAutoresizingMaskIntoConstraints = NO;
        _text.numberOfLines = 0;
        _text.font = [UIFont systemFontOfSize:17];
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
        } else if (glyph) {
            NSTextAttachment *att = [NSTextAttachment new];
            att.image = [[UIImage systemImageNamed:glyph] imageWithTintColor:IMTheme.textSecondary
                                                              renderingMode:UIImageRenderingModeAlwaysOriginal];
            att.bounds = CGRectMake(0, -2, 15, 13);
            [body appendAttributedString:[NSAttributedString attributedStringWithAttachment:att]];
            [body appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:quoteAttr]];
        }
        [body appendAttributedString:[[NSAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"%@\n", snap] attributes:quoteAttr]];
    }
    // 正文：文件消息 → SF Symbol 文档图标 + 文件名（emoji 在富文本里渲染成 "?" tofu，故用符号内嵌，点击整条气泡打开）；
    // 纯 URL → 链接蓝+下划线（点击打开）；其余普通文本。
    NSString *contentText = message.content ?: @"";
    NSMutableDictionary *contentAttr = [@{ NSFontAttributeName: [UIFont systemFontOfSize:17],
                                           NSForegroundColorAttributeName: IMTheme.textPrimary } mutableCopy];
    if ([message.contentType isEqualToString:@"file"]) {
        NSString *fname = IMFileNameFromContent(message.content);
        UIColor *fileColor = UIColor.systemBlueColor;
        UIImage *icon = [UIImage systemImageNamed:IMFileGlyphForName(fname)] ?: [UIImage systemImageNamed:@"doc.fill"];
        NSTextAttachment *att = [NSTextAttachment new];
        att.image = [icon imageWithTintColor:fileColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        att.bounds = CGRectMake(0, -3, 18, 18);
        [body appendAttributedString:[NSAttributedString attributedStringWithAttachment:att]];
        [body appendAttributedString:[[NSAttributedString alloc] initWithString:[@"  " stringByAppendingString:fname]
            attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:17], NSForegroundColorAttributeName: fileColor }]];
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

#pragma mark - 系统消息 cell（content_type=system：群邀请/移除/转让/禁言等留痕，居中灰字胶囊）

@interface IMSystemCell : UITableViewCell
- (void)configureWithText:(NSString *)text;
/// 撤回留痕：胶囊文案 + 可选"重新编辑"（reeditHandler 非空时显示，点按回填输入框）。
- (void)configureWithText:(NSString *)text reeditHandler:(nullable void (^)(void))reeditHandler;
@end

@implementation IMSystemCell {
    UIView  *_pill;
    UILabel *_label;
    UIButton *_reeditButton;
    void (^_reeditHandler)(void);
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _pill = [UIView new];
        _pill.translatesAutoresizingMaskIntoConstraints = NO;
        _pill.backgroundColor = IMTheme.datePillBg;
        _pill.layer.cornerRadius = 11;
        _pill.layer.masksToBounds = YES;
        [self.contentView addSubview:_pill];
        _label = [UILabel new];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = [UIFont systemFontOfSize:12];
        _label.textColor = IMTheme.datePillText;
        _label.textAlignment = NSTextAlignmentCenter;
        _label.numberOfLines = 0;
        [_pill addSubview:_label];
        [NSLayoutConstraint activateConstraints:@[
            [_pill.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [_pill.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],
            [_pill.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_pill.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:40],
            [_pill.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-40],
            [_label.topAnchor constraintEqualToAnchor:_pill.topAnchor constant:4],
            [_label.bottomAnchor constraintEqualToAnchor:_pill.bottomAnchor constant:-4],
            [_label.leadingAnchor constraintEqualToAnchor:_pill.leadingAnchor constant:10],
            [_label.trailingAnchor constraintEqualToAnchor:_pill.trailingAnchor constant:-10],
        ]];
        _reeditButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _reeditButton.translatesAutoresizingMaskIntoConstraints = NO;
        _reeditButton.titleLabel.font = [UIFont systemFontOfSize:12];
        [_reeditButton setTitle:@"重新编辑" forState:UIControlStateNormal];
        [_reeditButton addTarget:self action:@selector(onReedit) forControlEvents:UIControlEventTouchUpInside];
        _reeditButton.hidden = YES;
        [self.contentView addSubview:_reeditButton];
        [NSLayoutConstraint activateConstraints:@[
            [_reeditButton.leadingAnchor constraintEqualToAnchor:_pill.trailingAnchor constant:6],
            [_reeditButton.centerYAnchor constraintEqualToAnchor:_pill.centerYAnchor],
        ]];
    }
    return self;
}
- (void)configureWithText:(NSString *)text {
    [self configureWithText:text reeditHandler:nil];
}
- (void)configureWithText:(NSString *)text reeditHandler:(void (^)(void))reeditHandler {
    _label.text = text.length > 0 ? text : @"";
    _reeditHandler = [reeditHandler copy];
    _reeditButton.hidden = (reeditHandler == nil);
}
- (void)onReedit {
    if (_reeditHandler) { _reeditHandler(); }
}
- (void)prepareForReuse {
    [super prepareForReuse];
    _reeditHandler = nil;
    _reeditButton.hidden = YES;
}
@end

#pragma mark - 图片消息 cell（content_type=image/video，M4-6）

@interface IMImageCell : UITableViewCell
/// 点击气泡回调：image 为已加载的缩略图/视频首帧（可能为 nil，查看器会自行按 URL 加载）。
@property (nonatomic, copy, nullable) void (^onTap)(UIImage *_Nullable image);
/// isVideo=YES 时显示首帧封面 + 居中播放角标（不自动播放，点击进查看器整页播放）。
/// preview 非空时立即显示（本地乐观预览/防闪）；fullURL 为空表示尚未上传完成（只显预览）。
/// senderName 非空（群聊对方消息）时在缩略图上方显示发送者昵称（主色小字），与文本气泡一致。
- (void)configureWithURL:(NSString *)fullURL isVideo:(BOOL)isVideo mine:(BOOL)mine previewImage:(nullable UIImage *)preview senderName:(nullable NSString *)senderName;
/// 上传进度（批量发送 UX）：0..1 显示居中百分比（0=等待中）；>=1 或 <0 隐藏；-2 显示"发送失败"。
- (void)setUploadProgress:(float)p;
/// 群聊 Telegram 式头像列（对方消息）：gutter=YES 缩略图右移留头像位；showAvatar=YES（连续段末条）显示头像。
- (void)applyGroupAvatarURL:(nullable NSString *)url seed:(NSString *)seed name:(nullable NSString *)name
                 showAvatar:(BOOL)showAvatar gutter:(BOOL)gutter;
@end

@implementation IMImageCell {
    UIImageView *_thumb;
    UIImageView *_playBadge;   // 视频封面上的播放角标
    UIView  *_progressWrap;    // 居中进度胶囊（上传中）
    UILabel *_progressLabel;
    UILabel *_senderLabel;     // 群聊对方昵称（缩略图上方）
    UILabel *_avatar;          // 群聊对方头像（连续段末条，贴缩略图底左侧）
    NSLayoutConstraint *_leading;
    NSLayoutConstraint *_trailing;
    NSLayoutConstraint *_thumbTopPlain;      // 无昵称：thumb 贴 cell 顶
    NSLayoutConstraint *_thumbTopUnderName;  // 有昵称：thumb 挂昵称下方
    NSString *_url;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _thumb = [UIImageView new];
        _thumb.translatesAutoresizingMaskIntoConstraints = NO;
        _thumb.contentMode = UIViewContentModeScaleAspectFill;
        _thumb.clipsToBounds = YES;
        _thumb.layer.cornerRadius = 10;
        _thumb.backgroundColor = UIColor.tertiarySystemFillColor;
        _thumb.userInteractionEnabled = YES;
        [_thumb addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
        [self.contentView addSubview:_thumb];

        _playBadge = [[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:@"play.circle.fill"
                    withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:44 weight:UIImageSymbolWeightRegular]]];
        _playBadge.tintColor = [UIColor colorWithWhite:1 alpha:0.95];
        _playBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _playBadge.hidden = YES;
        [self.contentView addSubview:_playBadge];

        _progressWrap = [UIView new];
        _progressWrap.translatesAutoresizingMaskIntoConstraints = NO;
        _progressWrap.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
        _progressWrap.layer.cornerRadius = 14;
        _progressWrap.hidden = YES;
        [self.contentView addSubview:_progressWrap];
        _progressLabel = [UILabel new];
        _progressLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _progressLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
        _progressLabel.textColor = UIColor.whiteColor;
        [_progressWrap addSubview:_progressLabel];

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
        [self.contentView addSubview:_avatar];

        _leading = [_thumb.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12];
        _trailing = [_thumb.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
        _thumbTopPlain = [_thumb.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:3];
        _thumbTopUnderName = [_thumb.topAnchor constraintEqualToAnchor:_senderLabel.bottomAnchor constant:4];
        _thumbTopPlain.active = YES;
        [NSLayoutConstraint activateConstraints:@[
            [_senderLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
            [_senderLabel.leadingAnchor constraintEqualToAnchor:_thumb.leadingAnchor constant:2],
            [_senderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_avatar.bottomAnchor constraintEqualToAnchor:_thumb.bottomAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:30],
            [_avatar.heightAnchor constraintEqualToConstant:30],
            [_thumb.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3],
            [_thumb.widthAnchor constraintEqualToConstant:180],
            [_thumb.heightAnchor constraintEqualToConstant:180],
            [_playBadge.centerXAnchor constraintEqualToAnchor:_thumb.centerXAnchor],
            [_playBadge.centerYAnchor constraintEqualToAnchor:_thumb.centerYAnchor],
            [_progressWrap.centerXAnchor constraintEqualToAnchor:_thumb.centerXAnchor],
            [_progressWrap.centerYAnchor constraintEqualToAnchor:_thumb.centerYAnchor],
            [_progressWrap.heightAnchor constraintEqualToConstant:28],
            [_progressLabel.leadingAnchor constraintEqualToAnchor:_progressWrap.leadingAnchor constant:12],
            [_progressLabel.trailingAnchor constraintEqualToAnchor:_progressWrap.trailingAnchor constant:-12],
            [_progressLabel.centerYAnchor constraintEqualToAnchor:_progressWrap.centerYAnchor],
        ]];
    }
    return self;
}

- (void)setUploadProgress:(float)p {
    if (p < -1.5) { // -2：失败
        _progressWrap.hidden = NO;
        _progressLabel.text = @"发送失败";
        return;
    }
    if (p < 0 || p >= 1) { _progressWrap.hidden = YES; return; } // 无进度态 / 已完成
    _progressWrap.hidden = NO;
    [self.contentView bringSubviewToFront:_progressWrap];
    _progressLabel.text = p <= 0 ? @"等待中" : [NSString stringWithFormat:@"%d%%", (int)(p * 100)];
}
- (void)configureWithURL:(NSString *)fullURL isVideo:(BOOL)isVideo mine:(BOOL)mine previewImage:(UIImage *)preview senderName:(NSString *)senderName {
    _url = fullURL;
    _leading.active = !mine;
    _trailing.active = mine;
    BOOL showName = senderName.length > 0;
    _senderLabel.text = senderName;
    _senderLabel.hidden = !showName;
    _thumbTopPlain.active = !showName;
    _thumbTopUnderName.active = showName;
    _thumb.image = preview; // 本地预览先行（上传中/防闪）；无预览为 nil 占位灰底
    _playBadge.hidden = !isVideo;
    _progressWrap.hidden = YES;
    if (fullURL.length == 0) { return; } // 尚未上传完成：只显本地预览，不发起网络加载
    __weak typeof(self) ws = self;
    NSString *want = fullURL;
    void (^apply)(UIImage *) = ^(UIImage *image) {
        __strong typeof(ws) self = ws;
        if (self && image && [self->_url isEqualToString:want]) { self->_thumb.image = image; } // 复用安全
    };
    if (isVideo) {
        [[IMVideoThumbnailLoader shared] loadPosterForVideoURL:fullURL completion:apply]; // 视频显首帧
    } else {
        [[IMImageLoader shared] loadImageURL:fullURL completion:apply];
    }
}
- (void)tapped { if (_onTap) { _onTap(_thumb.image); } }
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
- (void)prepareForReuse { [super prepareForReuse]; _thumb.image = nil; _playBadge.hidden = YES; _progressWrap.hidden = YES;
    _senderLabel.hidden = YES; _senderLabel.text = nil; _thumbTopUnderName.active = NO; _thumbTopPlain.active = YES;
    _avatar.hidden = YES; _leading.constant = 12; _onTap = nil; }
@end

#pragma mark - 相册宫格 Cell（M4+：同 group_id 的多图/视频合并为一个 Telegram 式宫格，消除逐条插行的闪动）

/// 每个宫格块：缩略图 + 视频播放角标 + 环形上传进度（CAShapeLayer strokeEnd）+ 失败角标。
@interface IMAlbumTileView : UIView
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIImageView *playBadge;
@property (nonatomic, strong) IMMessageModel *member; ///< 本格对应的消息（tap/菜单定位用）
@property (nonatomic, copy)   NSString *loadKey;      ///< 异步加载防串图
- (void)setProgress:(nullable NSNumber *)p; ///< nil=无/完成；0..1=环形进度；<0=失败
@end

@implementation IMAlbumTileView {
    UIView       *_dim;      // 上传中压暗
    CAShapeLayer *_ringBG;   // 环底
    CAShapeLayer *_ring;     // 进度环
    UILabel      *_failBadge;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = YES;
        self.backgroundColor = UIColor.tertiarySystemFillColor;
        _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
        _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        [self addSubview:_imageView];

        _dim = [[UIView alloc] initWithFrame:self.bounds];
        _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
        _dim.hidden = YES;
        [self addSubview:_dim];

        _playBadge = [[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:@"play.circle.fill"
                    withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:30 weight:UIImageSymbolWeightRegular]]];
        _playBadge.tintColor = [UIColor colorWithWhite:1 alpha:0.95];
        _playBadge.hidden = YES;
        [self addSubview:_playBadge];

        UIBezierPath *circle = [UIBezierPath bezierPathWithArcCenter:CGPointMake(18, 18) radius:15
                                                          startAngle:-M_PI_2 endAngle:M_PI * 1.5 clockwise:YES];
        _ringBG = [CAShapeLayer layer];
        _ringBG.path = circle.CGPath;
        _ringBG.fillColor = UIColor.clearColor.CGColor;
        _ringBG.strokeColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
        _ringBG.lineWidth = 3;
        _ringBG.frame = CGRectMake(0, 0, 36, 36);
        _ringBG.hidden = YES;
        [self.layer addSublayer:_ringBG];

        _ring = [CAShapeLayer layer];
        _ring.path = circle.CGPath;
        _ring.fillColor = UIColor.clearColor.CGColor;
        _ring.strokeColor = UIColor.whiteColor.CGColor;
        _ring.lineWidth = 3;
        _ring.lineCap = kCALineCapRound;
        _ring.strokeEnd = 0;
        _ring.frame = CGRectMake(0, 0, 36, 36);
        _ring.hidden = YES;
        [self.layer addSublayer:_ring];

        _failBadge = [UILabel new];
        _failBadge.text = @"!";
        _failBadge.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
        _failBadge.textColor = UIColor.whiteColor;
        _failBadge.textAlignment = NSTextAlignmentCenter;
        _failBadge.backgroundColor = UIColor.systemRedColor;
        _failBadge.layer.cornerRadius = 14;
        _failBadge.clipsToBounds = YES;
        _failBadge.hidden = YES;
        [self addSubview:_failBadge];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGPoint c = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
    _playBadge.center = c;
    _failBadge.frame = CGRectMake(0, 0, 28, 28);
    _failBadge.center = c;
    CGRect ringFrame = CGRectMake(c.x - 18, c.y - 18, 36, 36);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _ringBG.frame = ringFrame;
    _ring.frame = ringFrame;
    [CATransaction commit];
}
- (void)setProgress:(NSNumber *)p {
    if (!p || p.floatValue >= 1) { // 无进度 / 完成
        _dim.hidden = YES; _ringBG.hidden = YES; _ring.hidden = YES; _failBadge.hidden = YES;
        return;
    }
    if (p.floatValue < 0) { // 失败
        _dim.hidden = NO; _ringBG.hidden = YES; _ring.hidden = YES; _failBadge.hidden = NO;
        return;
    }
    _dim.hidden = NO; _failBadge.hidden = YES;
    _ringBG.hidden = NO; _ring.hidden = NO;
    [CATransaction begin];
    [CATransaction setDisableActions:YES]; // 高频进度回调不做隐式动画（避免滞后）
    _ring.strokeEnd = MAX(0.02, p.floatValue); // 0% 也露一点头，可感知"在动"
    [CATransaction commit];
}
@end

/// 相册宫格 cell：leader 行渲染同组全部成员；行高由块布局决定（同数量恒定高，进度/缩略图更新不动布局）。
@interface IMAlbumCell : UITableViewCell
@property (nonatomic, copy, nullable) void (^onTapItem)(IMMessageModel *m);
@property (nonatomic, copy, nullable) UIMenu *_Nullable (^menuForItem)(IMMessageModel *m);
/// senderName 非空（群聊对方消息）时在宫格上方显示发送者昵称（主色小字），与文本/图片气泡一致。
- (void)configureWithMembers:(NSArray<IMMessageModel *> *)members mine:(BOOL)mine host:(NSString *)host
                    previews:(NSDictionary<NSString *, UIImage *> *)previews
                    progress:(NSDictionary<NSString *, NSNumber *> *)progress
                  senderName:(nullable NSString *)senderName;
/// 只刷缩略图/进度/角标（不重建布局、不触发行高变化）——上传进度 tick / ACK 用。
- (void)refreshWithPreviews:(NSDictionary<NSString *, UIImage *> *)previews
                   progress:(NSDictionary<NSString *, NSNumber *> *)progress;
/// 群聊 Telegram 式头像列（对方消息）：gutter=YES 宫格右移留头像位；showAvatar=YES（连续段末条）显示头像。
- (void)applyGroupAvatarURL:(nullable NSString *)url seed:(NSString *)seed name:(nullable NSString *)name
                 showAvatar:(BOOL)showAvatar gutter:(BOOL)gutter;
@end

/// 按块数返回行模式（Telegram 近似）：如 3 → [1,2]=首行1大块+次行2块。
static NSArray<NSNumber *> *IMAlbumRowPattern(NSUInteger n) {
    switch (n) {
        case 1:  return @[@1];
        case 2:  return @[@2];
        case 3:  return @[@1, @2];
        case 4:  return @[@2, @2];
        case 5:  return @[@2, @3];
        case 6:  return @[@3, @3];
        case 7:  return @[@1, @3, @3];
        case 8:  return @[@2, @3, @3];
        default: return @[@3, @3, @3]; // 9（selectionLimit=9 封顶）
    }
}

static const CGFloat kIMAlbumWidth = 240;
static const CGFloat kIMAlbumGap = 2;

/// 给定块数的宫格总高（布局确定 → 行高确定，自适应行高稳定）。
static CGFloat IMAlbumHeightForCount(NSUInteger n) {
    if (n == 0) { return 0; }
    CGFloat h = 0;
    for (NSNumber *k in IMAlbumRowPattern(n)) {
        NSUInteger cols = k.unsignedIntegerValue;
        CGFloat tileH = cols == 1 ? 150 : (kIMAlbumWidth - (cols - 1) * kIMAlbumGap) / cols;
        h += tileH + kIMAlbumGap;
    }
    return h - kIMAlbumGap;
}

@interface IMAlbumCell () <UIContextMenuInteractionDelegate>
@end

@implementation IMAlbumCell {
    UIView *_container;                        // 固定宽 240，圆角裁切
    NSMutableArray<IMAlbumTileView *> *_tiles; // 复用池（按需增建）
    UILabel *_metaChip;                        // 右下角 时间+状态 小胶囊
    UILabel *_senderLabel;                     // 群聊对方昵称（宫格上方）
    UILabel *_avatar;                          // 群聊对方头像（连续段末条，贴宫格底左侧）
    NSLayoutConstraint *_containerHeight;
    NSLayoutConstraint *_leading, *_trailing;
    NSLayoutConstraint *_containerTopPlain;      // 无昵称：宫格贴 cell 顶
    NSLayoutConstraint *_containerTopUnderName;  // 有昵称：宫格挂昵称下方
    NSString *_host;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _tiles = [NSMutableArray array];
        _container = [UIView new];
        _container.translatesAutoresizingMaskIntoConstraints = NO;
        _container.layer.cornerRadius = 12;
        _container.clipsToBounds = YES;
        [self.contentView addSubview:_container];

        _metaChip = [UILabel new];
        _metaChip.font = [UIFont systemFontOfSize:11];
        _metaChip.textColor = UIColor.whiteColor;
        _metaChip.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
        _metaChip.layer.cornerRadius = 9;
        _metaChip.clipsToBounds = YES;
        _metaChip.textAlignment = NSTextAlignmentCenter;
        [_container addSubview:_metaChip];

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
        [self.contentView addSubview:_avatar];

        _leading = [_container.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12];
        _trailing = [_container.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
        _containerHeight = [_container.heightAnchor constraintEqualToConstant:100];
        _containerTopPlain = [_container.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:3];
        _containerTopUnderName = [_container.topAnchor constraintEqualToAnchor:_senderLabel.bottomAnchor constant:4];
        _containerTopPlain.active = YES;
        [NSLayoutConstraint activateConstraints:@[
            [_senderLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
            [_senderLabel.leadingAnchor constraintEqualToAnchor:_container.leadingAnchor constant:2],
            [_senderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_avatar.bottomAnchor constraintEqualToAnchor:_container.bottomAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:30],
            [_avatar.heightAnchor constraintEqualToConstant:30],
            [_container.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3],
            [_container.widthAnchor constraintEqualToConstant:kIMAlbumWidth],
            _containerHeight,
        ]];
    }
    return self;
}

- (void)configureWithMembers:(NSArray<IMMessageModel *> *)members mine:(BOOL)mine host:(NSString *)host
                    previews:(NSDictionary<NSString *, UIImage *> *)previews
                    progress:(NSDictionary<NSString *, NSNumber *> *)progress
                  senderName:(NSString *)senderName {
    _host = host;
    _leading.active = !mine;
    _trailing.active = mine;
    BOOL showName = senderName.length > 0;
    _senderLabel.text = senderName;
    _senderLabel.hidden = !showName;
    _containerTopPlain.active = !showName;
    _containerTopUnderName.active = showName;
    _containerHeight.constant = IMAlbumHeightForCount(members.count);

    // 按需补足块视图；多余的隐藏。
    while (_tiles.count < members.count) {
        IMAlbumTileView *tile = [[IMAlbumTileView alloc] initWithFrame:CGRectZero];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tileTapped:)];
        [tile addGestureRecognizer:tap];
        [tile addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:(id<UIContextMenuInteractionDelegate>)self]];
        [_container addSubview:tile];
        [_tiles addObject:tile];
    }
    for (NSUInteger i = members.count; i < _tiles.count; i++) { _tiles[i].hidden = YES; }

    // 布局块（frame 手排，宽 240 固定；行模式决定块尺寸）。
    NSArray<NSNumber *> *pattern = IMAlbumRowPattern(members.count);
    NSUInteger idx = 0;
    CGFloat y = 0;
    for (NSNumber *k in pattern) {
        NSUInteger cols = k.unsignedIntegerValue;
        CGFloat tileW = (kIMAlbumWidth - (cols - 1) * kIMAlbumGap) / cols;
        CGFloat tileH = cols == 1 ? 150 : tileW;
        for (NSUInteger c = 0; c < cols && idx < members.count; c++, idx++) {
            IMAlbumTileView *tile = _tiles[idx];
            tile.hidden = NO;
            tile.frame = CGRectMake(c * (tileW + kIMAlbumGap), y, cols == 1 ? kIMAlbumWidth : tileW, tileH);
            [self bindTile:tile toMember:members[idx] previews:previews progress:progress];
        }
        y += tileH + kIMAlbumGap;
    }
    [_container bringSubviewToFront:_metaChip];
    [self updateMetaWithMembers:members mine:mine];
}

/// 单块绑定：本地预览优先（上传中/防闪），否则按 URL 异步加载（复用防串图）。
- (void)bindTile:(IMAlbumTileView *)tile toMember:(IMMessageModel *)m
        previews:(NSDictionary<NSString *, UIImage *> *)previews
        progress:(NSDictionary<NSString *, NSNumber *> *)progress {
    tile.member = m;
    BOOL isVideo = [m.contentType isEqualToString:@"video"];
    tile.playBadge.hidden = !isVideo;
    [tile setProgress:progress[m.clientMsgID ?: @""]];

    UIImage *preview = previews[m.clientMsgID ?: @""];
    if (preview) { tile.imageView.image = preview; tile.loadKey = nil; return; }
    if (m.content.length == 0) { tile.imageView.image = nil; tile.loadKey = nil; return; } // 占位灰底
    NSString *full = IMMediaFullURL(m.content, _host);
    tile.loadKey = full;
    tile.imageView.image = nil;
    __weak IMAlbumTileView *wt = tile;
    void (^apply)(UIImage *) = ^(UIImage *img) {
        __strong IMAlbumTileView *t = wt;
        if (t && img && [t.loadKey isEqualToString:full]) { t.imageView.image = img; }
    };
    if (isVideo) { [[IMVideoThumbnailLoader shared] loadPosterForVideoURL:full completion:apply]; }
    else { [[IMImageLoader shared] loadImageURL:full completion:apply]; }
}

- (void)refreshWithPreviews:(NSDictionary<NSString *, UIImage *> *)previews
                   progress:(NSDictionary<NSString *, NSNumber *> *)progress {
    BOOL mine = NO;
    NSMutableArray<IMMessageModel *> *members = [NSMutableArray array];
    for (IMAlbumTileView *tile in _tiles) {
        IMMessageModel *m = tile.member;
        if (tile.hidden || !m) { continue; }
        [members addObject:m];
        mine = mine || m.status != IMMessageStatusReceived;
        [tile setProgress:progress[m.clientMsgID ?: @""]];
        UIImage *preview = previews[m.clientMsgID ?: @""];
        if (preview && tile.imageView.image == nil) { tile.imageView.image = preview; }
    }
    [self updateMetaWithMembers:members mine:mine];
}

/// 右下角小胶囊：末条成员时间 + 自己消息的状态（… 发送中 / ✓ 全部送达 / ! 有失败）。
- (void)updateMetaWithMembers:(NSArray<IMMessageModel *> *)members mine:(BOOL)mine {
    IMMessageModel *last = members.lastObject;
    if (!last) { _metaChip.hidden = YES; return; }
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"HH:mm";
    NSString *time = last.timestamp > 0
        ? [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:last.timestamp / 1000.0]] : @"";
    NSString *suffix = @"";
    if (mine) {
        BOOL anyFailed = NO, allSent = YES;
        for (IMMessageModel *m in members) {
            if (m.status == IMMessageStatusFailed) { anyFailed = YES; }
            if (m.status != IMMessageStatusSent) { allSent = NO; }
        }
        suffix = anyFailed ? @" !" : (allSent ? @" ✓" : @" …");
    }
    _metaChip.hidden = NO;
    _metaChip.text = [NSString stringWithFormat:@" %@%@ ", time, suffix];
    [_metaChip sizeToFit];
    CGSize s = CGSizeMake(_metaChip.bounds.size.width + 8, 18);
    _metaChip.frame = CGRectMake(kIMAlbumWidth - s.width - 6, _containerHeight.constant - s.height - 6, s.width, s.height);
}

- (void)tileTapped:(UITapGestureRecognizer *)gr {
    IMAlbumTileView *tile = (IMAlbumTileView *)gr.view;
    if ([tile isKindOfClass:IMAlbumTileView.class] && tile.member && _onTapItem) { _onTapItem(tile.member); }
}

/// 每块自带长按菜单（定位到该块对应的单条消息 → 单张引用/转发/撤回/收藏等）。
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                       configurationForMenuAtLocation:(CGPoint)location {
    IMAlbumTileView *tile = (IMAlbumTileView *)interaction.view;
    if (![tile isKindOfClass:IMAlbumTileView.class] || !tile.member || !_menuForItem) { return nil; }
    IMMessageModel *m = tile.member;
    UIMenu * (^provider)(IMMessageModel *) = _menuForItem;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) { return provider(m); }];
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

- (void)prepareForReuse {
    [super prepareForReuse];
    for (IMAlbumTileView *tile in _tiles) { tile.member = nil; tile.loadKey = nil; tile.imageView.image = nil; [tile setProgress:nil]; }
    _avatar.hidden = YES;
    _leading.constant = 12;
    _onTapItem = nil;
    _menuForItem = nil;
}
@end

#pragma mark - 合并转发卡片 Cell（#3：聊天记录）

/// 解析 chat_record 的 content JSON（t=标题, items=[{n,ct,c}]）为 (标题, 预览行数组)。
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
        NSString *preview = [ct isEqualToString:@"image"] ? @"[图片]"
            : [ct isEqualToString:@"video"] ? @"[视频]"
            : [ct isEqualToString:@"file"] ? @"[文件]" : c;
        [lines addObject:[NSString stringWithFormat:@"%@: %@", n, preview]];
        if (lines.count >= 4) { break; }
    }
    *outLines = lines;
}

/// 合并转发消息气泡：卡片（标题 + 前几条预览 + 「聊天记录」脚注），点击进详情页。
@interface IMChatRecordCell : UITableViewCell
@property (nonatomic, copy, nullable) void (^onTap)(void);
- (void)configureWithMessage:(IMMessageModel *)message mine:(BOOL)mine;
@end

@implementation IMChatRecordCell {
    UIView  *_card;
    UILabel *_title;
    UILabel *_preview;
    UILabel *_footer;
    NSLayoutConstraint *_leading;
    NSLayoutConstraint *_trailing;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _card = [UIView new];
        _card.translatesAutoresizingMaskIntoConstraints = NO;
        _card.backgroundColor = UIColor.secondarySystemBackgroundColor;
        _card.layer.cornerRadius = 10;
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

        _leading = [_card.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12];
        _trailing = [_card.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
        [NSLayoutConstraint activateConstraints:@[
            [_card.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:3],
            [_card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3],
            [_card.widthAnchor constraintEqualToConstant:240],
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
- (void)configureWithMessage:(IMMessageModel *)message mine:(BOOL)mine {
    NSString *title; NSArray<NSString *> *lines;
    IMParseChatRecord(message.content, &title, &lines);
    _title.text = title;
    _preview.text = [lines componentsJoinedByString:@"\n"];
    _leading.active = !mine;
    _trailing.active = mine;
}
- (void)tapped { if (_onTap) { _onTap(); } }
- (void)prepareForReuse { [super prepareForReuse]; _onTap = nil; }
@end

#pragma mark - 链接富预览卡片 Cell（OG）

/// 纯 URL 消息的富预览卡片：先显链接，异步拉 OG 后补标题/描述/缩略图；点击整卡打开链接。
@interface IMLinkCardCell : UITableViewCell
@property (nonatomic, copy, nullable) void (^onTap)(NSString *url);
- (void)configureWithMessage:(IMMessageModel *)message mine:(BOOL)mine;
@end

@implementation IMLinkCardCell {
    UIStackView *_stack;      // 竖排：引用行(可选) + 可点击 URL 文本 + OG 卡片(拉到才显示)
    UILabel *_quote;          // 引用快照（点击整行空白处由 tableView 手势跳原消息）
    UILabel *_link;           // URL 文本：始终显示、蓝色下划线、可点击打开
    UIView *_card;
    UIImageView *_thumb;
    NSLayoutConstraint *_thumbHeight;
    UILabel *_title;
    UILabel *_desc;
    UILabel *_host;
    NSLayoutConstraint *_leading;
    NSLayoutConstraint *_trailing;
    NSString *_url;
}
+ (NSCache<NSString *, NSDictionary *> *)previewCache {
    static NSCache *c; static dispatch_once_t once; dispatch_once(&once, ^{ c = [NSCache new]; c.countLimit = 200; });
    return c;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _quote = [UILabel new];
        _quote.font = [UIFont systemFontOfSize:13];
        _quote.textColor = IMTheme.textSecondary;
        _quote.numberOfLines = 2;
        _quote.hidden = YES;

        _link = [UILabel new];
        _link.font = [UIFont systemFontOfSize:16];
        _link.numberOfLines = 0;
        _link.userInteractionEnabled = YES;
        [_link addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];

        _card = [UIView new];
        _card.backgroundColor = UIColor.secondarySystemBackgroundColor;
        _card.layer.cornerRadius = 10;
        _card.clipsToBounds = YES;
        _card.userInteractionEnabled = YES;
        _card.hidden = YES; // 拉到 OG 预览才显示（否则仅链接文本，与 Web 一致）
        [_card addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];

        _stack = [[UIStackView alloc] initWithArrangedSubviews:@[_quote, _link, _card]];
        _stack.axis = UILayoutConstraintAxisVertical;
        _stack.spacing = 6;
        _stack.alignment = UIStackViewAlignmentFill;
        _stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_stack];

        _thumb = [UIImageView new];
        _thumb.translatesAutoresizingMaskIntoConstraints = NO;
        _thumb.contentMode = UIViewContentModeScaleAspectFill;
        _thumb.clipsToBounds = YES;
        _thumb.backgroundColor = UIColor.tertiarySystemFillColor;
        [_card addSubview:_thumb];

        _title = [UILabel new]; _title.translatesAutoresizingMaskIntoConstraints = NO;
        _title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]; _title.numberOfLines = 2;
        _title.textColor = IMTheme.textPrimary;
        [_card addSubview:_title];
        _desc = [UILabel new]; _desc.translatesAutoresizingMaskIntoConstraints = NO;
        _desc.font = [UIFont systemFontOfSize:12]; _desc.numberOfLines = 2; _desc.textColor = IMTheme.textSecondary;
        [_card addSubview:_desc];
        _host = [UILabel new]; _host.translatesAutoresizingMaskIntoConstraints = NO;
        _host.font = [UIFont systemFontOfSize:11]; _host.textColor = IMTheme.textSecondary;
        [_card addSubview:_host];

        _leading = [_stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12];
        _trailing = [_stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
        _thumbHeight = [_thumb.heightAnchor constraintEqualToConstant:0]; // 无图时为 0
        [NSLayoutConstraint activateConstraints:@[
            [_stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:3],
            [_stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3],
            [_stack.widthAnchor constraintEqualToConstant:260],
            [_thumb.topAnchor constraintEqualToAnchor:_card.topAnchor],
            [_thumb.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor],
            [_thumb.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor],
            _thumbHeight,
            [_title.topAnchor constraintEqualToAnchor:_thumb.bottomAnchor constant:8],
            [_title.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:10],
            [_title.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-10],
            [_desc.topAnchor constraintEqualToAnchor:_title.bottomAnchor constant:3],
            [_desc.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:10],
            [_desc.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-10],
            [_host.topAnchor constraintEqualToAnchor:_desc.bottomAnchor constant:5],
            [_host.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:10],
            [_host.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-10],
            [_host.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor constant:-8],
        ]];
    }
    return self;
}
- (void)configureWithMessage:(IMMessageModel *)message mine:(BOOL)mine {
    NSString *url = message.content ?: @"";
    _url = url;
    _leading.active = !mine;
    _trailing.active = mine;
    // 引用行（共性 #1）：URL 消息带引用时也要显示引用条 + OG 卡片。
    if (message.replyToConvSeq > 0) {
        NSString *snap = IMLocalizeSnippet(message.replySnapshot.length > 0 ? message.replySnapshot : @"原消息");
        _quote.text = [NSString stringWithFormat:@"▏%@", snap];
        _quote.hidden = NO;
    } else {
        _quote.hidden = YES;
    }
    // URL 文本始终显示（蓝色下划线，可点击）；卡片拉到预览再显示在下方。
    _link.attributedText = [[NSAttributedString alloc] initWithString:url attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:16],
        NSForegroundColorAttributeName: UIColor.systemBlueColor,
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
    }];
    _card.hidden = YES;
    _title.text = nil; _desc.text = nil; _host.text = nil;
    _thumb.image = nil;
    _thumbHeight.constant = 0;

    NSDictionary *cached = [[IMLinkCardCell previewCache] objectForKey:url];
    if (cached) { [self applyPreview:cached forURL:url]; return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService linkPreviewWithToken:token url:url completion:^(NSDictionary *preview, NSError *error) {
        if (!preview) { return; }
        [[IMLinkCardCell previewCache] setObject:preview forKey:url];
        __strong typeof(ws) self = ws;
        if (self && [self->_url isEqualToString:url]) { [self applyPreview:preview forURL:url]; }
    }];
}
- (void)applyPreview:(NSDictionary *)p forURL:(NSString *)url {
    NSString *title = [p[@"title"] isKindOfClass:NSString.class] ? p[@"title"] : @"";
    NSString *desc = [p[@"description"] isKindOfClass:NSString.class] ? p[@"description"] : @"";
    NSString *site = [p[@"site_name"] isKindOfClass:NSString.class] ? p[@"site_name"] : @"";
    NSString *image = [p[@"image"] isKindOfClass:NSString.class] ? p[@"image"] : @"";
    if (title.length == 0 && image.length == 0) { return; } // 没有可展示的预览 → 保持仅链接
    _card.hidden = NO;
    _title.text = title.length ? title : url;
    _desc.text = desc;
    _host.text = site;
    if (image.length) {
        _thumbHeight.constant = 130;
        __weak typeof(self) ws = self;
        [[IMImageLoader shared] loadImageURL:image completion:^(UIImage *img) {
            __strong typeof(ws) self = ws;
            if (self && [self->_url isEqualToString:url]) { self->_thumb.image = img; }
        }];
    } else {
        _thumbHeight.constant = 0;
    }
}
- (void)tapped { if (_onTap && _url) { _onTap(_url); } }
- (void)prepareForReuse { [super prepareForReuse]; _thumb.image = nil; _thumbHeight.constant = 0; _card.hidden = YES; _quote.hidden = YES; _onTap = nil; }
@end

#pragma mark - 支持粘贴图片的输入框（#2）

/// UITextField 默认不接受图片粘贴；剪贴板有图片时放开 paste 菜单并回调图片（文本粘贴走原生路径）。
@interface IMPasteImageTextField : UITextField
@property (nonatomic, copy, nullable) void (^onPasteImage)(UIImage *image);
@end

@implementation IMPasteImageTextField
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(paste:) && UIPasteboard.generalPasteboard.hasImages) { return YES; }
    return [super canPerformAction:action withSender:sender];
}
- (void)paste:(id)sender {
    if (UIPasteboard.generalPasteboard.hasImages) {
        UIImage *img = UIPasteboard.generalPasteboard.image;
        if (img && self.onPasteImage) { self.onPasteImage(img); return; }
    }
    [super paste:sender];
}
@end

#pragma mark - 聊天页

@interface IMChatViewController () <IMSocketManagerDelegate, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy) NSString *peerID;         // 单聊对端 uid；群聊为空串
@property (nonatomic, assign) BOOL isGroupChat;        // YES=群聊（convID 为群 topic_id）
@property (nonatomic, copy, nullable) NSString *groupName;     // 群名（进入时用会话项的，拉到群资料后刷新）
@property (nonatomic, strong, nullable) IMGroupInfo *groupInfo; // 群资料缓存（标题成员数/气泡昵称回退/typing 昵称）
@property (nonatomic, strong) NSMutableArray<IMMessageModel *> *messages;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *seenConvSeqs; // 按 conv_seq 去重，避免推送+同步重复
@property (nonatomic, copy) NSString *convID;
@property (nonatomic, assign) int64_t entryReadSeq;   // 进入前已读位点（定位未读分割线，进会话锁定一次）
@property (nonatomic, assign) NSInteger entryUnread;   // 进入时未读数
@property (nonatomic, assign) int64_t maxReadReported; // 已上报的最大已读 conv_seq（可见即读，单调不回退）
@property (nonatomic, assign) int64_t pendingReadSeq;  // 已滚入视口的最大 conv_seq（节流后上报）
@property (nonatomic, assign) int64_t peerReadSeq;     // 对端已读位点（用于「已读」双勾）
@property (nonatomic, assign) BOOL peerOnline;         // 对端在线
@property (nonatomic, assign) IMSocketState connState; // 连接态（与在线点共同决定标题）
@property (nonatomic, assign) BOOL didInitialPosition; // 已做进会话定位（只定位一次）
@property (nonatomic, assign) NSTimeInterval lastTypingSent; // typing 节流
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) NSLayoutConstraint *inputBottom;
@property (nonatomic, strong) UILabel *typingLabel;
@property (nonatomic, strong) NSLayoutConstraint *typingHeight;
@property (nonatomic, strong) UIButton *jumpButton;   // 右下角"↓N"回到最新
@property (nonatomic, strong) UILabel *jumpBadge;     // 按钮上的未读计数（=视口下方未读数）
@property (nonatomic, strong) UIView *inputBar;       // 输入栏容器
@property (nonatomic, strong, nullable) IMMessageModel *replyingTo; // 正在引用回复的目标（M4-2）
@property (nonatomic, strong, nullable) IMMessageModel *editingMessage; // 正在编辑的目标（M4-5）
@property (nonatomic, assign) BOOL selecting;                 // 多选态（#2）
@property (nonatomic, strong, nullable) UIView *selectionBar; // 多选底部工具栏（转发/收藏/删除）
@property (nonatomic, strong, nullable) UIBarButtonItem *savedRightItem; // 多选前的右上按钮，退出恢复
@property (nonatomic, copy, nullable) NSString *savedTitle;   // 多选前标题
@property (nonatomic, strong, nullable) UIView *attachPanel; // 附件面板（M4-6，加号弹出，展开时顶起输入栏、显示在其下方）
@property (nonatomic, assign) BOOL attachPanelVisible;       // 面板是否展开（与键盘互斥，共同决定 inputBottom）
@property (nonatomic, assign) CGFloat kbInset;              // 键盘遮挡输入栏的高度（已减 safeArea），随 keyboardWillChange 更新
@property (nonatomic, strong) UIButton *emojiButton;  // 表情（占位）
@property (nonatomic, strong) UIButton *plusButton;   // 加号（附件面板）
@property (nonatomic, strong) UIButton *sendButton;   // 发送
@property (nonatomic, strong) NSLayoutConstraint *inputTrailToEmoji; // 无内容：输入框贴表情按钮
@property (nonatomic, strong) NSLayoutConstraint *inputTrailToSend;  // 有内容：输入框贴发送按钮
@property (nonatomic, strong) UIView *replyBar;       // 引用预览条（输入栏上方）
@property (nonatomic, strong) UILabel *replyLabel;
@property (nonatomic, strong) UIImageView *replyThumb; // 引用媒体时的小缩略图（#5，图片/视频）
@property (nonatomic, strong) NSLayoutConstraint *replyLabelLeadingNoThumb; // 无缩略图时 label 贴竖条
@property (nonatomic, strong) NSLayoutConstraint *replyLabelLeadingThumb;   // 有缩略图时 label 贴缩略图
@property (nonatomic, strong) NSLayoutConstraint *replyBarHeight;
// 批量发送 UX：选完立即上屏乐观气泡（本地预览），逐项真实字节进度居中显示。key=clientMsgID（发送前为 outbox- 临时键）。
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *outboxPreviews;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *outboxProgress; // 0..1 上传中；-2 失败
@end

@implementation IMChatViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID peerID:(NSString *)peerID
                     readSeq:(int64_t)readSeq unread:(NSInteger)unread peerReadSeq:(int64_t)peerReadSeq {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.hidesBottomBarWhenPushed = YES; // 进聊天页隐藏底部 TabBar（push 时全屏）
        _host = [host copy];
        _userID = [userID copy];
        _peerID = [peerID copy];
        _convID = IMConversationID(userID, peerID);
        _entryReadSeq = readSeq;
        _entryUnread = unread;
        _peerReadSeq = peerReadSeq;   // 进会话即用服务端已知对端已读位点播种（实时回执再往上推进）
        _maxReadReported = readSeq;   // 已读起点=进入前位点，仅在可见消息超过它时才上报
        _pendingReadSeq = readSeq;
        // 本地落库：进入即秒显历史。
        _messages = [[IMDatabase.sharedDatabase messagesForConv:_convID] mutableCopy];
        _seenConvSeqs = [NSMutableSet set];
        for (IMMessageModel *m in _messages) {
            if (m.convSeq > 0) { [_seenConvSeqs addObject:@(m.convSeq)]; }
        }
        _outboxPreviews = [NSMutableDictionary dictionary];
        _outboxProgress = [NSMutableDictionary dictionary];
    }
    return self;
}

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID
                 groupConvID:(NSString *)convID groupName:(NSString *)name
                     readSeq:(int64_t)readSeq unread:(NSInteger)unread {
    // 复用单聊指定初始化器（peerID 空），再覆写会话标识为群 topic_id。
    self = [self initWithHost:host userID:userID peerID:@"" readSeq:readSeq unread:unread peerReadSeq:0];
    if (self) {
        _isGroupChat = YES;
        _groupName = [name copy];
        _convID = [convID copy];
        // 指定初始化器按 IMConversationID(uid,"") 预载了错误会话，这里按群 convID 重载本地历史。
        _messages = [[IMDatabase.sharedDatabase messagesForConv:convID] mutableCopy];
        [_seenConvSeqs removeAllObjects];
        for (IMMessageModel *m in _messages) {
            if (m.convSeq > 0) { [_seenConvSeqs addObject:@(m.convSeq)]; }
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    if (self.isGroupChat) {
        [self updateTitle];
        // 右上 ⓘ 进群资料页（成员/邀请/退群/管理）。
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"info.circle"]
                                             style:UIBarButtonItemStylePlain target:self action:@selector(groupInfoTapped)];
        [self reloadGroupInfo];
        // 群变更（邀请/移除/退群/转让/改名）→ 刷新标题/群资料；被移出 → 提示并退出本页。
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onGroupEvent:)
                                                   name:IMSocketDidReceiveGroupEventNotification object:nil];
    } else {
        self.title = [NSString stringWithFormat:@"与 %@ 聊天", self.peerID];
    }
    [self setupUI];
    [self observeKeyboard];
    // 消息操作（撤回/编辑/置顶，M4）：应用到本会话某条 → 就地刷新；我方操作被拒（超窗）→ 吐司。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMsgOpApplied:)
                                               name:IMSocketDidApplyMsgOpNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMsgOpRejected:)
                                               name:IMSocketDidRejectMsgOpNotification object:nil];
}

/// 消息操作应用到某条消息：本会话则就地更新内存模型 + 刷新（撤回→墓碑，编辑→改文本）。
- (void)onMsgOpApplied:(NSNotification *)note {
    NSString *convID = note.userInfo[kIMConvIDKey];
    if (![convID isEqualToString:self.convID]) { return; }
    int64_t target = [note.userInfo[kIMMsgOpTargetSeqKey] longLongValue];
    NSString *op = note.userInfo[kIMMsgOpKey];
    NSString *newContent = note.userInfo[kIMMsgOpContentKey];
    int64_t nowMs = (int64_t)([NSDate date].timeIntervalSince1970 * 1000);
    for (IMMessageModel *m in self.messages) {
        if (m.convSeq != target) { continue; }
        if ([op isEqualToString:kIMMsgOpRecall]) { m.recalledAt = nowMs; }
        else if ([op isEqualToString:kIMMsgOpEdit]) { m.editedAt = nowMs; if (newContent) { m.content = newContent; } }
        else if ([op isEqualToString:kIMMsgOpPin]) { m.pinnedAt = nowMs; }
        break;
    }
    [self.tableView reloadData];
}

/// 我方发起的操作被拒（如撤回超时）：吐司提示（不改消息）。
- (void)onMsgOpRejected:(NSNotification *)note {
    NSString *msg = note.userInfo[@"message"];
    [self im_showToast:msg.length > 0 ? msg : @"操作失败"];
}

#pragma mark - 群聊（M3-5）

/// 拉群资料：标题成员数 / 气泡昵称回退 / typing 昵称 / 群资料页数据源。best-effort。
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
        [self.tableView reloadData]; // 昵称回退可能变化（老消息无 from_nickname 时用成员表）
    }];
}

- (void)groupInfoTapped {
    IMGroupInfoViewController *info = [[IMGroupInfoViewController alloc] initWithHost:self.host
                                                                               userID:self.userID
                                                                               convID:self.convID];
    [self.navigationController pushViewController:info animated:YES];
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
- (NSString *)senderNameForMessage:(IMMessageModel *)m {
    if (m.fromNickname.length > 0) { return m.fromNickname; }
    NSString *nick = [self.groupInfo nicknameOfMember:m.from];
    return nick.length > 0 ? nick : (m.from ?: @"");
}

/// 群聊发送者头像绝对 URL（无则空串——头像圈回退首字母）。相对路径补 host。
- (NSString *)senderAvatarURLForMessage:(IMMessageModel *)m {
    NSString *url = [self.groupInfo avatarURLOfMember:m.from];
    return url.length > 0 ? [self fullMediaURL:url] : @"";
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
    for (NSInteger j = row + 1; j < (NSInteger)self.messages.count; j++) {
        if ([self isAlbumFollowerAtRow:j]) { continue; }
        return j;
    }
    return (NSInteger)self.messages.count;
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
    return ![self message:self.messages[(NSUInteger)p] sameSenderRunAs:self.messages[(NSUInteger)row]];
}

/// 该行是否为连续段末条（对方群消息用；决定是否显示头像）。
- (BOOL)isLastInSenderRun:(NSInteger)row {
    NSInteger n = [self nextVisibleRow:row];
    if (n >= (NSInteger)self.messages.count) { return YES; }
    return ![self message:self.messages[(NSUInteger)n] sameSenderRunAs:self.messages[(NSUInteger)row]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    IMSocketManager.sharedManager.delegate = self;
    // 同步当前真实连接态：socket 通常在会话列表页就已连上，进本页不会再触发 didChangeState，
    // 若不主动拉一次，connState 会停在默认值 → 标题误显「未连接」。
    self.connState = IMSocketManager.sharedManager.state;
    [self updateTitle];
    [IMSocketManager.sharedManager connectToHost:self.host userID:self.userID];
    // 登记本会话：以本地已存最大 conv_seq 为同步起点（断点续传），自动增量拉回缺失消息。
    int64_t synced = [IMDatabase.sharedDatabase maxConvSeqForConv:self.convID];
    [IMSocketManager.sharedManager trackConversation:self.convID syncedSeq:synced];
}

#pragma mark - 拉黑（微信式单向：拉黑者仍可发，故聊天页不拦输入；黑名单状态在通讯录管理）

// 微信式单向：拉黑者仍可给被拉黑者发消息（对方能收到），故聊天页不再拦输入/盖横幅。
// 是否拉黑、解除拉黑均在通讯录好友行（副标题"已拉黑" + 左滑"解除拉黑"）管理。

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // 在出现动画前、首次布局完成时即定位，避免"先显历史第一条→再滑到最新"的闪动。
    if (!self.didInitialPosition && self.messages.count > 0 && self.tableView.frame.size.height > 0) {
        [self positionInitialIfNeeded];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self positionInitialIfNeeded]; // 兜底：若 layout 时机未就绪（消息晚到），这里再定位一次
    // 进场动画结束、布局/safe-area inset 完全稳定后再精确贴一次底（无未读且用户未上滚时，#8）。
    if (self.didInitialPosition && [self firstUnreadRow] < 0 && [self isNearBottom]) {
        [self scrollToAbsoluteBottom];
    }
    // 可见即读：把定位后当前可见的消息标为已读（不滚动也算看到）。
    dispatch_async(dispatch_get_main_queue(), ^{ [self markVisibleRowsRead]; });
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController) {
        // 不断开长连接：返回会话列表后仍需常驻接收新消息以实时刷新未读（见 IMConversationListViewController）。
        // 仅交还 delegate，避免离开后本页继续处理消息。
        if (IMSocketManager.sharedManager.delegate == self) {
            IMSocketManager.sharedManager.delegate = nil;
        }
    }
}

#pragma mark - UI

- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.allowsSelection = NO;
    // 点击引用消息 → 跳转原消息（M4-2）。tap 与滚动(pan)/长按共存；非引用消息点击无副作用。
    UITapGestureRecognizer *jumpTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleReplyJumpTap:)];
    jumpTap.cancelsTouchesInView = NO;
    [self.tableView addGestureRecognizer:jumpTap];
    self.tableView.estimatedRowHeight = 56; // 估高更准 → 进会话滚到底更稳，减少自适应高度引起的偏移
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundView = [IMChatBackgroundView new]; // Telegram 绿主题壁纸
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.tableView registerClass:IMBubbleCell.class forCellReuseIdentifier:@"bubble"];
    [self.tableView registerClass:IMSystemCell.class forCellReuseIdentifier:@"system"];
    [self.tableView registerClass:IMImageCell.class forCellReuseIdentifier:@"image"];
    [self.tableView registerClass:IMAlbumCell.class forCellReuseIdentifier:@"album"];        // 相册宫格（leader 行）
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"albumPad"]; // 相册从行（零高占位）
    [self.tableView registerClass:IMChatRecordCell.class forCellReuseIdentifier:@"record"];
    [self.tableView registerClass:IMLinkCardCell.class forCellReuseIdentifier:@"link"];
    [self.view addSubview:self.tableView];

    // 「对方正在输入」提示条（默认高度 0，typing 时展开）。
    self.typingLabel = [UILabel new];
    self.typingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.typingLabel.font = [UIFont systemFontOfSize:12];
    self.typingLabel.textColor = UIColor.secondaryLabelColor;
    self.typingLabel.text = @"对方正在输入…";
    self.typingLabel.clipsToBounds = YES;
    [self.view addSubview:self.typingLabel];

    // 引用预览条（M4-2，默认高度 0；引用时展开：左竖条 + 预览文案 + 取消 ✕）。
    self.replyBar = [UIView new];
    self.replyBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.replyBar.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.replyBar.clipsToBounds = YES;
    [self.view addSubview:self.replyBar];
    UIView *replyStripe = [UIView new];
    replyStripe.translatesAutoresizingMaskIntoConstraints = NO;
    replyStripe.backgroundColor = IMTheme.accent;
    [self.replyBar addSubview:replyStripe];
    self.replyThumb = [UIImageView new];
    self.replyThumb.translatesAutoresizingMaskIntoConstraints = NO;
    self.replyThumb.contentMode = UIViewContentModeScaleAspectFill;
    self.replyThumb.clipsToBounds = YES;
    self.replyThumb.layer.cornerRadius = 4;
    self.replyThumb.hidden = YES;
    [self.replyBar addSubview:self.replyThumb];
    self.replyLabel = [UILabel new];
    self.replyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.replyLabel.font = [UIFont systemFontOfSize:13];
    self.replyLabel.textColor = UIColor.secondaryLabelColor;
    [self.replyBar addSubview:self.replyLabel];
    UIButton *replyCancel = [UIButton buttonWithType:UIButtonTypeSystem];
    replyCancel.translatesAutoresizingMaskIntoConstraints = NO;
    [replyCancel setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    replyCancel.tintColor = UIColor.tertiaryLabelColor;
    [replyCancel addTarget:self action:@selector(cancelReply) forControlEvents:UIControlEventTouchUpInside];
    [self.replyBar addSubview:replyCancel];
    [NSLayoutConstraint activateConstraints:@[
        [replyStripe.leadingAnchor constraintEqualToAnchor:self.replyBar.leadingAnchor constant:12],
        [replyStripe.widthAnchor constraintEqualToConstant:3],
        [replyStripe.topAnchor constraintEqualToAnchor:self.replyBar.topAnchor constant:6],
        [replyStripe.bottomAnchor constraintEqualToAnchor:self.replyBar.bottomAnchor constant:-6],
        [self.replyThumb.leadingAnchor constraintEqualToAnchor:replyStripe.trailingAnchor constant:8],
        [self.replyThumb.centerYAnchor constraintEqualToAnchor:self.replyBar.centerYAnchor],
        [self.replyThumb.widthAnchor constraintEqualToConstant:28],
        [self.replyThumb.heightAnchor constraintEqualToConstant:28],
        [self.replyLabel.centerYAnchor constraintEqualToAnchor:self.replyBar.centerYAnchor],
        [replyCancel.leadingAnchor constraintEqualToAnchor:self.replyLabel.trailingAnchor constant:8],
        [replyCancel.trailingAnchor constraintEqualToAnchor:self.replyBar.trailingAnchor constant:-12],
        [replyCancel.centerYAnchor constraintEqualToAnchor:self.replyBar.centerYAnchor],
    ]];
    // label 前导：无缩略图时贴竖条、有缩略图时贴缩略图（beginReplyTo/cancel 切换）。
    self.replyLabelLeadingNoThumb = [self.replyLabel.leadingAnchor constraintEqualToAnchor:replyStripe.trailingAnchor constant:8];
    self.replyLabelLeadingThumb = [self.replyLabel.leadingAnchor constraintEqualToAnchor:self.replyThumb.trailingAnchor constant:8];
    self.replyLabelLeadingNoThumb.active = YES;

    UIView *inputBar = [UIView new];
    self.inputBar = inputBar;
    inputBar.translatesAutoresizingMaskIntoConstraints = NO;
    inputBar.backgroundColor = UIColor.secondarySystemBackgroundColor;
    [self.view addSubview:inputBar];

    IMPasteImageTextField *pasteField = [IMPasteImageTextField new];
    __weak typeof(self) wsPaste = self;
    pasteField.onPasteImage = ^(UIImage *image) { [wsPaste presentPastedImagePreview:image]; }; // 粘贴图片→预览→发送（#2）
    self.inputField = pasteField;
    self.inputField.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputField.placeholder = @"输入消息…";
    self.inputField.font = [UIFont systemFontOfSize:16];
    self.inputField.returnKeyType = UIReturnKeySend;
    self.inputField.delegate = self;
    // 圆角胶囊输入框（Telegram 风格）。
    self.inputField.backgroundColor = UIColor.systemBackgroundColor;
    self.inputField.layer.cornerRadius = 18;
    self.inputField.layer.borderWidth = 1;
    self.inputField.layer.borderColor = UIColor.separatorColor.CGColor;
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 0)];
    self.inputField.leftView = pad;
    self.inputField.leftViewMode = UITextFieldViewModeAlways;
    [self.inputField addTarget:self action:@selector(inputChanged) forControlEvents:UIControlEventEditingChanged];
    [inputBar addSubview:self.inputField];

    // 微信式输入栏（M4-6）：语音（左）| 输入框 | 表情 | 加号 | 发送。语音/表情当前占位。
    UIImageSymbolConfiguration *barCfg = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightRegular];
    UIButton *voiceButton = [UIButton buttonWithType:UIButtonTypeSystem];
    voiceButton.translatesAutoresizingMaskIntoConstraints = NO;
    [voiceButton setImage:[UIImage systemImageNamed:@"waveform.circle" withConfiguration:barCfg] forState:UIControlStateNormal];
    voiceButton.tintColor = IMTheme.textSecondary;
    [voiceButton addTarget:self action:@selector(voiceTapped) forControlEvents:UIControlEventTouchUpInside];
    [inputBar addSubview:voiceButton];

    UIButton *emojiButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.emojiButton = emojiButton;
    emojiButton.translatesAutoresizingMaskIntoConstraints = NO;
    [emojiButton setImage:[UIImage systemImageNamed:@"face.smiling" withConfiguration:barCfg] forState:UIControlStateNormal];
    emojiButton.tintColor = IMTheme.textSecondary;
    [emojiButton addTarget:self action:@selector(emojiTapped) forControlEvents:UIControlEventTouchUpInside];
    [inputBar addSubview:emojiButton];

    UIButton *plusButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.plusButton = plusButton;
    plusButton.translatesAutoresizingMaskIntoConstraints = NO;
    [plusButton setImage:[UIImage systemImageNamed:@"plus.circle" withConfiguration:barCfg] forState:UIControlStateNormal];
    plusButton.tintColor = IMTheme.textSecondary;
    [plusButton addTarget:self action:@selector(toggleAttachPanel) forControlEvents:UIControlEventTouchUpInside];
    [inputBar addSubview:plusButton];

    // 圆形发送按钮（蓝底上箭头）。有内容时显示、与表情/加号互斥（#4）。
    UIButton *sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.sendButton = sendButton;
    sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightRegular];
    [sendButton setImage:[UIImage systemImageNamed:@"arrow.up.circle.fill" withConfiguration:cfg] forState:UIControlStateNormal];
    sendButton.tintColor = IMTheme.accent;
    [sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [inputBar addSubview:sendButton];

    // 右下角"↓N"悬浮跳转按钮（默认隐藏；滚离底部时出现，点按回到最新；CHAT_UX §7）。
    self.jumpButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.jumpButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *jcfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
    [self.jumpButton setImage:[UIImage systemImageNamed:@"chevron.down" withConfiguration:jcfg] forState:UIControlStateNormal];
    self.jumpButton.tintColor = IMTheme.textPrimary;
    self.jumpButton.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.jumpButton.layer.cornerRadius = 20;
    self.jumpButton.layer.shadowColor = UIColor.blackColor.CGColor;
    self.jumpButton.layer.shadowOpacity = 0.18;
    self.jumpButton.layer.shadowRadius = 4;
    self.jumpButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.jumpButton.hidden = YES;
    [self.jumpButton addTarget:self action:@selector(jumpTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.jumpButton];

    self.jumpBadge = [UILabel new];
    self.jumpBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.jumpBadge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.jumpBadge.textColor = UIColor.whiteColor;
    self.jumpBadge.backgroundColor = IMTheme.unreadBadge; // 与会话列表未读一致（蓝）
    self.jumpBadge.textAlignment = NSTextAlignmentCenter;
    self.jumpBadge.layer.cornerRadius = 9;
    self.jumpBadge.layer.masksToBounds = YES;
    self.jumpBadge.hidden = YES;
    [self.view addSubview:self.jumpBadge];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    self.inputBottom = [inputBar.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor];
    self.typingHeight = [self.typingLabel.heightAnchor constraintEqualToConstant:0];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.typingLabel.topAnchor],

        [self.typingLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.typingLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.typingLabel.bottomAnchor constraintEqualToAnchor:self.replyBar.topAnchor],
        self.typingHeight,

        // 引用条：夹在 typing 与输入栏之间；默认高度 0（cancelReply/showReply 切换）。
        [self.replyBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.replyBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.replyBar.bottomAnchor constraintEqualToAnchor:inputBar.topAnchor],
        (self.replyBarHeight = [self.replyBar.heightAnchor constraintEqualToConstant:0]),

        [inputBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [inputBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.inputBottom,
        [inputBar.heightAnchor constraintEqualToConstant:56],

        // 语音（左）| 输入框 | 表情 | 加号 | 发送（M4-6 微信式）。
        [voiceButton.leadingAnchor constraintEqualToAnchor:inputBar.leadingAnchor constant:8],
        [voiceButton.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [voiceButton.widthAnchor constraintEqualToConstant:34],
        [voiceButton.heightAnchor constraintEqualToConstant:36],
        [self.inputField.leadingAnchor constraintEqualToAnchor:voiceButton.trailingAnchor constant:4],
        [self.inputField.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [self.inputField.heightAnchor constraintEqualToConstant:36],
        // 表情/加号靠右并列；发送按钮与加号同槽位（互斥显示，#4）。
        [emojiButton.trailingAnchor constraintEqualToAnchor:plusButton.leadingAnchor constant:-2],
        [emojiButton.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [emojiButton.widthAnchor constraintEqualToConstant:34],
        [emojiButton.heightAnchor constraintEqualToConstant:36],
        [plusButton.trailingAnchor constraintEqualToAnchor:inputBar.trailingAnchor constant:-8],
        [plusButton.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [plusButton.widthAnchor constraintEqualToConstant:34],
        [plusButton.heightAnchor constraintEqualToConstant:36],
        [sendButton.trailingAnchor constraintEqualToAnchor:inputBar.trailingAnchor constant:-8],
        [sendButton.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [sendButton.widthAnchor constraintEqualToConstant:36],
        [sendButton.heightAnchor constraintEqualToConstant:36],

        [self.jumpButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.jumpButton.bottomAnchor constraintEqualToAnchor:self.typingLabel.topAnchor constant:-12],
        [self.jumpButton.widthAnchor constraintEqualToConstant:40],
        [self.jumpButton.heightAnchor constraintEqualToConstant:40],
        [self.jumpBadge.centerXAnchor constraintEqualToAnchor:self.jumpButton.trailingAnchor constant:-5],
        [self.jumpBadge.centerYAnchor constraintEqualToAnchor:self.jumpButton.topAnchor constant:5],
        [self.jumpBadge.heightAnchor constraintEqualToConstant:18],
        [self.jumpBadge.widthAnchor constraintGreaterThanOrEqualToConstant:18],
    ]];

    // 输入框右缘随内容切换：无内容贴表情、有内容贴发送（#4）。
    self.inputTrailToEmoji = [self.inputField.trailingAnchor constraintEqualToAnchor:emojiButton.leadingAnchor constant:-4];
    self.inputTrailToSend = [self.inputField.trailingAnchor constraintEqualToAnchor:sendButton.leadingAnchor constant:-4];
    [self updateSendButtonVisibility]; // 初始（空）：显示表情/加号，隐藏发送
}

/// 输入框有内容 → 显示发送、隐藏表情/加号；无内容（即便获焦）→ 显示表情/加号、隐藏发送（#4）。
/// 注意：程序化改 text（回填/清空）不触发 EditingChanged，需在改后手动调用本方法。
- (void)updateSendButtonVisibility {
    BOOL hasText = self.inputField.text.length > 0;
    self.sendButton.hidden = !hasText;
    self.emojiButton.hidden = hasText;
    self.plusButton.hidden = hasText;
    self.inputTrailToEmoji.active = !hasText;
    self.inputTrailToSend.active = hasText;
}

#pragma mark - 发送 / 接收

/// 输入变化 → 发「正在输入」（2s 节流，避免每次按键都发）。
- (void)inputChanged {
    [self updateSendButtonVisibility]; // 内容增删 → 切换发送/表情+加号（#4）
    if (self.inputField.text.length == 0) { return; }
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (now - self.lastTypingSent > 2.0) {
        self.lastTypingSent = now;
        [IMSocketManager.sharedManager sendTypingForConv:self.convID];
    }
}

- (void)sendTapped {
    NSString *text = [self.inputField.text stringByTrimmingCharactersInSet:
                      NSCharacterSet.whitespaceAndNewlineCharacterSet];
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
    // 群聊按 conv_id 路由（to 留空，服务端查成员写扩散）；单聊按对端 uid。
    clientMsgID = self.isGroupChat
        ? [IMSocketManager.sharedManager sendText:text toConv:self.convID replyToConvSeq:replySeq completion:completion]
        : [IMSocketManager.sharedManager sendText:text toUser:self.peerID replyToConvSeq:replySeq completion:completion];

    IMMessageModel *m = [IMMessageModel new];
    m.clientMsgID = clientMsgID;
    m.convID = self.convID;
    m.to = self.peerID;
    m.content = text;
    m.from = self.userID;
    m.contentType = @"text";
    m.status = IMMessageStatusSending;
    m.timestamp = (int64_t)(NSDate.date.timeIntervalSince1970 * 1000); // 本地时间，气泡尾巴即时显示时间（与 Web 一致）
    if (replySeq > 0) { // 本端即时快照（服务端会给收件方冻结权威快照；媒体用 [图片]/[视频] 占位）
        m.replyToConvSeq = replySeq;
        m.replySnapshot = IMReplySnippet(self.replyingTo);
    }
    [IMDatabase.sharedDatabase saveMessage:m]; // 落库（sending）
    [self.messages addObject:m];
    self.inputField.text = @"";
    [self updateSendButtonVisibility];
    [self cancelReply];
    [self appendReloadAndScroll];
}

#pragma mark - 引用回复（M4-2）

/// 进入引用态：展开引用条显示预览，聚焦输入框。
- (void)beginReplyTo:(IMMessageModel *)message {
    self.editingMessage = nil; // 引用与编辑互斥（共用引用条）
    self.replyingTo = message;
    NSString *who = [message.from isEqualToString:self.userID] ? @"自己"
        : (self.isGroupChat ? [self senderNameForMessage:message] : (self.peerID ?: @""));
    self.replyLabel.text = [NSString stringWithFormat:@"回复 %@：%@", who, IMReplySnippet(message)];
    // 引用图片/视频：预览条显示一枚小缩略图（#5）。
    BOOL isImage = [message.contentType isEqualToString:@"image"];
    BOOL isVideo = [message.contentType isEqualToString:@"video"];
    [self setReplyThumbForMediaMessage:(isImage || isVideo) ? message : nil isVideo:isVideo];
    self.replyBarHeight.constant = 40;
    [self.inputField becomeFirstResponder];
}

/// 显示/隐藏引用预览条的缩略图并切换 label 前导约束。message=nil → 隐藏（文本引用）。
- (void)setReplyThumbForMediaMessage:(IMMessageModel *)message isVideo:(BOOL)isVideo {
    if (!message) {
        self.replyThumb.hidden = YES;
        self.replyThumb.image = nil;
        self.replyLabelLeadingThumb.active = NO;
        self.replyLabelLeadingNoThumb.active = YES;
        return;
    }
    self.replyThumb.hidden = NO;
    self.replyThumb.image = nil;
    self.replyLabelLeadingNoThumb.active = NO;
    self.replyLabelLeadingThumb.active = YES;
    NSString *url = [self fullMediaURL:message.content];
    __weak typeof(self) ws = self;
    void (^apply)(UIImage *) = ^(UIImage *img) { ws.replyThumb.image = img; };
    if (isVideo) { [[IMVideoThumbnailLoader shared] loadPosterForVideoURL:url completion:apply]; }
    else { [[IMImageLoader shared] loadImageURL:url completion:apply]; }
}

/// 退出引用态（或编辑态，引用条为二者共用）：收起条。
- (void)cancelReply {
    if (self.editingMessage) { [self cancelEdit]; return; }
    self.replyingTo = nil;
    self.replyBarHeight.constant = 0;
    self.replyLabel.text = nil;
    [self setReplyThumbForMediaMessage:nil isVideo:NO];
}

#pragma mark - 收藏（M4-4）

/// 收藏一条消息（内容快照到服务端，原消息撤回/删除后仍在）。
- (void)favoriteMessage:(IMMessageModel *)message {
    if (message.content.length == 0) { return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService addFavoriteWithToken:token contentType:(message.contentType ?: @"text")
                                              content:message.content sourceConvID:message.convID
                                        sourceConvSeq:message.convSeq sourceFrom:(message.from ?: @"")
                                           completion:^(NSError *error) {
        [ws im_showToast:error ? [NSString stringWithFormat:@"收藏失败：%@", error.localizedDescription] : @"已收藏"];
    }];
}

#pragma mark - 编辑 / 翻译（M4-5）

/// 进入编辑态：引用条复用为"编辑消息"预览，输入框回填原文。
- (void)beginEditMessage:(IMMessageModel *)message {
    self.replyingTo = nil;
    self.editingMessage = message;
    [self setReplyThumbForMediaMessage:nil isVideo:NO]; // 编辑仅文本，无缩略图
    self.replyLabel.text = [NSString stringWithFormat:@"编辑消息：%@",
        message.content.length > 40 ? [[message.content substringToIndex:40] stringByAppendingString:@"…"] : (message.content ?: @"")];
    self.replyBarHeight.constant = 40;
    self.inputField.text = message.content;
    [self updateSendButtonVisibility];
    [self.inputField becomeFirstResponder];
}

/// 退出编辑态。
- (void)cancelEdit {
    self.editingMessage = nil;
    self.replyBarHeight.constant = 0;
    self.replyLabel.text = nil;
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

static const CGFloat kIMAttachPanelHeight = 236; // 面板高度（顶起输入栏的量）

/// 展开/收起附件面板（首次点击惰性构建 2×3 网格）。面板显示在输入栏「下方」（微信式）：
/// 展开时收起键盘、把输入栏上顶 kIMAttachPanelHeight，面板填充其下方空间。
- (void)toggleAttachPanel {
    if (!self.attachPanel) { [self buildAttachPanel]; }
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
- (void)presentMediaViewerForMessage:(IMMessageModel *)m preloaded:(UIImage *)image {
    if (m.content.length == 0) { return; }
    BOOL isVideo = [m.contentType isEqualToString:@"video"];
    __weak typeof(self) ws = self;
    IMMediaViewerViewController *viewer =
        [IMMediaViewerViewController viewerWithURL:[self fullMediaURL:m.content]
                                           isVideo:isVideo
                                    preloadedImage:image
                                     onOpenGallery:^{ [ws openConversationMediaGallery]; }];
    // 「更多」外部动作（内置「下载」由查看器自己加在最前）。
    NSMutableArray<IMBottomSheetItem *> *acts = [NSMutableArray array];
    if (m.convSeq > 0) {
        [acts addObject:[IMBottomSheetItem itemWithTitle:@"定位到聊天位置" symbol:@"text.bubble" handler:^{
            [ws jumpToConvSeq:m.convSeq];
        }]];
    }
    [acts addObject:[IMBottomSheetItem itemWithTitle:@"收藏" symbol:@"bookmark" handler:^{ [ws favoriteMessage:m]; }]];
    [acts addObject:[IMBottomSheetItem itemWithTitle:@"复制" symbol:@"doc.on.doc" handler:^{
        [ws copyMessageToPasteboard:m]; // 图片→复制图片字节（可粘贴回输入框发图）；其余→复制链接
    }]];
    if (m.recalledAt == 0 && m.convSeq > 0) {
        [acts addObject:[IMBottomSheetItem itemWithTitle:@"转发" symbol:@"arrowshape.turn.up.right" handler:^{ [ws forwardMessage:m]; }]];
    }
    viewer.moreActions = acts;
    [self presentViewController:viewer animated:YES completion:nil];
}

/// 会话媒体库：汇总当前会话所有图片/视频消息，按时间序展示，点击复用同一查看器。
- (void)openConversationMediaGallery {
    NSMutableArray<IMMediaItem *> *items = [NSMutableArray array];
    for (IMMessageModel *m in self.messages) {
        if (m.recalledAt > 0 || m.content.length == 0) { continue; }
        BOOL isVideo = [m.contentType isEqualToString:@"video"];
        BOOL isImage = [m.contentType isEqualToString:@"image"];
        if (!isVideo && !isImage) { continue; }
        [items addObject:[IMMediaItem itemWithURL:[self fullMediaURL:m.content] isVideo:isVideo timestamp:m.timestamp]];
    }
    IMConversationMediaViewController *gallery = [IMConversationMediaViewController galleryWithItems:items];
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
        m.timestamp = (int64_t)(NSDate.date.timeIntervalSince1970 * 1000);
        [self.messages addObject:m];
        [pending addObject:m];
        self.outboxProgress[m.clientMsgID] = @(0.0); // 排队中 → 环形进度 0%
    }
    [self.tableView reloadData]; // 一次性上屏：宫格只有 1 个可见 cell（从行零高），无逐条插行闪动
    [self scrollToAbsoluteBottom];
    // 缩略图逐格异步补上（拿到即刷对应格子，不动布局/行高）。
    for (NSUInteger i = 0; i < handles.count; i++) {
        IMMessageModel *m = pending[i];
        __weak typeof(self) ws = self;
        [handles[i] loadThumbnail:^(UIImage *thumb) {
            __strong typeof(ws) self = ws;
            if (!self || !thumb) { return; }
            self.outboxPreviews[m.clientMsgID ?: @""] = thumb; // 键随转正式发送迁移（读属性即取最新）
            [self refreshVisibleCellForMessage:m];
        }];
    }
    [self uploadMediaHandles:handles messages:pending index:0];
}

/// 串行处理+上传（避免并发转码/挤占带宽；单项失败标记该格但不中断后续）。
- (void)uploadMediaHandles:(NSArray<IMPickedMediaHandle *> *)handles
                  messages:(NSArray<IMMessageModel *> *)msgs index:(NSUInteger)idx {
    if (idx >= handles.count) { return; }
    IMMessageModel *m = msgs[idx];
    __weak typeof(self) ws = self;
    [handles[idx] loadData:^(IMPickedMedia *item) { // 压缩/转码在句柄内部串行队列执行
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        NSString *token = IMHTTPService.sharedService.currentToken;
        if (item.data.length == 0 || token.length == 0) {
            [self markOutboxFailed:m toastIndex:idx + 1];
            [self uploadMediaHandles:handles messages:msgs index:idx + 1];
            return;
        }
        [IMHTTPService.sharedService uploadData:item.data fileName:item.fileName mimeType:item.mimeType token:token
            progress:^(double fraction) {
                __strong typeof(ws) self2 = ws;
                if (!self2) { return; }
                self2.outboxProgress[m.clientMsgID ?: @""] = @(fraction);
                [self2 updateUploadProgressForMessage:m]; // 只改覆盖层/环 strokeEnd，不 reload（无闪烁）
            }
            completion:^(NSString *url, NSString *contentType, NSError *error) {
                __strong typeof(ws) self2 = ws;
                if (!self2) { return; }
                if (error || url.length == 0) {
                    [self2 markOutboxFailed:m toastIndex:idx + 1];
                } else {
                    [self2 dispatchOutboxMessage:m serverURL:url
                                     contentType:(contentType ?: m.contentType ?: (item.isVideo ? @"video" : @"image"))];
                }
                [self2 uploadMediaHandles:handles messages:msgs index:idx + 1];
            }];
    }];
}

- (void)markOutboxFailed:(IMMessageModel *)m toastIndex:(NSUInteger)n {
    m.status = IMMessageStatusFailed;
    self.outboxProgress[m.clientMsgID ?: @""] = @(-2); // 宫格该格标"!" / 单张气泡居中标"发送失败"
    [self updateUploadProgressForMessage:m];
    [self im_showToast:[NSString stringWithFormat:@"第 %lu 项发送失败", (unsigned long)n]];
}

/// 上传完成 → 转正式发送：预览种进加载器缓存（防切 URL 闪图）。视频先把首帧封面上传，拿到 URL 后带 poster 发送
/// （收端——尤其解不了 HEVC 的 Web——直显封面免解码）；其余直接发送。
- (void)dispatchOutboxMessage:(IMMessageModel *)m serverURL:(NSString *)url contentType:(NSString *)ct {
    NSString *oldKey = m.clientMsgID ?: @"";
    UIImage *preview = self.outboxPreviews[oldKey];
    [self.outboxProgress removeObjectForKey:oldKey];
    NSString *full = IMMediaFullURL(url, self.host);
    if (preview) {
        if ([ct isEqualToString:@"video"]) { [[IMVideoThumbnailLoader shared] cachePoster:preview forURL:full]; }
        else { [[IMImageLoader shared] cacheImage:preview forURL:full]; }
    }
    // 视频封面：把首帧预览图 JPEG 上传作 poster，成功后带 URL 发送；无预览/上传失败则无封面不阻塞发送。
    NSData *posterJPEG = ([ct isEqualToString:@"video"] && preview) ? UIImageJPEGRepresentation(preview, 0.8) : nil;
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (posterJPEG.length > 0 && token.length > 0) {
        __weak typeof(self) ws = self;
        [IMHTTPService.sharedService uploadData:posterJPEG fileName:@"poster.jpg" mimeType:@"image/jpeg" token:token
            completion:^(NSString *posterURL, NSString *pct, NSError *perr) {
                [ws finishOutboxMessage:m serverURL:url contentType:ct
                                 poster:(perr ? @"" : (posterURL ?: @"")) oldKey:oldKey preview:preview];
            }];
        return;
    }
    [self finishOutboxMessage:m serverURL:url contentType:ct poster:@"" oldKey:oldKey preview:preview];
}

/// 真正发送并落库（poster 为已上传的视频封面 URL，可空）。
- (void)finishOutboxMessage:(IMMessageModel *)m serverURL:(NSString *)url contentType:(NSString *)ct
                     poster:(NSString *)poster oldKey:(NSString *)oldKey preview:(UIImage *)preview {
    __weak typeof(self) ws = self;
    IMSendCompletion completion = ^(BOOL success, NSError *error, int64_t convSeq) {
        [ws handleSendResult:success convSeq:convSeq error:error forClientMsgID:m.clientMsgID];
    };
    NSString *toUser = self.isGroupChat ? @"" : self.peerID;
    NSString *realID = [IMSocketManager.sharedManager sendMedia:url contentType:ct
                                                         toConv:self.convID toUser:toUser
                                                        groupID:m.groupID poster:poster completion:completion];
    m.clientMsgID = realID;
    m.content = url;
    m.contentType = ct;
    m.poster = poster.length > 0 ? poster : nil;
    if (preview && realID.length > 0) { self.outboxPreviews[realID] = preview; }
    [self.outboxPreviews removeObjectForKey:oldKey];
    [IMDatabase.sharedDatabase saveMessage:m];
    [self refreshVisibleCellForMessage:m];
}

/// 定点刷新消息的可见 cell：相册成员 → leader 行的宫格只刷格子（不 reload、不动布局）；
/// 普通消息 → reload 自身行（媒体 cell 固定高，不影响滚动位置）。
- (void)refreshVisibleCellForMessage:(IMMessageModel *)m {
    NSUInteger row = [self visibleRowForMessage:m];
    if (row == NSNotFound) { return; }
    NSIndexPath *ip = [NSIndexPath indexPathForRow:(NSInteger)row inSection:0];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:ip];
    if ([cell isKindOfClass:IMAlbumCell.class]) {
        [(IMAlbumCell *)cell refreshWithPreviews:self.outboxPreviews progress:self.outboxProgress];
        return;
    }
    [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}

/// 进度只改可见 cell 的覆盖层/进度环（不 reload，避免高频进度回调闪烁）。
- (void)updateUploadProgressForMessage:(IMMessageModel *)m {
    NSUInteger row = [self visibleRowForMessage:m];
    if (row == NSNotFound) { return; }
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]];
    if ([cell isKindOfClass:IMAlbumCell.class]) {
        [(IMAlbumCell *)cell refreshWithPreviews:self.outboxPreviews progress:self.outboxProgress];
    } else if ([cell isKindOfClass:IMImageCell.class]) {
        NSNumber *p = self.outboxProgress[m.clientMsgID ?: @""];
        [(IMImageCell *)cell setUploadProgress:(p ? p.floatValue : -1)];
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
    IMFilePickerViewController *panel = [[IMFilePickerViewController alloc]
        initWithRecentFiles:[IMRecentFiles listForOwner:self.userID]
        onFromPhotos:^{ [ws openPhotoPicker]; }
        onFromFiles:^{ [ws presentDocumentPicker]; }
        onPickRecent:^(NSString *url, NSString *name) { [ws sendMediaURL:url contentType:@"file"]; }];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:panel];
    [self presentViewController:nav animated:YES completion:nil];
}

/// 系统文档选择器（可访问 iCloud/本机「文件」App，拷贝模式）→ 上传 → 发文件消息 + 记入最近文件。
- (void)presentDocumentPicker {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    picker.allowsMultipleSelection = NO;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) { return; }
    NSData *data = [NSData dataWithContentsOfURL:url];
    NSString *token = IMHTTPService.sharedService.currentToken;
    NSString *originalName = url.lastPathComponent ?: @"file.bin";
    if (data.length == 0 || token.length == 0) { [self im_showToast:@"文件读取失败"]; return; }
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
        [IMRecentFiles recordForOwner:self.userID url:up name:originalName]; // 记入最近文件
        [self sendMediaURL:up contentType:(contentType ?: @"file")];
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
        [self sendMediaURL:url contentType:(contentType ?: @"image")];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

/// 发送已上传的媒体：走 socket sendMedia，乐观上屏。
- (void)sendMediaURL:(NSString *)url contentType:(NSString *)contentType {
    __block NSString *clientMsgID = nil;
    __weak typeof(self) ws = self;
    IMSendCompletion completion = ^(BOOL success, NSError *error, int64_t convSeq) {
        [ws handleSendResult:success convSeq:convSeq error:error forClientMsgID:clientMsgID];
    };
    NSString *toUser = self.isGroupChat ? @"" : self.peerID;
    clientMsgID = [IMSocketManager.sharedManager sendMedia:url contentType:contentType toConv:self.convID toUser:toUser completion:completion];

    IMMessageModel *m = [IMMessageModel new];
    m.clientMsgID = clientMsgID; m.convID = self.convID; m.to = self.peerID; m.from = self.userID;
    m.content = url; m.contentType = contentType; m.status = IMMessageStatusSending;
    m.timestamp = (int64_t)(NSDate.date.timeIntervalSince1970 * 1000);
    [IMDatabase.sharedDatabase saveMessage:m];
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

/// 粘贴图片预览（#2）：蒙层 + 图片 + 取消/发送。发送 = JPEG 压缩 → 上传 → 发 image 消息。
- (void)presentPastedImagePreview:(UIImage *)image {
    UIView *mask = [UIView new];
    mask.frame = self.view.bounds;
    mask.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    mask.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    [self.view addSubview:mask];

    UIImageView *iv = [[UIImageView alloc] initWithImage:image];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.layer.cornerRadius = 12;
    iv.clipsToBounds = YES;
    [mask addSubview:iv];

    UIButton *(^makeBtn)(NSString *, UIColor *) = ^(NSString *title, UIColor *bg) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.translatesAutoresizingMaskIntoConstraints = NO;
        [b setTitle:title forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        b.backgroundColor = bg;
        b.layer.cornerRadius = 20;
        [mask addSubview:b];
        return b;
    };
    UIButton *cancel = makeBtn(@"取消", [UIColor colorWithWhite:0.25 alpha:1]);
    UIButton *sendBtn = makeBtn(@"发送", IMTheme.accent);
    [NSLayoutConstraint activateConstraints:@[
        [iv.centerXAnchor constraintEqualToAnchor:mask.centerXAnchor],
        [iv.centerYAnchor constraintEqualToAnchor:mask.centerYAnchor constant:-30],
        [iv.widthAnchor constraintLessThanOrEqualToAnchor:mask.widthAnchor constant:-48],
        [iv.heightAnchor constraintLessThanOrEqualToAnchor:mask.heightAnchor multiplier:0.6],
        [cancel.trailingAnchor constraintEqualToAnchor:mask.centerXAnchor constant:-16],
        [cancel.topAnchor constraintEqualToAnchor:iv.bottomAnchor constant:24],
        [cancel.widthAnchor constraintEqualToConstant:120],
        [cancel.heightAnchor constraintEqualToConstant:40],
        [sendBtn.leadingAnchor constraintEqualToAnchor:mask.centerXAnchor constant:16],
        [sendBtn.centerYAnchor constraintEqualToAnchor:cancel.centerYAnchor],
        [sendBtn.widthAnchor constraintEqualToConstant:120],
        [sendBtn.heightAnchor constraintEqualToConstant:40],
    ]];

    __weak typeof(self) ws = self;
    [cancel addAction:[UIAction actionWithHandler:^(UIAction *a) { [mask removeFromSuperview]; }]
     forControlEvents:UIControlEventTouchUpInside];
    [sendBtn addAction:[UIAction actionWithHandler:^(UIAction *a) {
        [mask removeFromSuperview];
        [ws uploadAndSendPastedImage:image];
    }] forControlEvents:UIControlEventTouchUpInside];
}

- (void)uploadAndSendPastedImage:(UIImage *)image {
    NSData *jpeg = UIImageJPEGRepresentation(image, 0.8);
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (jpeg.length == 0 || token.length == 0) { [self im_showToast:@"图片处理失败"]; return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService uploadData:jpeg fileName:@"pasted.jpg" mimeType:@"image/jpeg" token:token
                                 completion:^(NSString *url, NSString *contentType, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error || url.length == 0) { [self im_showToast:@"图片上传失败"]; return; }
        [self sendMediaURL:url contentType:(contentType ?: @"image")];
    }];
}

#pragma mark - 转发（M4-3）

/// 转发一条消息（#6）：整页会话选择器（单/多选，最多 9）→ 逐条转发，保留 content_type（图片/视频不退化成文本）。
- (void)forwardMessage:(IMMessageModel *)message {
    if (message.content.length == 0 || message.recalledAt > 0) { return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    NSString *origin = message.forwardFrom.length > 0 ? message.forwardFrom
        : (message.fromNickname.length > 0 ? message.fromNickname : (message.from ?: @"")); // 转发链保留最初作者
    NSString *content = message.content;
    NSString *contentType = message.contentType ?: @"text";
    __weak typeof(self) ws = self;
    IMForwardPickerViewController *picker = [[IMForwardPickerViewController alloc]
        initWithHost:self.host token:token onDone:^(NSArray<IMConversation *> *selected) {
        __strong typeof(ws) self = ws;
        if (!self || selected.count == 0) { return; }
        for (IMConversation *c in selected) {
            NSString *toUser = c.isGroup ? @"" : (c.peer ?: @"");
            [self forwardEchoContent:content contentType:contentType forwardFrom:origin
                              toConv:c.convID toUser:toUser];
        }
        [self im_showToast:selected.count == 1 ? @"已转发" : [NSString stringWithFormat:@"已转发到 %lu 个会话", (unsigned long)selected.count]];
    }];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    [self presentViewController:nav animated:YES completion:nil];
}

/// 点击引用消息（有 replyToConvSeq）→ 跳到原消息；其余点击忽略。附件面板展开时点空白先收起面板（#3）。
- (void)handleReplyJumpTap:(UITapGestureRecognizer *)gr {
    if (self.selecting) { return; } // 多选态：点击交给表格选中，不触发引用跳转
    if (self.attachPanelVisible) { [self showAttachPanel:NO]; return; }
    CGPoint p = [gr locationInView:self.tableView];
    NSIndexPath *ip = [self.tableView indexPathForRowAtPoint:p];
    if (!ip || ip.row >= (NSInteger)self.messages.count) { return; }
    IMMessageModel *m = self.messages[(NSUInteger)ip.row];
    if (m.replyToConvSeq > 0) { [self jumpToConvSeq:m.replyToConvSeq]; return; }
    if (m.recalledAt > 0) { return; }
    // 文件消息 → 打开/下载（URL 文本消息由独立的链接卡片 cell 自行处理点击，不在此重复）。
    if ([m.contentType isEqualToString:@"file"]) { [self openLink:[self fullMediaURL:m.content]]; }
}

/// 应用内浏览器打开链接（SFSafariViewController，仅接受 http/https）。
- (void)openLink:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString ?: @""];
    if (!url || !([url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"https"])) { return; }
    SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:url];
    [self presentViewController:safari animated:YES completion:nil];
}

/// 跳转到被引用的原消息：滚到该 conv_seq 行（不在已加载窗口则提示）。
- (void)jumpToConvSeq:(int64_t)targetConvSeq {
    for (NSUInteger i = 0; i < self.messages.count; i++) {
        if (self.messages[i].convSeq == targetConvSeq) {
            [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]
                                  atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
            return;
        }
    }
    [self im_showToast:@"原消息不在当前视图"];
}

- (void)handleSendResult:(BOOL)success convSeq:(int64_t)convSeq error:(NSError *)error forClientMsgID:(NSString *)clientMsgID {
    // 结果到来前先记录是否贴底：被拒收会给该条挂"系统行"，cell 随之变高，
    // 不重新贴底则系统行被顶出屏幕（需手动下滚才可见）。自己发的消息贴底（CHAT_UX §9）。
    BOOL wasNearBottom = [self isNearBottom];
    for (IMMessageModel *m in self.messages) {
        if ([m.clientMsgID isEqualToString:clientMsgID]) {
            m.status = success ? IMMessageStatusSent : IMMessageStatusFailed;
            // 被拒收 → 把服务端友好文案挂到 note，气泡下方居中显示（微信式系统行）；其余失败（如 ack 超时）不挂 note，仍显"未发送 ✗"。
            // 覆盖：被拉黑 200102 / 被禁言 300004 / 非群成员 300203 / 群全员禁言 300206（后端回「本群已开启全员禁言」）。
            m.note = (!success && (error.code == 200102 || error.code == 300004 ||
                                   error.code == 300203 || error.code == 300206)) ? error.localizedDescription : nil;
            m.convSeq = convSeq;
            [IMDatabase.sharedDatabase saveMessage:m]; // upsert：更新状态/conv_seq/note（含被拒文案，重进会话不丢）
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

#pragma mark - IMSocketManagerDelegate（主线程回调）

- (void)socketManager:(IMSocketManager *)manager didChangeState:(IMSocketState)state {
    self.connState = state;
    [self updateTitle];
    if (state == IMSocketStateConnected) {
        [self markVisibleRowsRead]; // 重连后把当前可见的补报一次已读（可见即读）
    }
}

/// 标题：单聊=在线点 + 对方 uid + 连接态；群聊=群名（N人）+ 连接态。
- (void)updateTitle {
    NSString *suffix = @"";
    switch (self.connState) {
        case IMSocketStateConnected:    suffix = @""; break;
        case IMSocketStateConnecting:   suffix = @"（连接中…）"; break;
        case IMSocketStateDisconnected: suffix = @"（未连接）"; break;
    }
    if (self.isGroupChat) {
        NSString *name = self.groupName.length > 0 ? self.groupName : @"群聊";
        NSUInteger count = self.groupInfo.members.count;
        NSString *countStr = count > 0 ? [NSString stringWithFormat:@"（%lu人）", (unsigned long)count] : @"";
        self.title = [NSString stringWithFormat:@"%@%@%@", name, countStr, suffix];
        return;
    }
    NSString *dot = self.peerOnline ? @"🟢 " : @"";
    if (self.connState == IMSocketStateConnected && self.peerOnline) { suffix = @"（在线）"; }
    self.title = [NSString stringWithFormat:@"%@%@%@", dot, self.peerID, suffix];
}

- (void)socketManager:(IMSocketManager *)manager didReceiveMessage:(IMMessageModel *)message {
    [IMDatabase.sharedDatabase saveMessage:message]; // 任何会话的消息都落库（按 conv_seq 幂等）
    if (![message.convID isEqualToString:self.convID]) { return; } // 非本会话不在此页显示
    // 同一条消息可能既被 new_msg 推送、又被 sync_resp 拉到，按 conv_seq 去重。
    if (message.convSeq > 0) {
        NSNumber *key = @(message.convSeq);
        if ([self.seenConvSeqs containsObject:key]) { return; }
        [self.seenConvSeqs addObject:key];
    }
    // 收到新消息：贴底才自动贴底；在上方看历史则不打断，累加到"↓N"（CHAT_UX §9）。
    BOOL wasNearBottom = [self isNearBottom];
    [self.messages addObject:message];
    [self.tableView reloadData];
    if (wasNearBottom) { [self scrollToBottomAnimated:YES]; }
    // 可见即读 + ↓N 刷新：贴底时新消息进视口即标已读；在上方看历史则不读、↓N 计数 +1（markVisibleRowsRead 内重算）。
    [self markVisibleRowsRead];
}

/// 对端已读到 upToConvSeq → 记录并刷新（已送达 → 已读）。
- (void)socketManager:(IMSocketManager *)manager didReadConv:(NSString *)convID by:(NSString *)from upToConvSeq:(int64_t)convSeq {
    if (![convID isEqualToString:self.convID] || [from isEqualToString:self.userID]) { return; }
    if (convSeq > self.peerReadSeq) {
        self.peerReadSeq = convSeq;
        [self.tableView reloadData];
    }
}

/// 对端正在输入 → 展开提示条，3s 后自动收起（群聊显示"谁"在输入）。
- (void)socketManager:(IMSocketManager *)manager didTypingInConv:(NSString *)convID by:(NSString *)from {
    if (![convID isEqualToString:self.convID] || [from isEqualToString:self.userID]) { return; }
    if (self.isGroupChat) {
        NSString *nick = [self.groupInfo nicknameOfMember:from];
        self.typingLabel.text = [NSString stringWithFormat:@"%@ 正在输入…", nick.length > 0 ? nick : from];
    }
    self.typingHeight.constant = 20;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideTyping) object:nil];
    [self performSelector:@selector(hideTyping) withObject:nil afterDelay:3.0];
}

- (void)hideTyping {
    self.typingHeight.constant = 0;
}

/// 对端在线状态变化 → 更新标题在线点。
- (void)socketManager:(IMSocketManager *)manager didChangePresenceForUser:(NSString *)user online:(BOOL)online {
    if (![user isEqualToString:self.peerID]) { return; }
    self.peerOnline = online;
    [self updateTitle];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendTapped];
    return NO;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMMessageModel *m = self.messages[indexPath.row];
    // 系统消息（群邀请/移除/转让/禁言等留痕）：独立居中灰字行，无气泡/头像/时间勾。
    if ([m.contentType isEqualToString:@"system"]) {
        IMSystemCell *sys = [tableView dequeueReusableCellWithIdentifier:@"system" forIndexPath:indexPath];
        [sys configureWithText:m.content];
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
        [rec configureWithMessage:m mine:[m.from isEqualToString:self.userID]];
        __weak typeof(self) ws = self;
        rec.onTap = ^{ [ws openChatRecord:m]; };
        return rec;
    }
    // 纯 URL 文本消息：URL 文本 + 链接富预览卡片（OG），点击应用内打开（带引用时也显示引用行+卡片）。
    if ([m.contentType isEqualToString:@"text"] && m.recalledAt == 0 && m.translation.length == 0 && IMLooksLikeURL(m.content)) {
        IMLinkCardCell *link = [tableView dequeueReusableCellWithIdentifier:@"link" forIndexPath:indexPath];
        [link configureWithMessage:m mine:[m.from isEqualToString:self.userID]];
        __weak typeof(self) ws = self;
        link.onTap = ^(NSString *url) { [ws openLink:url]; };
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
        [alb configureWithMembers:members mine:mineAlb host:self.host
                         previews:self.outboxPreviews progress:self.outboxProgress senderName:senderNameAlb];
        [alb applyGroupAvatarURL:(grpAlb ? [self senderAvatarURLForMessage:m] : nil)
                            seed:(m.from ?: @"") name:(grpAlb ? [self senderNameForMessage:m] : nil)
                      showAvatar:lastAlb gutter:grpAlb];
        __weak typeof(self) ws = self;
        alb.onTapItem = ^(IMMessageModel *mm) {
            if (mm.content.length > 0) { [ws presentMediaViewerForMessage:mm preloaded:nil]; } // 上传中不可点
        };
        alb.menuForItem = ^UIMenu *(IMMessageModel *mm) {
            __strong typeof(ws) self = ws;
            if (!self || mm.content.length == 0) { return nil; } // 上传中无菜单
            return [IMMenuAction menuWithActions:[self messageActionsForMessage:mm
                                                                           mine:[mm.from isEqualToString:self.userID]]];
        };
        return alb;
    }
    // 图片/视频消息（M4-6）：独立媒体 cell。图片显缩略图、视频显首帧+播放角标（不自动播放）；点击进全屏查看器。
    // 上传中的乐观气泡：content 为空 → 显本地预览 + 居中进度（批量发送 UX）。
    if ([m.contentType isEqualToString:@"image"] || [m.contentType isEqualToString:@"video"]) {
        IMImageCell *img = [tableView dequeueReusableCellWithIdentifier:@"image" forIndexPath:indexPath];
        BOOL mineI = [m.from isEqualToString:self.userID];
        BOOL isVideo = [m.contentType isEqualToString:@"video"];
        NSString *key = m.clientMsgID ?: @"";
        BOOL grpI = self.isGroupChat && !mineI;
        BOOL firstI = grpI && [self isFirstInSenderRun:indexPath.row];
        BOOL lastI = grpI && [self isLastInSenderRun:indexPath.row];
        NSString *senderNameI = firstI ? [self senderNameForMessage:m] : nil;
        [img configureWithURL:(m.content.length > 0 ? [self fullMediaURL:m.content] : @"")
                      isVideo:isVideo mine:mineI previewImage:self.outboxPreviews[key] senderName:senderNameI];
        [img applyGroupAvatarURL:(grpI ? [self senderAvatarURLForMessage:m] : nil)
                            seed:(m.from ?: @"") name:(grpI ? [self senderNameForMessage:m] : nil)
                      showAvatar:lastI gutter:grpI];
        NSNumber *prog = self.outboxProgress[key];
        [img setUploadProgress:(prog ? prog.floatValue : -1)];
        __weak typeof(self) ws = self;
        img.onTap = ^(UIImage *image) { [ws presentMediaViewerForMessage:m preloaded:image]; };
        return img;
    }
    IMBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"bubble" forIndexPath:indexPath];
    BOOL mine = [m.from isEqualToString:self.userID];
    BOOL showsDivider = (indexPath.row == [self firstUnreadRow]);
    // 群聊：对方气泡带发送者昵称（自己/单聊不带）；连续同发送者只首条显名、末条显头像（Telegram 式）。
    BOOL grp = self.isGroupChat && !mine;
    BOOL firstInRun = grp && [self isFirstInSenderRun:indexPath.row];
    BOOL lastInRun = grp && [self isLastInSenderRun:indexPath.row];
    NSString *senderName = firstInRun ? [self senderNameForMessage:m] : nil;
    // 引用的是图片/视频：把原消息的媒体 URL 传给 cell，引用条内显示真缩略图（#4）。
    NSString *replyThumbURL = nil;
    BOOL replyThumbIsVideo = NO;
    if (m.replyToConvSeq > 0) {
        IMMessageModel *target = [self messageWithConvSeq:m.replyToConvSeq];
        if (target && ([target.contentType isEqualToString:@"image"] || [target.contentType isEqualToString:@"video"])
            && target.recalledAt == 0 && target.content.length > 0) {
            replyThumbURL = [self fullMediaURL:target.content];
            replyThumbIsVideo = [target.contentType isEqualToString:@"video"];
        }
    }
    [cell configureWithMessage:m mine:mine peerReadSeq:self.peerReadSeq
                     dayHeader:[self dayHeaderForRow:indexPath.row]
            showsUnreadDivider:showsDivider
                    senderName:senderName
                 replyThumbURL:replyThumbURL
             replyThumbIsVideo:replyThumbIsVideo];
    [cell applyGroupAvatarURL:(grp ? [self senderAvatarURLForMessage:m] : nil)
                         seed:(m.from ?: @"") name:(grp ? [self senderNameForMessage:m] : nil)
                   showAvatar:lastInRun gutter:grp];
    return cell;
}

#pragma mark - 相册聚簇（M4+：同 group_id 的多图/视频渲染为一个宫格）

/// 相册成员判定：有 group_id 的图片/视频且未撤回。**多选态不聚簇**（展开成独立行以便逐条勾选/转发）。
- (BOOL)isAlbumMember:(IMMessageModel *)m {
    return !self.selecting && m.groupID.length > 0 && m.recalledAt == 0
        && ([m.contentType isEqualToString:@"image"] || [m.contentType isEqualToString:@"video"]);
}

/// 该行是否相册"从行"：同组首个成员为主行（渲染整个宫格），其余成员行零高隐藏。
/// 同批消息相邻发送，向前找通常 1~2 步即命中。
- (BOOL)isAlbumFollowerAtRow:(NSInteger)row {
    IMMessageModel *m = self.messages[(NSUInteger)row];
    if (![self isAlbumMember:m]) { return NO; }
    for (NSInteger i = row - 1; i >= 0; i--) {
        IMMessageModel *p = self.messages[(NSUInteger)i];
        if (p.groupID.length > 0 && [p.groupID isEqualToString:m.groupID] && [self isAlbumMember:p]) { return YES; }
    }
    return NO;
}

/// 同组全部成员（按消息顺序）。
- (NSArray<IMMessageModel *> *)albumMembersForGroupID:(NSString *)gid {
    NSMutableArray<IMMessageModel *> *out = [NSMutableArray array];
    for (IMMessageModel *m in self.messages) {
        if (m.groupID.length > 0 && [m.groupID isEqualToString:gid] && [self isAlbumMember:m]) { [out addObject:m]; }
    }
    return out;
}

/// 消息所属的"可见行"：相册成员 → 该组 leader 行；普通消息 → 自身行。NSNotFound=不在列表。
- (NSUInteger)visibleRowForMessage:(IMMessageModel *)m {
    NSUInteger own = [self.messages indexOfObjectIdenticalTo:m];
    if (own == NSNotFound || ![self isAlbumMember:m]) { return own; }
    for (NSUInteger i = 0; i <= own; i++) {
        IMMessageModel *p = self.messages[i];
        if (p.groupID.length > 0 && [p.groupID isEqualToString:m.groupID] && [self isAlbumMember:p]) { return i; }
    }
    return own;
}

/// 从行零高（宫格已在 leader 行整体渲染）；其余行自适应。
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row < (NSInteger)self.messages.count && [self isAlbumFollowerAtRow:indexPath.row]) { return 0; }
    return UITableViewAutomaticDimension;
}

/// 按 conv_seq 找已加载的消息（引用缩略图解析用；不在窗口内返回 nil）。
- (IMMessageModel *)messageWithConvSeq:(int64_t)convSeq {
    for (IMMessageModel *x in self.messages) {
        if (x.convSeq == convSeq) { return x; }
    }
    return nil;
}

/// 按时间分组：每自然日首条消息上方显示日期分隔胶囊（今天/昨天/M月d日）。无效时间或同日返回 nil。
- (NSString *)dayHeaderForRow:(NSInteger)row {
    IMMessageModel *m = self.messages[row];
    if (m.timestamp <= 0) { return nil; } // 发送中（未拿到服务端时间）不显示日期
    if (row == 0) { return [IMTheme dayHeaderStringFromMillis:m.timestamp]; }
    IMMessageModel *prev = self.messages[row - 1];
    if ([IMTheme isMillis:m.timestamp sameDayAsMillis:prev.timestamp]) { return nil; }
    return [IMTheme dayHeaderStringFromMillis:m.timestamp];
}

#pragma mark - 长按消息菜单（数据驱动：IMMenuAction 单一来源）

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
    contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    if (self.selecting) { return nil; } // 多选态无长按菜单
    if (indexPath.row >= (NSInteger)self.messages.count) { return nil; }
    IMMessageModel *message = self.messages[indexPath.row];
    if ([message.contentType isEqualToString:@"system"]) { return nil; } // 系统消息无操作菜单
    if (message.recalledAt > 0) { return nil; } // 撤回墓碑无操作菜单
    if ([self isAlbumMember:message]) { return nil; } // 相册宫格：菜单由每个格子自带（定位到单条成员）
    BOOL mine = [message.from isEqualToString:self.userID];
    NSArray<IMMenuAction *> *actions = [self messageActionsForMessage:message mine:mine];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
            return [IMMenuAction menuWithActions:actions];
        }];
}

/// 单条消息的菜单动作（按显示顺序，仅含可见项）：
/// 复制 / 引用 / 转发 / 收藏 / 撤回(仅自己且有真实 conv_seq) / 多选 / 翻译 / 删除(破坏性)；
/// 对方消息额外含 举报消息 / 举报发送者。已接：复制、删除、举报*；其余 → 开发中吐司。
- (NSArray<IMMenuAction *> *)messageActionsForMessage:(IMMessageModel *)message mine:(BOOL)mine {
    __weak typeof(self) ws = self;
    NSMutableArray<IMMenuAction *> *actions = [NSMutableArray array];

    [actions addObject:[IMMenuAction actionWithId:@"copy" title:@"复制" image:@"doc.on.doc" handler:^{
        [ws copyMessageToPasteboard:message];
    }]];
    if (message.recalledAt == 0 && message.convSeq > 0) {
        [actions addObject:[IMMenuAction actionWithId:@"reply" title:@"引用" image:@"arrowshape.turn.up.left" handler:^{
            [ws beginReplyTo:message];
        }]];
    }
    if (message.recalledAt == 0 && message.convSeq > 0) {
        [actions addObject:[IMMenuAction actionWithId:@"forward" title:@"转发" image:@"arrowshape.turn.up.right" handler:^{
            [ws forwardMessage:message];
        }]];
    }
    // 收藏：文本/图片/视频/文件/链接均可（快照存 content+content_type，后端通用；system/撤回除外）。
    if (message.content.length > 0 && message.recalledAt == 0 && ![message.contentType isEqualToString:@"system"]) {
        [actions addObject:[IMMenuAction actionWithId:@"favorite" title:@"收藏" image:@"bookmark" handler:^{
            [ws favoriteMessage:message];
        }]];
    }
    // 撤回（M4-1）：仅本人、已拿到 conv_seq、未撤回、2min 窗口内（服务端为准，此处仅避免必然失败的入口）。
    int64_t nowMs = (int64_t)([NSDate date].timeIntervalSince1970 * 1000);
    if (mine && message.convSeq > 0 && message.recalledAt == 0 && (nowMs - message.timestamp) <= kIMRecallWindowMs) {
        [actions addObject:[IMMenuAction actionWithId:@"recall" title:@"撤回" image:@"arrow.uturn.backward" handler:^{
            [IMSocketManager.sharedManager recallMessageInConv:(message.convID ?: @"") targetConvSeq:message.convSeq];
        }]];
    }
    // 编辑（M4-5）：仅本人文本、未撤回。
    if (mine && [message.contentType isEqualToString:@"text"] && message.content.length > 0 && message.recalledAt == 0) {
        [actions addObject:[IMMenuAction actionWithId:@"edit" title:@"编辑" image:@"pencil" handler:^{
            [ws beginEditMessage:message];
        }]];
    }
    [actions addObject:[IMMenuAction actionWithId:@"multiSelect" title:@"多选" image:@"checkmark.circle" handler:^{
        [ws enterSelectionWithMessage:message];
    }]];
    if ([message.contentType isEqualToString:@"text"] && message.content.length > 0 && message.recalledAt == 0) {
        [actions addObject:[IMMenuAction actionWithId:@"translate" title:@"翻译" image:@"character.bubble" handler:^{
            [ws translateMessage:message];
        }]];
    }
    // 举报（AG-3）：仅对方消息可举报。举报消息用 conv_seq 定位（与 Web 一致）。
    if (!mine) {
        [actions addObject:[IMMenuAction actionWithId:@"reportMessage" title:@"举报消息" image:@"exclamationmark.bubble" handler:^{
            [ws reportTargetType:@"message" targetID:[@(message.convSeq) stringValue] title:@"举报这条消息"];
        }]];
        [actions addObject:[IMMenuAction actionWithId:@"reportUser" title:@"举报发送者" image:@"person.crop.circle.badge.exclamationmark" handler:^{
            [ws reportTargetType:@"user" targetID:(message.from ?: @"") title:[NSString stringWithFormat:@"举报用户 %@", message.from]];
        }]];
    }
    [actions addObject:[IMMenuAction destructiveActionWithId:@"delete" title:@"删除" image:@"trash" handler:^{
        [ws deleteMessage:message];
    }]];
    return actions;
}

/// 本地删除一条消息（仅本端：从库 + 内存移除并刷新；不影响对端）。
- (void)deleteMessage:(IMMessageModel *)message {
    [IMDatabase.sharedDatabase deleteMessage:message];
    [self.messages removeObject:message];
    if (message.convSeq > 0) { [self.seenConvSeqs removeObject:@(message.convSeq)]; }
    [self.tableView reloadData];
}

#pragma mark - 多选态（#2：转发/收藏/删除）

/// 进入多选：表格进入编辑多选态，隐藏输入栏、显示底部工具栏，并默认选中触发的那条。
- (void)enterSelectionWithMessage:(IMMessageModel *)message {
    if (self.selecting) { return; }
    self.selecting = YES;
    [self showAttachPanel:NO];
    [self cancelReply];
    [self.inputField resignFirstResponder];

    self.tableView.allowsMultipleSelectionDuringEditing = YES;
    [self.tableView setEditing:YES animated:YES];
    [self.tableView reloadData]; // 相册宫格展开为独立行（逐条可勾选）；isAlbumMember 在多选态恒 NO
    // 已在屏上的 cell 不会再走 willDisplay，就地改 selectionStyle 让勾选态可见（#5）。
    for (UITableViewCell *c in self.tableView.visibleCells) { [self applySelectionStyleForCell:c]; }

    [self buildSelectionBarIfNeeded];
    self.selectionBar.hidden = NO;
    self.inputBar.hidden = YES;

    self.savedTitle = self.title;
    self.savedRightItem = self.navigationItem.rightBarButtonItem;
    self.navigationItem.rightBarButtonItem = nil;
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(exitSelection)];

    NSUInteger row = [self.messages indexOfObject:message];
    if (row != NSNotFound) {
        [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]
                                    animated:NO scrollPosition:UITableViewScrollPositionNone];
    }
    [self updateSelectionUI];
}

- (void)exitSelection {
    if (!self.selecting) { return; }
    self.selecting = NO;
    [self.tableView setEditing:NO animated:YES];
    [self.tableView reloadData]; // 相册宫格恢复聚簇渲染
    for (UITableViewCell *c in self.tableView.visibleCells) { [self applySelectionStyleForCell:c]; }
    self.selectionBar.hidden = YES;
    self.inputBar.hidden = NO;
    self.title = self.savedTitle;
    self.navigationItem.leftBarButtonItem = nil; // 恢复默认返回
    self.navigationItem.rightBarButtonItem = self.savedRightItem;
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
        NSString *json = [ws mergedForwardJSONForMessages:msgs];
        [ws pickConversationsThen:^(NSArray<IMConversation *> *convs) { [ws forwardMergedRecord:json toConversations:convs]; }];
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
- (void)forwardEchoContent:(NSString *)content contentType:(NSString *)ct forwardFrom:(NSString *)origin
                    toConv:(NSString *)convID toUser:(NSString *)toUser {
    IMMessageModel *m = [IMMessageModel new];
    __weak typeof(self) ws = self;
    NSString *clientMsgID = [IMSocketManager.sharedManager forwardContent:content contentType:ct
                                                                   toConv:convID toUser:toUser forwardFrom:origin
                                                               completion:^(BOOL success, NSError *error, int64_t convSeq) {
        m.status = success ? IMMessageStatusSent : IMMessageStatusFailed;
        m.convSeq = convSeq;
        [IMDatabase.sharedDatabase saveMessage:m];
        __strong typeof(ws) self = ws;
        if (self && [convID isEqualToString:self.convID]) {
            if (convSeq > 0) { [self.seenConvSeqs addObject:@(convSeq)]; } // 防 sync 重复回显
            [self.tableView reloadData];
        }
    }];
    m.clientMsgID = clientMsgID;
    m.convID = convID; m.to = toUser; m.from = self.userID;
    m.content = content; m.contentType = ct;
    m.forwardFrom = origin.length > 0 ? origin : nil;
    m.status = IMMessageStatusSending;
    m.timestamp = (int64_t)(NSDate.date.timeIntervalSince1970 * 1000);
    [IMDatabase.sharedDatabase saveMessage:m];
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
    for (IMConversation *c in convs) {
        NSString *toUser = c.isGroup ? @"" : (c.peer ?: @"");
        for (IMMessageModel *m in msgs) {
            if (m.recalledAt > 0 || m.content.length == 0 || [m.contentType isEqualToString:@"system"]) { continue; }
            NSString *origin = m.forwardFrom.length > 0 ? m.forwardFrom
                : (m.fromNickname.length > 0 ? m.fromNickname : (m.from ?: @""));
            [self forwardEchoContent:m.content contentType:(m.contentType ?: @"text") forwardFrom:origin
                              toConv:c.convID toUser:toUser];
        }
    }
    [self exitSelection];
    [self im_showToast:convs.count == 1 ? @"已转发" : [NSString stringWithFormat:@"已转发到 %lu 个会话", (unsigned long)convs.count]];
}

- (void)forwardMergedRecord:(NSString *)json toConversations:(NSArray<IMConversation *> *)convs {
    if (json.length == 0) { return; }
    for (IMConversation *c in convs) {
        NSString *toUser = c.isGroup ? @"" : (c.peer ?: @"");
        [self forwardEchoContent:json contentType:@"chat_record" forwardFrom:@""
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
            [IMDatabase.sharedDatabase deleteMessage:m];
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

/// 合并转发内容：JSON（t=标题，items=[{n:发送者, ct:类型, c:内容/URL}]），content_type=chat_record。
- (NSString *)mergedForwardJSONForMessages:(NSArray<IMMessageModel *> *)msgs {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (IMMessageModel *m in msgs) {
        if (m.recalledAt > 0 || [m.contentType isEqualToString:@"system"] || m.content.length == 0) { continue; }
        [items addObject:@{ @"n": [self displayNameForMessage:m] ?: @"",
                            @"ct": m.contentType ?: @"text",
                            @"c": m.content ?: @"" }];
    }
    // 多选态下 self.title 已被替换为"已选择 N 条"，用 savedTitle 取真实会话名。
    NSString *base = self.savedTitle.length ? self.savedTitle : (self.title.length ? self.title : (self.peerID ?: @"聊天"));
    NSDictionary *dict = @{ @"t": [NSString stringWithFormat:@"%@ 的聊天记录", base], @"items": items };
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:NULL];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
}

#pragma mark - 编辑/选择 delegate

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.selecting; // 仅多选态可选中
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
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.selecting) { [self updateSelectionUI]; }
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.selecting) { [self updateSelectionUI]; }
}

/// 举报（AG-3）：弹出输入框填理由 → 调 POST /api/v1/reports。message 举报带会话上下文。
- (void)reportTargetType:(NSString *)targetType targetID:(NSString *)targetID title:(NSString *)title {
    if (targetID.length == 0) { return; }
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
        message:@"请填写举报理由（可空）" preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"理由"; }];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"提交举报" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *a) {
            NSString *reason = ac.textFields.firstObject.text ?: @"";
            NSString *convID = [targetType isEqualToString:@"message"] ? weakSelf.convID : nil;
            NSString *token = IMHTTPService.sharedService.currentToken;
            if (token.length == 0) { [weakSelf showReportResult:@"举报失败：未登录"]; return; }
            [IMHTTPService.sharedService reportWithToken:token targetType:targetType targetID:targetID
                convID:convID reason:reason completion:^(NSError *error) {
                    [weakSelf showReportResult:error ? [NSString stringWithFormat:@"举报失败：%@", error.localizedDescription]
                                                      : @"举报已提交，感谢反馈。"];
                }];
        }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)showReportResult:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

/// 首条未读所在行：conv_seq > entryReadSeq 的第一条「对端」消息；无未读返回 -1。
- (NSInteger)firstUnreadRow {
    if (self.entryUnread <= 0) { return -1; }
    for (NSInteger i = 0; i < (NSInteger)self.messages.count; i++) {
        IMMessageModel *m = self.messages[i];
        if (m.convSeq > self.entryReadSeq && ![m.from isEqualToString:self.userID]) { return i; }
    }
    return -1;
}

/// 进会话定位（只做一次）：有未读则停在首条未读，否则到底（CHAT_UX §3）。
- (void)positionInitialIfNeeded {
    if (self.didInitialPosition || self.messages.count == 0) { return; }
    self.didInitialPosition = YES;
    NSInteger unreadRow = [self firstUnreadRow];
    if (unreadRow >= 0) {
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:unreadRow inSection:0]
                              atScrollPosition:UITableViewScrollPositionTop animated:NO];
    } else {
        // 无未读：估高会让 scrollToRow…Bottom 欠滚（stop 在真正底部之上）→ 用强制布局后的精确贴底。
        [self scrollToAbsoluteBottom];
    }
    // 定位后下一轮 runloop（自适应高度落定）再兜一次：无未读再精确贴底 + 推进已读/刷新 ↓N。
    dispatch_async(dispatch_get_main_queue(), ^{
        if (unreadRow < 0) { [self scrollToAbsoluteBottom]; }
        [self markVisibleRowsRead];
    });
}

/// 可见即读（CHAT_UX §6 完整语义）：扫描当前在视口内的行，取其最大 conv_seq；
/// 若超过已滚入位点则记录并节流上报（read_seq 单调推进，对端据此显示已读双勾、列表未读递减）。
- (void)markVisibleRowsRead {
    int64_t maxSeq = 0;
    for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
        if (ip.row < (NSInteger)self.messages.count) {
            int64_t s = self.messages[ip.row].convSeq;
            if (s > maxSeq) { maxSeq = s; }
        }
    }
    if (maxSeq > self.pendingReadSeq) {
        self.pendingReadSeq = maxSeq;
        // 节流：滚动停 0.3s 后才真正发，避免每像素一条 receipt。
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flushReadPosition) object:nil];
        [self performSelector:@selector(flushReadPosition) withObject:nil afterDelay:0.3];
    }
    [self updateJumpButton]; // 位点推进/新消息后刷新 ↓N 计数
}

/// 把节流累积的已读位点上报（仅在超过上次上报值时发）。
- (void)flushReadPosition {
    if (self.pendingReadSeq > self.maxReadReported) {
        self.maxReadReported = self.pendingReadSeq;
        [IMSocketManager.sharedManager markReadConv:self.convID upToConvSeq:self.maxReadReported];
    }
}

#pragma mark - 辅助

/// 自己发送：刷新 + 始终贴底（贴底后 ↓N 自动隐藏）。
- (void)appendReloadAndScroll {
    [self.tableView reloadData];
    [self scrollToBottomAnimated:YES];
    [self markVisibleRowsRead];
}

#pragma mark - ↓N 跳转按钮 / 自动滚动（CHAT_UX §7、§9）

- (void)scrollToBottomAnimated:(BOOL)animated {
    if (self.messages.count == 0) { return; }
    NSIndexPath *last = [NSIndexPath indexPathForRow:self.messages.count - 1 inSection:0];
    [self.tableView scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

/// 精确贴底：自适应行高下 contentSize 初始基于估高（estimatedRowHeight=56），单次 layoutIfNeeded 只布局
/// 视口附近的行、离屏行仍是估算 → 一跳会停在真底部之上（进会话不贴底的根因）。
/// 改为「滚到末行(触发底部区域真实布局)→按最新 contentSize 精确对齐→再验证」迭代至收敛（≤6 轮防御死循环）。
- (void)scrollToAbsoluteBottom {
    if (self.messages.count == 0) { return; }
    NSIndexPath *last = [NSIndexPath indexPathForRow:(NSInteger)self.messages.count - 1 inSection:0];
    for (int pass = 0; pass < 6; pass++) {
        [self.tableView scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        [self.tableView layoutIfNeeded];
        CGFloat bottomInset = self.tableView.adjustedContentInset.bottom;
        CGFloat topInset = self.tableView.adjustedContentInset.top;
        CGFloat y = self.tableView.contentSize.height - self.tableView.bounds.size.height + bottomInset;
        if (y < -topInset) { y = -topInset; }
        if (fabs(self.tableView.contentOffset.y - y) < 0.5) { return; } // 已精确贴底
        [self.tableView setContentOffset:CGPointMake(0, y) animated:NO];
    }
}

/// 是否贴近底部（距底 < 80pt，计入底部安全区 inset）。
- (BOOL)isNearBottom {
    UIScrollView *sv = self.tableView;
    CGFloat distance = sv.contentSize.height - sv.contentOffset.y - sv.bounds.size.height + sv.adjustedContentInset.bottom;
    return distance < 80;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (self.tableView.contentSize.height <= 0) { return; }
    [self markVisibleRowsRead]; // 可见即读：滚到哪、读到哪（先推进 pendingReadSeq）
    [self updateJumpButton];    // 再据新位点刷新 ↓N 计数
}

/// 据当前滚动位置显示/隐藏"↓N"：贴底则隐藏；离底则显示，徽标=视口下方未读数（随滚动递减）。
- (void)updateJumpButton {
    if ([self isNearBottom]) {
        self.jumpButton.hidden = YES;
        self.jumpBadge.hidden = YES;
        return;
    }
    self.jumpButton.hidden = NO;
    NSInteger below = [self unreadBelowReadFrontier];
    if (below > 0) {
        self.jumpBadge.hidden = NO;
        self.jumpBadge.text = below > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)below];
    } else {
        self.jumpBadge.hidden = YES;
    }
}

/// 视口下方仍未读的对端消息数 = conv_seq 超过已滚入位点(pendingReadSeq)的对端消息数。
/// 随着向下滚动 pendingReadSeq 推进 → 该数递减，滚到底为 0。
- (NSInteger)unreadBelowReadFrontier {
    NSInteger n = 0;
    for (IMMessageModel *m in self.messages) {
        if (![m.from isEqualToString:self.userID] && m.convSeq > self.pendingReadSeq) { n++; }
    }
    return n;
}

- (void)jumpTapped {
    [self scrollToBottomAnimated:YES];
    [self updateJumpButton];
}

- (void)observeKeyboard {
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWillChange:)
                                               name:UIKeyboardWillChangeFrameNotification object:nil];
}

- (void)keyboardWillChange:(NSNotification *)note {
    CGRect endFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat overlap = CGRectGetHeight(self.view.bounds) - [self.view convertRect:endFrame fromView:nil].origin.y;
    self.kbInset = MAX(0, overlap - self.view.safeAreaInsets.bottom);
    if (self.kbInset > 0 && self.attachPanelVisible) { // 键盘弹起 → 收起附件面板（二者互斥）
        self.attachPanelVisible = NO;
        self.attachPanel.hidden = YES;
    }
    [self updateInputBottomAnimated:NO];
}

/// 输入栏底部偏移 = 键盘遮挡 与 面板高度 取较大者（二者互斥，但统一处理避免竞态）。
- (void)updateInputBottomAnimated:(BOOL)animated {
    CGFloat h = MAX(self.kbInset, self.attachPanelVisible ? kIMAttachPanelHeight : 0);
    self.inputBottom.constant = -h;
    if (animated) {
        [UIView animateWithDuration:0.25 animations:^{ [self.view layoutIfNeeded]; }];
    } else {
        [self.view layoutIfNeeded];
    }
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

@end
