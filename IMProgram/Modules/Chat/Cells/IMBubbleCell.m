#import "IMBubbleCell.h"
#import "IMRejectNoteView.h"
#import "IMMessageModel.h"
#import "IMUploadProgress.h"
#import "IMDownloadProgress.h"
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMediaPlaceholder.h" // 引用缩略磨砂占位（三处共用）
#import "IMMediaUtil.h"
#import "UILabel+IMAvatar.h"
#import "IMAppearance.h"
#import "IMTheme.h"
#import "IMMessageCell.h"  // +clampSenderName:（发送者昵称截断规则，各类气泡共用）
#import "IMFailBadgeView.h" // 发送失败红❗（点击重发），与继承 IMMessageCell 的各 cell 共用同一款
#import "IMChatMessageLogic.h" // IMResendPolicyForMessage：红❗可不可点的唯一判据
#import "IMLinkPreviewView.h" // 文本气泡里首个 URL 的 og 预览卡片子视图

// 引用快照本地化统一走 IMMediaUtil 的 IMLocalizeReplySnippet（与 IMLinkCardCell 共用，防两份 static 分叉）。

/// 文件名/纯 URL 判定统一走 IMMediaUtil（聊天/收藏/记录共用），此处保留短别名以少改调用点。
#define IMFileNameFromContent(c) IMMediaFileName(c)
#define IMLooksLikeURL(s) IMMediaLooksLikeURL(s)

NSString *const IMMentionUIDAttributeName = @"IMMentionUID";

/// 群主/管理员角色徽标 → 富文本内联小图（胶囊：主色 tint / 次要灰，与媒体气泡 IMMessageCell 徽标同款）。
/// 文本气泡的昵称在气泡内富文本首行，用 NSTextAttachment 把徽标烘成图挂在昵称同一行右侧。
/// 普通成员返回 nil（不显徽标）。颜色按当前 traitCollection 解析，随深浅色。
static NSAttributedString *IMRoleBadgeAttachment(IMGroupRole role, UITraitCollection *traits) {
    NSString *title = (role == IMGroupRoleOwner) ? @"群主" : (role == IMGroupRoleAdmin ? @"管理员" : nil);
    if (!title) { return nil; }
    UIColor *fg = (role == IMGroupRoleOwner) ? IMTheme.accent : IMTheme.textSecondary;
    UIColor *bg = (role == IMGroupRoleOwner) ? [IMTheme.accent colorWithAlphaComponent:0.14]
                                             : [IMTheme.separator colorWithAlphaComponent:0.5];
    if (traits) { fg = [fg resolvedColorWithTraitCollection:traits]; bg = [bg resolvedColorWithTraitCollection:traits]; }
    UIFont *font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    NSDictionary *attrs = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: fg };
    CGSize textSize = [title sizeWithAttributes:attrs];
    const CGFloat padH = 6, height = 16, radius = 4;
    CGFloat width = ceil(textSize.width) + padH * 2;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc]
        initWithSize:CGSizeMake(width, height) format:fmt];
    UIImage *img = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        UIBezierPath *pill = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, width, height) cornerRadius:radius];
        [bg setFill]; [pill fill];
        [title drawAtPoint:CGPointMake(padH, (height - textSize.height) / 2) withAttributes:attrs];
    }];
    NSTextAttachment *att = [NSTextAttachment new];
    att.image = img;
    // 相对 13pt 昵称基线垂直居中（capHeight 与胶囊高差半分，再微调 1pt）。
    UIFont *nameFont = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    att.bounds = CGRectMake(0, (nameFont.capHeight - height) / 2 - 1, width, height);
    return [NSAttributedString attributedStringWithAttachment:att];
}

// —— 长文本分档阈值（与 Web longtext.ts 严格一致）——
static const NSUInteger IMTextHugeChars = 2000;
static const NSUInteger IMTextHugeLines = 60;
static const NSUInteger IMTextLongChars = 300;
static const NSUInteger IMTextLongLines = 10;
static const NSUInteger IMTextCollapsedLines = 8;   // Long 折叠态气泡内保留行数
static const NSUInteger IMTextCollapsedChars = 400; // 折叠态字数硬顶（防单行超长）
static const NSUInteger IMTextHugePreviewChars = 120; // Huge 摘要卡预览字数

static NSUInteger IMHardLineCount(NSString *s) {
    NSUInteger n = 1;
    for (NSUInteger i = 0; i < s.length; i++) if ([s characterAtIndex:i] == '\n') n++;
    return n;
}

/// Unicode 码点数（代理对按 1 计），与 Web `[...text].length` 同口径——分档字数判据两端必须一致。
/// 高代理 0xD800–0xDBFF、低代理 0xDC00–0xDFFF；成对则合并为 1 个码点。
static NSUInteger IMCodePointCount(NSString *s) {
    NSUInteger n = 0, i = 0, len = s.length;
    while (i < len) {
        unichar c = [s characterAtIndex:i];
        BOOL high = (c >= 0xD800 && c <= 0xDBFF);
        if (high && i + 1 < len) {
            unichar lo = [s characterAtIndex:i + 1];
            i += (lo >= 0xDC00 && lo <= 0xDFFF) ? 2 : 1;
        } else {
            i += 1;
        }
        n++;
    }
    return n;
}

/// 按行、再按字数截断（不切断组合字符/代理对），供 Long 折叠与 Huge 预览共用。
static NSString *IMTruncateText(NSString *content, NSUInteger maxLines, NSUInteger maxChars) {
    NSString *out = content;
    NSArray<NSString *> *lines = [out componentsSeparatedByString:@"\n"];
    if (lines.count > maxLines) {
        out = [[lines subarrayWithRange:NSMakeRange(0, maxLines)] componentsJoinedByString:@"\n"];
    }
    if (out.length > maxChars) {
        NSRange r = [out rangeOfComposedCharacterSequenceAtIndex:maxChars];
        out = [out substringToIndex:r.location];
    }
    return out;
}

/// 若快照是媒体占位（[图片]/[视频]/[文件]），返回对应 SF Symbol 名做内嵌小图标；否则 nil。
/// 统一用 .fill 填充变体（与输入框回复条 video.fill/photo.fill 观感一致，矢量、跟随文字色）；
/// 均为 iOS 13 基线符号，不随系统更新消失。
static NSString *IMMediaGlyphForSnippet(NSString *snap) {
    if ([snap isEqualToString:@"[图片]"]) { return @"photo.fill"; }
    if ([snap isEqualToString:@"[视频]"]) { return @"video.fill"; }
    if ([snap isEqualToString:@"[文件]"]) { return @"doc.fill"; }
    if ([snap hasPrefix:@"[聊天记录]"]) { return @"text.bubble.fill"; } // 引用合并转发卡片
    return nil;
}

/// 生成染成 textSecondary 的 SF Symbol 内嵌小图标，**等比缩放居中绘入 side×side 方形画布**。
/// 关键：`NSTextAttachment` 会把图拉伸填满 `bounds`，而 video.fill 等符号是非方形（横向偏宽），
/// 直接塞进方形 bounds 会被压扁变形——故这里先 aspect-fit 进方形画布，配方形 bounds 即不失真
/// （后续异步真帧/磨砂本就是方形，bounds 保持不变即可无缝替换）。
/// 防呆：名字取不到（旧系统缺该符号 → systemImageNamed: 返回 nil）时回退 photo.fill，避免留空白。
static UIImage *IMTintedGlyph(NSString *name, CGFloat side) {
    UIImage *sym = name.length ? [UIImage systemImageNamed:name] : nil;
    if (!sym) { sym = [UIImage systemImageNamed:@"photo.fill"]; }
    if (!sym) { return nil; }
    sym = [sym imageWithTintColor:IMTheme.textSecondary renderingMode:UIImageRenderingModeAlwaysOriginal];
    CGFloat sw = sym.size.width, sh = sym.size.height;
    if (sw <= 0 || sh <= 0 || side <= 0) { return sym; }
    CGFloat k = MIN(side / sw, side / sh); // aspect fit（不裁不拉，长边贴边、短边居中留白）
    CGSize d = CGSizeMake(sw * k, sh * k);
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.opaque = NO;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:fmt];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [sym drawInRect:CGRectMake((side - d.width) / 2, (side - d.height) / 2, d.width, d.height)];
    }];
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
    IMFailBadgeView *_failBadge; // 发送失败：气泡左侧红色❗（微信式），点击重发
    IMRejectNoteView *_sysNote;  // 被拒收系统行（三类气泡共用组件；可恢复时自带「发送好友申请」入口）
    NSLayoutConstraint *_bubbleBottom;   // 无系统行时：气泡贴 cell 底
    NSLayoutConstraint *_noteTop;        // 有系统行时：系统行接气泡底
    NSLayoutConstraint *_noteBottom;     // 有系统行时：系统行贴 cell 底
    NSLayoutConstraint *_failBadgeTrailing;
    NSMutableAttributedString *_bodyText;  // 当前富文本（引用缩略图异步到达后就地更新重渲，#4）
    NSTextAttachment *_quoteThumbAtt;      // 引用媒体缩略图占位 attachment
    NSString *_quoteThumbKey;              // 复用防串图：URL 匹配才应用
    UILabel *_avatar;                      // 群聊对方头像（连续段末条，贴气泡底左侧）
    UILabel *_senderLabel;                 // 群聊对方昵称+角色徽标（气泡**外**上方，与媒体气泡统一；昵称在富文本内的旧写法已移除）
    NSLayoutConstraint *_bubbleTopPlain;   // 无昵称行：气泡贴分割线底
    NSLayoutConstraint *_bubbleTopUnderName; // 有昵称行：气泡接昵称底
    NSLayoutConstraint *_textBottom;       // 非文件消息：正文贴气泡底（与 _fileRowBottom 互斥）
    UIView *_fileRow;                      // 文件消息两栏容器：左 44pt 图标位 + 右 文件名/状态/时间
    UIView *_fileIconWrap;                 // 图标位：完成=类型图标；上传中=圆环进度+状态 glyph（可点）
    UIImageView *_fileIcon;
    CAShapeLayer *_fileRingTrack;          // 圆环底轨（灰）
    CAShapeLayer *_fileRing;               // 圆环进度（strokeEnd=overallFraction）
    CAShapeLayer *_fileDisc;               // 未下载态：与圆环等大的实心圆底（accent 填充，中间白色 ↓）
    UILabel *_fileNameLabel;               // 文件名：最多两行、中间截断保扩展名
    UILabel *_fileStatusLabel;             // 第二行：大小 / 准备中… / 已传 x/y / 已暂停 / 发送失败
    UILabel *_fileMetaLabel;               // 右下角：时间 + ✓/✓✓
    int64_t _fileSizeBytes;                // 记住文件字节数：进度就地更新时未下载/就绪态拼"尺寸 · …"用
    UITapGestureRecognizer *_fileTap;
    NSLayoutConstraint *_fileRowBottom;    // 文件消息：文件行贴气泡底（无 caption 时）
    NSLayoutConstraint *_fileMinWidth;     // 文件消息：行定宽=气泡上限宽（仅文件模式激活，勿撑大文本气泡）
    NSArray<NSLayoutConstraint *> *_fileConstraints; // 文件行全部结构约束（仅文件模式激活，见 init 注释）
    UILabel *_fileCaption;                 // 文件文 caption（Telegram 模型）：文件卡下方随附文本，同气泡内，iOS 只显示
    NSArray<NSLayoutConstraint *> *_fileCaptionConstraints; // 有 caption 时整组激活：文件行→caption→气泡底 + 左右对齐
    // URL 富预览子视图（文本气泡里首个 URL 的 og 卡片，与 IMLinkCardCell 视觉一致）：仅当抓到 og 且非文件模式时挂；
    // 整组结构约束（_linkPreviewConstraints）只在**卡片可见**时激活，与 _textBottom 互斥。
    IMLinkPreviewView *_linkPreview;
    NSArray<NSLayoutConstraint *> *_linkPreviewConstraints;
    NSString *_linkPreviewURL;             // 当前正在配置的 URL（onContentSizeResolved 回调时用于比对防串图）
}

+ (IMBubbleTextTier)textTierForContent:(NSString *)content {
    if (content.length == 0) return IMBubbleTextTierShort;
    NSUInteger chars = IMCodePointCount(content); // 码点计，与 Web `[...text].length` 一致
    NSUInteger lines = IMHardLineCount(content);
    if (chars >= IMTextHugeChars || lines >= IMTextHugeLines) return IMBubbleTextTierHuge;
    if (chars >= IMTextLongChars || lines >= IMTextLongLines) return IMBubbleTextTierLong;
    return IMBubbleTextTierShort;
}

/// 摘要卡/阅读器的字数标签「约 8,400 字」（千分位、按码点计）。cell 与阅读器共用同一入口，避免重复实现（与 Web charCountLabel 同口径）。
+ (NSString *)charCountLabelForText:(NSString *)text {
    NSNumberFormatter *f = [NSNumberFormatter new];
    f.numberStyle = NSNumberFormatterDecimalStyle;
    f.groupingSeparator = @",";
    f.usesGroupingSeparator = YES;
    NSNumber *n = @(IMCodePointCount(text ?: @""));
    return [NSString stringWithFormat:@"约 %@ 字", [f stringFromNumber:n] ?: n.stringValue];
}

/// 把 `text` 按已知 `@昵称` token 切段构造富文本：命中的 token 用 `color`（+medium 字重）高亮，其余用 `base`。
/// token 边界与 `IMChatTextContainsMentionToken` 同规则（token 后须紧跟空白或结尾；长名优先，防 `@小美` 误命中 `@小美丽`）。
/// names 为空/nil → 整段用 base。cell 与全屏阅读器共用（与 Web `segmentMentions` 同口径）。
+ (NSAttributedString *)attributedContent:(NSString *)text
                                     base:(NSDictionary *)base
                             mentionColor:(UIColor *)color
                                 mentions:(NSDictionary<NSString *, NSString *> *)mentions {
    NSMutableAttributedString *out = [NSMutableAttributedString new];
    if (text.length == 0) { return out; }
    NSArray<NSString *> *sorted = mentions.count > 0
        ? [mentions.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
              if (a.length == b.length) { return NSOrderedSame; }
              return a.length > b.length ? NSOrderedAscending : NSOrderedDescending; // 长名优先
          }]
        : nil;
    NSMutableDictionary *matt = [base mutableCopy];
    matt[NSForegroundColorAttributeName] = color;
    UIFont *bf = base[NSFontAttributeName];
    if (bf) { matt[NSFontAttributeName] = [UIFont systemFontOfSize:bf.pointSize weight:UIFontWeightMedium]; }
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSUInteger i = 0, len = text.length;
    NSMutableString *buf = [NSMutableString string];
    void (^flush)(void) = ^{
        if (buf.length) { [out appendAttributedString:[[NSAttributedString alloc] initWithString:buf attributes:base]]; [buf setString:@""]; }
    };
    while (i < len) {
        NSString *hitName = nil;
        if (sorted && [text characterAtIndex:i] == '@') {
            for (NSString *n in sorted) {
                NSString *token = [@"@" stringByAppendingString:n];
                if (i + token.length <= len && [[text substringWithRange:NSMakeRange(i, token.length)] isEqualToString:token]) {
                    NSUInteger after = i + token.length;
                    if (after >= len || [ws characterIsMember:[text characterAtIndex:after]]) { hitName = n; break; }
                }
            }
        }
        if (hitName) {
            flush();
            NSMutableDictionary *seg = matt;
            NSString *uid = mentions[hitName];
            if (uid.length > 0) { // 有 uid 才可点：挂 uid 属性（@所有人 uid 空串，只高亮）
                seg = [matt mutableCopy];
                seg[IMMentionUIDAttributeName] = uid;
            }
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:[@"@" stringByAppendingString:hitName] attributes:seg]];
            i += hitName.length + 1;
        } else {
            [buf appendFormat:@"%C", [text characterAtIndex:i]];
            i += 1;
        }
    }
    flush();
    return out;
}

/// 搜索命中词高亮：att 内 keyword 的所有大小写不敏感命中段染 accent 前景 + accentSoft 底
///（与全局搜索页 IMSearchHighlighted / Web `<mark class="search-hit">` 同语义）。就地改写 mutable 版。
+ (void)applySearchHighlight:(NSString *)keyword toMutable:(NSMutableAttributedString *)att {
    if (keyword.length == 0 || att.length == 0) { return; }
    NSRange search = NSMakeRange(0, att.length);
    while (search.location < att.length) {
        NSRange r = [att.string rangeOfString:keyword options:NSCaseInsensitiveSearch range:search];
        if (r.location == NSNotFound) { break; }
        [att addAttributes:@{ NSBackgroundColorAttributeName: IMTheme.accentSoft,
                              NSForegroundColorAttributeName: IMTheme.accent } range:r];
        search = NSMakeRange(NSMaxRange(r), att.length - NSMaxRange(r));
    }
}

+ (NSAttributedString *)attributed:(NSAttributedString *)att highlighting:(nullable NSString *)keyword {
    if (keyword.length == 0 || att.length == 0) { return att; }
    NSMutableAttributedString *m = [att mutableCopy];
    [IMBubbleCell applySearchHighlight:keyword toMutable:m];
    return m;
}

/// 把 srcText 中检测到的 http(s) URL 范围染成 linkAttrs（蓝色下划线），
/// 应用到 body 上的相对偏移（startOffset = 追加 srcText 之前的 body.length）。
/// 用于文本气泡混排 URL 的高亮（整段是 URL 时上层直接给全串染 urlAttr，不走此路径）。
+ (void)applyURLHighlight:(NSString *)srcText toBody:(NSMutableAttributedString *)body
              startOffset:(NSUInteger)startOffset linkAttrs:(NSDictionary *)linkAttrs {
    if (srcText.length == 0 || body.length == 0) { return; }
    for (NSValue *v in IMURLRangesInText(srcText)) {
        NSRange r = v.rangeValue;
        NSRange target = NSMakeRange(startOffset + r.location, r.length);
        if (NSMaxRange(target) <= body.length) { [body addAttributes:linkAttrs range:target]; }
    }
}

/// TextKit 反查：命中点（cell 坐标系）是否落在某个挂了 IMMentionUIDAttributeName 的 `@昵称` token 上。
- (NSString *)mentionUIDAtPoint:(CGPoint)pointInCell {
    // 正文命中优先；未中再查文件文 caption（图说 @ 可点，2026-08-19）。
    NSString *uid = [IMBubbleCell mentionUIDInLabel:_text atPoint:[self convertPoint:pointInCell toView:_text]];
    if (uid) { return uid; }
    return [IMBubbleCell mentionUIDInLabel:_fileCaption atPoint:[self convertPoint:pointInCell toView:_fileCaption]];
}

+ (nullable NSString *)mentionUIDInLabel:(UILabel *)label atPoint:(CGPoint)p {
    NSAttributedString *as = label.attributedText;
    if (as.length == 0 || label.hidden || label.window == nil) { return nil; }
    if (!CGRectContainsPoint(label.bounds, p)) { return nil; }
    NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:as];
    NSLayoutManager *lm = [NSLayoutManager new];
    [storage addLayoutManager:lm];
    NSTextContainer *container = [[NSTextContainer alloc] initWithSize:label.bounds.size];
    container.lineFragmentPadding = 0;
    container.maximumNumberOfLines = label.numberOfLines;
    container.lineBreakMode = label.lineBreakMode;
    [lm addTextContainer:container];
    [lm ensureLayoutForTextContainer:container];
    // UILabel 内容比 bounds 矮时会垂直居中，TextKit 从顶部排版——按实际高度差把点上移对齐。
    CGFloat used = [lm usedRectForTextContainer:container].size.height;
    CGFloat dy = MAX(0, (label.bounds.size.height - used) / 2.0);
    p.y -= dy;
    NSUInteger glyphIdx = [lm glyphIndexForPoint:p inTextContainer:container];
    CGRect glyphRect = [lm boundingRectForGlyphRange:NSMakeRange(glyphIdx, 1) inTextContainer:container];
    if (!CGRectContainsPoint(glyphRect, p)) { return nil; } // 命中矩形外（点在字之外）不算
    NSUInteger charIdx = [lm characterIndexForGlyphAtIndex:glyphIdx];
    if (charIdx >= as.length) { return nil; }
    return [as attribute:IMMentionUIDAttributeName atIndex:charIdx effectiveRange:NULL];
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

        _failBadge = [IMFailBadgeView new];
        __weak typeof(self) wsFail = self;
        _failBadge.onTap = ^{ if (wsFail.onRetryTap) { wsFail.onRetryTap(); } };
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
        _fileDisc = [CAShapeLayer layer];        // 实心圆底与圆环同心同径（radius 19.5）；置于图标之下
        _fileDisc.path = ringPath.CGPath;
        _fileDisc.fillColor = UIColor.clearColor.CGColor;
        _fileDisc.hidden = YES;
        [_fileIconWrap.layer addSublayer:_fileDisc];
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

        // 文件文 caption（Telegram 模型）：文件卡下方随附文本，与文件卡同气泡内（IMBubbleCell 有气泡背景）。
        _fileCaption = [UILabel new];
        _fileCaption.translatesAutoresizingMaskIntoConstraints = NO;
        _fileCaption.numberOfLines = 0;
        _fileCaption.font = [UIFont systemFontOfSize:IMTheme.chatFontSize];
        _fileCaption.textColor = IMTheme.textPrimary;
        _fileCaption.hidden = YES;
        [_bubble addSubview:_fileCaption];

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

        // 群聊对方昵称 + 角色徽标：气泡**外**上方独立一行（与图片/相册/链接/记录气泡统一）。
        // 昵称主色小字，尾部截断；角色徽标（群主/管理员）用 IMRoleBadgeAttachment 内联挂在昵称右侧。
        _senderLabel = [UILabel new];
        _senderLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _senderLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _senderLabel.textColor = IMTheme.accent;
        _senderLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _senderLabel.hidden = YES;
        [self.contentView addSubview:_senderLabel];

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

            [_bubble.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.75],

            // 昵称行：贴分割线底、leading 对齐气泡（随头像 gutter 一起右移）、trailing 不超内容区。
            [_senderLabel.topAnchor constraintEqualToAnchor:_divider.bottomAnchor constant:2],
            [_senderLabel.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:2],
            [_senderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-12],

            // 红❗：钉在气泡左侧、垂直居中（宽高由 IMFailBadgeView 自持；贴左那条仅失败时激活）。
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

        // 气泡顶：无昵称行→贴分割线底（_bubbleTopPlain）；有昵称行→接昵称底（_bubbleTopUnderName）。二选一。
        _bubbleTopPlain = [_bubble.topAnchor constraintEqualToAnchor:_divider.bottomAnchor constant:2];
        _bubbleTopUnderName = [_bubble.topAnchor constraintEqualToAnchor:_senderLabel.bottomAnchor constant:2];
        _bubbleTopPlain.active = YES;

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
        // 文件文 caption 整组（仅当文件消息带 caption 时激活）：文件行 → caption → 气泡底，替下 _fileRowBottom。
        _fileCaptionConstraints = @[
            [_fileCaption.topAnchor constraintEqualToAnchor:_fileRow.bottomAnchor constant:6],
            [_fileCaption.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:12],
            [_fileCaption.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-12],
            [_fileCaption.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:-8],
        ];
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

        // URL 富预览子视图（默认不挂约束，仅当 og 抓到 title/image 且非文件模式时激活整组）。
        // 视觉与 IMLinkCardCell 卡片一致，260pt 定宽（同款 stack.width），左右各 10 内边距。
        _linkPreview = [IMLinkPreviewView new];
        _linkPreview.translatesAutoresizingMaskIntoConstraints = NO;
        [_bubble addSubview:_linkPreview];
        __weak typeof(self) wsPrev = self;
        _linkPreview.onTap = ^(NSString *url) { if (wsPrev.onLinkTap && url.length) { wsPrev.onLinkTap(url); } };
        _linkPreview.onContentSizeResolved = ^{
            __strong typeof(wsPrev) self = wsPrev;
            if (!self) { return; }
            // 卡片从"隐藏"变"展开"：激活整组约束（挤开 _textBottom），并回调宿主刷行高。
            [self applyLinkPreviewVisibleConstraints:YES];
            if (self.onLinkPreviewResolved) { self.onLinkPreviewResolved(); }
        };
        _linkPreviewConstraints = @[
            [_linkPreview.topAnchor constraintEqualToAnchor:_text.bottomAnchor constant:6],
            [_linkPreview.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:10],
            [_linkPreview.widthAnchor constraintEqualToConstant:260],
            [_linkPreview.trailingAnchor constraintLessThanOrEqualToAnchor:_bubble.trailingAnchor constant:-10],
            [_linkPreview.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:-8],
        ];
    }
    return self;
}

/// preview 卡片可见/隐藏时的约束切换（互斥于 _textBottom）：
/// - visible=YES：激活 _linkPreviewConstraints、停用 _textBottom；卡片挤在正文下方、气泡底由卡片撑。
/// - visible=NO：停用 _linkPreviewConstraints、激活 _textBottom；恢复"正文直接贴气泡底"。
/// 文件模式（_fileRowBottom 撑气泡底）由 configure 里独立处理，不走此方法。
- (void)applyLinkPreviewVisibleConstraints:(BOOL)visible {
    if (visible) {
        _textBottom.active = NO;
        for (NSLayoutConstraint *c in _linkPreviewConstraints) { c.active = YES; }
    } else {
        for (NSLayoutConstraint *c in _linkPreviewConstraints) { c.active = NO; }
        _textBottom.active = YES;
    }
}

- (void)configureWithMessage:(IMMessageModel *)message
                        mine:(BOOL)mine
                 peerReadSeq:(int64_t)peerReadSeq
                   dayHeader:(NSString *)dayHeader
          showsUnreadDivider:(BOOL)showsDivider
                  senderName:(NSString *)senderName
                  senderRole:(IMGroupRole)senderRole
               replyThumbURL:(NSString *)replyThumbURL
              replyThumbData:(NSString *)replyThumbData
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

    [IMTheme applyBubbleDirectionStyle:_bubble mine:mine]; // 底色+圆角+尾角（收发方向样式，四类气泡 cell 共用）
    _text.font = [UIFont systemFontOfSize:IMTheme.chatFontSize];
    // 正文 + 小字尾巴（时间/✓/✓✓）拼成一段富文本，保证状态一定随气泡渲染。
    NSMutableAttributedString *body = [NSMutableAttributedString new];
    // 群聊对方昵称 + 角色徽标：移到气泡**外**上方独立 _senderLabel（与图片/相册/链接/记录气泡统一风格），
    // 不再拼进气泡富文本。昵称≤12 中文字截断 + 群主/管理员徽标（IMRoleBadgeAttachment 内联小图，随深浅色）。
    BOOL showSender = senderName.length > 0;
    if (showSender) {
        NSString *shownName = [IMMessageCell clampSenderName:senderName];
        NSMutableAttributedString *nameLine = [[NSMutableAttributedString alloc]
            initWithString:shownName
                attributes:@{ NSFontAttributeName: _senderLabel.font,
                              NSForegroundColorAttributeName: IMTheme.accent }];
        NSAttributedString *badge = IMRoleBadgeAttachment(senderRole, self.traitCollection);
        if (badge) {
            [nameLine appendAttributedString:[[NSAttributedString alloc] initWithString:@"  "
                attributes:@{ NSFontAttributeName: _senderLabel.font }]];
            [nameLine appendAttributedString:badge];
        }
        _senderLabel.attributedText = nameLine;
    }
    _senderLabel.hidden = !showSender;
    _bubbleTopPlain.active = !showSender;
    _bubbleTopUnderName.active = showSender;
    // 转发消息按普通消息收发显示（隐私保护）：不再渲染"转发自 X"溯源行。forwardFrom 仍保留在模型/DB，
    // 供再次转发时保留最初作者链路，但界面不外显（与 Web 拉齐）。
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
        // 门控一致（M4-7）：有媒体地址即走 IMMediaPlaceholder 统一取图（真帧仅已下载 > thumb 磨砂 > nil）；
        // 复用 key 用完整媒体地址；返回 nil（未下载且无 thumb）则保留占位图标。绝不为引用小图联网拉原件/抽远端帧。
        NSString *previewKey = replyThumbURL;
        if (previewKey.length > 0) {
            // 真缩略图：先用占位图标撑住固定 24x24 位置（行高稳定），异步图到达后原地替换重渲。
            NSTextAttachment *att = [NSTextAttachment new];
            att.image = IMTintedGlyph(glyph, 24); // 方形画布防拉伸；nil→回退 photo.fill；异步真图/磨砂到达后原地替换
            att.bounds = CGRectMake(0, -6, 24, 24);
            _quoteThumbAtt = att;
            _quoteThumbKey = previewKey;
            [body appendAttributedString:[NSAttributedString attributedStringWithAttachment:att]];
            [body appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:quoteAttr]];
            __weak typeof(self) ws = self;
            void (^apply)(UIImage *) = ^(UIImage *img) {
                __strong typeof(ws) self = ws;
                if (!self || !img || ![self->_quoteThumbKey isEqualToString:previewKey]) { return; } // 复用防串图
                self->_quoteThumbAtt.image = IMSquareThumb(img, 24);
                self->_text.attributedText = self->_bodyText; // 重新赋值触发重渲（bounds 固定，行高不变）
            };
            [IMMediaPlaceholder previewForURL:replyThumbURL isVideo:replyThumbIsVideo thumb:replyThumbData completion:apply];
        } else if (glyph || fileSnippet) {
            NSTextAttachment *att = [NSTextAttachment new];
            att.image = fileSnippet ? IMFileTypeIconForName(quoteFileName, 18)
                                    : IMTintedGlyph(glyph, 13); // 方形画布防拉伸（side=13 保持原行高）
            att.bounds = fileSnippet ? CGRectMake(0, -4, 18, 18) : CGRectMake(0, -2, 13, 13);
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
        BOOL isURL = IMLooksLikeURL(contentText);
        // URL 不参与长文本分档（纯 URL 不会超长）；其余按 chars/lines 双判据分档（与 Web longtext.ts 一致）。
        IMBubbleTextTier tier = isURL ? IMBubbleTextTierShort : [IMBubbleCell textTierForContent:contentText];
        NSDictionary *contentAttr = @{ NSFontAttributeName: [UIFont systemFontOfSize:IMTheme.chatFontSize],
                                       NSForegroundColorAttributeName: IMTheme.textPrimary };
        NSDictionary *urlAttr = @{ NSFontAttributeName: [UIFont systemFontOfSize:IMTheme.chatFontSize],
                                   NSForegroundColorAttributeName: UIColor.systemBlueColor,
                                   NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle) };
        NSDictionary *affordanceAttr = @{ NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium],
                                          NSForegroundColorAttributeName: IMTheme.accent };
        // 气泡内 @昵称 高亮：URL 不参与（整段是链接）；其余按宿主推导的 mentionNames 上强调色。
        NSDictionary<NSString *, NSString *> *mMap = isURL ? nil : self.mentionMap;
        BOOL collapsed = NO; // Long 折叠态：跳过译文/展开态尾巴，避免折叠时下方还挂译文
        if (tier == IMBubbleTextTierHuge) {
            // 超长 → 摘要卡：📄 长文本 · 约N字\n 预览(次要色, 截断) \n 查看全文 ›
            NSTextAttachment *icon = [NSTextAttachment new];
            icon.image = IMTintedGlyph(@"doc.text", 15);
            icon.bounds = CGRectMake(0, -2, 15, 15);
            [body appendAttributedString:[NSAttributedString attributedStringWithAttachment:icon]];
            [body appendAttributedString:[[NSAttributedString alloc]
                initWithString:[NSString stringWithFormat:@" 长文本 · %@\n", [IMBubbleCell charCountLabelForText:contentText]]
                    attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:IMTheme.chatFontSize weight:UIFontWeightSemibold],
                                  NSForegroundColorAttributeName: IMTheme.textPrimary }]];
            NSString *preview = [IMTruncateText(contentText, 3, IMTextHugePreviewChars) stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            NSDictionary *previewAttr = @{ NSFontAttributeName: [UIFont systemFontOfSize:13],
                                           NSForegroundColorAttributeName: IMTheme.textSecondary };
            [body appendAttributedString:[IMBubbleCell attributedContent:preview base:previewAttr mentionColor:IMTheme.accent mentions:mMap]];
            [body appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n查看全文 ›" attributes:affordanceAttr]];
        } else if (tier == IMBubbleTextTierLong && !self.textExpanded) {
            // 中长折叠：前若干行（并按字数硬顶）+ 省略号 + 「展开全文」
            collapsed = YES;
            NSString *shown = IMTruncateText(contentText, IMTextCollapsedLines, IMTextCollapsedChars);
            NSUInteger contentStart = body.length;
            [body appendAttributedString:[IMBubbleCell attributedContent:shown base:(isURL ? urlAttr : contentAttr) mentionColor:IMTheme.accent mentions:mMap]];
            // 混排文本里的 URL 高亮：整段是 URL 时上面 urlAttr 已全染；否则按检测出的 URL 范围逐段补染。
            if (!isURL) { [IMBubbleCell applyURLHighlight:shown toBody:body startOffset:contentStart linkAttrs:urlAttr]; }
            [body appendAttributedString:[[NSAttributedString alloc] initWithString:@"…\n展开全文 ∨" attributes:affordanceAttr]];
        } else {
            // 短文本，或中长已展开：全显。展开态末尾加「收起」。
            NSUInteger contentStart = body.length;
            [body appendAttributedString:[IMBubbleCell attributedContent:contentText base:(isURL ? urlAttr : contentAttr) mentionColor:IMTheme.accent mentions:mMap]];
            if (!isURL) { [IMBubbleCell applyURLHighlight:contentText toBody:body startOffset:contentStart linkAttrs:urlAttr]; }
            if (tier == IMBubbleTextTierLong) {
                [body appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n收起 ∧" attributes:affordanceAttr]];
            }
        }
        // 翻译（M4-5）：译文另起一行挂气泡内（灰字小字）。折叠态不挂（展开后再出现）。
        if (message.translation.length > 0 && !collapsed) {
            [body appendAttributedString:[[NSAttributedString alloc]
                initWithString:[NSString stringWithFormat:@"\n%@", message.translation]
                    attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:14],
                                  NSForegroundColorAttributeName: IMTheme.textSecondary }]];
        }
        NSAttributedString *meta = [IMMessageCell attributedMetaForMessage:message mine:mine peerReadSeq:peerReadSeq];
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
    // 会话内搜索命中词高亮（搜索态才有 keyword）：直接染在 body 上——_bodyText 的各重渲路径（如引用
    // 缩略图异步回填后重赋值）都携带高亮，不会滚一下就丢。
    if (self.searchHighlightKeyword.length > 0) {
        [IMBubbleCell applySearchHighlight:self.searchHighlightKeyword toMutable:body];
    }
    _bodyText = body;
    _text.attributedText = body;
    _fileRow.hidden = !fileMode;
    // 文件文 caption（Telegram 模型）：文件卡下方随附文本，同气泡内。iOS 只显示（不发送）。
    NSString *fileCaption = (fileMode && message.caption.length > 0) ? message.caption : nil;
    BOOL hasFileCaption = fileCaption != nil;
    if (hasFileCaption) {
        // 配文 @高亮（Telegram 模型，仅群聊）：命中的 @昵称/@所有人 上强调色。
        NSDictionary *capBase = @{ NSFontAttributeName: _fileCaption.font, NSForegroundColorAttributeName: _fileCaption.textColor };
        _fileCaption.attributedText = [IMBubbleCell attributed:[IMBubbleCell attributedContent:fileCaption base:capBase mentionColor:IMTheme.accent mentions:self.captionMentionMap]
                                                  highlighting:self.searchHighlightKeyword];
    } else {
        _fileCaption.attributedText = nil;
        _fileCaption.text = nil;
    }
    _fileCaption.hidden = !hasFileCaption;
    // 文本气泡里首个 URL 的 preview 卡片：仅非文件、非"整段就是 URL"（那由 IMLinkCardCell 路径处理）时挂。
    // configureWithURL: 命中缓存同步展开→ hasContent=YES；未命中先隐藏，异步回来触发 onContentSizeResolved
    // 里翻转约束 + 通知宿主刷行高（applyLinkPreviewVisibleConstraints: 承担二次布局）。
    NSString *firstURL = nil;
    if (!fileMode) {
        NSString *ct = message.content ?: @"";
        if (!IMMediaLooksLikeURL(ct)) { firstURL = IMFirstURLInText(ct); }
    }
    _linkPreviewURL = firstURL;
    [_linkPreview configureWithURL:firstURL];
    if (fileMode) {
        [self applyLinkPreviewVisibleConstraints:NO]; // 文件消息底部由 file 行/caption 撑，preview 一律隐藏
        _textBottom.active = NO;
        [NSLayoutConstraint activateConstraints:_fileConstraints];
        // 有 caption：气泡底由 caption 撑（文件行→caption→底）；无 caption：文件行直接贴底。
        _fileRowBottom.active = !hasFileCaption;
        if (hasFileCaption) { [NSLayoutConstraint activateConstraints:_fileCaptionConstraints]; }
        else { [NSLayoutConstraint deactivateConstraints:_fileCaptionConstraints]; }
        _fileMinWidth.active = YES;
        [self configureFileRowWithMessage:message mine:mine peerReadSeq:peerReadSeq];
    } else {
        _fileRowBottom.active = NO;
        _fileMinWidth.active = NO;
        [NSLayoutConstraint deactivateConstraints:_fileConstraints];
        [NSLayoutConstraint deactivateConstraints:_fileCaptionConstraints];
        // 气泡底：命中缓存的 preview（hasContent=YES）直接激活整组、挤开 _textBottom；否则回到"正文贴底"。
        [self applyLinkPreviewVisibleConstraints:_linkPreview.hasContent];
        _fileTap.enabled = NO;
        // 清残留内容防御：复用自文件气泡的 cell 若留着文件名/状态文案，一旦约束误开又会撑宽气泡。
        _fileNameLabel.text = nil;
        _fileStatusLabel.text = nil;
        _fileStatusLabel.attributedText = nil;
        _fileMetaLabel.attributedText = nil;
        _fileIcon.image = nil;
        _fileDisc.hidden = _fileRingTrack.hidden = _fileRing.hidden = YES; // 复用回非文件消息：清掉圆底/圆环残留
    }

    // 发送失败：气泡左侧红❗（仅自己）；被拒收等→气泡下方居中系统行（微信式）。
    BOOL failed = mine && message.status == IMMessageStatusFailed;
    _failBadge.hidden = !failed;
    // 可点 = 可重发；被拒收那批红❗照显但不吃点击（恢复入口是下方系统行，见 IMResendPolicyForMessage）。
    _failBadge.tappable = failed && IMResendPolicyForMessage(message, mine) != IMResendPolicyNone;
    _failBadgeTrailing.active = failed;
    [_sysNote configureWithNote:message.note code:message.noteCode];
    BOOL hasNote = _sysNote.hasContent;
    _bubbleBottom.active = !hasNote;
    _noteTop.active = hasNote;
    _noteBottom.active = hasNote;

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
    _fileSizeBytes = message.fileSize; // 记住：进度就地更新时未下载/就绪态要拼"尺寸 · 点击下载"
    [self applyFileStatusLine];
    _fileMetaLabel.attributedText = [IMMessageCell attributedMetaForMessage:message mine:mine peerReadSeq:peerReadSeq];
    [self applyFileControlStateWithFileName:_fileNameLabel.text];
}

/// 第二行状态文案：按下载态（收到的文件）或上传态渲染。configure 与进度就地更新共用一份。
- (void)applyFileStatusLine {
    IMDownloadProgress *dp = self.downloadProgress;
    IMUploadProgress *p = self.uploadProgress;
    UIColor *statusColor;
    NSString *statusText;
    BOOL pausedPrefix;
    if (dp) { // 收到的文件：下载态（未下载显"尺寸 · 点击下载"，就绪显尺寸，其余显 已下/总 或失败文案）
        statusColor = (dp.phase == IMDownloadPhaseFailed) ? IMTheme.danger : IMTheme.textSecondary;
        switch (dp.phase) {
            case IMDownloadPhaseNotStarted: statusText = [NSString stringWithFormat:@"%@ · 点击下载", IMFormatFileSize(_fileSizeBytes)]; break;
            case IMDownloadPhaseDone:       statusText = IMFormatFileSize(_fileSizeBytes); break;
            default:                        statusText = [dp fileLineText]; break; // 下载中 / 暂停 / 失败
        }
        pausedPrefix = (dp.phase == IMDownloadPhasePaused);
    } else {
        statusColor = p.failed ? IMTheme.danger : IMTheme.textSecondary;
        statusText = p ? [p fileLineText] : IMFormatFileSize(_fileSizeBytes);
        pausedPrefix = (p.pausedByUser && !p.failed);
    }
    if (pausedPrefix) {
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
}

/// 下载进度**就地更新**（M4-7）：宿主在高频 onProgress 回调里调用——只改第二行文案 + 图标位环/字形，
/// 不重配整行、不 reloadRows（文件气泡固定高，reload 也无跳变，但高频 reload 会卡死主线程）。
- (void)updateDownloadProgress:(IMDownloadProgress *)dp {
    if (!self.downloadProgress) { return; } // 非收到文件的下载态，忽略
    self.downloadProgress = dp;
    [self applyFileStatusLine];
    [self applyFileControlStateWithFileName:_fileNameLabel.text];
}

/// 图标位状态机：无进度=文件类型图标（不可点，点整条气泡=打开）；有进度=圆环+glyph（可点）。
- (void)applyFileControlStateWithFileName:(NSString *)fileName {
    if (self.downloadProgress) { [self applyDownloadControlState:self.downloadProgress fileName:fileName]; return; }
    IMUploadProgress *p = self.uploadProgress;
    _fileDisc.hidden = YES; // 上传态/无进度态不用实心圆底
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

/// 下载态图标位状态机（收到的文件，M4-7）：未下载↓ / 下载中⏸+环 / 暂停↓ / 失败↻ / 就绪=文件图标（点整条打开）。
/// 文件图标位用小号线性符号（媒体大钮才用 .circle.fill）；就绪态放行给表级手势。
- (void)applyDownloadControlState:(IMDownloadProgress *)dp fileName:(NSString *)fileName {
    BOOL showRing = (dp.phase == IMDownloadPhaseDownloading || dp.phase == IMDownloadPhasePaused);
    _fileRingTrack.hidden = _fileRing.hidden = !showRing;
    _fileDisc.hidden = YES; // 默认隐藏实心圆底，仅未下载态显
    // 已失效（服务端已清理）与就绪一样不可点：前者无从重试，后者点整条气泡打开（草图 §02-B）。
    _fileTap.enabled = (dp.phase != IMDownloadPhaseDone && !dp.expired);
    if (dp.phase == IMDownloadPhaseDone) {
        _fileIcon.image = IMFileTypeIconForName(fileName, 38);
        return;
    }
    UIColor *tint = (dp.phase == IMDownloadPhaseFailed) ? IMTheme.danger : IMTheme.accent;
    // 未下载态：不再是孤零零一个箭头 —— 与圆环等大的 accent 实心圆底 + 中间白色 ↓。
    BOOL notStarted = (dp.phase == IMDownloadPhaseNotStarted);
    if (notStarted) {
        _fileDisc.hidden = NO;
        _fileDisc.fillColor = IMTheme.accent.CGColor;
    }
    if (showRing) {
        _fileRingTrack.strokeColor = [IMTheme.textSecondary colorWithAlphaComponent:0.25].CGColor;
        _fileRing.strokeColor = tint.CGColor;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _fileRing.strokeEnd = MIN(1.0, MAX(0.0, dp.fraction));
        [CATransaction commit];
    }
    NSString *symbol = (dp.phase == IMDownloadPhaseFailed) ? (dp.expired ? @"xmark.octagon" : @"arrow.clockwise")
        : (dp.phase == IMDownloadPhaseDownloading) ? (dp.pausable ? @"pause.fill" : nil)
        : @"arrow.down"; // 未下载 / 已暂停
    UIColor *glyphTint = notStarted ? UIColor.whiteColor : tint; // 未下载态箭头落在实心圆底上 → 白色
    _fileIcon.image = symbol.length > 0
        ? [[UIImage systemImageNamed:symbol
                   withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15
                                                                                     weight:UIImageSymbolWeightSemibold]]
           imageWithTintColor:glyphTint renderingMode:UIImageRenderingModeAlwaysOriginal]
        : nil;
}

- (UIView *)previewTargetView { return _bubble; }

- (void)handleFileIconTap {
    if (self.onFileControlTap) { self.onFileControlTap(); }
}

/// 表级点击命中判断（IMBubbleHitTesting）：仅气泡本体，气泡旁整行空白不算——修「点文件/引用消息横向空白也响应」。
- (BOOL)pointInsideBubble:(CGPoint)pointInCell {
    return _bubble && !_bubble.hidden && CGRectContainsPoint([_bubble convertRect:_bubble.bounds toView:self], pointInCell);
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

@end
