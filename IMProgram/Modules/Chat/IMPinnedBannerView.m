//  IMPinnedBannerView.m

#import "IMPinnedBannerView.h"
#import "IMPinnedMessage.h"
#import "IMTheme.h"

static CGFloat const kBannerHeight = 44;

@interface IMPinnedBannerView ()
@property (nonatomic, assign) IMBannerStyle style;
@property (nonatomic, strong) UIView *bar;          ///< 左侧竖条（多条置顶时上亮下暗，暗示还有别的）
@property (nonatomic, strong) CAGradientLayer *barGradient;
@property (nonatomic, strong) UILabel *kicker;      ///< 「📌 置顶消息 2/3 · 小刚」
@property (nonatomic, strong) UILabel *preview;     ///< 单行预览
@property (nonatomic, strong) UIButton *tapButton;  ///< 覆盖主体区域的透明按钮（整条可点）
@property (nonatomic, strong) UIButton *listButton;
@end

@implementation IMPinnedBannerView

+ (CGFloat)bannerHeight { return kBannerHeight; }

/// 横幅强调色：置顶=主题色，公告=系统橙（对齐 sketch 的黄条）。
- (UIColor *)accentColor {
    return self.style == IMBannerStyleAnnouncement ? UIColor.systemOrangeColor : IMTheme.accent;
}

- (instancetype)initWithStyle:(IMBannerStyle)style {
    if ((self = [self initWithFrame:CGRectZero])) {
        _style = style;
        self.bar.backgroundColor = [self accentColor];
        self.kicker.textColor = [self accentColor];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = IMTheme.surfaceElevated;

        UIView *hairline = [UIView new];
        hairline.backgroundColor = IMTheme.separator;
        hairline.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:hairline];

        _bar = [UIView new];
        _bar.layer.cornerRadius = 1.5;
        _bar.clipsToBounds = YES;
        _bar.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_bar];
        _barGradient = [CAGradientLayer layer];
        _barGradient.startPoint = CGPointMake(0.5, 0);
        _barGradient.endPoint = CGPointMake(0.5, 1);
        [_bar.layer addSublayer:_barGradient];

        _kicker = [UILabel new];
        _kicker.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        _kicker.textColor = IMTheme.accent;
        _kicker.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_kicker];

        _preview = [UILabel new];
        _preview.font = [UIFont systemFontOfSize:13];
        _preview.textColor = IMTheme.textPrimary;
        _preview.lineBreakMode = NSLineBreakByTruncatingTail;
        _preview.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_preview];

        _listButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_listButton setImage:[UIImage systemImageNamed:@"list.bullet"] forState:UIControlStateNormal];
        _listButton.tintColor = IMTheme.textSecondary;
        _listButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_listButton addTarget:self action:@selector(listTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_listButton];

        // 主体点击区：盖在文字上、让在列表键左侧的整片区域都可点（文字本身不拦触摸）。
        _tapButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _tapButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_tapButton addTarget:self action:@selector(mainTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_tapButton];

        [NSLayoutConstraint activateConstraints:@[
            [hairline.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [hairline.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [hairline.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [hairline.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],

            [_bar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_bar.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_bar.widthAnchor constraintEqualToConstant:3],
            [_bar.heightAnchor constraintEqualToConstant:30],

            [_kicker.leadingAnchor constraintEqualToAnchor:_bar.trailingAnchor constant:10],
            [_kicker.topAnchor constraintEqualToAnchor:self.topAnchor constant:6],
            [_kicker.trailingAnchor constraintLessThanOrEqualToAnchor:_listButton.leadingAnchor constant:-8],

            [_preview.leadingAnchor constraintEqualToAnchor:_kicker.leadingAnchor],
            [_preview.topAnchor constraintEqualToAnchor:_kicker.bottomAnchor constant:1],
            [_preview.trailingAnchor constraintLessThanOrEqualToAnchor:_listButton.leadingAnchor constant:-8],

            [_listButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [_listButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_listButton.widthAnchor constraintEqualToConstant:34],
            [_listButton.heightAnchor constraintEqualToConstant:34],

            [_tapButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_tapButton.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_tapButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_tapButton.trailingAnchor constraintEqualToAnchor:_listButton.leadingAnchor],
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.barGradient.frame = self.bar.bounds;
}

- (void)applyItem:(IMPinnedMessage *)item index:(NSInteger)index total:(NSInteger)total isGroup:(BOOL)isGroup {
    if (!item) {
        self.hidden = YES;
        return;
    }
    self.hidden = NO;

    NSMutableString *kicker = [NSMutableString stringWithString:@"📌 置顶消息"];
    if (total > 1) { [kicker appendFormat:@" %ld/%ld", (long)(index + 1), (long)total]; }
    NSString *sender = [item senderLabelForGroup:isGroup];
    if (sender.length > 0) { [kicker appendFormat:@" · %@", sender]; }
    self.kicker.text = kicker;
    self.preview.text = [item previewText];

    // 单条=整条实色；多条=上亮下暗的两段，一眼看出还有别的置顶（对齐 Telegram 与 Web）。
    UIColor *accent = [self accentColor];
    if (total > 1) {
        self.bar.backgroundColor = UIColor.clearColor;
        self.barGradient.hidden = NO;
        self.barGradient.colors = @[(__bridge id)accent.CGColor,
                                    (__bridge id)accent.CGColor,
                                    (__bridge id)[accent colorWithAlphaComponent:0.28].CGColor,
                                    (__bridge id)[accent colorWithAlphaComponent:0.28].CGColor];
        self.barGradient.locations = @[@0, @0.46, @0.52, @1];
    } else {
        self.barGradient.hidden = YES;
        self.bar.backgroundColor = accent;
    }
    self.listButton.hidden = (total <= 1);
}

- (void)applyAnnouncement:(nullable NSString *)text {
    if (text.length == 0) { self.hidden = YES; return; }
    self.hidden = NO;
    self.kicker.text = @"📢 群公告";
    // 折行/连续空白压成单行（横幅单行布局）。
    NSArray<NSString *> *parts = [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSString *part in parts) { if (part.length > 0) { [kept addObject:part]; } }
    self.preview.text = [kept componentsJoinedByString:@" "];
    self.barGradient.hidden = YES;
    self.bar.backgroundColor = [self accentColor];
    self.listButton.hidden = YES;
}

- (void)mainTapped { if (self.onTap) { self.onTap(); } }
- (void)listTapped { if (self.onList) { self.onList(); } }

@end
