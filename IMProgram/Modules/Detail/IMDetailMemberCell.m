//  IMDetailMemberCell.m

#import "IMDetailMemberCell.h"
#import "IMGroupInfo.h"       // IMGroupMember / IMGroupRole
#import "IMTheme.h"
#import "IMTimeUtil.h"        // IMNowMillis()：判定成员级禁言是否仍在期
#import "UILabel+IMAvatar.h"

@implementation IMDetailMemberCell {
    UILabel *_avatar; UILabel *_name; UILabel *_sub; UILabel *_role;
    UILabel *_muteBadge; ///< G2「禁言中」胶囊：muteUntil>now 时显示；与 role 徽标同一行、居右紧挨（role 左侧）
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        _avatar = [UILabel new]; _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textColor = UIColor.whiteColor; _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _avatar.layer.cornerRadius = 20; _avatar.layer.masksToBounds = YES;
        [self.contentView addSubview:_avatar];
        _name = [UILabel new]; _name.translatesAutoresizingMaskIntoConstraints = NO;
        _name.font = [UIFont systemFontOfSize:16]; _name.textColor = IMTheme.textPrimary;
        [self.contentView addSubview:_name];
        _sub = [UILabel new]; _sub.translatesAutoresizingMaskIntoConstraints = NO;
        _sub.font = [UIFont systemFontOfSize:12]; _sub.textColor = IMTheme.textSecondary;
        [self.contentView addSubview:_sub];
        _role = [UILabel new]; _role.translatesAutoresizingMaskIntoConstraints = NO;
        _role.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium]; _role.textAlignment = NSTextAlignmentCenter;
        _role.layer.cornerRadius = 8; _role.layer.masksToBounds = YES;
        [self.contentView addSubview:_role];
        [_role setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_role setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        // 禁言胶囊：与 role 同款样式，橙红色调；hidden 时不占宽（左边距对齐到 role.leading）。
        _muteBadge = [UILabel new]; _muteBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _muteBadge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _muteBadge.textAlignment = NSTextAlignmentCenter;
        _muteBadge.textColor = UIColor.systemOrangeColor;
        _muteBadge.backgroundColor = [UIColor.systemOrangeColor colorWithAlphaComponent:0.15];
        _muteBadge.layer.cornerRadius = 8; _muteBadge.layer.masksToBounds = YES;
        _muteBadge.text = @"禁言中";
        [self.contentView addSubview:_muteBadge];
        [_muteBadge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_muteBadge setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        UILayoutGuide *g = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
            [_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:40], [_avatar.heightAnchor constraintEqualToConstant:40],
            [_name.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:12],
            [_name.topAnchor constraintEqualToAnchor:_avatar.topAnchor],
            [_name.trailingAnchor constraintLessThanOrEqualToAnchor:_muteBadge.leadingAnchor constant:-8],
            [_sub.leadingAnchor constraintEqualToAnchor:_name.leadingAnchor],
            [_sub.topAnchor constraintEqualToAnchor:_name.bottomAnchor constant:2],
            [_muteBadge.trailingAnchor constraintEqualToAnchor:_role.leadingAnchor constant:-6],
            [_muteBadge.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_muteBadge.heightAnchor constraintEqualToConstant:20],
            [_muteBadge.widthAnchor constraintGreaterThanOrEqualToConstant:44],
            [_role.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_role.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_role.heightAnchor constraintEqualToConstant:20],
            [_role.widthAnchor constraintGreaterThanOrEqualToConstant:44],
        ]];
    }
    return self;
}
- (void)configureWithMember:(IMGroupMember *)m isMe:(BOOL)isMe {
    // 本机显示名（备注优先）：这一列只给我自己看，不进任何要发出去的内容。
    NSString *shown = m.localDisplayName;
    [_avatar im_setAvatarURL:m.avatarURL seed:m.userID displayName:shown];
    _name.text = isMe ? [NSString stringWithFormat:@"%@（我）", shown] : shown;
    _sub.text = m.userID;
    if (m.role == IMGroupRoleOwner) {
        _role.hidden = NO; _role.text = @"群主"; _role.textColor = IMTheme.accent;
        _role.backgroundColor = [IMTheme.accent colorWithAlphaComponent:0.15];
    } else if (m.role == IMGroupRoleAdmin) {
        _role.hidden = NO; _role.text = @"管理员"; _role.textColor = UIColor.systemGreenColor;
        _role.backgroundColor = [UIColor.systemGreenColor colorWithAlphaComponent:0.15];
    } else {
        _role.hidden = YES; _role.text = @"";
    }
    // G2 禁言中标签：服务端把「永久」归一为 MutePermanent(1<<62) 这样的大正数，直接 >now 判定即可。
    _muteBadge.hidden = !(m.muteUntil > IMNowMillis());
}
@end
