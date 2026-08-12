#import "IMMessageCell.h"
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

- (void)applyUnreadDivider:(BOOL)shows {
    _unreadDivider.hidden = !shows;
    _unreadDividerHeight.constant = shows ? 28 : 0;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.onAvatarTap = nil;
    _avatar.hidden = YES;
    _unreadDivider.hidden = YES;
    _unreadDividerHeight.constant = 0;
}

@end
