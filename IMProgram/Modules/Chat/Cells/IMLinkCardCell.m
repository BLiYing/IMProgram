#import "IMLinkCardCell.h"
#import "IMMessageModel.h"
#import "IMHTTPService.h"
#import "IMImageLoader.h"
#import "IMTheme.h"

static NSString *IMLocalizeSnippet(NSString *snap) {
    if ([snap isEqualToString:@"[image]"]) { return @"[图片]"; }
    if ([snap isEqualToString:@"[video]"]) { return @"[视频]"; }
    if ([snap isEqualToString:@"[file]"])  { return @"[文件]"; }
    return snap ?: @"";
}

/// 文件名/纯 URL 判定统一走 IMMediaUtil（聊天/收藏/记录共用），此处保留短别名以少改调用点。
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
        _link.font = [UIFont systemFontOfSize:IMTheme.chatFontSize];
        _link.numberOfLines = 0;
        _link.userInteractionEnabled = YES;
        [_link addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];

        _card = [UIView new];
        _card.backgroundColor = IMTheme.surface;
        _card.layer.cornerRadius = IMTheme.radiusBubble;
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
    _card.layer.cornerRadius = IMTheme.radiusBubble;
    _quote.font = [UIFont systemFontOfSize:MAX(12, IMTheme.chatFontSize - 4)];
    _title.font = [UIFont systemFontOfSize:MAX(14, IMTheme.chatFontSize - 2) weight:UIFontWeightSemibold];
    _desc.font = [UIFont systemFontOfSize:MAX(12, IMTheme.chatFontSize - 5)];
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
        NSFontAttributeName: [UIFont systemFontOfSize:IMTheme.chatFontSize],
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
