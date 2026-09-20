//  IMCallRecordCell.m

#import "IMCallRecordCell.h"
#import "IMCallRecord.h"
#import "IMMessageModel.h"
#import "UILabel+IMAvatar.h"
#import "IMTheme.h"

/// 通话记录气泡。骨架对齐 IMContactCardCell：普通气泡壳（底色/圆角/尾角走 applyBubbleDirectionStyle）、
/// 我方右对齐 / 对方左对齐、顶部锚基类未读分割线、失败红❗。
/// 规格（UX 稿 §03）：横内边距 12 / 竖 10；图标边长 = chatFontSize + 5，与文字间距 8；正文 chatFontSize 单行不换行；
/// 时间/勾 11，与文字间距 10、底对齐；最大宽 0.75 × 内容区；按下 alpha 0.7（0.08s），不做涟漪/缩放。
@implementation IMCallRecordCell {
    UIView *_bubble;
    UIImageView *_icon;
    UILabel *_label;
    UILabel *_meta;
    NSLayoutConstraint *_iconSize;
    NSLayoutConstraint *_leading;
    NSLayoutConstraint *_trailing;
    NSLayoutConstraint *_top;
    UILabel *_senderLabel;
    NSLayoutConstraint *_topUnderName;
    BOOL _tappable;
    BOOL _video;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _bubble = [UIView new];
        _bubble.translatesAutoresizingMaskIntoConstraints = NO;
        _bubble.userInteractionEnabled = YES;
        [_bubble addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
        [self.contentView addSubview:_bubble];

        _icon = [UIImageView new];
        _icon.translatesAutoresizingMaskIntoConstraints = NO;
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        [_bubble addSubview:_icon];

        _label = [UILabel new];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.numberOfLines = 1;                      // 单行不换行、不截断
        [_label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_bubble addSubview:_label];

        _meta = [UILabel new];
        _meta.translatesAutoresizingMaskIntoConstraints = NO;
        [_meta setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_meta setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_bubble addSubview:_meta];

        _senderLabel = [UILabel new];
        _senderLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _senderLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _senderLabel.textColor = IMTheme.accent;
        _senderLabel.hidden = YES;
        [self.contentView addSubview:_senderLabel];
        [self installSenderRoleBadgeForNameLabel:_senderLabel];

        _leading = [_bubble.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12];
        _trailing = [_bubble.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
        _top = [_bubble.topAnchor constraintEqualToAnchor:_unreadDivider.bottomAnchor constant:3];
        _topUnderName = [_bubble.topAnchor constraintEqualToAnchor:_senderLabel.bottomAnchor constant:4];
        _top.active = YES;
        _iconSize = [_icon.widthAnchor constraintEqualToConstant:22];
        [self installFailBadgeAnchor:[_failBadge.trailingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:-6]];
        [NSLayoutConstraint activateConstraints:@[
            _iconSize,
            [_icon.heightAnchor constraintEqualToAnchor:_icon.widthAnchor],
            [_icon.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:12],
            [_icon.centerYAnchor constraintEqualToAnchor:_label.centerYAnchor],
            [_label.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:8],
            [_label.topAnchor constraintEqualToAnchor:_bubble.topAnchor constant:10],
            [_label.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:-10],
            [_meta.leadingAnchor constraintEqualToAnchor:_label.trailingAnchor constant:10],
            [_meta.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-12],
            [_meta.lastBaselineAnchor constraintEqualToAnchor:_label.lastBaselineAnchor],
            [_bubble.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.75],
            [_failBadge.centerYAnchor constraintEqualToAnchor:_bubble.centerYAnchor],
            [_bubble.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3],
            [_senderLabel.topAnchor constraintEqualToAnchor:_unreadDivider.bottomAnchor constant:4],
            [_senderLabel.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:2],
            [_senderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_avatar.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:30],
            [_avatar.heightAnchor constraintEqualToConstant:30],
        ]];
    }
    return self;
}

- (void)configureWithMessage:(IMMessageModel *)message mine:(BOOL)mine
                 displayName:(NSString *)displayName
                 peerReadSeq:(int64_t)peerReadSeq
                  senderName:(NSString *)senderName
                  senderRole:(IMGroupRole)senderRole {
    [IMTheme applyBubbleDirectionStyle:_bubble mine:mine];
    IMCallRecordDisplay *d = IMCallRecordRender(message.content, mine, NO, nil);
    _tappable = d.supported && d.tappable;
    _video = d.video;

    CGFloat font = IMTheme.chatFontSize;
    BOOL missed = d.tone == IMCallRecordToneMissed;
    UIColor *textColor = missed ? IMTheme.danger : (mine ? IMTheme.bubbleMeText : IMTheme.textPrimary); // 红只用在被叫未接一处
    _label.font = [UIFont systemFontOfSize:font weight:UIFontWeightRegular];
    _label.textColor = d.supported ? textColor : IMTheme.textSecondary;
    _label.text = d.text;
    _iconSize.constant = font + 5;
    _icon.hidden = !d.supported;                       // 兜底：只留灰字
    _icon.image = [UIImage systemImageNamed:d.video ? @"video.fill" : @"phone.fill"];
    _icon.tintColor = textColor;
    _meta.attributedText = [IMMessageCell attributedMetaForMessage:message mine:mine peerReadSeq:peerReadSeq];

    _leading.active = !mine;
    _trailing.active = mine;
    BOOL showName = senderName.length > 0;
    _senderLabel.font = [UIFont systemFontOfSize:MAX(12, font - 4) weight:UIFontWeightSemibold];
    [self applySenderName:senderName role:senderRole toNameLabel:_senderLabel];
    _senderLabel.hidden = !showName;
    _top.active = !showName;
    _topUnderName.active = showName;
    _bubble.alpha = 1;
    [self applyFailBadgeForMessage:message mine:mine];
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
    if (!_tappable) { return; }
    _bubble.alpha = 0.7;                               // 按下态 0.7，0.08s 恢复
    [UIView animateWithDuration:0.08 animations:^{ self->_bubble.alpha = 1; }];
    if (_onTap) { _onTap(_video); }
}

- (BOOL)pointInsideBubble:(CGPoint)pointInCell {
    return _bubble && !_bubble.hidden && CGRectContainsPoint([_bubble convertRect:_bubble.bounds toView:self], pointInCell);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _onTap = nil;
    _tappable = NO;
    _bubble.alpha = 1;
    _senderLabel.hidden = YES; _senderLabel.text = nil;
    _avatar.hidden = YES; _leading.constant = 12;
}

- (UIView *)previewTargetView { return _bubble; }

@end
