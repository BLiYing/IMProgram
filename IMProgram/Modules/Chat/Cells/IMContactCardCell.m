//  IMContactCardCell.m

#import "IMContactCardCell.h"
#import "IMContactCardView.h"
#import "IMContactCard.h"
#import "IMMessageModel.h"
#import "UILabel+IMAvatar.h"
#import "IMTheme.h"

/// 名片气泡。布局骨架逐项对齐 IMChatRecordCell（同为定宽卡片气泡）：
/// 卡片 240 定宽、我方右对齐/对方左对齐、群聊留头像列、连续段首条上方显发送者昵称、
/// 顶部锚基类的未读分割线。差别只在卡片内容与「卡片底=名片脚注同排的时间/勾」。
///
/// 脏数据（JSON 非法 / 缺 u）**不上可点卡**：退化成一行灰字「[个人名片]」的卡（tap 不挂），
/// 免得历史里留一张点不动的死卡（设计文档 §9）。
@implementation IMContactCardCell {
    IMContactCardView *_card;
    UILabel *_fallback;                    // 脏数据降级文案（与 _card 二选一显示）
    NSLayoutConstraint *_leading;
    NSLayoutConstraint *_trailing;
    UILabel *_senderLabel;
    NSLayoutConstraint *_cardTop;
    NSLayoutConstraint *_cardTopUnderName;
    BOOL _tappable;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _card = [IMContactCardView new];
        _card.translatesAutoresizingMaskIntoConstraints = NO;
        _card.layer.cornerRadius = IMTheme.radiusBubble; // 底色/尾角在 configure 按 mine 设
        _card.userInteractionEnabled = YES;
        [_card addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
        [self.contentView addSubview:_card];

        _fallback = [UILabel new];
        _fallback.translatesAutoresizingMaskIntoConstraints = NO;
        _fallback.font = [UIFont systemFontOfSize:13];
        _fallback.textColor = IMTheme.textSecondary;
        _fallback.text = @"[个人名片]";
        _fallback.textAlignment = NSTextAlignmentCenter;
        _fallback.hidden = YES;
        [_card addSubview:_fallback];

        _senderLabel = [UILabel new];
        _senderLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _senderLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _senderLabel.textColor = IMTheme.accent;
        _senderLabel.hidden = YES;
        [self.contentView addSubview:_senderLabel];
        [self installSenderRoleBadgeForNameLabel:_senderLabel];

        _leading = [_card.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12];
        _trailing = [_card.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
        _cardTop = [_card.topAnchor constraintEqualToAnchor:_unreadDivider.bottomAnchor constant:3];
        _cardTopUnderName = [_card.topAnchor constraintEqualToAnchor:_senderLabel.bottomAnchor constant:4];
        _cardTop.active = YES;
        [NSLayoutConstraint activateConstraints:@[
            [_card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3],
            [_senderLabel.topAnchor constraintEqualToAnchor:_unreadDivider.bottomAnchor constant:4],
            [_senderLabel.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:2],
            [_senderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            // 头像：30×30 贴 cell 左、底对齐卡片底（连续段末条才 show），与其它卡片气泡一致。
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_avatar.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:30],
            [_avatar.heightAnchor constraintEqualToConstant:30],
            [_fallback.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:12],
            [_fallback.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-12],
            [_fallback.centerYAnchor constraintEqualToAnchor:_card.centerYAnchor],
        ]];
    }
    return self;
}

- (void)configureWithMessage:(IMMessageModel *)message mine:(BOOL)mine
                 displayName:(NSString *)displayName
                 peerReadSeq:(int64_t)peerReadSeq
                  senderName:(NSString *)senderName
                  senderRole:(IMGroupRole)senderRole {
    [IMTheme applyBubbleDirectionStyle:_card mine:mine];
    IMContactCard *card = IMContactCardParse(message.content);
    _tappable = card != nil;
    _fallback.hidden = _tappable;
    NSAttributedString *meta = [IMMessageCell attributedMetaForMessage:message mine:mine peerReadSeq:peerReadSeq];
    if (card) {
        [_card configureWithCard:card displayName:displayName meta:meta];
    } else {
        [_card configureAsUnparsable];   // 只留降级灰字，卡片内容整块隐藏（含作废在途头像加载）
    }
    _leading.active = !mine;
    _trailing.active = mine;

    BOOL showName = senderName.length > 0;
    _senderLabel.font = [UIFont systemFontOfSize:MAX(12, IMTheme.chatFontSize - 4) weight:UIFontWeightSemibold];
    [self applySenderName:senderName role:senderRole toNameLabel:_senderLabel];
    _senderLabel.hidden = !showName;
    _cardTop.active = !showName;
    _cardTopUnderName.active = showName;
}

- (void)applyGroupAvatarURL:(NSString *)url seed:(NSString *)seed name:(NSString *)name
                 showAvatar:(BOOL)showAvatar gutter:(BOOL)gutter {
    _leading.constant = gutter ? 48 : 12;
    if (gutter && showAvatar) {
        _avatar.hidden = NO;
        [_avatar im_setAvatarURL:url seed:seed displayName:name];
    } else {
        _avatar.hidden = YES;
    }
}

- (void)tapped {
    if (!_tappable) { return; }   // 脏名片不可点（没有 uid 可去）
    if (_onTap) { _onTap(); }
}

/// 表级点击命中判断：仅卡片本体，旁边空白不触发。
- (BOOL)pointInsideBubble:(CGPoint)pointInCell {
    return _card && !_card.hidden && CGRectContainsPoint([_card convertRect:_card.bounds toView:self], pointInCell);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _onTap = nil;
    _tappable = NO;
    _senderLabel.hidden = YES; _senderLabel.text = nil;
    _avatar.hidden = YES; _leading.constant = 12;
}

- (UIView *)previewTargetView { return _card; }

@end
