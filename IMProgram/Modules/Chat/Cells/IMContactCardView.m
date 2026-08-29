//  IMContactCardView.m

#import "IMContactCardView.h"
#import "IMContactCard.h"
#import "UILabel+IMAvatar.h"
#import "IMTheme.h"

const CGFloat IMContactCardViewWidth = 240;

@implementation IMContactCardView {
    UILabel *_avatar;
    UILabel *_name;
    UILabel *_sub;
    UIView  *_sep;
    UIImageView *_footIcon;
    UILabel *_footText;
    UILabel *_meta;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.layer.cornerRadius = 22;   // 44/2
        _avatar.clipsToBounds = YES;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
        _avatar.textColor = UIColor.whiteColor;
        [self addSubview:_avatar];

        _name = [UILabel new];
        _name.translatesAutoresizingMaskIntoConstraints = NO;
        _name.textColor = IMTheme.textPrimary;
        _name.numberOfLines = 1;
        _name.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_name];

        _sub = [UILabel new];
        _sub.translatesAutoresizingMaskIntoConstraints = NO;
        _sub.textColor = IMTheme.textSecondary;
        _sub.numberOfLines = 1;
        _sub.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_sub];

        _sep = [UIView new];
        _sep.translatesAutoresizingMaskIntoConstraints = NO;
        _sep.backgroundColor = UIColor.separatorColor;
        [self addSubview:_sep];

        _footIcon = [UIImageView new];
        _footIcon.translatesAutoresizingMaskIntoConstraints = NO;
        _footIcon.contentMode = UIViewContentModeScaleAspectFit;
        _footIcon.tintColor = IMTheme.textSecondary;
        _footIcon.image = [UIImage systemImageNamed:@"person.crop.square"
                              withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:11]];
        [self addSubview:_footIcon];

        _footText = [UILabel new];
        _footText.translatesAutoresizingMaskIntoConstraints = NO;
        _footText.font = [UIFont systemFontOfSize:11];
        _footText.textColor = IMTheme.textSecondary;
        _footText.text = @"个人名片";
        [self addSubview:_footText];

        _meta = [UILabel new];   // 时间 + 勾（气泡右下角），确认 sheet 里为空
        _meta.translatesAutoresizingMaskIntoConstraints = NO;
        _meta.font = [UIFont systemFontOfSize:11];
        [_meta setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self addSubview:_meta];

        [NSLayoutConstraint activateConstraints:@[
            [self.widthAnchor constraintEqualToConstant:IMContactCardViewWidth],
            [_avatar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_avatar.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
            [_avatar.widthAnchor constraintEqualToConstant:44],
            [_avatar.heightAnchor constraintEqualToConstant:44],
            [_name.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:10],
            [_name.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [_name.topAnchor constraintEqualToAnchor:_avatar.topAnchor constant:2],
            [_sub.leadingAnchor constraintEqualToAnchor:_name.leadingAnchor],
            [_sub.trailingAnchor constraintEqualToAnchor:_name.trailingAnchor],
            [_sub.topAnchor constraintEqualToAnchor:_name.bottomAnchor constant:3],
            [_sep.topAnchor constraintEqualToAnchor:_avatar.bottomAnchor constant:8],
            [_sep.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_sep.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [_sep.heightAnchor constraintEqualToConstant:0.5],
            [_footIcon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_footIcon.centerYAnchor constraintEqualToAnchor:_footText.centerYAnchor],
            [_footIcon.widthAnchor constraintEqualToConstant:12],
            [_footText.leadingAnchor constraintEqualToAnchor:_footIcon.trailingAnchor constant:4],
            [_footText.topAnchor constraintEqualToAnchor:_sep.bottomAnchor constant:6],
            [_footText.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
            [_meta.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [_meta.centerYAnchor constraintEqualToAnchor:_footText.centerYAnchor],
            [_meta.leadingAnchor constraintGreaterThanOrEqualToAnchor:_footText.trailingAnchor constant:6],
        ]];
    }
    return self;
}

- (void)configureAsUnparsable {
    for (UIView *v in @[_avatar, _name, _sub, _sep, _footIcon, _footText, _meta]) { v.hidden = YES; }
    [_avatar im_clearAvatarImage];  // 作废在途异步头像加载，否则上一行的照片会晚到覆盖上来
    _avatar.text = nil;
}

- (void)configureWithCard:(IMContactCard *)card displayName:(NSString *)displayName meta:(NSAttributedString *)metaText {
    for (UIView *v in @[_avatar, _name, _sub, _sep, _footIcon, _footText]) { v.hidden = NO; }
    // 主标题走**收方本地**显示名（备注优先）；副行恒显内部 ID，两者同源于 §9 的口径。
    NSString *shown = displayName.length > 0 ? displayName
                    : (card.nickname.length > 0 ? card.nickname : (card.userID ?: @""));
    _name.font = [UIFont systemFontOfSize:MAX(14, IMTheme.chatFontSize - 2) weight:UIFontWeightSemibold];
    _sub.font = [UIFont systemFontOfSize:MAX(12, IMTheme.chatFontSize - 5)];
    _name.text = shown;
    _sub.text = card.userID.length > 0 ? [@"ID " stringByAppendingString:card.userID] : @"";
    // 头像：有 URL 走图片，无则首字母圈（seed=uid，取色稳定）。加载失败由 category 自行回退。
    [_avatar im_setAvatarURL:card.avatarURL seed:(card.userID ?: @"") displayName:shown];
    _meta.attributedText = metaText;
    _meta.hidden = metaText.length == 0;
}

@end
