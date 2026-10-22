//  IMActionListSheet.m

#import "IMActionListSheet.h"
#import "IMTheme.h"
#import "IMLocalization.h"

static const CGFloat kRowH = 56;
static const CGFloat kTitleH = 44;
static const CGFloat kSideMargin = 10;
static const CGFloat kRadius = 20;
static const NSInteger kCheckTag = 0x4348;
static const CGFloat kMaxListFraction = 0.6; ///< 选项区最高占屏高比例，超出滚动

@implementation IMActionListItem
+ (instancetype)itemWithTitle:(NSString *)title destructive:(BOOL)destructive handler:(void (^)(void))handler {
    IMActionListItem *it = [IMActionListItem new];
    it.title = title; it.destructive = destructive; it.handler = handler;
    return it;
}
+ (instancetype)itemWithTitle:(NSString *)title selected:(BOOL)selected handler:(void (^)(void))handler {
    IMActionListItem *it = [self itemWithTitle:title destructive:NO handler:handler];
    it.selected = selected;
    return it;
}
@end

@implementation IMActionListSheet {
    UIScrollView *_scroll;
    NSString *_sheetTitle;
    NSArray<IMActionListItem *> *_items;
    UIView *_dim;
    UIView *_card;
    NSLayoutConstraint *_cardBottom;
}

+ (void)presentFrom:(UIViewController *)host title:(NSString *)title items:(NSArray<IMActionListItem *> *)items {
    if (!host) { return; }
    IMActionListSheet *vc = [IMActionListSheet new];
    vc->_sheetTitle = [title copy];
    vc->_items = [items copy];
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    vc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve; // 遮罩淡入；卡片自己上滑
    [host presentViewController:vc animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    _dim = [UIView new];
    _dim.translatesAutoresizingMaskIntoConstraints = NO;
    _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    [_dim addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cancelTapped)]];
    [self.view addSubview:_dim];

    _card = [UIView new];
    _card.translatesAutoresizingMaskIntoConstraints = NO;
    _card.backgroundColor = IMTheme.surface;
    _card.layer.cornerRadius = kRadius;
    _card.clipsToBounds = YES;
    [self.view addSubview:_card];

    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:stack];

    if (_sheetTitle.length > 0) {
        UILabel *t = [UILabel new];
        t.text = _sheetTitle;
        t.font = [UIFont systemFontOfSize:13];
        t.textColor = IMTheme.textSecondary;
        t.textAlignment = NSTextAlignmentCenter;
        [t.heightAnchor constraintEqualToConstant:kTitleH].active = YES;
        [stack addArrangedSubview:t];
    }
    [stack addArrangedSubview:[self scrollableItemList]];
    // 与 self.view 比高必须等 _scroll 入层级（卡片 -> stack）后才能激活，否则 "no common ancestor" 直接抛异常
    [_scroll.heightAnchor constraintLessThanOrEqualToAnchor:self.view.heightAnchor multiplier:kMaxListFraction].active = YES;
    [stack addArrangedSubview:[self rowWithTitle:IMLocalized(@"common.cancel") destructive:NO selected:NO tag:-1]];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    _cardBottom = [_card.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:0];
    [NSLayoutConstraint activateConstraints:@[
        [_dim.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_dim.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_dim.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_dim.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:kSideMargin],
        [_card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-kSideMargin],
        _cardBottom,
        [stack.topAnchor constraintEqualToAnchor:_card.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor],
    ]];
}

/// 选项区：行叠在 scrollView 里；高度 = 内容高，但不超过屏高 * kMaxListFraction（短列表如免打扰 5 行不滚）。
- (UIScrollView *)scrollableItemList {
    _scroll = [UIScrollView new];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    UIStackView *rows = [UIStackView new];
    rows.axis = UILayoutConstraintAxisVertical;
    rows.translatesAutoresizingMaskIntoConstraints = NO;
    [_scroll addSubview:rows];
    for (NSUInteger i = 0; i < _items.count; i++) {
        IMActionListItem *it = _items[i];
        [rows addArrangedSubview:[self rowWithTitle:it.title destructive:it.destructive selected:it.selected tag:(NSInteger)i]];
    }
    NSLayoutConstraint *fit = [_scroll.heightAnchor constraintEqualToAnchor:rows.heightAnchor];
    fit.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [rows.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor],
        [rows.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor],
        [rows.leadingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.leadingAnchor],
        [rows.trailingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.trailingAnchor],
        [rows.widthAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.widthAnchor],
        fit,
    ]];
    return _scroll;
}

- (void)scrollToSelectedRow {
    for (NSUInteger i = 0; i < _items.count; i++) {
        if (!_items[i].selected) { continue; }
        CGFloat y = i * kRowH - (_scroll.bounds.size.height - kRowH) / 2;
        CGFloat maxY = MAX(0, _scroll.contentSize.height - _scroll.bounds.size.height);
        _scroll.contentOffset = CGPointMake(0, MIN(MAX(0, y), maxY));
        return;
    }
}

- (UIView *)rowWithTitle:(NSString *)title destructive:(BOOL)destructive selected:(BOOL)selected tag:(NSInteger)tag {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = tag;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:(destructive ? IMTheme.danger : IMTheme.textPrimary) forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:17];
    [b setBackgroundImage:[self pixel:[IMTheme.separator colorWithAlphaComponent:0.35]] forState:UIControlStateHighlighted];
    [b.heightAnchor constraintEqualToConstant:kRowH].active = YES;
    [b addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    UIView *line = [UIView new];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.backgroundColor = IMTheme.separator;
    [b addSubview:line];
    [NSLayoutConstraint activateConstraints:@[
        [line.topAnchor constraintEqualToAnchor:b.topAnchor],
        [line.leadingAnchor constraintEqualToAnchor:b.leadingAnchor],
        [line.trailingAnchor constraintEqualToAnchor:b.trailingAnchor],
        [line.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    ]];
    if (selected) {
        UILabel *check = [UILabel new];
        check.translatesAutoresizingMaskIntoConstraints = NO;
        check.text = @"✓";
        check.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        check.tag = kCheckTag;
        check.textColor = b.tintColor; // 构建时还没入窗，取到的是系统默认蓝；viewWillAppear 里按窗口 tint 重取
        check.isAccessibilityElement = NO;
        [b addSubview:check];
        [NSLayoutConstraint activateConstraints:@[
            [check.trailingAnchor constraintEqualToAnchor:b.trailingAnchor constant:-20],
            [check.centerYAnchor constraintEqualToAnchor:b.centerYAnchor],
        ]];
        b.accessibilityTraits |= UIAccessibilityTraitSelected;
    }
    return b;
}

- (UIImage *)pixel:(UIColor *)c {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1, 1)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) { [c setFill]; [ctx fillRect:CGRectMake(0, 0, 1, 1)]; }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 卡片先放到屏幕下方，再随转场上滑进来。
    [self.view layoutIfNeeded];
    // viewWillAppear 时 overFullScreen 的 view 还没挂进窗口（自身 tintColor 仍是系统默认蓝），故取 presenting 的 tint（= 窗口 tint，与列表页系统 ✓ 同色）
    UIColor *tint = self.presentingViewController.view.tintColor ?: self.view.tintColor;
    for (UIView *v in _scroll.subviews.firstObject.subviews) { // 重取 ✓ 色
        UILabel *l = (UILabel *)[v viewWithTag:kCheckTag];
        if ([l isKindOfClass:UILabel.class]) { l.textColor = tint; }
    }
    [self scrollToSelectedRow];
    _cardBottom.constant = _card.bounds.size.height + 40;
    [self.view layoutIfNeeded];
    _cardBottom.constant = 0;
    [UIView animateWithDuration:0.28 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        [self.view layoutIfNeeded];
    } completion:nil];
}

- (void)dismissThen:(void (^)(void))after {
    _cardBottom.constant = _card.bounds.size.height + 40;
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        [self.view layoutIfNeeded];
    } completion:nil];
    [self dismissViewControllerAnimated:YES completion:after];
}

- (void)cancelTapped { [self dismissThen:nil]; }

- (void)rowTapped:(UIButton *)b {
    if (b.tag < 0 || (NSUInteger)b.tag >= _items.count) { [self cancelTapped]; return; }
    void (^h)(void) = _items[(NSUInteger)b.tag].handler;
    [self dismissThen:h];
}

@end
