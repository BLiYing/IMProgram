#import "IMMessageCell.h"
#import "IMChatMessageLogic.h"
#import "IMFailBadgeView.h"
#import "IMMessageModel.h"
#import "IMTheme.h"

@implementation IMMessageCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // 群头像列：仅创建视图 + 点击插桩；leading/bottom/size 约束因锚点各异（贴各自内容底）交由子类补。
        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textColor = UIColor.whiteColor;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _avatar.layer.cornerRadius = 15;
        _avatar.layer.masksToBounds = YES;
        _avatar.hidden = YES;
        _avatar.userInteractionEnabled = YES;
        [_avatar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleAvatarTap)]];
        [self.contentView addSubview:_avatar];

        // 「未读消息」分割线：贴 contentView 顶、默认高 0（此时 bottom==contentView.top，布局与无分割线逐像素等价）；
        // 仅首条未读行展开到 28。子类把自身顶部内容改锚 _unreadDivider.bottomAnchor 即随之下移。
        _unreadDivider = [UILabel new];
        _unreadDivider.translatesAutoresizingMaskIntoConstraints = NO;
        _unreadDivider.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _unreadDivider.textColor = IMTheme.textSecondary;
        _unreadDivider.textAlignment = NSTextAlignmentCenter;
        _unreadDivider.text = @"未读消息";
        _unreadDivider.clipsToBounds = YES;
        _unreadDivider.hidden = YES;
        [self.contentView addSubview:_unreadDivider];
        // 发送失败红❗：视图与点击插桩在基类（样式收敛在 IMFailBadgeView），
        // 定位约束因锚点各异（贴各自内容区左侧）交由子类经 installFailBadgeAnchor: 登记。
        _failBadge = [IMFailBadgeView new];
        __weak typeof(self) ws = self;
        _failBadge.onTap = ^{ if (ws.onRetryTap) { ws.onRetryTap(); } };
        [self.contentView addSubview:_failBadge];

        _unreadDividerHeight = [_unreadDivider.heightAnchor constraintEqualToConstant:0];
        [NSLayoutConstraint activateConstraints:@[
            [_unreadDivider.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_unreadDivider.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_unreadDivider.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            _unreadDividerHeight,
        ]];
    }
    return self;
}

- (void)handleAvatarTap { if (self.onAvatarTap) { self.onAvatarTap(); } }

- (void)installFailBadgeAnchor:(NSLayoutConstraint *)anchor {
    _failBadgeAnchor = anchor; // 仅失败时激活（见 applyFailBadgeForMessage:mine:）
}

- (void)applyFailBadgeForMessage:(IMMessageModel *)message mine:(BOOL)mine {
    BOOL failed = mine && message.status == IMMessageStatusFailed;
    [self applyFailBadgeShows:failed
                     tappable:(failed && IMResendPolicyForMessage(message, mine) != IMResendPolicyNone)];
}

- (void)applyFailBadgeShows:(BOOL)shows tappable:(BOOL)tappable {
    _failBadge.hidden = !shows;
    _failBadge.tappable = shows && tappable;
    _failBadgeAnchor.active = shows;
}

- (void)applyUnreadDivider:(BOOL)shows {
    _unreadDivider.hidden = !shows;
    _unreadDividerHeight.constant = shows ? 28 : 0;
}

- (void)installSenderRoleBadgeForNameLabel:(UILabel *)nameLabel {
    if (!nameLabel || _senderRoleBadge) { return; }
    // 昵称已在 apply 时按字符簇截断至 ≤12；truncatingTail + 低抗压再兜底极窄屏，杜绝把徽标挤出屏幕。
    nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [nameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    UIView *wrap = [UIView new];
    wrap.translatesAutoresizingMaskIntoConstraints = NO;
    wrap.layer.cornerRadius = 4;
    wrap.layer.cornerCurve = kCACornerCurveContinuous;
    wrap.layer.masksToBounds = YES;
    wrap.hidden = YES;
    wrap.userInteractionEnabled = NO;
    [wrap setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [wrap setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.contentView addSubview:wrap];

    UILabel *lbl = [UILabel new];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [wrap addSubview:lbl];

    [NSLayoutConstraint activateConstraints:@[
        [wrap.leadingAnchor constraintEqualToAnchor:nameLabel.trailingAnchor constant:6],
        [wrap.centerYAnchor constraintEqualToAnchor:nameLabel.centerYAnchor],
        [wrap.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        [wrap.heightAnchor constraintEqualToConstant:16],
        [lbl.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:6],
        [lbl.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-6],
        [lbl.centerYAnchor constraintEqualToAnchor:wrap.centerYAnchor],
    ]];
    _senderRoleBadge = wrap;
    _senderRoleLabel = lbl;
}

- (void)applySenderName:(NSString *)name role:(IMGroupRole)role toNameLabel:(UILabel *)nameLabel {
    nameLabel.text = [IMMessageCell clampSenderName:name];
    if (name.length == 0 || role == IMGroupRoleMember) {
        _senderRoleBadge.hidden = YES;
        _senderRoleLabel.text = nil;
        return;
    }
    if (role == IMGroupRoleOwner) {
        _senderRoleLabel.text = @"群主";
        _senderRoleLabel.textColor = IMTheme.accent;
        _senderRoleBadge.backgroundColor = [IMTheme.accent colorWithAlphaComponent:0.14];
    } else { // IMGroupRoleAdmin
        _senderRoleLabel.text = @"管理员";
        _senderRoleLabel.textColor = IMTheme.textSecondary;
        _senderRoleBadge.backgroundColor = [IMTheme.separator colorWithAlphaComponent:0.5];
    }
    _senderRoleBadge.hidden = NO;
}

+ (NSString *)clampSenderName:(NSString *)name {
    static const NSUInteger kMax = 12;   // 最多约 12 个中文字
    if (name.length == 0) { return name ?: @""; }
    __block NSUInteger count = 0;
    __block NSUInteger cut = NSNotFound;
    [name enumerateSubstringsInRange:NSMakeRange(0, name.length)
                             options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString *sub, NSRange r, NSRange er, BOOL *stop) {
        count++;
        if (count == kMax) { cut = NSMaxRange(r); }
        if (count > kMax) { *stop = YES; }
    }];
    if (count <= kMax || cut == NSNotFound) { return name; }
    return [[name substringToIndex:cut] stringByAppendingString:@"…"];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.onAvatarTap = nil;
    self.onRetryTap = nil;
    _failBadge.hidden = YES;
    _failBadge.tappable = NO;
    _failBadgeAnchor.active = NO;
    _avatar.hidden = YES;
    _unreadDivider.hidden = YES;
    _unreadDividerHeight.constant = 0;
    _senderRoleBadge.hidden = YES;
    _senderRoleLabel.text = nil;
}

/// 气泡内右下角富文本：时间(灰)；自己消息追加状态勾——已送达 ✓(灰)/已读 ✓✓(绿)/发送中/失败。
const int64_t kIMPeerReadSeqHidden = -1;

+ (NSAttributedString *)attributedMetaForMessage:(IMMessageModel *)message
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
    if (message.convSeq > 0 && peerReadSeq != kIMPeerReadSeqHidden) {
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
