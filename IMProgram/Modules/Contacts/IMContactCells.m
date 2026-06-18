//  IMContactCells.m

#import "IMContactCells.h"
#import "IMUserCard.h"
#import "IMTheme.h"
#import "UILabel+IMAvatar.h"

static CGFloat const kIMContactAvatarSize = 48;
static CGFloat const kIMContactLeading = 16;

/// 通讯录里统一的小动作按钮（绿底白字；ghost=灰底描边不可点）。用 UIButtonConfiguration（iOS15+，免 contentEdgeInsets 弃用告警）。
static UIButton *IMMakeMiniButton(void) {
    UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
    cfg.contentInsets = NSDirectionalEdgeInsetsMake(5, 12, 5, 12);
    cfg.cornerStyle = UIButtonConfigurationCornerStyleFixed;
    cfg.background.cornerRadius = IMTheme.radiusCard;
    cfg.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attrs) {
        NSMutableDictionary *m = [attrs mutableCopy];
        m[NSFontAttributeName] = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        return m;
    };
    UIButton *b = [UIButton new];
    b.configuration = cfg;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    return b;
}

/// 设置标题（走 configuration，避免与 setTitle:forState: 混用的运行时告警）。
static void IMSetMiniTitle(UIButton *b, NSString *title) {
    UIButtonConfiguration *cfg = b.configuration ?: [UIButtonConfiguration plainButtonConfiguration];
    cfg.title = title;
    b.configuration = cfg;
}

// 按钮三态：primary=绿底可点；secondary=灰底描边**可点**（如"拒绝"）；disabled=灰底不可点（如"已申请"）。
// 注意区分 secondary 与 disabled：之前用一个 BOOL 把"灰色外观"和"不可点"绑死，导致"拒绝"被禁用、点击无反应。
typedef NS_ENUM(NSInteger, IMMiniStyle) {
    IMMiniPrimary,
    IMMiniSecondary,
    IMMiniDisabled,
};

static void IMStyleMiniButton(UIButton *b, IMMiniStyle style) {
    b.enabled = (style != IMMiniDisabled);
    BOOL ghost = (style != IMMiniPrimary); // secondary / disabled 都是灰底描边
    UIButtonConfiguration *cfg = b.configuration ?: [UIButtonConfiguration plainButtonConfiguration];
    cfg.baseForegroundColor = style == IMMiniPrimary ? UIColor.whiteColor
        : (style == IMMiniSecondary ? IMTheme.textPrimary : IMTheme.textSecondary);
    cfg.background.backgroundColor = ghost ? IMTheme.bubbleThem : IMTheme.accent;
    cfg.background.strokeColor = ghost ? IMTheme.textSecondary : nil;
    cfg.background.strokeWidth = ghost ? 1 : 0;
    b.configuration = cfg;
}

#pragma mark - 头像/名称/副标题 通用视图

/// 给 cell 添加圆形头像 + 名称 + 副标题，返回三个 label 供配置。约束基于 contentView。
/// trailingGuide：标题/副标题右侧的可让位锚点（按钮区域）。
static void IMBuildContactBody(UITableViewCell *cell, UILabel *__strong *avatarOut, UILabel *__strong *titleOut, UILabel *__strong *subtitleOut, UIView *trailingRef) {
    UILabel *avatar = [UILabel new];
    avatar.translatesAutoresizingMaskIntoConstraints = NO;
    avatar.textColor = UIColor.whiteColor;
    avatar.textAlignment = NSTextAlignmentCenter;
    avatar.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    avatar.layer.cornerRadius = kIMContactAvatarSize / 2;
    avatar.layer.masksToBounds = YES;
    [cell.contentView addSubview:avatar];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    title.textColor = IMTheme.textPrimary;
    [cell.contentView addSubview:title];

    UILabel *subtitle = [UILabel new];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.font = [UIFont systemFontOfSize:14];
    subtitle.textColor = IMTheme.textSecondary;
    [cell.contentView addSubview:subtitle];

    [NSLayoutConstraint activateConstraints:@[
        [avatar.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:kIMContactLeading],
        [avatar.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [avatar.widthAnchor constraintEqualToConstant:kIMContactAvatarSize],
        [avatar.heightAnchor constraintEqualToConstant:kIMContactAvatarSize],

        [title.leadingAnchor constraintEqualToAnchor:avatar.trailingAnchor constant:12],
        [title.topAnchor constraintEqualToAnchor:avatar.topAnchor constant:2],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:trailingRef.leadingAnchor constant:-8],

        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:3],
        [subtitle.trailingAnchor constraintLessThanOrEqualToAnchor:trailingRef.leadingAnchor constant:-8],
    ]];
    *avatarOut = avatar;
    *titleOut = title;
    *subtitleOut = subtitle;
}

static void IMConfigureBody(UILabel *avatar, UILabel *title, UILabel *subtitle, IMUserCard *card, NSString *sub) {
    NSString *name = card.displayName;
    [avatar im_setAvatarURL:card.avatarURL seed:card.userID displayName:name]; // 有 avatar_url 渲染图，否则首字母圈
    title.text = name;
    subtitle.text = sub ?: @"";
    subtitle.hidden = (sub.length == 0);
}

#pragma mark - IMContactCell

@implementation IMContactCell {
    UILabel *_avatar;
    UILabel *_title;
    UILabel *_subtitle;
    UIButton *_action;
    void (^_onAction)(void);
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _action = IMMakeMiniButton();
        [_action addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_action];
        UILayoutGuide *g = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_action.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_action.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
        IMBuildContactBody(self, &_avatar, &_title, &_subtitle, _action);
    }
    return self;
}

- (void)configureWithCard:(IMUserCard *)card subtitle:(NSString *)subtitle {
    IMConfigureBody(_avatar, _title, _subtitle, card, subtitle);
}

- (void)setActionTitle:(NSString *)title enabled:(BOOL)enabled action:(void (^)(void))onAction {
    _onAction = [onAction copy];
    if (title.length == 0) {
        _action.hidden = YES;
        return;
    }
    _action.hidden = NO;
    IMSetMiniTitle(_action, title);
    IMStyleMiniButton(_action, enabled ? IMMiniPrimary : IMMiniDisabled);
}

- (void)actionTapped {
    if (_onAction) { _onAction(); }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _onAction = nil;
    _action.hidden = YES;
}

@end

#pragma mark - IMContactRequestCell

@implementation IMContactRequestCell {
    UILabel *_avatar;
    UILabel *_title;
    UILabel *_subtitle;
    UIButton *_accept;
    UIButton *_reject;
    void (^_onAccept)(void);
    void (^_onReject)(void);
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _accept = IMMakeMiniButton();
        IMSetMiniTitle(_accept, @"同意");
        IMStyleMiniButton(_accept, IMMiniPrimary);
        [_accept addTarget:self action:@selector(acceptTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_accept];

        _reject = IMMakeMiniButton();
        IMSetMiniTitle(_reject, @"拒绝");
        IMStyleMiniButton(_reject, IMMiniSecondary); // 灰底但**可点**（修复点击无反应）
        [_reject addTarget:self action:@selector(rejectTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_reject];

        UILayoutGuide *g = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_reject.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_reject.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_accept.trailingAnchor constraintEqualToAnchor:_reject.leadingAnchor constant:-8],
            [_accept.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
        IMBuildContactBody(self, &_avatar, &_title, &_subtitle, _accept);
    }
    return self;
}

- (void)configureWithCard:(IMUserCard *)card onAccept:(void (^)(void))onAccept onReject:(void (^)(void))onReject {
    IMConfigureBody(_avatar, _title, _subtitle, card, @"请求加你为好友");
    _onAccept = [onAccept copy];
    _onReject = [onReject copy];
}

- (void)acceptTapped { if (_onAccept) { _onAccept(); } }
- (void)rejectTapped { if (_onReject) { _onReject(); } }

- (void)prepareForReuse {
    [super prepareForReuse];
    _onAccept = nil;
    _onReject = nil;
}

@end
