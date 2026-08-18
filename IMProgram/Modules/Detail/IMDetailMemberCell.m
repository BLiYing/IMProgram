//  IMDetailMemberCell.m

#import "IMDetailMemberCell.h"
#import "IMGroupInfo.h"       // IMGroupMember / IMGroupRole
#import "IMTheme.h"
#import "UILabel+IMAvatar.h"

@implementation IMDetailMemberCell {
    UILabel *_avatar; UILabel *_name; UILabel *_sub; UILabel *_role;
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
        UILayoutGuide *g = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
            [_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:40], [_avatar.heightAnchor constraintEqualToConstant:40],
            [_name.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:12],
            [_name.topAnchor constraintEqualToAnchor:_avatar.topAnchor],
            [_name.trailingAnchor constraintLessThanOrEqualToAnchor:_role.leadingAnchor constant:-8],
            [_sub.leadingAnchor constraintEqualToAnchor:_name.leadingAnchor],
            [_sub.topAnchor constraintEqualToAnchor:_name.bottomAnchor constant:2],
            [_role.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_role.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_role.heightAnchor constraintEqualToConstant:20],
            [_role.widthAnchor constraintGreaterThanOrEqualToConstant:44],
        ]];
    }
    return self;
}
- (void)configureWithMember:(IMGroupMember *)m isMe:(BOOL)isMe {
    [_avatar im_setAvatarURL:m.avatarURL seed:m.userID displayName:m.displayName];
    _name.text = isMe ? [NSString stringWithFormat:@"%@（我）", m.displayName] : m.displayName;
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
}
@end
