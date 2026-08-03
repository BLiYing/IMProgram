//  IMPopoverCard.m
//  Telegram 式锚点上下文菜单；详情“更多”和列表“+”共用这一实现。

#import "IMPopoverCard.h"
#import "IMGlass.h"
#import "IMTheme.h"

@implementation IMPopoverCardItem
+ (instancetype)itemWithTitle:(NSString *)title symbol:(NSString *)symbol
                  destructive:(BOOL)destructive handler:(void (^)(void))handler {
    IMPopoverCardItem *it = [IMPopoverCardItem new];
    it.title = title; it.symbol = symbol; it.destructive = destructive; it.handler = handler;
    return it;
}
@end

static CGFloat const kIMContextMenuWidth = 230;
static CGFloat const kIMContextMenuRowHeight = 50;
static CGFloat const kIMContextMenuMargin = 8;

@interface IMContextMenuRow : UIControl
@property (nonatomic, strong) IMPopoverCardItem *item;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *iconView;
@end

@implementation IMContextMenuRow
- (instancetype)initWithItem:(IMPopoverCardItem *)item {
    if ((self = [super initWithFrame:CGRectZero])) {
        _item = item;
        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont systemFontOfSize:16];
        _titleLabel.text = item.title;
        _titleLabel.textColor = item.destructive ? IMTheme.danger : IMTheme.textPrimary;
        [self addSubview:_titleLabel];

        UIImageSymbolConfiguration *configuration =
            [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightRegular];
        _iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:item.symbol
                                                                  withConfiguration:configuration]];
        _iconView.contentMode = UIViewContentModeCenter;
        _iconView.tintColor = item.destructive ? IMTheme.danger : IMTheme.textPrimary;
        [self addSubview:_iconView];
        self.accessibilityLabel = item.title;
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    // 图标在左、文字在右（对齐系统长按 UIMenu 与微信式菜单）。
    self.iconView.frame = CGRectMake(16, 0, 24, self.bounds.size.height);
    CGFloat titleX = 16 + 24 + 12;
    self.titleLabel.frame = CGRectMake(titleX, 0, self.bounds.size.width - titleX - 14, self.bounds.size.height);
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor = highlighted ? [IMTheme.textPrimary colorWithAlphaComponent:0.08] : UIColor.clearColor;
}
@end

@interface IMContextMenuOverlay : UIView
@property (nonatomic, strong) UIButton *backdrop;
@property (nonatomic, strong) UIVisualEffectView *card;
@property (nonatomic, strong) NSArray<IMPopoverCardItem *> *items;
- (instancetype)initWithHost:(UIView *)host anchorRect:(CGRect)anchorRect items:(NSArray<IMPopoverCardItem *> *)items;
- (void)show;
- (void)dismissWithHandler:(nullable void (^)(void))handler;
@end

@implementation IMContextMenuOverlay
- (instancetype)initWithHost:(UIView *)host anchorRect:(CGRect)anchorRect items:(NSArray<IMPopoverCardItem *> *)items {
    if ((self = [super initWithFrame:host.bounds])) {
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _items = [items copy];

        _backdrop = [UIButton buttonWithType:UIButtonTypeCustom];
        _backdrop.frame = self.bounds;
        _backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _backdrop.backgroundColor = UIColor.clearColor;
        [_backdrop addTarget:self action:@selector(backdropTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_backdrop];

        _card = IMGlassEffectView(NO);
        _card.clipsToBounds = YES;
        _card.layer.cornerRadius = IMTheme.radiusBubble;  // 走设计令牌，不写魔法值（当前=14，与气泡同档）
        _card.layer.cornerCurve = kCACornerCurveContinuous;
        _card.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        _card.layer.borderColor = [IMTheme.separator colorWithAlphaComponent:0.55].CGColor;
        [self addSubview:_card];

        CGFloat height = kIMContextMenuRowHeight * items.count;
        UIEdgeInsets safe = host.safeAreaInsets;
        CGFloat x = MIN(CGRectGetMaxX(anchorRect) - kIMContextMenuWidth,
                        self.bounds.size.width - safe.right - kIMContextMenuMargin - kIMContextMenuWidth);
        x = MAX(safe.left + kIMContextMenuMargin, x);
        CGFloat belowY = CGRectGetMaxY(anchorRect) + 6;
        CGFloat maximumY = self.bounds.size.height - safe.bottom - kIMContextMenuMargin - height;
        CGFloat y = belowY <= maximumY ? belowY : CGRectGetMinY(anchorRect) - 6 - height;
        y = MAX(safe.top + kIMContextMenuMargin, MIN(y, maximumY));
        _card.frame = CGRectMake(x, y, kIMContextMenuWidth, height);

        [items enumerateObjectsUsingBlock:^(IMPopoverCardItem *item, NSUInteger index, BOOL *stop) {
            IMContextMenuRow *row = [[IMContextMenuRow alloc] initWithItem:item];
            row.frame = CGRectMake(0, index * kIMContextMenuRowHeight,
                                   kIMContextMenuWidth, kIMContextMenuRowHeight);
            row.tag = index;
            [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
            [self.card.contentView addSubview:row];
            if (index + 1 < items.count) {
                UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(16,
                    CGRectGetMaxY(row.frame) - 1.0 / UIScreen.mainScreen.scale,
                    kIMContextMenuWidth - 16, 1.0 / UIScreen.mainScreen.scale)];
                separator.backgroundColor = IMTheme.separator;
                [self.card.contentView addSubview:separator];
            }
        }];
    }
    return self;
}
- (void)show {
    self.backdrop.backgroundColor = UIColor.clearColor;
    self.card.alpha = 0;
    self.card.transform = CGAffineTransformMakeScale(0.88, 0.88);
    [UIView animateWithDuration:0.22 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.backdrop.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.06];
        self.card.alpha = 1;
        self.card.transform = CGAffineTransformIdentity;
    } completion:nil];
}
- (void)backdropTapped { [self dismissWithHandler:nil]; }
- (void)rowTapped:(IMContextMenuRow *)row {
    void (^handler)(void) = row.item.handler;
    [self dismissWithHandler:handler];
}
- (void)dismissWithHandler:(void (^)(void))handler {
    self.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.16 animations:^{
        self.backdrop.backgroundColor = UIColor.clearColor;
        self.card.alpha = 0;
        self.card.transform = CGAffineTransformMakeScale(0.94, 0.94);
    } completion:^(__unused BOOL finished) {
        [self removeFromSuperview];
        if (handler) { handler(); }
    }];
}
@end

@implementation IMPopoverCard

+ (BOOL)isPresentingInHostView:(UIView *)host {
    for (UIView *view in host.subviews) {
        if ([view isKindOfClass:IMContextMenuOverlay.class]) { return YES; }
    }
    return NO;
}

+ (void)presentFromAnchor:(UIView *)anchor inHostView:(UIView *)host items:(NSArray<IMPopoverCardItem *> *)items {
    if (items.count == 0 || !anchor || !host || [self isPresentingInHostView:host]) { return; }
    CGRect anchorRect = [anchor convertRect:anchor.bounds toView:host];
    IMContextMenuOverlay *overlay = [[IMContextMenuOverlay alloc] initWithHost:host anchorRect:anchorRect items:items];
    [host addSubview:overlay];
    [overlay show];
}

+ (void)presentFromBarButtonItem:(UIBarButtonItem *)barButtonItem
                      inHostView:(UIView *)host
                           items:(NSArray<IMPopoverCardItem *> *)items {
    if (items.count == 0 || !barButtonItem || !host || [self isPresentingInHostView:host]) { return; }
    CGFloat anchorY = MAX(kIMContextMenuMargin, host.safeAreaInsets.top - 50);
    CGRect anchorRect = CGRectMake(host.bounds.size.width - host.safeAreaInsets.right - 60,
                                   anchorY, 44, 44);
    IMContextMenuOverlay *overlay = [[IMContextMenuOverlay alloc] initWithHost:host anchorRect:anchorRect items:items];
    [host addSubview:overlay];
    [overlay show];
}

@end
