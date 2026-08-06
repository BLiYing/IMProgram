//  IMLiquidSegmentedControl.m

#import "IMLiquidSegmentedControl.h"
#import "IMGlass.h"

/// 段内文字左右留白（设计稿里各段间距较宽松）。
static CGFloat const kSegHPadding = 18;
/// 单段最小宽度，避免「文件」这类两字标题点击区过窄。
static CGFloat const kSegMinWidth = 56;
static CGFloat const kSegDefaultHeight = 40;

@interface IMLiquidSegmentedControl ()
@property (nonatomic, strong) UIVisualEffectView *track;
@property (nonatomic, strong) UIView *pill;
@property (nonatomic, strong) NSMutableArray<UIButton *> *buttons;
@end

@implementation IMLiquidSegmentedControl

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _pillInset = 4;
        _selectedIndex = 0;
        _titles = @[];
        _buttons = [NSMutableArray array];

        // 底轨：非 interactive 玻璃（跟手高光留给药丸，否则整条轨都会发亮）。
        // ⚠️ 这里**不能**设 userInteractionEnabled = NO：段按钮就挂在 track.contentView 上，
        // 关掉会连同子视图一起被 hit-test 排除，整排 tab 直接点不动。
        // 「不跟手发亮」由 effect 的 interactive 参数决定，与是否接收触摸无关。
        _track = IMGlassEffectView(NO);
        [self addSubview:_track];

        // 药丸：iOS 26 用可交互玻璃（跟手高光，与底部 TabBar 选中态同源）；旧系统降级为半透明填充。
        if (@available(iOS 26.0, *)) {
            _pill = IMGlassEffectView(YES);
        } else {
            _pill = [[UIView alloc] initWithFrame:CGRectZero];
            _pill.backgroundColor = UIColor.tertiarySystemFillColor;
        }
        _pill.userInteractionEnabled = NO;
        [_track.contentView addSubview:_pill];
    }
    return self;
}

#pragma mark - 内容

- (void)setTitles:(NSArray<NSString *> *)titles {
    _titles = [titles copy] ?: @[];
    for (UIButton *b in self.buttons) { [b removeFromSuperview]; }
    [self.buttons removeAllObjects];

    [_titles enumerateObjectsUsingBlock:^(NSString *t, NSUInteger i, BOOL *stop) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        [b setTitle:t forState:UIControlStateNormal];
        [b setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
        b.tag = (NSInteger)i;
        [b addTarget:self action:@selector(segmentTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.track.contentView addSubview:b]; // 恒在药丸之上，文字不被玻璃盖住
        [self.buttons addObject:b];
    }];

    if (_selectedIndex >= (NSInteger)_titles.count) { _selectedIndex = 0; }
    [self applyFonts];
    [self setNeedsLayout];
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
        return;
    }
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
        b.titleLabel.font = [UIFont systemFontOfSize:15
                                              weight:on ? UIFontWeightSemibold : UIFontWeightMedium];
        b.accessibilityTraits = on ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected)
                                   : UIAccessibilityTraitButton;
    }];
}

#pragma mark - 布局

/// 段宽 = 文字宽 + 左右留白（下限 kSegMinWidth）；控件被拉宽时富余量在各段间**均分**，
/// 使标题整体铺开而不是挤在左侧。
- (NSArray<NSNumber *> *)segmentWidthsForWidth:(CGFloat)width {
    NSMutableArray<NSNumber *> *ws = [NSMutableArray array];
    CGFloat total = 0;
    for (UIButton *b in self.buttons) {
        CGFloat t = [b.titleLabel.text ?: @"" sizeWithAttributes:@{NSFontAttributeName: b.titleLabel.font ?:
                     [UIFont systemFontOfSize:15 weight:UIFontWeightMedium]}].width;
        CGFloat w = MAX(kSegMinWidth, ceil(t) + 2 * kSegHPadding);
        [ws addObject:@(w)];
        total += w;
    }
    if (ws.count == 0) { return ws; }
    CGFloat slack = width - total;
    if (slack > 0) {
        CGFloat add = slack / (CGFloat)ws.count;
        for (NSUInteger i = 0; i < ws.count; i++) { ws[i] = @(ws[i].doubleValue + add); }
    }
    return ws;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.track.frame = self.bounds;
    self.track.layer.cornerRadius = CGRectGetHeight(self.bounds) / 2;
    self.track.clipsToBounds = YES;

    NSArray<NSNumber *> *ws = [self segmentWidthsForWidth:CGRectGetWidth(self.bounds)];
    CGFloat x = 0;
    for (NSUInteger i = 0; i < self.buttons.count && i < ws.count; i++) {
        CGFloat w = ws[i].doubleValue;
        self.buttons[i].frame = CGRectMake(x, 0, w, CGRectGetHeight(self.bounds));
        x += w;
    }
    [self layoutPill];
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
    for (NSNumber *n in [self segmentWidthsForWidth:0]) { total += n.doubleValue; }
    return CGSizeMake(total, h);
}

@end
