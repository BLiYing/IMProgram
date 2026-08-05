#import "IMBubbleCell.h"
#import "IMRejectNoteView.h"
#import "IMMessageModel.h"
#import "IMUploadProgress.h"
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMediaUtil.h"
#import "UILabel+IMAvatar.h"
#import "IMAppearance.h"
#import "IMTheme.h"

// 引用快照本地化统一走 IMMediaUtil 的 IMLocalizeReplySnippet（与 IMLinkCardCell 共用，防两份 static 分叉）。

/// 文件名/纯 URL 判定统一走 IMMediaUtil（聊天/收藏/记录共用），此处保留短别名以少改调用点。
#define IMFileNameFromContent(c) IMMediaFileName(c)
#define IMLooksLikeURL(s) IMMediaLooksLikeURL(s)

/// 若快照是媒体占位（[图片]/[视频]/[文件]），返回对应 SF Symbol 名做内嵌小图标；否则 nil。
static NSString *IMMediaGlyphForSnippet(NSString *snap) {
    if ([snap isEqualToString:@"[图片]"]) { return @"photo"; }
    if ([snap isEqualToString:@"[视频]"]) { return @"video"; }
    if ([snap isEqualToString:@"[文件]"]) { return @"doc"; }
    if ([snap hasPrefix:@"[聊天记录]"]) { return @"text.bubble"; } // 引用合并转发卡片
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
    IMRejectNoteView *_sysNote;  // 被拒收系统行（三类气泡共用组件；可恢复时自带「发送好友申请」入口）
    NSLayoutConstraint *_bubbleBottom;   // 无系统行时：气泡贴 cell 底
    NSLayoutConstraint *_noteTop;        // 有系统行时：系统行接气泡底
    NSLayoutConstraint *_noteBottom;     // 有系统行时：系统行贴 cell 底
    NSLayoutConstraint *_failBadgeTrailing;
    NSMutableAttributedString *_bodyText;  // 当前富文本（引用缩略图异步到达后就地更新重渲，#4）
    NSTextAttachment *_quoteThumbAtt;      // 引用媒体缩略图占位 attachment
    NSString *_quoteThumbKey;              // 复用防串图：URL 匹配才应用
    UILabel *_avatar;                      // 群聊对方头像（连续段末条，贴气泡底左侧）
    NSLayoutConstraint *_textBottom;       // 非文件消息：正文贴气泡底（与 _fileRowBottom 互斥）
    UIView *_fileRow;                      // 文件消息两栏容器：左 44pt 图标位 + 右 文件名/状态/时间
    UIView *_fileIconWrap;                 // 图标位：完成=类型图标；上传中=圆环进度+状态 glyph（可点）
    UIImageView *_fileIcon;
    CAShapeLayer *_fileRingTrack;          // 圆环底轨（灰）
    CAShapeLayer *_fileRing;               // 圆环进度（strokeEnd=overallFraction）
    UILabel *_fileNameLabel;               // 文件名：最多两行、中间截断保扩展名
    UILabel *_fileStatusLabel;             // 第二行：大小 / 准备中… / 已传 x/y / 已暂停 / 发送失败
    UILabel *_fileMetaLabel;               // 右下角：时间 + ✓/✓✓
    UITapGestureRecognizer *_fileTap;
    NSLayoutConstraint *_fileRowBottom;    // 文件消息：文件行贴气泡底
    NSLayoutConstraint *_fileMinWidth;     // 文件消息：行定宽=气泡上限宽（仅文件模式激活，勿撑大文本气泡）
    NSArray<NSLayoutConstraint *> *_fileConstraints; // 文件行全部结构约束（仅文件模式激活，见 init 注释）
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.clearColor;

        _datePill = [UIView new];
        _datePill.translatesAutoresizingMaskIntoConstraints = NO;
        // 日期胶囊底色跟随所选聊天主题的强调色（与外观页「今天」预览一致：accent·0.64，白字）。
        _datePill.backgroundColor = [IMTheme.accent colorWithAlphaComponent:0.64];
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

        _sysNote = [IMRejectNoteView new];
        _sysNote.translatesAutoresizingMaskIntoConstraints = NO;
        _sysNote.hidden = YES;
        __weak typeof(self) wsNote = self;
        _sysNote.onActionTap = ^{ if (wsNote.onNoteActionTap) { wsNote.onNoteActionTap(); } };
        [self.contentView addSubview:_sysNote];

        // 文件消息两栏布局（Telegram 式）：左 44pt 图标位（上传中变圆环状态机、可点），
        // 右侧 文件名(≤2 行、中间截断) + 状态行 + 右下时间。头部（昵称/转发/引用）仍走 _text。
        _fileRow = [UIView new];
        _fileRow.translatesAutoresizingMaskIntoConstraints = NO;
        _fileRow.hidden = YES;
        [_bubble addSubview:_fileRow];

        _fileIconWrap = [UIView new];
        _fileIconWrap.translatesAutoresizingMaskIntoConstraints = NO;
        [_fileRow addSubview:_fileIconWrap];
        UIBezierPath *ringPath = [UIBezierPath bezierPathWithArcCenter:CGPointMake(22, 22) radius:19.5
                                                            startAngle:-M_PI_2 endAngle:M_PI_2 * 3 clockwise:YES];
        _fileRingTrack = [CAShapeLayer layer];
        _fileRingTrack.path = ringPath.CGPath;
        _fileRingTrack.fillColor = UIColor.clearColor.CGColor;
        _fileRingTrack.lineWidth = 3;
        _fileRingTrack.hidden = YES;
        [_fileIconWrap.layer addSublayer:_fileRingTrack];
        _fileRing = [CAShapeLayer layer];
        _fileRing.path = ringPath.CGPath;
        _fileRing.fillColor = UIColor.clearColor.CGColor;
        _fileRing.lineWidth = 3;
        _fileRing.lineCap = kCALineCapRound;
        _fileRing.strokeEnd = 0;
        _fileRing.hidden = YES;
        [_fileIconWrap.layer addSublayer:_fileRing];
        _fileIcon = [UIImageView new];
        _fileIcon.translatesAutoresizingMaskIntoConstraints = NO;
        _fileIcon.contentMode = UIViewContentModeCenter;
        [_fileIconWrap addSubview:_fileIcon];
        _fileTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleFileIconTap)];
        _fileTap.enabled = NO; // 仅上传中/失败态可点；完成态放行给表级手势（点气泡=打开文件）
        [_fileIconWrap addGestureRecognizer:_fileTap];

        _fileNameLabel = [UILabel new];
        _fileNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _fileNameLabel.numberOfLines = 2;
        _fileNameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle; // 两行封顶，中间截断保扩展名
        [_fileRow addSubview:_fileNameLabel];

        _fileStatusLabel = [UILabel new];
        _fileStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _fileStatusLabel.font = [UIFont systemFontOfSize:12];
        [_fileRow addSubview:_fileStatusLabel];

        _fileMetaLabel = [UILabel new];
        _fileMetaLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_fileRow addSubview:_fileMetaLabel];

        // 群聊对方头像（Telegram 式）：贴气泡底、位于左侧头像列；仅连续段末条显示。
        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textColor = UIColor.whiteColor;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _avatar.layer.cornerRadius = 15;
        _avatar.layer.masksToBounds = YES;
        _avatar.hidden = YES;
        _avatar.userInteractionEnabled = YES; // 点头像 → 进该成员资料页（onAvatarTap，微信式）
        [_avatar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleAvatarTap)]];
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
        // 气泡底：普通消息由正文撑（_textBottom），文件消息由文件行撑（_fileRowBottom），二选一。
        _textBottom = [_text.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:-6];
        _fileRowBottom = [_fileRow.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:-8];
        _textBottom.active = YES;
        // 文件行的**全部结构约束只在文件模式激活**：hidden 的视图仍参与布局，若常开，
        // 每个文本气泡都会被固定 44pt 图标位撑出最小宽，复用自文件气泡的 cell 还会被残留文件名
        // 撑得更宽——正是"连续发文本宽度各种变化"的根因。文本模式整组停用，气泡宽度回归纯文本驱动。
        _fileConstraints = @[
            [_fileRow.topAnchor constraintEqualToAnchor:_text.bottomAnchor constant:2],
            [_fileRow.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:12],
            [_fileRow.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-12],
            [_fileIconWrap.leadingAnchor constraintEqualToAnchor:_fileRow.leadingAnchor],
            [_fileIconWrap.topAnchor constraintEqualToAnchor:_fileRow.topAnchor constant:2],
            [_fileIconWrap.widthAnchor constraintEqualToConstant:44],
            [_fileIconWrap.heightAnchor constraintEqualToConstant:44],
            [_fileIconWrap.bottomAnchor constraintLessThanOrEqualToAnchor:_fileRow.bottomAnchor],
            [_fileIcon.topAnchor constraintEqualToAnchor:_fileIconWrap.topAnchor],
            [_fileIcon.leadingAnchor constraintEqualToAnchor:_fileIconWrap.leadingAnchor],
            [_fileIcon.trailingAnchor constraintEqualToAnchor:_fileIconWrap.trailingAnchor],
            [_fileIcon.bottomAnchor constraintEqualToAnchor:_fileIconWrap.bottomAnchor],
            [_fileNameLabel.leadingAnchor constraintEqualToAnchor:_fileIconWrap.trailingAnchor constant:10],
            [_fileNameLabel.trailingAnchor constraintEqualToAnchor:_fileRow.trailingAnchor],
            [_fileNameLabel.topAnchor constraintEqualToAnchor:_fileRow.topAnchor],
            [_fileStatusLabel.leadingAnchor constraintEqualToAnchor:_fileNameLabel.leadingAnchor],
            [_fileStatusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_fileRow.trailingAnchor],
            [_fileStatusLabel.topAnchor constraintEqualToAnchor:_fileNameLabel.bottomAnchor constant:3],
            [_fileMetaLabel.trailingAnchor constraintEqualToAnchor:_fileRow.trailingAnchor],
            [_fileMetaLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_fileNameLabel.leadingAnchor],
            [_fileMetaLabel.topAnchor constraintEqualToAnchor:_fileStatusLabel.bottomAnchor constant:2],
            [_fileMetaLabel.bottomAnchor constraintEqualToAnchor:_fileRow.bottomAnchor],
        ];
        // 文件气泡**定宽**=气泡宽度上限（0.75×内容区 − 左右 padding 24）：宽度不随状态文案长短 reflow。
        // 旧最小宽 190 的问题：第二行「120.4 MB / 358.4 MB」等进度串会把气泡撑到各不相同的宽度，
        // 且暂停/完成时文案变短→气泡缩窄→文件名换行数变→行高跳（列表跳动的根因之一）。
        // 定宽后文件名可用宽恒定，行数只取决于名字本身，所有文件气泡等宽（Telegram 式）。仅文件模式激活。
        _fileMinWidth = [_fileRow.widthAnchor constraintEqualToAnchor:self.contentView.widthAnchor
                                                           multiplier:0.75 constant:-24];
        _fileMinWidth.priority = UILayoutPriorityRequired - 1; // 与「气泡≤0.75」上限恰好相等，999 防御万一
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
          replyThumbIsVideo:(BOOL)replyThumbIsVideo
               replyFromName:(NSString *)replyFromName {
    BOOL showsDate = dayHeader.length > 0;
    _datePill.hidden = !showsDate;
    // 复用 cell 时按当前主题强调色刷新，切主题后无需整表重建也能与外观页预览保持一致。
    _datePill.backgroundColor = [IMTheme.accent colorWithAlphaComponent:0.64];
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
        NSString *snap = IMLocalizeReplySnippet(raw);
        NSDictionary *quoteAttr = @{ NSFontAttributeName: [UIFont systemFontOfSize:13],
                                     NSForegroundColorAttributeName: IMTheme.textSecondary };
        // 群聊两行式（M4-x）：被引用者昵称独占一行（accent 小字），其下为图标 + 内容快照；单聊不传 replyFromName。
        if (replyFromName.length > 0) {
            [body appendAttributedString:[[NSAttributedString alloc]
                initWithString:[NSString stringWithFormat:@"▏%@\n", replyFromName]
                    attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:MAX(12, IMTheme.chatFontSize - 4) weight:UIFontWeightSemibold],
                                  NSForegroundColorAttributeName: IMTheme.accent }]];
        }
        [body appendAttributedString:[[NSAttributedString alloc] initWithString:@"▏" attributes:quoteAttr]];
        NSString *glyph = IMMediaGlyphForSnippet(snap);
        NSString *quoteFileName = IMReplySnippetFileName(raw); // 一次解析（wire 形/本端存量本地化形皆可），文件判定与图标共用
        BOOL fileSnippet = quoteFileName != nil || [snap isEqualToString:@"[文件]"];
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
            att.image = fileSnippet ? IMFileTypeIconForName(quoteFileName, 18)
                                    : [[UIImage systemImageNamed:glyph] imageWithTintColor:IMTheme.textSecondary
                                                                             renderingMode:UIImageRenderingModeAlwaysOriginal];
            att.bounds = fileSnippet ? CGRectMake(0, -4, 18, 18) : CGRectMake(0, -2, 15, 13);
            [body appendAttributedString:[NSAttributedString attributedStringWithAttachment:att]];
            [body appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:quoteAttr]];
        }
        [body appendAttributedString:[[NSAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"%@\n", snap] attributes:quoteAttr]];
    }
    // 正文：文件消息 → 左右两栏子视图（图标固定左侧、文件名≤2 行，见 configureFileRowWithMessage:）；
    // 纯 URL → 链接蓝+下划线（点击打开）；其余普通文本。头部（昵称/转发/引用）两种模式都走 _text。
    BOOL fileMode = [message.contentType isEqualToString:@"file"];
    if (!fileMode) {
        NSString *contentText = message.content ?: @"";
        NSMutableDictionary *contentAttr = [@{ NSFontAttributeName: [UIFont systemFontOfSize:IMTheme.chatFontSize],
                                               NSForegroundColorAttributeName: IMTheme.textPrimary } mutableCopy];
        if (IMLooksLikeURL(contentText)) {
            contentAttr[NSForegroundColorAttributeName] = UIColor.systemBlueColor;
            contentAttr[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
        }
        [body appendAttributedString:[[NSAttributedString alloc] initWithString:contentText attributes:contentAttr]];
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
    }
    // 文件模式：头部（昵称/转发/引用）各段都以 \n 收尾（原本为衔接正文），此处已无正文跟随，
    // 裁掉尾随换行避免头部与文件行之间多出一行空白。
    if (fileMode && body.length > 0 && [body.string hasSuffix:@"\n"]) {
        [body deleteCharactersInRange:NSMakeRange(body.length - 1, 1)];
    }
    _bodyText = body;
    _text.attributedText = body;
    _fileRow.hidden = !fileMode;
    if (fileMode) {
        _textBottom.active = NO;
        [NSLayoutConstraint activateConstraints:_fileConstraints];
        _fileRowBottom.active = YES;
        _fileMinWidth.active = YES;
        [self configureFileRowWithMessage:message mine:mine peerReadSeq:peerReadSeq];
    } else {
        _fileRowBottom.active = NO;
        _fileMinWidth.active = NO;
        [NSLayoutConstraint deactivateConstraints:_fileConstraints];
        _textBottom.active = YES;
        _fileTap.enabled = NO;
        // 清残留内容防御：复用自文件气泡的 cell 若留着文件名/状态文案，一旦约束误开又会撑宽气泡。
        _fileNameLabel.text = nil;
        _fileStatusLabel.text = nil;
        _fileStatusLabel.attributedText = nil;
        _fileMetaLabel.attributedText = nil;
        _fileIcon.image = nil;
    }

    // 发送失败：气泡左侧红❗（仅自己）；被拒收等→气泡下方居中系统行（微信式）。
    BOOL failed = mine && message.status == IMMessageStatusFailed;
    _failBadge.hidden = !failed;
    _failBadgeTrailing.active = failed;
    [_sysNote configureWithNote:message.note code:message.noteCode];
    BOOL hasNote = _sysNote.hasContent;
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

#pragma mark - 文件气泡（左右两栏 + 圆环状态机）

/// 文件消息内容区：左 44pt 图标位 + 右侧 文件名/状态行/时间。上传中图标位变圆环进度 + 状态 glyph
///（与媒体气泡中心按钮同一套状态机：排队✕ / 上传中⏸ / 已暂停↑ / 失败↻），点击经 onFileControlTap 回调。
- (void)configureFileRowWithMessage:(IMMessageModel *)message mine:(BOOL)mine peerReadSeq:(int64_t)peerReadSeq {
    _fileNameLabel.font = [UIFont systemFontOfSize:IMTheme.chatFontSize];
    _fileNameLabel.textColor = IMTheme.accent;
    _fileNameLabel.text = message.fileName.length > 0 ? message.fileName : @"文件";
    IMUploadProgress *p = self.uploadProgress;
    UIColor *statusColor = p.failed ? IMTheme.danger : IMTheme.textSecondary;
    NSString *statusText = p ? [p fileLineText] : IMFormatFileSize(message.fileSize);
    if (p.pausedByUser && !p.failed) {
        // 暂停态：行首 ⏸ 小图标 + 字节数（与媒体角标一致；不用「已暂停」文本，图标零成本更直观）。
        UIImage *icon = [[UIImage systemImageNamed:@"pause.fill"
                                 withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:9
                                                                                                   weight:UIImageSymbolWeightBold]]
                         imageWithTintColor:statusColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        NSTextAttachment *att = [NSTextAttachment new];
        att.image = icon;
        att.bounds = CGRectMake(0, (_fileStatusLabel.font.capHeight - 9) / 2.0, 9, 9);
        NSMutableAttributedString *s = [[NSAttributedString attributedStringWithAttachment:att] mutableCopy];
        [s appendAttributedString:[[NSAttributedString alloc]
            initWithString:[@" " stringByAppendingString:statusText]
                attributes:@{ NSFontAttributeName: _fileStatusLabel.font,
                              NSForegroundColorAttributeName: statusColor }]];
        _fileStatusLabel.attributedText = s;
    } else {
        _fileStatusLabel.text = statusText;
        _fileStatusLabel.textColor = statusColor;
    }
    _fileMetaLabel.attributedText = [self attributedMetaForMessage:message mine:mine peerReadSeq:peerReadSeq];
    [self applyFileControlStateWithFileName:_fileNameLabel.text];
}

/// 图标位状态机：无进度=文件类型图标（不可点，点整条气泡=打开）；有进度=圆环+glyph（可点）。
- (void)applyFileControlStateWithFileName:(NSString *)fileName {
    IMUploadProgress *p = self.uploadProgress;
    _fileRingTrack.hidden = _fileRing.hidden = (p == nil);
    _fileTap.enabled = (p != nil);
    if (!p) {
        _fileIcon.image = IMFileTypeIconForName(fileName, 38);
        return;
    }
    UIColor *tint = p.failed ? IMTheme.danger : (p.pausedByUser ? IMTheme.textSecondary : IMTheme.accent);
    _fileRingTrack.strokeColor = [(p.failed ? IMTheme.danger : IMTheme.textSecondary)
                                  colorWithAlphaComponent:0.25].CGColor;
    _fileRing.strokeColor = tint.CGColor;
    [CATransaction begin];
    [CATransaction setDisableActions:YES]; // cell 复用/进度刷新不做 strokeEnd 隐式动画
    _fileRing.strokeEnd = p.failed ? 0 : MIN(1.0, MAX(0.0, p.overallFraction));
    [CATransaction commit];
    NSString *symbol = p.failed ? @"arrow.clockwise"
        : (p.phase == IMUploadPhaseQueued || p.phase == IMUploadPhaseTranscoding) ? @"xmark"
        : !p.pausable ? nil // 一次性小上传：只显进度环，无可操作 glyph（几秒传完，无暂停价值）
        : p.pausedByUser ? @"arrow.up" : @"pause.fill";
    _fileIcon.image = symbol.length > 0
        ? [[UIImage systemImageNamed:symbol
                   withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15
                                                                                     weight:UIImageSymbolWeightSemibold]]
           imageWithTintColor:tint renderingMode:UIImageRenderingModeAlwaysOriginal]
        : nil;
}

- (UIView *)previewTargetView { return _bubble; }

- (void)handleFileIconTap {
    if (self.onFileControlTap) { self.onFileControlTap(); }
}

- (void)handleAvatarTap {
    if (self.onAvatarTap) { self.onAvatarTap(); }
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
