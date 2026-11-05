//  IMSelectedChipStrip.m

#import "IMSelectedChipStrip.h"
#import "IMLocalization.h"
#import "IMTheme.h"
#import "UILabel+IMAvatar.h"

static const CGFloat kIMChipWidth = 46;
static const CGFloat kIMChipHeight = 68;
static const CGFloat kIMChipAvatar = 44;

/// ✕ 按钮自带回调：网格（分享确认面板）与横条共用一个造格子的方法，不经 strip 实例转发。
@interface IMChipRemoveButton : UIButton
@property (nonatomic, copy, nullable) void (^handler)(void);
- (void)fire;
@end

@implementation IMChipRemoveButton
- (void)fire { if (self.handler) { self.handler(); } }
@end

@implementation IMSelectedChip
+ (instancetype)chipWithID:(NSString *)chipID avatarURL:(NSString *)avatarURL seed:(NSString *)seed name:(NSString *)name {
    IMSelectedChip *c = [IMSelectedChip new];
    c.chipID = chipID ?: @"";
    c.avatarURL = avatarURL;
    c.seed = seed ?: @"";
    c.name = name ?: @"";
    return c;
}
@end

@implementation IMSelectedChipStrip

+ (CGFloat)chipWidth { return kIMChipWidth; }
+ (CGFloat)chipHeight { return kIMChipHeight; }

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.showsHorizontalScrollIndicator = NO;
        self.alwaysBounceHorizontal = NO;
        _leadingInset = IMTheme.space4;
        _chipTop = 12;
    }
    return self;
}

- (void)setChips:(NSArray<IMSelectedChip *> *)chips scrollToEnd:(BOOL)scrollToEnd {
    for (UIView *v in self.subviews) { [v removeFromSuperview]; }
    CGFloat x = self.leadingInset;
    NSUInteger shown = self.maxChips > 0 ? MIN(chips.count, self.maxChips) : chips.count;
    for (NSUInteger i = 0; i < shown; i++) {
        IMSelectedChip *c = chips[i];
        __weak typeof(self) ws = self;
        [self addSubview:[IMSelectedChipStrip chipViewForChip:c origin:CGPointMake(x, self.chipTop)
                                                     onRemove:^(NSString *chipID) { if (ws.onRemove) { ws.onRemove(chipID); } }]];
        x += kIMChipWidth + IMTheme.space3;
    }
    if (chips.count > shown) {
        UILabel *more = [UILabel new];
        more.text = [NSString stringWithFormat:@"+%lu", (unsigned long)(chips.count - shown)];
        more.font = [UIFont systemFontOfSize:13];
        more.textColor = IMTheme.textSecondary;
        more.frame = CGRectMake(x, self.chipTop, kIMChipWidth, kIMChipAvatar);
        more.textAlignment = NSTextAlignmentCenter;
        [self addSubview:more];
        x += kIMChipWidth + IMTheme.space3;
    }
    CGFloat width = chips.count > 0 ? x - IMTheme.space3 + IMTheme.space2 : 0;
    self.contentSize = CGSizeMake(width, 0);
    if (scrollToEnd) {
        [self layoutIfNeeded];
        CGFloat maxX = MAX(0, self.contentSize.width - CGRectGetWidth(self.bounds));
        [self setContentOffset:CGPointMake(maxX, 0) animated:YES];
    } else if (self.contentOffset.x > MAX(0, width - CGRectGetWidth(self.bounds))) {
        // 删掉末尾几格后内容变短：别停在空白处。
        self.contentOffset = CGPointMake(MAX(0, width - CGRectGetWidth(self.bounds)), 0);
    }
}

+ (UIView *)chipViewForChip:(IMSelectedChip *)c origin:(CGPoint)origin
                    onRemove:(void (^)(NSString *chipID))onRemove {
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(origin.x, origin.y, kIMChipWidth, kIMChipHeight)];
    UILabel *avatar = [self avatarCircle];
    avatar.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [avatar im_setAvatarURL:c.avatarURL seed:c.seed displayName:c.name];
    [wrap addSubview:avatar];
    [wrap addSubview:[self titleLabel:c.name]];

    if (c.chipID.length > 0 && onRemove) {
        IMChipRemoveButton *rm = [IMChipRemoveButton buttonWithType:UIButtonTypeSystem];
        rm.frame = CGRectMake(29, -2, 18, 18);
        rm.layer.cornerRadius = 9;
        rm.layer.masksToBounds = YES;
        rm.backgroundColor = IMTheme.textSecondary;
        rm.tintColor = UIColor.whiteColor;
        [rm setImage:[[UIImage systemImageNamed:@"xmark"] imageByApplyingSymbolConfiguration:
                      [UIImageSymbolConfiguration configurationWithPointSize:9 weight:UIImageSymbolWeightBold]]
            forState:UIControlStateNormal];
        rm.accessibilityLabel = IMLocalizedFormat(@"group.create.remove_member", c.name ?: @"");
        NSString *chipID = [c.chipID copy];
        rm.handler = ^{ onRemove(chipID); };
        [rm addTarget:rm action:@selector(fire) forControlEvents:UIControlEventTouchUpInside];
        [wrap addSubview:rm];
    }
    return wrap;
}

+ (UILabel *)avatarCircle {
    UILabel *avatar = [[UILabel alloc] initWithFrame:CGRectMake(1, 0, kIMChipAvatar, kIMChipAvatar)];
    avatar.layer.cornerRadius = kIMChipAvatar / 2;
    avatar.layer.masksToBounds = YES;
    avatar.textAlignment = NSTextAlignmentCenter;
    avatar.userInteractionEnabled = YES;
    return avatar;
}

+ (UILabel *)titleLabel:(NSString *)name {
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 49, kIMChipWidth, 14)];
    title.text = name;
    title.font = [UIFont systemFontOfSize:11];
    title.textColor = IMTheme.textSecondary;
    title.textAlignment = NSTextAlignmentCenter;
    title.lineBreakMode = NSLineBreakByTruncatingTail;
    return title;
}

+ (UIView *)addChipWithTitle:(NSString *)title target:(id)target action:(SEL)action circle:(UILabel **)circle {
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 12, kIMChipWidth, kIMChipHeight)];
    UILabel *avatar = [self avatarCircle];
    avatar.text = @"＋";
    avatar.font = [UIFont systemFontOfSize:19];
    avatar.textColor = IMTheme.textSecondary;
    avatar.layer.borderWidth = 1;
    avatar.layer.borderColor = IMTheme.separator.CGColor;
    [avatar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:target action:action]];
    [wrap addSubview:avatar];
    [wrap addSubview:[self titleLabel:title]];
    if (circle) { *circle = avatar; }
    return wrap;
}

@end
