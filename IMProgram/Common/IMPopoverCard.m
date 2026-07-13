//  IMPopoverCard.m

#import "IMPopoverCard.h"
#import "IMTheme.h"

@implementation IMPopoverCardItem
+ (instancetype)itemWithTitle:(NSString *)title symbol:(NSString *)symbol
                  destructive:(BOOL)destructive handler:(void (^)(void))handler {
    IMPopoverCardItem *it = [IMPopoverCardItem new];
    it.title = title; it.symbol = symbol; it.destructive = destructive; it.handler = handler;
    return it;
}
@end

@implementation IMPopoverCard

+ (void)presentFromAnchor:(UIView *)anchor inHostView:(UIView *)host items:(NSArray<IMPopoverCardItem *> *)items {
    if (items.count == 0 || !anchor || !host) { return; }

    // dim 覆盖层：捕获点击关闭（几乎透明，像原生下拉菜单）。
    UIView *dim = [[UIView alloc] initWithFrame:host.bounds];
    dim.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.001];
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host addSubview:dim];

    CGFloat cardW = 232, rowH = 48;
    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial]];
    card.layer.cornerRadius = 13; card.layer.masksToBounds = YES;
    card.layer.cornerCurve = kCACornerCurveContinuous;   // 与系统卡片/全局圆角一致（连续圆角）
    card.layer.borderWidth = 0.5;
    card.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.4].CGColor;

    CGRect ar = [anchor convertRect:anchor.bounds toView:host];
    CGFloat x = MIN(CGRectGetMaxX(ar) - cardW, host.bounds.size.width - cardW - 8);
    x = MAX(8, x);
    CGFloat y = CGRectGetMaxY(ar) + 6;                   // 锚按钮正下方
    card.frame = CGRectMake(x, y, cardW, rowH * items.count);
    [dim addSubview:card];

    void (^dismiss)(void) = ^{
        [UIView animateWithDuration:0.16 animations:^{
            card.alpha = 0; card.transform = CGAffineTransformMakeScale(0.85, 0.85); dim.alpha = 0;
        } completion:^(BOOL f) { [dim removeFromSuperview]; }];
    };
    // 点 dim 空白处关闭（用一个隐藏按钮铺满，避免 target 生命周期问题）。
    UIButton *catcher = [UIButton buttonWithType:UIButtonTypeCustom];
    catcher.frame = dim.bounds;
    catcher.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [catcher addAction:[UIAction actionWithHandler:^(UIAction *a) { dismiss(); }] forControlEvents:UIControlEventTouchUpInside];
    [dim insertSubview:catcher belowSubview:card];

    [items enumerateObjectsUsingBlock:^(IMPopoverCardItem *it, NSUInteger i, BOOL *stop) {
        UIColor *tint = it.destructive ? UIColor.systemRedColor : IMTheme.textPrimary;
        UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
        row.frame = CGRectMake(0, i * rowH, cardW, rowH);
        UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, cardW - 60, rowH)];
        tl.text = it.title; tl.textColor = tint; tl.font = [UIFont systemFontOfSize:15.5];
        [row addSubview:tl];
        UIImageView *ic = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:it.symbol]];
        ic.tintColor = tint; ic.frame = CGRectMake(cardW - 42, (rowH - 22) / 2, 22, 22);
        ic.contentMode = UIViewContentModeScaleAspectFit;
        [row addSubview:ic];
        if (i > 0) {
            UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(16, i * rowH, cardW - 16, 0.5)];
            sep.backgroundColor = [UIColor.separatorColor colorWithAlphaComponent:0.5];
            [card.contentView addSubview:sep];
        }
        void (^handler)(void) = it.handler;
        [row addAction:[UIAction actionWithHandler:^(UIAction *a) {
            dismiss();
            if (handler) { dispatch_async(dispatch_get_main_queue(), handler); }
        }] forControlEvents:UIControlEventTouchUpInside];
        [card.contentView addSubview:row];
    }];

    // 上→下弹出：**先记原始 frame**（改 anchorPoint 会立即偏移 frame），顶部中点为锚缩放。
    CGRect f = card.frame;
    card.layer.anchorPoint = CGPointMake(0.5, 0);
    card.layer.position = CGPointMake(CGRectGetMidX(f), CGRectGetMinY(f));
    card.transform = CGAffineTransformMakeScale(0.85, 0.85);
    card.alpha = 0;
    [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0.4
                        options:UIViewAnimationOptionCurveEaseOut animations:^{
        card.transform = CGAffineTransformIdentity; card.alpha = 1;
    } completion:nil];
}

@end
