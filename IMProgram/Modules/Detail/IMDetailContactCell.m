//  IMDetailContactCell.m

#import "IMDetailContactCell.h"
#import "IMContactCard.h"
#import "IMMediaUtil.h"        // IMFormatFileDateTime（与详情页文件/链接 tab 同一时间口径）
#import "UILabel+IMAvatar.h"
#import "IMTheme.h"
#import "IMAccountIdentity.h"

const CGFloat IMDetailContactCellHeight = 64;
const CGFloat IMDetailContactCellHeightWithSource = 82;

@implementation IMDetailContactCell {
    UILabel *_avatar;
    UILabel *_name;
    UILabel *_sub;
    UILabel *_source;   ///< 「由 X 分享」独占第三行（accent，与收藏页其它分类的来源行同色）
    UILabel *_time;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.layer.cornerRadius = 22;
        _avatar.clipsToBounds = YES;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
        _avatar.textColor = UIColor.whiteColor;
        [self.contentView addSubview:_avatar];

        _name = [UILabel new];
        _name.translatesAutoresizingMaskIntoConstraints = NO;
        _name.font = [UIFont systemFontOfSize:16];
        _name.textColor = IMTheme.textPrimary;
        _name.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_name];

        _sub = [UILabel new];
        _sub.translatesAutoresizingMaskIntoConstraints = NO;
        _sub.font = [UIFont systemFontOfSize:13];
        _sub.textColor = IMTheme.textSecondary;
        _sub.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_sub];

        // 来源行独占一行：曾写成副行「@句柄 · 由 X 分享」，备注名/群昵称一长就把句柄和来源一起截没。
        _source = [UILabel new];
        _source.translatesAutoresizingMaskIntoConstraints = NO;
        _source.font = [UIFont systemFontOfSize:12];
        _source.textColor = IMTheme.accent;
        _source.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_source];

        _time = [UILabel new];
        _time.translatesAutoresizingMaskIntoConstraints = NO;
        _time.font = [UIFont systemFontOfSize:13];
        _time.textColor = IMTheme.textSecondary;
        // 时间不可被压缩/拉伸：否则长昵称会把它挤没（右上角时间是这一行的第二信息锚点）。
        [_time setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_time setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentView addSubview:_time];

        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:44],
            [_avatar.heightAnchor constraintEqualToConstant:44],
            [_name.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:11],
            [_name.topAnchor constraintEqualToAnchor:_avatar.topAnchor constant:2],
            [_time.leadingAnchor constraintGreaterThanOrEqualToAnchor:_name.trailingAnchor constant:8],
            [_time.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_time.firstBaselineAnchor constraintEqualToAnchor:_name.firstBaselineAnchor],
            [_sub.leadingAnchor constraintEqualToAnchor:_name.leadingAnchor],
            [_sub.topAnchor constraintEqualToAnchor:_name.bottomAnchor constant:3],
            [_sub.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            // 第三行不设 bottom 约束：行高由宿主表按"有无来源"固定给（64 / IMDetailContactCellHeightWithSource）。
            [_source.leadingAnchor constraintEqualToAnchor:_name.leadingAnchor],
            [_source.topAnchor constraintEqualToAnchor:_sub.bottomAnchor constant:2],
            [_source.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        ]];
    }
    return self;
}

/// cell 复用安全：configure 写的四处（名字/副行/时间/头像）在 nil 分支也全部清掉，
/// 否则出池的这一行会挂着上一条名片的内容（§9「cell 出池重置要覆盖每个 builder 会写的属性」）。
- (void)prepareForReuse {
    [super prepareForReuse];
    [self clearContent];
}

- (void)clearContent {
    _name.text = nil; _sub.text = nil; _source.text = nil; _time.text = nil;
    [_avatar im_clearAvatarImage];   // 同时作废在途异步头像加载，防上一行照片晚到覆盖
    _avatar.text = nil;
    _avatar.backgroundColor = UIColor.clearColor;
}

- (void)configureWithCard:(IMContactCard *)card
              displayName:(NSString *)displayName
               sourceName:(NSString *)sourceName
          timestampMillis:(int64_t)timestampMillis {
    if (!card) { [self clearContent]; return; }
    // 末级不落 userID（10 位随机数字内部 ID），统一走 IMDisplayName 的兜底链。
    NSString *shown = displayName.length > 0 ? displayName : IMDisplayName(card.nickname, card.username);
    _name.text = shown;
    // 副标题 = @句柄。绝不显示 userID。来源另起一行（见 _source）。
    _sub.text = card.username.length > 0 ? [@"@" stringByAppendingString:card.username] : @"";
    _source.text = sourceName.length > 0 ? [NSString stringWithFormat:@"由 %@ 分享", sourceName] : nil;
    _time.text = timestampMillis > 0 ? IMFormatFileDateTime(timestampMillis) : @"";
    [_avatar im_setAvatarURL:card.avatarURL seed:(card.userID ?: @"") displayName:shown];
}

@end
