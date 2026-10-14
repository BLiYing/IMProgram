//  IMChatFolderConvCell.m

#import "IMChatFolderConvCell.h"
#import "IMConversation.h"
#import "IMTheme.h"
#import "UILabel+IMAvatar.h"

@implementation IMChatFolderConvCell {
    UILabel *_avatar;
    UILabel *_nameLabel;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _avatar.textColor = UIColor.whiteColor;
        _avatar.layer.cornerRadius = 20;
        _avatar.layer.masksToBounds = YES;
        [self.contentView addSubview:_avatar];
        _nameLabel = [UILabel new];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = [UIFont systemFontOfSize:16];
        _nameLabel.textColor = IMTheme.textPrimary;
        [self.contentView addSubview:_nameLabel];
        UILayoutGuide *g = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
            [_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:40],
            [_avatar.heightAnchor constraintEqualToConstant:40],
            [_nameLabel.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:12],
            [_nameLabel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_nameLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:60],
        ]];
    }
    return self;
}

- (void)configureWithConversation:(IMConversation *)c checked:(NSNumber *)checked {
    NSString *name = c.displayName;
    NSString *url = c.isGroup ? c.avatarURL : c.peerAvatarURL;
    NSString *seed = c.isGroup ? (c.convID ?: name) : (c.peer ?: name);
    [_avatar im_setAvatarURL:url seed:seed displayName:name];
    _nameLabel.text = name;
    if (!checked) { self.accessoryType = UITableViewCellAccessoryNone; }
    else {
        self.accessoryType = checked.boolValue ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        self.tintColor = IMTheme.accent;
    }
}

@end
