//  IMPinnedBannerView.m

#import "IMPinnedBannerView.h"
#import "IMPinnedMessage.h"
#import "IMTheme.h"

// 卡片视觉高度 + 上方留白（横幅整体高度 = 卡片 + 顶部间隔；左右间隔由内层卡片相对 self 内缩实现）。
static CGFloat const kCardHeight = 44;
static CGFloat const kTopGap     = 8;
static CGFloat const kSideInset  = 8;

@interface IMPinnedBannerView ()
@property (nonatomic, assign) IMBannerStyle style;
@property (nonatomic, strong) UIView *card;         ///< 圆角卡片（内缩于 self，四周留间隔；承载所有内容）
@property (nonatomic, strong) UIView *bar;          ///< 左侧竖条（多条置顶时上亮下暗，暗示还有别的）
@property (nonatomic, strong) CAGradientLayer *barGradient;
@property (nonatomic, strong) UILabel *kicker;      ///< 「📌 置顶消息 2/3 · 小刚」
@property (nonatomic, strong) UILabel *preview;     ///< 单行预览
@property (nonatomic, strong) UIButton *tapButton;  ///< 覆盖主体区域的透明按钮（整条可点）
@property (nonatomic, strong) UIButton *listButton;
@property (nonatomic, strong) UIButton *closeButton; ///< 右侧 ✕：非破坏性收起本横幅
@end

@implementation IMPinnedBannerView

+ (CGFloat)bannerHeight { return kCardHeight + kTopGap; }

/// 横幅强调色：公告=系统橙（对齐 sketch 黄条），入群申请=系统蓝，置顶=主题色。
- (UIColor *)accentColor {
    if (self.style == IMBannerStyleAnnouncement) { return UIColor.systemOrangeColor; }
    if (self.style == IMBannerStyleApproval) { return UIColor.systemBlueColor; }
    return IMTheme.accent;
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
        self.backgroundColor = UIColor.clearColor; // 间隔透明，露出聊天壁纸

        // 圆角卡片：内缩于 self（顶 kTopGap、左右 kSideInset），承载全部内容。
        _card = [UIView new];
        _card.translatesAutoresizingMaskIntoConstraints = NO;
        _card.backgroundColor = IMTheme.surfaceElevated;
        _card.layer.cornerRadius = 12;
        _card.layer.cornerCurve = kCACornerCurveContinuous;
        _card.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        _card.layer.borderColor = IMTheme.separator.CGColor;
        _card.clipsToBounds = YES;
        [self addSubview:_card];

        _bar = [UIView new];
        _bar.layer.cornerRadius = 1.5;
        _bar.clipsToBounds = YES;
        _bar.translatesAutoresizingMaskIntoConstraints = NO;
        [_card addSubview:_bar];
        _barGradient = [CAGradientLayer layer];
        _barGradient.startPoint = CGPointMake(0.5, 0);
        _barGradient.endPoint = CGPointMake(0.5, 1);
        [_bar.layer addSublayer:_barGradient];

        _kicker = [UILabel new];
        _kicker.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        _kicker.textColor = IMTheme.accent;
        _kicker.translatesAutoresizingMaskIntoConstraints = NO;
        [_card addSubview:_kicker];

        _preview = [UILabel new];
        _preview.font = [UIFont systemFontOfSize:13];
        _preview.textColor = IMTheme.textPrimary;
        _preview.lineBreakMode = NSLineBreakByTruncatingTail;
        _preview.translatesAutoresizingMaskIntoConstraints = NO;
        [_card addSubview:_preview];

        _listButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_listButton setImage:[UIImage systemImageNamed:@"list.bullet"] forState:UIControlStateNormal];
        _listButton.tintColor = IMTheme.textSecondary;
        _listButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_listButton addTarget:self action:@selector(listTapped) forControlEvents:UIControlEventTouchUpInside];
        [_card addSubview:_listButton];

        // 关闭（✕）：非破坏性收起横幅（不取消置顶/不撤下公告）。恒显，固定在最右端。
        _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_closeButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
        _closeButton.tintColor = IMTheme.textSecondary;
        _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [_card addSubview:_closeButton];

        // 主体点击区：盖在文字上、让列表键/关闭键左侧的整片区域都可点（文字本身不拦触摸）。
        _tapButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _tapButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_tapButton addTarget:self action:@selector(mainTapped) forControlEvents:UIControlEventTouchUpInside];
        [_card addSubview:_tapButton];

        // 收起态把整条 height 压到 0（见 IMChatBannerStack）；card 的 top(kTopGap)+bottom 是要求约束时会与
        // height==0 直接冲突刷 "Unable to satisfy"。把 bottom 降到 999，收起时它被静默让开，展开时（height=bannerHeight）
        // 仍严格贴底，无副作用。
        NSLayoutConstraint *cardBottom = [_card.bottomAnchor constraintEqualToAnchor:self.bottomAnchor];
        cardBottom.priority = UILayoutPriorityRequired - 1;
        [NSLayoutConstraint activateConstraints:@[
            [_card.topAnchor constraintEqualToAnchor:self.topAnchor constant:kTopGap],
            [_card.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:kSideInset],
            [_card.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-kSideInset],
            cardBottom,

            [_bar.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:10],
            [_bar.centerYAnchor constraintEqualToAnchor:_card.centerYAnchor],
            [_bar.widthAnchor constraintEqualToConstant:3],
            [_bar.heightAnchor constraintEqualToConstant:26],

            // 右侧按钮簇：关闭在最右，列表键在其左（仅多条置顶时显示，隐藏时仍占位——与旧版一致）。
            [_closeButton.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-6],
            [_closeButton.centerYAnchor constraintEqualToAnchor:_card.centerYAnchor],
            [_closeButton.widthAnchor constraintEqualToConstant:30],
            [_closeButton.heightAnchor constraintEqualToConstant:30],

            [_listButton.trailingAnchor constraintEqualToAnchor:_closeButton.leadingAnchor constant:-2],
            [_listButton.centerYAnchor constraintEqualToAnchor:_card.centerYAnchor],
            [_listButton.widthAnchor constraintEqualToConstant:30],
            [_listButton.heightAnchor constraintEqualToConstant:30],

            [_kicker.leadingAnchor constraintEqualToAnchor:_bar.trailingAnchor constant:10],
            [_kicker.topAnchor constraintEqualToAnchor:_card.topAnchor constant:6],
            [_kicker.trailingAnchor constraintLessThanOrEqualToAnchor:_listButton.leadingAnchor constant:-8],

            [_preview.leadingAnchor constraintEqualToAnchor:_kicker.leadingAnchor],
            [_preview.topAnchor constraintEqualToAnchor:_kicker.bottomAnchor constant:1],
            [_preview.trailingAnchor constraintLessThanOrEqualToAnchor:_listButton.leadingAnchor constant:-8],

            [_tapButton.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor],
            [_tapButton.topAnchor constraintEqualToAnchor:_card.topAnchor],
            [_tapButton.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor],
            [_tapButton.trailingAnchor constraintEqualToAnchor:_listButton.leadingAnchor],
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.barGradient.frame = self.bar.bounds;
    // 边框色随深浅色变化（CGColor 不自动跟随 trait）。
    self.card.layer.borderColor = IMTheme.separator.CGColor;
}

/// 用 SF Symbol（染成强调色）+ 文字拼 kicker——**不用 emoji**：emoji 依赖系统字体、iOS 26 横幅内不渲染，
/// 且无法随主题/强调色染色（决策 15）。symbol 走 `NSTextAttachment`，预先 `imageWithTintColor:` 上色。
- (void)setKickerSymbol:(NSString *)symbolName text:(NSString *)text {
    UIColor *accent = [self accentColor];
    NSMutableAttributedString *s = [NSMutableAttributedString new];
    UIImage *img = [UIImage systemImageNamed:symbolName];
    if (img) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:10 weight:UIImageSymbolWeightSemibold];
        img = [[img imageByApplyingSymbolConfiguration:cfg] imageWithTintColor:accent renderingMode:UIImageRenderingModeAlwaysOriginal];
        NSTextAttachment *att = [NSTextAttachment new];
        att.image = img;
        att.bounds = CGRectMake(0, -1, img.size.width, img.size.height); // 视觉居中微调
        [s appendAttributedString:[NSAttributedString attributedStringWithAttachment:att]];
        [s appendAttributedString:[[NSAttributedString alloc] initWithString:@" "]];
    }
    [s appendAttributedString:[[NSAttributedString alloc] initWithString:(text ?: @"")
                                                             attributes:@{NSForegroundColorAttributeName: accent,
                                                                          NSFontAttributeName: self.kicker.font}]];
    self.kicker.attributedText = s;
}

- (void)applyItem:(IMPinnedMessage *)item index:(NSInteger)index total:(NSInteger)total isGroup:(BOOL)isGroup {
    if (!item) {
        self.hidden = YES;
        return;
    }
    self.hidden = NO;

    NSMutableString *kicker = [NSMutableString stringWithString:@"置顶消息"];
    if (total > 1) { [kicker appendFormat:@" %ld/%ld", (long)(index + 1), (long)total]; }
    NSString *sender = [item senderLabelForGroup:isGroup];
    if (sender.length > 0) { [kicker appendFormat:@" · %@", sender]; }
    [self setKickerSymbol:@"pin.fill" text:kicker];
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
    [self setKickerSymbol:@"megaphone" text:@"群公告"];
    // 折行/连续空白压成单行（横幅单行布局）。
    NSArray<NSString *> *parts = [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSString *part in parts) { if (part.length > 0) { [kept addObject:part]; } }
    self.preview.text = [kept componentsJoinedByString:@" "];
    self.barGradient.hidden = YES;
    self.bar.backgroundColor = [self accentColor];
    self.listButton.hidden = YES;
}

- (void)applyApprovalCount:(NSInteger)count {
    if (count <= 0) { self.hidden = YES; return; }
    self.hidden = NO;
    [self setKickerSymbol:@"person.badge.plus" text:@"入群申请"];
    self.preview.text = [NSString stringWithFormat:@"%ld 人申请加入本群 · 点击审批", (long)count];
    self.barGradient.hidden = YES;
    self.bar.backgroundColor = [self accentColor];
    self.listButton.hidden = YES;
}

- (void)mainTapped { if (self.onTap) { self.onTap(); } }
- (void)listTapped { if (self.onList) { self.onList(); } }
- (void)closeTapped { if (self.onClose) { self.onClose(); } }

@end
