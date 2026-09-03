//  IMChatRecordViewController.m

#import "IMChatRecordViewController.h"
#import "IMContactCard.h"
#import "IMChatDetailViewController.h"
#import "IMProfileEditViewController.h"
#import "IMDatabase.h"
#import <SafariServices/SafariServices.h>
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMediaUtil.h"
#import "IMMediaViewerViewController.h"
#import "IMMessageModel.h"
#import "IMVoiceMiniPlayerView.h"
#import "IMVoicePlayer.h"
#import "IMMediaDownloader.h"   // 老记录补探时长：只看本地缓存，不为此发下载
#import "IMTheme.h"
#import "UILabel+IMAvatar.h"
#import "IMAccountIdentity.h"        // IMDisplayName：末级不落 userID
#import "UIViewController+IMToast.h"

// 记录预览/标题解析统一走 IMMediaUtil 的 IMSummarizeRecord/IMRecordItemPreview（含嵌套 chat_record→[聊天记录] 子标题），
// 与气泡卡片 IMChatRecordCell 共用同一 token 映射，避免各持 static 分叉。

/// 记录条目右上角的时间（打包端 `ts` = 原消息时间毫秒；老记录没有 → 空串，整块不渲染）。
/// 同一天只显 HH:mm，跨天带「M月d日」——记录常横跨多天，只显时分看不出是哪天。
/// 与 Web `recordItemTime` 同口径。
static NSString *IMRecordItemTimeText(int64_t timestampMillis) {
    if (timestampMillis <= 0) { return @""; }
    NSDate *d = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)timestampMillis / 1000.0];
    NSCalendar *cal = NSCalendar.currentCalendar;
    static NSDateFormatter *hm = nil, *mdhm = nil;
    static dispatch_once_t once; dispatch_once(&once, ^{
        hm = [NSDateFormatter new]; hm.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"]; hm.dateFormat = @"HH:mm";
        mdhm = [NSDateFormatter new]; mdhm.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"]; mdhm.dateFormat = @"M月d日 HH:mm";
    });
    return [cal isDateInToday:d] ? [hm stringFromDate:d] : [mdhm stringFromDate:d];
}

#pragma mark - 单条记录 Cell

@interface IMRecordItemCell : UITableViewCell
/// voiceModel：ct=voice/audio 时由宿主合成并**按行缓存**的消息模型（IMVoicePlayer 靠它的 id 认这条），
/// 其余类型传 nil。onPlayTap 由宿主接到 IMVoicePlayer.toggleEnsuringLocal:。
- (void)configureWithName:(NSString *)name type:(NSString *)type content:(NSString *)content fullURL:(NSString *)fullURL
                 fileName:(NSString *)fileName fileSize:(int64_t)fileSize caption:(nullable NSString *)caption
               voiceModel:(nullable IMMessageModel *)voiceModel;
/// 头行：头像 + 昵称 + 右上时间。`continued`=与上一条同一发送者 → 只留时间，头像列仍占位（正文不左右跳）。
/// avatarURL/uid/timeText 老记录可能全空（打包端 2026-08-30 才加 a/u/ts），此时头像退化成按名字生成的
/// 首字母色块、时间整块不显——**绝不能因为缺字段就不渲染这一行**。
- (void)configureHeadWithName:(NSString *)name avatarURL:(nullable NSString *)avatarURL
                          uid:(nullable NSString *)uid timeText:(NSString *)timeText continued:(BOOL)continued;
@property (nonatomic, copy, nullable) void (^onPlayTap)(void);
@end

@implementation IMRecordItemCell {
    UILabel *_name;
    UILabel *_text;
    UILabel *_caption;      // 图说条目「有字显字」：媒体/文件下方随附文本
    UIImageView *_thumb;
    UIImageView *_playBadge;
    NSString *_thumbURL;
    UIView  *_recCard;      // 嵌套合并转发：套娃 mini 卡片（标题 + 2 行预览 + 「聊天记录 ›」脚注）
    UILabel *_recTitle;
    UILabel *_recPreview;
    UIView  *_cardBox;      // 个人名片：与聊天气泡同款 mini 卡片（头像 + 名字 + @句柄 + 「个人名片」脚注）
    UILabel *_cardAvatar;
    UILabel *_cardName;
    UILabel *_cardHandle;
    IMVoiceMiniPlayerView *_voice; // 语音：与详情页/收藏页同一迷你播放器（▶ + 波形进度 + 时长）
    UILabel *_avatar;      // 头行左：28pt 头像（连续同一人时隐藏，但列宽仍由约束占住）
    UILabel *_time;        // 头行右：原消息时间
    NSLayoutConstraint *_nameLeading;   // 名字/正文缩进：恒 = 头像右缘 + 8
    NSLayoutConstraint *_avatarHeight;  // 28（首条）/ 16（连续同人：头行只剩时间，别留一格空白）
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.textColor = UIColor.whiteColor;
        _avatar.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _avatar.layer.cornerRadius = 14;
        _avatar.clipsToBounds = YES;
        [self.contentView addSubview:_avatar];

        _name = [UILabel new];
        _name.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _name.textColor = UIColor.secondaryLabelColor;
        _name.translatesAutoresizingMaskIntoConstraints = NO;
        _name.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_name];

        _time = [UILabel new];   // 原消息时间（打包端 ts；老记录没有 → 空）
        _time.translatesAutoresizingMaskIntoConstraints = NO;
        _time.font = [UIFont systemFontOfSize:12];
        _time.textColor = UIColor.tertiaryLabelColor;
        [_time setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_time setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentView addSubview:_time];

        _text = [UILabel new];
        _text.font = [UIFont systemFontOfSize:16];
        _text.textColor = UIColor.labelColor;
        _text.numberOfLines = 0;

        _caption = [UILabel new];
        _caption.font = [UIFont systemFontOfSize:15];
        _caption.textColor = UIColor.labelColor;
        _caption.numberOfLines = 0;
        _caption.hidden = YES;

        _thumb = [UIImageView new];
        _thumb.contentMode = UIViewContentModeScaleAspectFill;
        _thumb.clipsToBounds = YES;
        _thumb.layer.cornerRadius = 8;
        _thumb.backgroundColor = UIColor.tertiarySystemFillColor;
        _thumb.translatesAutoresizingMaskIntoConstraints = NO;
        [_thumb.widthAnchor constraintEqualToConstant:200].active = YES;
        [_thumb.heightAnchor constraintEqualToConstant:140].active = YES;

        _playBadge = [[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:@"play.circle.fill"
                    withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:34 weight:UIImageSymbolWeightRegular]]];
        _playBadge.tintColor = UIColor.whiteColor;
        _playBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _playBadge.hidden = YES;
        [_thumb addSubview:_playBadge];
        [NSLayoutConstraint activateConstraints:@[
            [_playBadge.centerXAnchor constraintEqualToAnchor:_thumb.centerXAnchor],
            [_playBadge.centerYAnchor constraintEqualToAnchor:_thumb.centerYAnchor],
        ]];

        // 嵌套合并转发条目 → 套娃 mini 卡片（描边圆角、比外层窄；整行点击下钻，见 didSelectRow）。
        _recCard = [UIView new];
        _recCard.translatesAutoresizingMaskIntoConstraints = NO;
        _recCard.backgroundColor = UIColor.secondarySystemBackgroundColor;
        _recCard.layer.cornerRadius = 10;
        _recCard.layer.borderWidth = 0.5;
        _recCard.layer.borderColor = UIColor.separatorColor.CGColor;
        _recTitle = [UILabel new];
        _recTitle.translatesAutoresizingMaskIntoConstraints = NO;
        _recTitle.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        _recTitle.textColor = UIColor.labelColor;
        _recTitle.numberOfLines = 1;
        [_recCard addSubview:_recTitle];
        _recPreview = [UILabel new];
        _recPreview.translatesAutoresizingMaskIntoConstraints = NO;
        _recPreview.font = [UIFont systemFontOfSize:12];
        _recPreview.textColor = UIColor.secondaryLabelColor;
        _recPreview.numberOfLines = 2;
        [_recCard addSubview:_recPreview];
        UIView *recSep = [UIView new];
        recSep.translatesAutoresizingMaskIntoConstraints = NO;
        recSep.backgroundColor = UIColor.separatorColor;
        [_recCard addSubview:recSep];
        UILabel *recFoot = [UILabel new];
        recFoot.translatesAutoresizingMaskIntoConstraints = NO;
        recFoot.font = [UIFont systemFontOfSize:11];
        recFoot.textColor = UIColor.secondaryLabelColor;
        recFoot.text = @"聊天记录 ›";
        [_recCard addSubview:recFoot];
        [NSLayoutConstraint activateConstraints:@[
            [_recCard.widthAnchor constraintEqualToConstant:240],
            [_recTitle.topAnchor constraintEqualToAnchor:_recCard.topAnchor constant:10],
            [_recTitle.leadingAnchor constraintEqualToAnchor:_recCard.leadingAnchor constant:12],
            [_recTitle.trailingAnchor constraintEqualToAnchor:_recCard.trailingAnchor constant:-12],
            [_recPreview.topAnchor constraintEqualToAnchor:_recTitle.bottomAnchor constant:6],
            [_recPreview.leadingAnchor constraintEqualToAnchor:_recCard.leadingAnchor constant:12],
            [_recPreview.trailingAnchor constraintEqualToAnchor:_recCard.trailingAnchor constant:-12],
            [recSep.topAnchor constraintEqualToAnchor:_recPreview.bottomAnchor constant:8],
            [recSep.leadingAnchor constraintEqualToAnchor:_recCard.leadingAnchor constant:12],
            [recSep.trailingAnchor constraintEqualToAnchor:_recCard.trailingAnchor constant:-12],
            [recSep.heightAnchor constraintEqualToConstant:0.5],
            [recFoot.topAnchor constraintEqualToAnchor:recSep.bottomAnchor constant:6],
            [recFoot.leadingAnchor constraintEqualToAnchor:_recCard.leadingAnchor constant:12],
            [recFoot.bottomAnchor constraintEqualToAnchor:_recCard.bottomAnchor constant:-8],
        ]];

        // 个人名片条目 → 与聊天气泡同款 mini 卡片（此前直接 `_text.text = content`，屏幕上是一串
        // {"u":"…","n":"…","a":"…"} 的 JSON 原文）。点整行进资料页（didSelectRow 已有分支）。
        _cardBox = [UIView new];
        _cardBox.translatesAutoresizingMaskIntoConstraints = NO;
        _cardBox.backgroundColor = UIColor.secondarySystemBackgroundColor;
        _cardBox.layer.cornerRadius = 10;
        _cardBox.layer.borderWidth = 0.5;
        _cardBox.layer.borderColor = UIColor.separatorColor.CGColor;
        _cardAvatar = [UILabel new];
        _cardAvatar.translatesAutoresizingMaskIntoConstraints = NO;
        _cardAvatar.textAlignment = NSTextAlignmentCenter;
        _cardAvatar.textColor = UIColor.whiteColor;
        _cardAvatar.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        _cardAvatar.layer.cornerRadius = 20;
        _cardAvatar.clipsToBounds = YES;
        [_cardBox addSubview:_cardAvatar];
        _cardName = [UILabel new];
        _cardName.translatesAutoresizingMaskIntoConstraints = NO;
        _cardName.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _cardName.textColor = UIColor.labelColor;
        _cardName.lineBreakMode = NSLineBreakByTruncatingTail;
        [_cardBox addSubview:_cardName];
        _cardHandle = [UILabel new];   // @句柄；绝不显 userID（10 位内部数字 ID）
        _cardHandle.translatesAutoresizingMaskIntoConstraints = NO;
        _cardHandle.font = [UIFont systemFontOfSize:12];
        _cardHandle.textColor = UIColor.secondaryLabelColor;
        _cardHandle.lineBreakMode = NSLineBreakByTruncatingTail;
        [_cardBox addSubview:_cardHandle];
        UIView *cardSep = [UIView new];
        cardSep.translatesAutoresizingMaskIntoConstraints = NO;
        cardSep.backgroundColor = UIColor.separatorColor;
        [_cardBox addSubview:cardSep];
        UILabel *cardFoot = [UILabel new];
        cardFoot.translatesAutoresizingMaskIntoConstraints = NO;
        cardFoot.font = [UIFont systemFontOfSize:11];
        cardFoot.textColor = UIColor.secondaryLabelColor;
        cardFoot.text = @"个人名片 ›";
        [_cardBox addSubview:cardFoot];
        [NSLayoutConstraint activateConstraints:@[
            [_cardBox.widthAnchor constraintEqualToConstant:240],
            [_cardAvatar.topAnchor constraintEqualToAnchor:_cardBox.topAnchor constant:10],
            [_cardAvatar.leadingAnchor constraintEqualToAnchor:_cardBox.leadingAnchor constant:12],
            [_cardAvatar.widthAnchor constraintEqualToConstant:40],
            [_cardAvatar.heightAnchor constraintEqualToConstant:40],
            [_cardName.topAnchor constraintEqualToAnchor:_cardAvatar.topAnchor constant:1],
            [_cardName.leadingAnchor constraintEqualToAnchor:_cardAvatar.trailingAnchor constant:10],
            [_cardName.trailingAnchor constraintEqualToAnchor:_cardBox.trailingAnchor constant:-12],
            [_cardHandle.topAnchor constraintEqualToAnchor:_cardName.bottomAnchor constant:2],
            [_cardHandle.leadingAnchor constraintEqualToAnchor:_cardName.leadingAnchor],
            [_cardHandle.trailingAnchor constraintEqualToAnchor:_cardBox.trailingAnchor constant:-12],
            [cardSep.topAnchor constraintEqualToAnchor:_cardAvatar.bottomAnchor constant:8],
            [cardSep.leadingAnchor constraintEqualToAnchor:_cardBox.leadingAnchor constant:12],
            [cardSep.trailingAnchor constraintEqualToAnchor:_cardBox.trailingAnchor constant:-12],
            [cardSep.heightAnchor constraintEqualToConstant:0.5],
            [cardFoot.topAnchor constraintEqualToAnchor:cardSep.bottomAnchor constant:6],
            [cardFoot.leadingAnchor constraintEqualToAnchor:_cardBox.leadingAnchor constant:12],
            [cardFoot.bottomAnchor constraintEqualToAnchor:_cardBox.bottomAnchor constant:-8],
        ]];

        // 语音条目 → 与资料页语音 tab / 收藏页语音行同一迷你播放器（此前直接铺 URL 文本）。
        _voice = [IMVoiceMiniPlayerView new];
        _voice.translatesAutoresizingMaskIntoConstraints = NO;
        [_voice.widthAnchor constraintEqualToConstant:240].active = YES;
        __weak typeof(self) wcell = self;
        _voice.onPlayTap = ^{ __strong typeof(wcell) sself = wcell; if (sself && sself.onPlayTap) { sself.onPlayTap(); } };

        // 正文块（不含头行）：缩进对齐头像右缘，与聊天流同一种读法。
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_text, _thumb, _caption, _recCard, _cardBox, _voice]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.alignment = UIStackViewAlignmentLeading;
        stack.spacing = 6;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        _nameLeading = [_name.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:8];
        _avatarHeight = [_avatar.heightAnchor constraintEqualToConstant:28];
        [NSLayoutConstraint activateConstraints:@[
            // 头行：头像（28pt）+ 昵称 + 右上时间。头像 hidden 时列宽由约束保住，正文不会左右跳。
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_avatar.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [_avatar.widthAnchor constraintEqualToConstant:28],
            _avatarHeight,
            _nameLeading,
            [_name.centerYAnchor constraintEqualToAnchor:_avatar.centerYAnchor],
            [_time.leadingAnchor constraintGreaterThanOrEqualToAnchor:_name.trailingAnchor constant:8],
            [_time.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_time.centerYAnchor constraintEqualToAnchor:_avatar.centerYAnchor],
            // 正文：接在头行下，左缘与昵称对齐。
            [stack.topAnchor constraintEqualToAnchor:_avatar.bottomAnchor constant:4],
            [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
            [stack.leadingAnchor constraintEqualToAnchor:_name.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        ]];
    }
    return self;
}
- (void)configureWithName:(NSString *)name type:(NSString *)type content:(NSString *)content fullURL:(NSString *)fullURL
                 fileName:(NSString *)fileName fileSize:(int64_t)fileSize caption:(NSString *)caption
               voiceModel:(IMMessageModel *)voiceModel {
    BOOL isRecord = [type isEqualToString:@"chat_record"];
    BOOL isImage = [type isEqualToString:@"image"];
    BOOL isVideo = [type isEqualToString:@"video"];
    BOOL isMedia = isImage || isVideo;
    BOOL isContact = [type isEqualToString:IMContentTypeContact];
    BOOL isVoice = [type isEqualToString:@"voice"] || [type isEqualToString:@"audio"];
    IMContactCard *card = isContact ? IMContactCardParse(content) : nil;
    // 脏名片（解析不出）退回灰字文本行，与气泡侧同口径——历史记录该保留，但不能铺 JSON 原文。
    BOOL showsCard = card != nil;
    // 图说条目「有字显字」：媒体/文件下方随附文本（在各分支 early-return 之前统一设置）。
    BOOL hasCaption = caption.length > 0 && (isMedia || [type isEqualToString:@"file"]);
    _caption.text = hasCaption ? caption : nil;
    _caption.hidden = !hasCaption;
    _recCard.hidden = !isRecord;
    _cardBox.hidden = !showsCard;
    _voice.hidden = !isVoice;
    _text.hidden = isMedia || isRecord || showsCard || isVoice;
    _thumb.hidden = !isMedia;
    _playBadge.hidden = !isVideo;
    if (isVoice) {
        [_voice configureWithMessage:(voiceModel ?: [IMMessageModel new]) mine:NO peerReadSeq:0 isGroupContext:NO];
        _thumb.image = nil; _thumbURL = nil;
        return;
    }
    if (showsCard) {
        NSString *shown = IMDisplayName(card.nickname, card.username);
        _cardName.text = shown;
        _cardHandle.text = card.username.length > 0 ? [@"@" stringByAppendingString:card.username] : @"";
        [_cardAvatar im_setAvatarURL:card.avatarURL seed:(card.userID ?: @"") displayName:shown];
        _thumb.image = nil; _thumbURL = nil;
        return;
    }
    if (isContact) {
        // 脏名片：显灰字占位而不是整段 JSON。
        _text.text = @"[个人名片]";
        _text.textColor = UIColor.secondaryLabelColor;
        _thumb.image = nil; _thumbURL = nil;
        return;
    }
    _text.textColor = UIColor.labelColor; // cell 复用：上一行可能是脏名片的灰字
    if (isRecord) {
        // 套娃 mini 卡片：content 即子记录 JSON（打包时嵌套保留），标题 + 前 2 行预览。
        NSString *subTitle = nil; NSArray<NSString *> *subLines = nil;
        IMSummarizeRecord(content, &subTitle, &subLines, 2);
        _recTitle.text = subTitle;
        _recPreview.text = [subLines componentsJoinedByString:@"\n"];
        _thumb.image = nil; _thumbURL = nil;
        return;
    }
    if (!isMedia) {
        if ([type isEqualToString:@"file"]) {
            // 文件行=类型图标 + 原名 + 大小（与聊天文件气泡同语言），点击整行打开（详情页 didSelectRow）。
            NSString *fn = fileName.length > 0 ? fileName : IMMediaFileName(content);
            if (fn.length == 0) {
                _text.text = @"[文件]";
            } else {
                NSTextAttachment *att = [NSTextAttachment new];
                att.image = IMFileTypeIconForName(fn, 24);
                att.bounds = CGRectMake(0, -6, 24, 24);
                NSMutableAttributedString *line = [[NSAttributedString attributedStringWithAttachment:att] mutableCopy];
                [line appendAttributedString:[[NSAttributedString alloc]
                    initWithString:[@" " stringByAppendingString:fn]
                        attributes:@{ NSFontAttributeName: _text.font, NSForegroundColorAttributeName: self.tintColor }]];
                NSString *size = fileSize > 0 ? IMFormatFileSize(fileSize) : @"";
                if (size.length > 0) {
                    [line appendAttributedString:[[NSAttributedString alloc]
                        initWithString:[NSString stringWithFormat:@" · %@", size]
                            attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:13],
                                          NSForegroundColorAttributeName: UIColor.secondaryLabelColor }]];
                }
                _text.attributedText = line;
            }
        } else {
            _text.text = content;
        }
        _thumb.image = nil;
        _thumbURL = nil;
        return;
    }
    _thumb.image = nil;
    _thumbURL = fullURL;
    __weak typeof(self) ws = self;
    NSString *want = fullURL;
    void (^apply)(UIImage *) = ^(UIImage *img) {
        __strong typeof(ws) self = ws;
        if (self && [self->_thumbURL isEqualToString:want]) { self->_thumb.image = img; }
    };
    if (isVideo) { [[IMVideoThumbnailLoader shared] loadPosterForVideoURL:fullURL completion:apply]; }
    else { [[IMImageLoader shared] loadImageURL:fullURL completion:apply]; }
}
/// 出池重置（§8「cell 出池重置要覆盖每个 builder 会写的属性」）：
/// 各分支已在 early-return 前把 hidden 全设好，肉眼看不到残留；但头像是**异步**加载的——
/// 上一行名片的图片可能晚到、落在被复用的这个 cell 上，故显式作废在途请求。
- (void)prepareForReuse {
    [super prepareForReuse];
    [_avatar im_clearAvatarImage];
    _avatar.text = nil; _avatar.backgroundColor = UIColor.clearColor;
    _name.text = nil; _time.text = nil;
    [_cardAvatar im_clearAvatarImage];
    _cardAvatar.text = nil;
    _cardAvatar.backgroundColor = UIColor.clearColor;
    _cardName.text = nil; _cardHandle.text = nil;
    _text.attributedText = nil; _text.text = nil;
    _text.textColor = UIColor.labelColor;
    _thumb.image = nil; _thumbURL = nil;
    self.onPlayTap = nil;
}

- (void)configureHeadWithName:(NSString *)name avatarURL:(NSString *)avatarURL
                          uid:(NSString *)uid timeText:(NSString *)timeText continued:(BOOL)continued {
    _time.text = timeText ?: @"";
    _name.hidden = continued;
    _avatar.hidden = continued;
    // 连续同人：头行只剩右侧时间，头像高度收到 16 —— 否则每条都白留一格 28pt（列宽仍由 width 保住）。
    _avatarHeight.constant = continued ? 16 : 28;
    if (continued) { [_avatar im_clearAvatarImage]; return; }  // 作废在途头像请求，防晚到的图落在别人头上
    _name.text = name;
    // seed 用**名字**：`u` 自 2026-08-31 起是卡片内匿名序号（s1/s2…），拿它当色种会让同一个人在
    // 不同卡片里换色、不同的人在两张卡里同色——毫无意义。名字虽会改，但至少同一人同色。
    // 名字为空才退回 u（老记录里它是真 uid，仍是个稳定色种）。
    [_avatar im_setAvatarURL:avatarURL seed:(name.length > 0 ? name : (uid ?: @"")) displayName:name];
}

// CALayer 的 CGColor 不随明暗动态解析：外观切换时手动重刷 mini 卡片描边色（背景是动态 UIColor 会自更新）。
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous]) {
        _recCard.layer.borderColor = UIColor.separatorColor.CGColor;
        _cardBox.layer.borderColor = UIColor.separatorColor.CGColor;
    }
}
@end

#pragma mark - 详情页

@interface IMChatRecordViewController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation IMChatRecordViewController {
    NSString *_host;
    NSString *_title;
    NSArray<NSDictionary *> *_items;
    UITableView *_tableView;
    NSMutableDictionary<NSString *, IMMessageModel *> *_voiceModels; // 行号→语音消息模型（播放态跟踪）
}

- (instancetype)initWithHost:(NSString *)host recordJSON:(NSString *)recordJSON {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _host = [host copy];
        _title = @"聊天记录";
        _items = @[];
        _voiceModels = [NSMutableDictionary dictionary];
        NSData *d = [recordJSON dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *dict = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
        if ([dict isKindOfClass:NSDictionary.class]) {
            if ([dict[@"t"] isKindOfClass:NSString.class]) { _title = dict[@"t"]; }
            if ([dict[@"items"] isKindOfClass:NSArray.class]) { _items = dict[@"items"]; }
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _title;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 60;
    [_tableView registerClass:IMRecordItemCell.class forCellReuseIdentifier:@"item"];
    [self.view addSubview:_tableView];
}

/// 「与上一条同一发送者」——连续同一人只显一次头像与昵称（微信/Telegram 式）。
/// 身份判据在 `IMRecordSenderKey`（纯函数，与 Web `recordSenderKey` 同口径、各自有单测）。
- (BOOL)isSameSenderAsPreviousAtIndex:(NSInteger)index {
    if (index <= 0 || index >= (NSInteger)_items.count) { return NO; }
    NSDictionary *cur = _items[(NSUInteger)index];
    NSDictionary *prev = _items[(NSUInteger)index - 1];
    if (![cur isKindOfClass:NSDictionary.class] || ![prev isKindOfClass:NSDictionary.class]) { return NO; }
    return [IMRecordSenderKey(cur) isEqualToString:IMRecordSenderKey(prev)];
}

/// 媒体地址补全统一走 IMMediaFullURL（含外站白名单）。此前这里是它的一份拷贝，
/// 于是同一条规则有两处实现、改一处漏一处。
- (NSString *)fullURLFor:(NSString *)content {
    return IMMediaFullURL(content, _host);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _items.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    IMRecordItemCell *cell = [tableView dequeueReusableCellWithIdentifier:@"item" forIndexPath:ip];
    NSDictionary *it = _items[ip.row];
    NSString *n = [it[@"n"] isKindOfClass:NSString.class] ? it[@"n"] : @"";
    NSString *ct = [it[@"ct"] isKindOfClass:NSString.class] ? it[@"ct"] : @"text";
    NSString *c = [it[@"c"] isKindOfClass:NSString.class] ? it[@"c"] : @"";
    NSString *fn = [it[@"fn"] isKindOfClass:NSString.class] ? it[@"fn"] : @"";
    int64_t fs = [it[@"fs"] respondsToSelector:@selector(longLongValue)] ? [it[@"fs"] longLongValue] : 0;
    NSString *cap = [it[@"cap"] isKindOfClass:NSString.class] ? it[@"cap"] : nil;
    NSString *uid = [it[@"u"] isKindOfClass:NSString.class] ? it[@"u"] : @"";
    NSString *avatar = [it[@"a"] isKindOfClass:NSString.class] ? it[@"a"] : @"";
    int64_t ts = [it[@"ts"] respondsToSelector:@selector(longLongValue)] ? [it[@"ts"] longLongValue] : 0;
    [cell configureHeadWithName:n
                      avatarURL:(avatar.length > 0 ? [self fullURLFor:avatar] : nil)
                            uid:uid
                       timeText:IMRecordItemTimeText(ts)
                      continued:[self isSameSenderAsPreviousAtIndex:ip.row]];
    IMMessageModel *vm = [self voiceModelForItem:it atIndex:ip.row];
    [cell configureWithName:n type:ct content:c fullURL:[self fullURLFor:c] fileName:fn fileSize:fs caption:cap
                 voiceModel:vm];
    __weak typeof(self) ws = self;
    cell.onPlayTap = vm ? ^{ __strong typeof(ws) self = ws; if (self) { [self playVoice:vm]; } } : nil;
    return cell;
}

/// 语音条目 → 合成消息模型（按行缓存**同一实例**：IMVoicePlayer 按 id 认这条，重建实例会丢播放态）。
/// d/w 是打包端随包带的时长与波形；老记录没有这两个字段时播放器退化成等高条纹 + 0:00，仍可播。
- (nullable IMMessageModel *)voiceModelForItem:(NSDictionary *)it atIndex:(NSInteger)index {
    NSString *ct = [it[@"ct"] isKindOfClass:NSString.class] ? it[@"ct"] : @"text";
    if (![ct isEqualToString:@"voice"] && ![ct isEqualToString:@"audio"]) { return nil; }
    NSString *key = [NSString stringWithFormat:@"%ld", (long)index];
    IMMessageModel *m = _voiceModels[key];
    if (m) { return m; }
    m = [IMMessageModel new];
    // id 里带行号：同一条语音在记录里出现多次时，两行不能共用一个播放态。
    m.clientMsgID = [NSString stringWithFormat:@"rec-%@-%@", key, [it[@"c"] isKindOfClass:NSString.class] ? it[@"c"] : @""];
    m.contentType = ct;
    m.content = [it[@"c"] isKindOfClass:NSString.class] ? it[@"c"] : @"";
    m.duration = [it[@"d"] respondsToSelector:@selector(longLongValue)] ? [it[@"d"] longLongValue] : 0;
    m.waveform = [it[@"w"] isKindOfClass:NSString.class] && [it[@"w"] length] > 0 ? it[@"w"] : nil;
    [self fillDurationFromLocalFileIfNeeded:m];
    _voiceModels[key] = m;
    return m;
}

/// 老记录（2026-08-30 之前打包的）没有 `d` 字段 → 时长只能从本地音频文件里探。
/// **只看已缓存的文件，绝不为了显个时长去发下载**（用户只是打开一张卡片，不该顺手拉一串音频）；
/// 聊天里播过/自动下载过的那些本就在缓存里，命中率不低。探不到就保持 0（显 0:00）。
/// 播放触发的下载完成后会再探一次并刷新该行，见 playVoice:。
- (void)fillDurationFromLocalFileIfNeeded:(IMMessageModel *)m {
    if (m.duration > 0 || m.content.length == 0) { return; }
    NSURL *cached = [IMMediaDownloader cachedFileURLForContent:m.content];
    if (!cached || ![NSFileManager.defaultManager fileExistsAtPath:cached.path]) { return; }
    int64_t ms = 0;
    // 同一把 IMVoiceFileIsPlayable：坏文件（如 MP4/Opus）报的时长是天文数字，它会一并挡掉。
    if (IMVoiceFileIsPlayable(cached, &ms) && ms > 0) { m.duration = ms; }
}

- (void)playVoice:(IMMessageModel *)m {
    __weak typeof(self) ws = self;
    [[IMVoicePlayer sharedPlayer] toggleEnsuringLocal:m host:_host completion:^(NSError *err) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        // IO / 格式错误不吞（CODING_STYLE §5）：直接把播放器给的文案吐出来，
        // 「下载失败」与「该语音格式无法播放」是两回事，混成一句会把排查引偏。
        if (err) { [self im_showToast:(err.localizedDescription ?: @"语音播放失败")]; return; }
        // 刚下完的文件此时才有：老记录的时长在这一刻才补得上 → 刷该行。
        if (m.duration == 0) {
            [self fillDurationFromLocalFileIfNeeded:m];
            if (m.duration > 0) { [self reloadRowForVoiceModel:m]; }
        }
    }];
}

- (void)reloadRowForVoiceModel:(IMMessageModel *)m {
    for (NSString *key in _voiceModels) {
        if (_voiceModels[key] != m) { continue; }
        NSInteger row = key.integerValue;
        if (row < 0 || row >= (NSInteger)_items.count) { return; }
        [_tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:0]]
                          withRowAnimation:UITableViewRowAnimationNone];
        return;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:NO];
    NSDictionary *it = _items[ip.row];
    NSString *ct = [it[@"ct"] isKindOfClass:NSString.class] ? it[@"ct"] : @"text";
    NSString *c = [it[@"c"] isKindOfClass:NSString.class] ? it[@"c"] : @"";
    if ([ct isEqualToString:@"chat_record"]) {
        // 套娃下钻：再 push 一层详情页渲染子记录（任意深度，靠导航栈返回）。
        // 空/非记录 JSON 不下钻（否则推出一张空白「聊天记录」死页），与顶层 openChatRecord 守卫一致。
        if (c.length == 0 || !IMLooksLikeChatRecordJSON(c)) { return; }
        IMChatRecordViewController *sub = [[IMChatRecordViewController alloc] initWithHost:_host recordJSON:c];
        [self.navigationController pushViewController:sub animated:YES];
        return;
    }
    // 个人名片条目 → 该人的资料页（P1 补齐；此前列为"不可点"，理由是"跨栈 push"——
    // 实则本页本就在导航栈里，直接 push 即可。self uid 取当前账号上下文，免改 init 签名与 4 个调用点）。
    if ([ct isEqualToString:IMContentTypeContact]) {
        IMContactCard *card = IMContactCardParse(c);
        NSString *me = IMDatabase.sharedDatabase.currentAccountContext.ownerUserID ?: @"";
        if (!card || me.length == 0) { return; }  // 脏名片不可点（与列表侧口径一致）
        if ([card.userID isEqualToString:me]) {   // §6：是我自己 → 编辑资料
            [self.navigationController pushViewController:
                [[IMProfileEditViewController alloc] initWithHost:_host userID:me] animated:YES];
            return;
        }
        IMChatDetailViewController *vc =
            [[IMChatDetailViewController alloc] initSingleWithHost:_host userID:me
                                                           peerID:card.userID
                                                     peerNickname:card.nickname
                                                    peerAvatarURL:card.avatarURL];
        vc.showsMessagePill = YES;
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }
    BOOL isVideo = [ct isEqualToString:@"video"];
    BOOL isImage = [ct isEqualToString:@"image"];
    if (!isVideo && !isImage) {
        // 文件行：应用内浏览器打开/下载（与聊天页 openLink 同口径，仅接受 http/https）。
        if ([ct isEqualToString:@"file"]) {
            NSURL *url = [NSURL URLWithString:[self fullURLFor:c]];
            if (url && ([url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"https"])) {
                [self presentViewController:[[SFSafariViewController alloc] initWithURL:url] animated:YES completion:nil];
            }
        }
        return;
    }
    IMMediaViewerViewController *viewer = [IMMediaViewerViewController viewerWithURL:[self fullURLFor:c]
                                                                            isVideo:isVideo
                                                                     preloadedImage:nil
                                                                      onOpenGallery:nil];
    [self presentViewController:viewer animated:YES completion:nil];
}

@end
