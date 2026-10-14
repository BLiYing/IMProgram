//  IMLiquidSegmentedControl.m

#import "IMLiquidSegmentedControl.h"
#import "IMGlass.h"
#import "IMTheme.h"

/// 段内文字左右留白（设计稿里各段间距较宽松）。
static CGFloat const kSegHPadding = 18;
/// 单段最小宽度，避免「文件」这类两字标题点击区过窄。
static CGFloat const kSegMinWidth = 56;
static CGFloat const kSegDefaultHeight = 40;
/// 角标：高 20、圆角 10、文字左右各 6（同会话行角标 kIM 规格，设计稿 §4.2）；与标题间距 5。
static CGFloat const kSegBadgeHeight = 20;
static CGFloat const kSegBadgeHPadding = 6;
static CGFloat const kSegBadgeMinWidth = 20;
static CGFloat const kSegBadgeGap = 5;

@interface IMLiquidSegmentedControl ()
@property (nonatomic, strong) UIVisualEffectView *track;
@property (nonatomic, strong) UIScrollView *scroll;   ///< 段容器：段总宽超出控件时横向滚动（见 layoutSubviews）
@property (nonatomic, strong) UIView *pill;
@property (nonatomic, strong) NSMutableArray<UIButton *> *buttons;
@property (nonatomic, strong) NSMutableArray<UILabel *> *titleLabels;  ///< 与 buttons 一一对应：自绘标题（让角标能与文字一起居中）
@property (nonatomic, strong) NSMutableArray<UILabel *> *badgeLabels;  ///< 与 buttons 一一对应：未读角标（无文案时隐藏）
@property (nonatomic, copy) NSArray<NSString *> *badgeTexts;
@property (nonatomic, copy) NSArray<NSNumber *> *badgeMuted;
@end

@implementation IMLiquidSegmentedControl

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _pillInset = 4;
        _selectedIndex = 0;
        _titles = @[];
        _buttons = [NSMutableArray array];
        _titleLabels = [NSMutableArray array];
        _badgeLabels = [NSMutableArray array];
        _badgeTexts = @[];
        _badgeMuted = @[];

        // 底轨：非 interactive 玻璃（跟手高光留给药丸，否则整条轨都会发亮）。
        // ⚠️ 这里**不能**设 userInteractionEnabled = NO：段按钮就挂在 track.contentView 上，
        // 关掉会连同子视图一起被 hit-test 排除，整排 tab 直接点不动。
        // 「不跟手发亮」由 effect 的 interactive 参数决定，与是否接收触摸无关。
        _track = IMGlassEffectView(NO);
        [self addSubview:_track];

        // 段容器：段总宽 > 控件宽时横向滚动。**必须有**——底轨 clipsToBounds=YES，没有滚动容器时
        // 排在后面的段（详情页 6 签的「名片」/收藏页 7 签的「名片」）被直接裁掉且无从划到，
        // 用户看到的就是"最后一个 tab 看不全 / 根本不存在"。段总宽够放时 scrollEnabled=NO，
        // 手势不参与竞争，行为与加滚动前完全一致。
        _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
        _scroll.showsHorizontalScrollIndicator = NO;
        _scroll.showsVerticalScrollIndicator = NO;
        _scroll.alwaysBounceVertical = NO;
        _scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        [_track.contentView addSubview:_scroll];

        // 药丸：iOS 26 用可交互玻璃（跟手高光，与底部 TabBar 选中态同源）；旧系统降级为半透明填充。
        if (@available(iOS 26.0, *)) {
            _pill = IMGlassEffectView(YES);
        } else {
            _pill = [[UIView alloc] initWithFrame:CGRectZero];
            _pill.backgroundColor = UIColor.tertiarySystemFillColor;
        }
        _pill.userInteractionEnabled = NO;
        [_scroll addSubview:_pill];
    }
    return self;
}

#pragma mark - 内容

- (void)setTitles:(NSArray<NSString *> *)titles {
    _titles = [titles copy] ?: @[];
    for (UIButton *b in self.buttons) { [b removeFromSuperview]; }
    for (UILabel *l in self.titleLabels) { [l removeFromSuperview]; }
    for (UILabel *l in self.badgeLabels) { [l removeFromSuperview]; }
    [self.buttons removeAllObjects];
    [self.titleLabels removeAllObjects];
    [self.badgeLabels removeAllObjects];

    [_titles enumerateObjectsUsingBlock:^(NSString *t, NSUInteger i, BOOL *stop) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = (NSInteger)i;
        [b addTarget:self action:@selector(segmentTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.scroll addSubview:b];
        [self.buttons addObject:b];

        // 标题 / 角标是 button 之上的自绘 label（不吃触摸，点击落在 button 上）：自绘才能让「文字 + 角标」
        // 作为整体居中，而 UIButton 的 title 只能整体居中、不会给右侧角标让位。恒在药丸之上，文字不被玻璃盖住。
        UILabel *tl = [UILabel new];
        tl.text = t;
        tl.textColor = UIColor.labelColor;
        tl.userInteractionEnabled = NO;
        [self.scroll addSubview:tl];
        [self.titleLabels addObject:tl];

        UILabel *bl = [UILabel new];
        bl.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        bl.textColor = UIColor.whiteColor;
        bl.textAlignment = NSTextAlignmentCenter;
        bl.layer.cornerRadius = kSegBadgeHeight / 2;
        bl.layer.masksToBounds = YES;
        bl.userInteractionEnabled = NO;
        bl.hidden = YES;
        [self.scroll addSubview:bl];
        [self.badgeLabels addObject:bl];
    }];

    if (_selectedIndex >= (NSInteger)_titles.count) { _selectedIndex = 0; }
    [self applyFonts];
    [self applyBadges];
    [self setNeedsLayout];
}

- (void)setBadgeTexts:(NSArray<NSString *> *)texts muted:(NSArray<NSNumber *> *)muted {
    NSArray *newTexts = [texts copy] ?: @[];
    NSArray *newMuted = [muted copy] ?: @[];
    if ([newTexts isEqualToArray:_badgeTexts] && [newMuted isEqualToArray:_badgeMuted]) { return; }
    _badgeTexts = newTexts;
    _badgeMuted = newMuted;
    [self applyBadges];
    [self setNeedsLayout];
}

- (void)applyBadges {
    [self.badgeLabels enumerateObjectsUsingBlock:^(UILabel *bl, NSUInteger i, BOOL *stop) {
        NSString *text = i < self.badgeTexts.count ? self.badgeTexts[i] : @"";
        BOOL muted = i < self.badgeMuted.count && self.badgeMuted[i].boolValue;
        bl.text = text;
        bl.hidden = text.length == 0;
        bl.backgroundColor = muted ? UIColor.systemGrayColor : IMTheme.unreadBadge; // 同会话行角标：蓝=有提醒，灰=静音
    }];
    [self.buttons enumerateObjectsUsingBlock:^(UIButton *b, NSUInteger i, BOOL *stop) {
        NSString *text = i < self.badgeTexts.count ? self.badgeTexts[i] : @"";
        NSString *title = i < self.titles.count ? self.titles[i] : @"";
        b.accessibilityLabel = text.length > 0 ? [NSString stringWithFormat:@"%@ %@", title, text] : title;
    }];
}

- (void)segmentTapped:(UIButton *)sender {
    if (sender.tag == self.selectedIndex) { return; }
    [self setSelectedIndex:sender.tag animated:YES];
    [self sendActionsForControlEvents:UIControlEventValueChanged]; // 仅用户点击才发
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    [self setSelectedIndex:selectedIndex animated:NO];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex animated:(BOOL)animated {
    NSInteger count = (NSInteger)self.titles.count;
    NSInteger clamped = count == 0 ? 0 : MAX(0, MIN(selectedIndex, count - 1));
    if (clamped == _selectedIndex && self.pill.frame.size.width > 0) { return; }
    _selectedIndex = clamped;
    [self applyFonts];
    if (!animated) {
        [self layoutPill];
        [self scrollSelectedToVisibleAnimated:NO];
        return;
    }
    [self scrollSelectedToVisibleAnimated:YES];
    // 与系统玻璃控件同调性的轻弹簧；只动药丸，文字字重直接切换（避免中途糊字）。
    [UIView animateWithDuration:0.32 delay:0
         usingSpringWithDamping:0.86 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionAllowUserInteraction
                     animations:^{ [self layoutPill]; }
                     completion:nil];
}

/// 选中/未选中同为主文字色，仅以字重区分（对齐设计稿：未选中并非灰字）。
- (void)applyFonts {
    [self.buttons enumerateObjectsUsingBlock:^(UIButton *b, NSUInteger i, BOOL *stop) {
        BOOL on = ((NSInteger)i == self.selectedIndex);
        if (i < self.titleLabels.count) {
            self.titleLabels[i].font = [UIFont systemFontOfSize:15 weight:on ? UIFontWeightSemibold : UIFontWeightMedium];
        }
        b.accessibilityTraits = on ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected)
                                   : UIAccessibilityTraitButton;
    }];
    [self applyBadges]; // 辅助功能标签随标题一起维护
}

#pragma mark - 布局

/// 角标宽度（无角标 = 0）。
- (CGFloat)badgeWidthAtIndex:(NSUInteger)i {
    NSString *text = i < self.badgeTexts.count ? self.badgeTexts[i] : @"";
    if (text.length == 0) { return 0; }
    CGFloat tw = [text sizeWithAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold]}].width;
    return MAX(kSegBadgeMinWidth, ceil(tw) + 2 * kSegBadgeHPadding);
}

/// 标题文字宽度。
- (CGFloat)titleWidthAtIndex:(NSUInteger)i {
    if (i >= self.titleLabels.count) { return 0; }
    UILabel *l = self.titleLabels[i];
    UIFont *font = l.font ?: [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    return ceil([l.text ?: @"" sizeWithAttributes:@{NSFontAttributeName: font}].width);
}

/// 段宽 = 标题宽 +（角标宽 + 间距）+ 左右留白（下限 kSegMinWidth）。**不再均分富余宽度**：
/// 控件被页面拉宽时底轨贴合内容、居中（见 layoutSubviews），Tab 少时不会各占半屏。
- (NSArray<NSNumber *> *)segmentWidths {
    NSMutableArray<NSNumber *> *ws = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.buttons.count; i++) {
        CGFloat bw = [self badgeWidthAtIndex:i];
        CGFloat content = [self titleWidthAtIndex:i] + (bw > 0 ? kSegBadgeGap + bw : 0);
        [ws addObject:@(MAX(kSegMinWidth, content + 2 * kSegHPadding))];
    }
    return ws;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    NSArray<NSNumber *> *ws = [self segmentWidths];
    CGFloat total = 0;
    for (NSNumber *n in ws) { total += n.doubleValue; }
    CGFloat avail = CGRectGetWidth(self.bounds);
    CGFloat trackW = MIN(total, avail);
    self.track.frame = CGRectMake(floor((avail - trackW) / 2), 0, trackW, CGRectGetHeight(self.bounds));
    self.track.layer.cornerRadius = CGRectGetHeight(self.bounds) / 2;
    self.track.clipsToBounds = YES;
    self.scroll.frame = CGRectMake(0, 0, trackW, CGRectGetHeight(self.bounds)); // 与底轨等尺寸（contentView 的 bounds 本轮可能还没解算）

    CGFloat h = CGRectGetHeight(self.bounds);
    CGFloat x = 0; // 药丸的四周留白由 layoutPill 的 CGRectInset 给，段本身紧贴底轨
    for (NSUInteger i = 0; i < self.buttons.count && i < ws.count; i++) {
        CGFloat w = ws[i].doubleValue;
        self.buttons[i].frame = CGRectMake(x, 0, w, h);
        // 「标题 + 角标」整体在段内居中。
        CGFloat bw = [self badgeWidthAtIndex:i];
        CGFloat tw = [self titleWidthAtIndex:i];
        CGFloat content = tw + (bw > 0 ? kSegBadgeGap + bw : 0);
        CGFloat left = x + (w - content) / 2;
        self.titleLabels[i].frame = CGRectMake(left, 0, tw, h);
        self.badgeLabels[i].frame = CGRectMake(left + tw + kSegBadgeGap, (h - kSegBadgeHeight) / 2, bw, kSegBadgeHeight);
        x += w;
    }
    CGFloat contentW = x;
    // 段总宽：塞得下就锁死滚动（手势不参与竞争）；塞不下才允许横划露出后面的签。
    self.scroll.contentSize = CGSizeMake(MAX(contentW, trackW), h);
    self.scroll.scrollEnabled = contentW > trackW + 0.5;
    if (!self.scroll.scrollEnabled && self.scroll.contentOffset.x != 0) { self.scroll.contentOffset = CGPointZero; }
    [self layoutPill];
    [self scrollSelectedToVisibleAnimated:NO];
}

/// 把当前选中段滚进可视区（程序化换签 / 首次布局都要——否则选中了却看不见药丸）。
- (void)scrollSelectedToVisibleAnimated:(BOOL)animated {
    if (!self.scroll.scrollEnabled) { return; }
    if (self.selectedIndex < 0 || self.selectedIndex >= (NSInteger)self.buttons.count) { return; }
    CGRect f = self.buttons[(NSUInteger)self.selectedIndex].frame;
    [self.scroll scrollRectToVisible:CGRectInset(f, -self.pillInset, 0) animated:animated];
}

- (NSInteger)segmentIndexAtPoint:(CGPoint)point {
    CGPoint inScroll = [self.scroll convertPoint:point fromView:self];
    for (NSUInteger i = 0; i < self.buttons.count; i++) {
        if (CGRectContainsPoint(self.buttons[i].frame, inScroll)) { return (NSInteger)i; }
    }
    return NSNotFound;
}

- (void)layoutPill {
    if (self.selectedIndex >= (NSInteger)self.buttons.count) { self.pill.hidden = YES; return; }
    self.pill.hidden = NO;
    CGRect f = CGRectInset(self.buttons[self.selectedIndex].frame, self.pillInset, self.pillInset);
    self.pill.frame = f;
    self.pill.layer.cornerRadius = CGRectGetHeight(f) / 2; // 恒为药丸，不会被切成方角
    self.pill.clipsToBounds = YES;
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGFloat h = size.height > 0 ? size.height : kSegDefaultHeight;
    CGFloat total = 0;
    for (NSNumber *n in [self segmentWidths]) { total += n.doubleValue; }
    return CGSizeMake(total, h);
}

@end
