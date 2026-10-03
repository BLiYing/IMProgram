//  IMActionListSheet.m

#import "IMActionListSheet.h"
#import "IMTheme.h"
#import "IMLocalization.h"

static const CGFloat kRowH = 56;
static const CGFloat kTitleH = 44;
static const CGFloat kSideMargin = 10;
static const CGFloat kRadius = 20;

@implementation IMActionListItem
+ (instancetype)itemWithTitle:(NSString *)title destructive:(BOOL)destructive handler:(void (^)(void))handler {
    IMActionListItem *it = [IMActionListItem new];
    it.title = title; it.destructive = destructive; it.handler = handler;
    return it;
}
@end

@implementation IMActionListSheet {
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
    for (NSUInteger i = 0; i < _items.count; i++) {
        [stack addArrangedSubview:[self rowWithTitle:_items[i].title destructive:_items[i].destructive tag:(NSInteger)i]];
    }
    [stack addArrangedSubview:[self rowWithTitle:IMLocalized(@"common.cancel") destructive:NO tag:-1]];

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

- (UIView *)rowWithTitle:(NSString *)title destructive:(BOOL)destructive tag:(NSInteger)tag {
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
