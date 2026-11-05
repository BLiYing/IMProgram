//  IMShareTargetCell.m

#import "IMShareTargetCell.h"
#import "IMConversation.h"
#import "IMCircleCheckbox.h"
#import "IMTheme.h"
#import "UILabel+IMAvatar.h"

@implementation IMShareTargetCell {
    IMCircleCheckbox *_checkbox;   // 行首圆形勾选框（仅多选态显示，对齐 Web/微信）
    UILabel *_avatar;
    UILabel *_nameLabel;
    NSLayoutConstraint *_checkboxWidth;   // 22 多选 / 0 单选（连同 avatar 前距收起）
    NSLayoutConstraint *_avatarLeading;   // = checkbox.trailing + (多选 12 / 单选 0)
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        _checkbox = [IMCircleCheckbox new];
        _checkbox.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_checkbox];

        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        _avatar.textColor = UIColor.whiteColor;
        _avatar.layer.cornerRadius = 17;
        _avatar.layer.masksToBounds = YES;
        [self.contentView addSubview:_avatar];

        _nameLabel = [UILabel new];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = [UIFont systemFontOfSize:15.5];
        _nameLabel.textColor = IMTheme.textPrimary;
        [self.contentView addSubview:_nameLabel];

        UILayoutGuide *g = self.contentView.layoutMarginsGuide;
        _checkboxWidth = [_checkbox.widthAnchor constraintEqualToConstant:0];
        _avatarLeading = [_avatar.leadingAnchor constraintEqualToAnchor:_checkbox.trailingAnchor constant:0];
        [NSLayoutConstraint activateConstraints:@[
            [_checkbox.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
            [_checkbox.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
            [_checkbox.heightAnchor constraintEqualToConstant:22],
            _checkboxWidth,
            _avatarLeading,
            [_avatar.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:34],
            [_avatar.heightAnchor constraintEqualToConstant:34],
            [_nameLabel.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:12],
            [_nameLabel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_nameLabel.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
            [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:50],
        ]];
    }
    return self;
}

/// 群聊用 name/avatarURL、seed=convID；单聊用 peerNickname/peerAvatarURL、seed=peer（对齐 Web convAvatarUrl）。
/// im_setAvatarURL 内部自动解析相对 URL 并做 cell 复用防错，故直接传原始 avatar_url。
/// 多选态在行首显圆形勾选框（选中 checkmark.circle.fill / 未选 circle）；单选态收起为 0 宽，avatar 顶到行首。
- (void)configureWithConversation:(IMConversation *)c multiSelect:(BOOL)multiSelect selected:(BOOL)selected {
    NSString *name = c.displayName; // 群名/会话备注、单聊备注名 > 昵称 > uid（全端统一口径）
    NSString *url = c.isGroup ? c.avatarURL : c.peerAvatarURL;
    NSString *seed = c.isGroup ? (c.convID ?: name) : (c.peer ?: name);
    [_avatar im_setAvatarURL:url seed:seed displayName:name];
    _nameLabel.text = name;

    _checkbox.hidden = !multiSelect;
    _checkboxWidth.constant = multiSelect ? 22 : 0;
    _avatarLeading.constant = multiSelect ? 12 : 0; // 与 IMContactCell 统一（共享 IMCircleCheckbox）
    if (multiSelect) { _checkbox.checked = selected; }
}

@end

@implementation IMShareEntryCell {
    UIImageView *_icon;
    UIView *_iconBox;
    UILabel *_titleLabel;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        _iconBox = [UIView new];
        _iconBox.translatesAutoresizingMaskIntoConstraints = NO;
        _iconBox.layer.cornerRadius = 9;
        _iconBox.layer.cornerCurve = kCACornerCurveContinuous;
        [self.contentView addSubview:_iconBox];

        _icon = [UIImageView new];
        _icon.translatesAutoresizingMaskIntoConstraints = NO;
        _icon.tintColor = UIColor.whiteColor;
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        [_iconBox addSubview:_icon];

        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont systemFontOfSize:15.5];
        _titleLabel.textColor = IMTheme.textPrimary;
        [self.contentView addSubview:_titleLabel];

        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        UILayoutGuide *g = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_iconBox.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
            [_iconBox.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
            [_iconBox.widthAnchor constraintEqualToConstant:34],
            [_iconBox.heightAnchor constraintEqualToConstant:34],
            [_icon.centerXAnchor constraintEqualToAnchor:_iconBox.centerXAnchor],
            [_icon.centerYAnchor constraintEqualToAnchor:_iconBox.centerYAnchor],
            [_icon.widthAnchor constraintEqualToConstant:20],
            [_icon.heightAnchor constraintEqualToConstant:20],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconBox.trailingAnchor constant:12],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
            [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:50],
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title symbol:(NSString *)symbol tint:(UIColor *)tint {
    _titleLabel.text = title;
    _iconBox.backgroundColor = tint;
    _icon.image = [UIImage systemImageNamed:symbol];
}

@end

UIView *IMShareTitleView(NSString *title, NSString *subtitle) {
    UILabel *t = [UILabel new];
    t.text = title;
    t.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    t.textColor = IMTheme.textPrimary;
    t.textAlignment = NSTextAlignmentCenter;
    if (subtitle.length == 0) {
        [t sizeToFit];
        return t;
    }
    UILabel *s = [UILabel new];
    s.text = subtitle;
    s.font = [UIFont systemFontOfSize:12];
    s.textColor = IMTheme.textSecondary;
    s.textAlignment = NSTextAlignmentCenter;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[t, s]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 0;
    return stack;
}
