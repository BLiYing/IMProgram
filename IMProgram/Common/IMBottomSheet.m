//  IMBottomSheet.m

#import "IMBottomSheet.h"

@implementation IMBottomSheetItem
+ (instancetype)itemWithTitle:(NSString *)title symbol:(NSString *)symbol handler:(dispatch_block_t)handler {
    IMBottomSheetItem *it = [IMBottomSheetItem new];
    it.title = title; it.symbol = symbol; it.handler = handler;
    return it;
}
@end

/// 私有容器视图：持有 items，负责蒙层/面板布局与消失动画。
@interface IMBottomSheetView : UIView
- (instancetype)initWithItems:(NSArray<IMBottomSheetItem *> *)items;
- (void)presentIn:(UIView *)host;
@end

@implementation IMBottomSheetView {
    NSArray<IMBottomSheetItem *> *_items;
    UIView *_panel;
}

- (instancetype)initWithItems:(NSArray<IMBottomSheetItem *> *)items {
    if ((self = [super initWithFrame:CGRectZero])) {
        _items = items;
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35]; // 蒙层
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissSheet)]];

        _panel = [UIView new];
        _panel.translatesAutoresizingMaskIntoConstraints = NO;
        _panel.backgroundColor = UIColor.secondarySystemBackgroundColor;
        _panel.layer.cornerRadius = 14;
        _panel.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        [self addSubview:_panel];

        // 图文按钮横排（个数少，单行均分即可；超 5 个自动换行用两行网格）。
        NSMutableArray<UIView *> *buttons = [NSMutableArray array];
        for (NSUInteger i = 0; i < items.count; i++) {
            [buttons addObject:[self itemButtonAt:i]];
        }
        UIStackView *rows = [UIStackView new];
        rows.axis = UILayoutConstraintAxisVertical;
        rows.spacing = 12;
        rows.translatesAutoresizingMaskIntoConstraints = NO;
        NSUInteger perRow = items.count > 5 ? (items.count + 1) / 2 : items.count;
        UIStackView *cur = nil;
        for (NSUInteger i = 0; i < buttons.count; i++) {
            if (i % perRow == 0) {
                cur = [UIStackView new];
                cur.axis = UILayoutConstraintAxisHorizontal;
                cur.distribution = UIStackViewDistributionFillEqually;
                cur.spacing = 8;
                [rows addArrangedSubview:cur];
            }
            [cur addArrangedSubview:buttons[i]];
        }
        // 末行不满时补空视图占位，保持等宽。
        while (cur && cur.arrangedSubviews.count < perRow) { [cur addArrangedSubview:[UIView new]]; }
        [_panel addSubview:rows];

        UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
        cancel.translatesAutoresizingMaskIntoConstraints = NO;
        [cancel setTitle:@"取消" forState:UIControlStateNormal];
        cancel.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        [cancel setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
        cancel.backgroundColor = UIColor.systemBackgroundColor;
        cancel.layer.cornerRadius = 10;
        [cancel addTarget:self action:@selector(dismissSheet) forControlEvents:UIControlEventTouchUpInside];
        [_panel addSubview:cancel];

        [NSLayoutConstraint activateConstraints:@[
            [_panel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_panel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_panel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [rows.topAnchor constraintEqualToAnchor:_panel.topAnchor constant:20],
            [rows.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor constant:16],
            [rows.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor constant:-16],
            [cancel.topAnchor constraintEqualToAnchor:rows.bottomAnchor constant:16],
            [cancel.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor constant:16],
            [cancel.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor constant:-16],
            [cancel.heightAnchor constraintEqualToConstant:48],
            [cancel.bottomAnchor constraintEqualToAnchor:_panel.safeAreaLayoutGuide.bottomAnchor constant:-10],
        ]];
    }
    return self;
}

- (UIView *)itemButtonAt:(NSUInteger)idx {
    IMBottomSheetItem *it = _items[idx];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
    cfg.image = [UIImage systemImageNamed:it.symbol
                        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular]];
    cfg.title = it.title;
    cfg.imagePlacement = NSDirectionalRectEdgeTop;
    cfg.imagePadding = 6;
    cfg.baseForegroundColor = UIColor.labelColor;
    UIFont *f = [UIFont systemFontOfSize:12];
    cfg.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attrs) {
        NSMutableDictionary *m = [attrs mutableCopy];
        m[NSFontAttributeName] = f;
        return m;
    };
    b.configuration = cfg;
    b.tag = (NSInteger)idx;
    [b addTarget:self action:@selector(itemTapped:) forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)itemTapped:(UIButton *)sender {
    dispatch_block_t handler = nil;
    if (sender.tag >= 0 && sender.tag < (NSInteger)_items.count) { handler = _items[(NSUInteger)sender.tag].handler; }
    [self dismissThen:handler];
}

- (void)dismissSheet { [self dismissThen:nil]; }

- (void)dismissThen:(dispatch_block_t)then {
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0;
        self->_panel.transform = CGAffineTransformMakeTranslation(0, self->_panel.bounds.size.height);
    } completion:^(BOOL done) {
        [self removeFromSuperview];
        if (then) { then(); }
    }];
}

- (void)presentIn:(UIView *)host {
    self.frame = host.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host addSubview:self];
    [self layoutIfNeeded];
    self.alpha = 0;
    _panel.transform = CGAffineTransformMakeTranslation(0, _panel.bounds.size.height ?: 200);
    [UIView animateWithDuration:0.22 animations:^{
        self.alpha = 1;
        self->_panel.transform = CGAffineTransformIdentity;
    }];
}

@end

@implementation IMBottomSheet

+ (void)showInView:(UIView *)host items:(NSArray<IMBottomSheetItem *> *)items {
    if (!host || items.count == 0) { return; }
    IMBottomSheetView *v = [[IMBottomSheetView alloc] initWithItems:items];
    [v presentIn:host];
}

@end
