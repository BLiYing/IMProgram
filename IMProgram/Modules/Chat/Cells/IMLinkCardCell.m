#import "IMLinkCardCell.h"
#import "IMMessageModel.h"
#import "IMHTTPService.h"
#import "IMImageLoader.h"
#import "IMMediaUtil.h"
#import "UILabel+IMAvatar.h"
#import "IMTheme.h"

/// 文件名/纯 URL 判定统一走 IMMediaUtil（聊天/收藏/记录共用），此处保留短别名以少改调用点。
@implementation IMLinkCardCell {
    UIView *_bubble;          // 气泡底：包裹 引用+链接+OG卡 整体（与 Web 一致——链接与卡片在同一个气泡里）
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
    UILabel *_senderLabel;    // 群聊对方消息：发送者昵称（连续段首条显示，主色小字）
    // _avatar 由 IMMessageCell 基类持有（贴内容底左侧，约束在本类补）。
    NSLayoutConstraint *_stackTop;          // 无昵称：stack 贴 cell 顶
    NSLayoutConstraint *_stackTopUnderName; // 有昵称：stack 接昵称底
    // _unreadDivider / _unreadDividerHeight 由 IMMessageCell 基类持有。
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
        // 卡片改用嵌入式底色（tertiary fill）：卡片在气泡内部，surface 底会与气泡底融为一体看不出层次。
        _card.backgroundColor = UIColor.tertiarySystemFillColor;
        _card.layer.cornerRadius = IMTheme.radiusBubble;
        _card.clipsToBounds = YES;
        _card.userInteractionEnabled = YES;
        _card.hidden = YES; // 拉到 OG 预览才显示（否则仅链接文本，与 Web 一致）
        [_card addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];

        // 气泡底：链接文本与 OG 卡片装进**同一个气泡**（对齐 Web——一个白/绿气泡里 链接 + 卡片）。
        // 整个气泡可点（打开链接），与链接/卡片各自的 tap 同一动作。
        _bubble = [UIView new];
        _bubble.layer.cornerRadius = IMTheme.radiusBubble; // 底色/尾角在 configure 按 mine 设（applyBubbleDirectionStyle）
        _bubble.userInteractionEnabled = YES;
        _bubble.translatesAutoresizingMaskIntoConstraints = NO;
        [_bubble addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
        [self.contentView addSubview:_bubble];

        _stack = [[UIStackView alloc] initWithArrangedSubviews:@[_quote, _link, _card]];
        _stack.axis = UILayoutConstraintAxisVertical;
        _stack.spacing = 6;
        _stack.alignment = UIStackViewAlignmentFill;
        _stack.translatesAutoresizingMaskIntoConstraints = NO;
        // 内容装进**气泡子树**（约束本就全相对 _bubble）：否则 stack 只是盖在 _bubble 上的兄弟视图，
        // 长按落点祖先链不含 _bubble → 挂在 _bubble 上的 UIContextMenuInteraction 收不到触摸（长按无反应）。
        // 与 IMBubbleCell(_text 在 _bubble 内)/IMChatRecordCell(内容在 _card 内) 结构对齐。
        [_bubble addSubview:_stack];

        // 群聊对方消息（与 IMBubbleCell/IMImageCell 一致）：昵称在内容上方、头像贴内容底左侧。
        _senderLabel = [UILabel new];
        _senderLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _senderLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _senderLabel.textColor = IMTheme.accent;
        _senderLabel.hidden = YES;
        [self.contentView addSubview:_senderLabel];
        [self installSenderRoleBadgeForNameLabel:_senderLabel];  // 群主/管理员徽标（基类统一样式/截断）

        // _avatar 由 IMMessageCell 基类创建（视图 + 点击插桩）；本类只补它的 leading/bottom/size 约束。

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

        // 外沿约束落在**气泡**上（stack 藏在气泡内、四周留 10/8 内边距）；gutter/靠边逻辑不变。
        _leading = [_bubble.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12];
        _trailing = [_bubble.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
        _thumbHeight = [_thumb.heightAnchor constraintEqualToConstant:0]; // 无图时为 0
        // _unreadDivider 由 IMMessageCell 基类创建并自锚（顶/左/右 + 高 0）；本类把顶部内容改锚它的 bottom。
        // 气泡顶：无昵称贴分割线底，有昵称接昵称底（群聊连续段首条）——二选一。
        _stackTop = [_bubble.topAnchor constraintEqualToAnchor:_unreadDivider.bottomAnchor constant:3];
        _stackTopUnderName = [_bubble.topAnchor constraintEqualToAnchor:_senderLabel.bottomAnchor constant:4];
        [NSLayoutConstraint activateConstraints:@[
            _stackTop,
            [_bubble.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3],
            // stack 嵌在气泡内：左右 10、上下 8 内边距。
            [_stack.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:10],
            [_stack.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-10],
            [_stack.topAnchor constraintEqualToAnchor:_bubble.topAnchor constant:8],
            [_stack.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:-8],
            [_stack.widthAnchor constraintEqualToConstant:260],
            // 昵称：顶贴 cell、左对齐内容（stack 左移时随之右移）。
            [_senderLabel.topAnchor constraintEqualToAnchor:_unreadDivider.bottomAnchor constant:4],
            [_senderLabel.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:2],
            [_senderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            // 头像：30×30 贴 cell 左、底对齐气泡底（连续段末条才 show）。
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_avatar.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:30],
            [_avatar.heightAnchor constraintEqualToConstant:30],
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
- (void)configureWithMessage:(IMMessageModel *)message mine:(BOOL)mine
                  senderName:(NSString *)senderName
                  senderRole:(IMGroupRole)senderRole {
    _card.layer.cornerRadius = IMTheme.radiusBubble;
    _quote.font = [UIFont systemFontOfSize:MAX(12, IMTheme.chatFontSize - 4)];
    _title.font = [UIFont systemFontOfSize:MAX(14, IMTheme.chatFontSize - 2) weight:UIFontWeightSemibold];
    _desc.font = [UIFont systemFontOfSize:MAX(12, IMTheme.chatFontSize - 5)];
    NSString *url = message.content ?: @"";
    _url = url;
    _leading.active = !mine;
    _trailing.active = mine;
    [IMTheme applyBubbleDirectionStyle:_bubble mine:mine]; // 底色+圆角+尾角（收发方向样式，四类气泡 cell 共用）
    // 群聊对方消息昵称（连续段首条）：显示时 stack 接昵称底，否则贴 cell 顶。
    BOOL showName = senderName.length > 0;
    _senderLabel.font = [UIFont systemFontOfSize:MAX(12, IMTheme.chatFontSize - 4) weight:UIFontWeightSemibold];
    [self applySenderName:senderName role:senderRole toNameLabel:_senderLabel];
    _senderLabel.hidden = !showName;
    _stackTop.active = !showName;
    _stackTopUnderName.active = showName;
    // 引用行（共性 #1）：URL 消息带引用时也要显示引用条 + OG 卡片。
    if (message.replyToConvSeq > 0) {
        NSString *snap = IMLocalizeReplySnippet(message.replySnapshot.length > 0 ? message.replySnapshot : @"原消息");
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
        // 服务端自家邀请卡返回**相对路径**（/avatars/…）——用本机配置的 host 补全（真机连局域网 IP 时
        // 服务端并不知道端可达地址）；外站 OG 的绝对 URL 原样透传（IMMediaFullURL 对 http 前缀不动）。
        NSString *imageURL = IMMediaFullURL(image, IMHTTPService.sharedService.host);
        [[IMImageLoader shared] loadImageURL:imageURL completion:^(UIImage *img) {
            __strong typeof(ws) self = ws;
            if (self && [self->_url isEqualToString:url]) { self->_thumb.image = img; }
        }];
    } else {
        _thumbHeight.constant = 0;
    }
    // 卡片从「仅链接」展开为「链接 + OG 卡片」→ 行高变大。UITableViewAutomaticDimension 不会自动重测，
    // 必须回调聊天页刷一次行高，否则展开内容被压进旧行高（表现为卡片被裁、滚动后才正常）。
    // 延到下一轮 runloop：命中 previewCache 时本方法**同步**跑在 cellForRow 内部，此刻回调会重入
    // tableView 的 begin/endUpdates（与 IMImageCell.onMediaSizeResolved 同样的防重入处理）。
    void (^resolved)(void) = self.onContentSizeResolved;
    if (resolved) { dispatch_async(dispatch_get_main_queue(), resolved); }
}
- (void)tapped { if (_onTap && _url) { _onTap(_url); } }

/// 表级点击命中判断（IMBubbleHitTesting）：仅气泡本体（含引用/链接/OG 卡），旁边空白不触发。
- (BOOL)pointInsideBubble:(CGPoint)pointInCell {
    return _bubble && !_bubble.hidden && CGRectContainsPoint([_bubble convertRect:_bubble.bounds toView:self], pointInCell);
}

// onAvatarTap 的手势、handleAvatarTap、applyUnreadDivider: 均由 IMMessageCell 基类提供。

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

- (void)prepareForReuse {
    [super prepareForReuse];
    _thumb.image = nil; _thumbHeight.constant = 0; _card.hidden = YES; _quote.hidden = YES;
    _senderLabel.hidden = YES; _senderLabel.text = nil; _leading.constant = 12;
    // onAvatarTap / 头像与分割线的复位由 IMMessageCell 基类 prepareForReuse 统一处理。
    _onTap = nil; _onContentSizeResolved = nil; self.onAvatarTap = nil;
}

/// 高亮/预览目标=整个气泡（链接+OG 卡片一体）：与 Web 一致一起高亮；也避免无 OG 卡片时
/// 圈到隐藏的 _card（零尺寸 → 高亮/长按预览落空）。
- (UIView *)previewTargetView { return _bubble; }

@end
