//  IMWorkbenchCells.m

#import "IMWorkbenchCells.h"
#import "IMImageLoader.h"
#import "IMLocalization.h"
#import "IMTheme.h"
#import "IMMediaUtil.h"
#import "IMJSONValue.h"
#import "IMAvatarPlaceholder.h"

NSString *const IMWorkbenchCardBackgroundKind = @"im.workbench.card";

@implementation IMWorkbenchAppIconView {
    UIImageView *_image;
    UILabel *_initial;
    NSString *_loadingURL;
}

- (instancetype)initWithSide:(CGFloat)side radius:(CGFloat)radius {
    self = [super initWithFrame:CGRectMake(0, 0, side, side)];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.layer.cornerRadius = radius;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;
        _initial = [UILabel new];
        _initial.translatesAutoresizingMaskIntoConstraints = NO;
        _initial.textColor = UIColor.whiteColor;
        _initial.font = [UIFont systemFontOfSize:side * 0.42 weight:UIFontWeightSemibold];
        _initial.textAlignment = NSTextAlignmentCenter;
        _image = [UIImageView new];
        _image.translatesAutoresizingMaskIntoConstraints = NO;
        _image.contentMode = UIViewContentModeScaleAspectFill;
        [self addSubview:_initial];
        [self addSubview:_image];
        [NSLayoutConstraint activateConstraints:@[
            [self.widthAnchor constraintEqualToConstant:side], [self.heightAnchor constraintEqualToConstant:side],
            [_initial.centerXAnchor constraintEqualToAnchor:self.centerXAnchor], [_initial.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_image.topAnchor constraintEqualToAnchor:self.topAnchor], [_image.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_image.leadingAnchor constraintEqualToAnchor:self.leadingAnchor], [_image.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];
    }
    return self;
}

- (void)setName:(NSString *)name logoURL:(NSString *)logoURL host:(NSString *)host {
    _initial.text = name.length > 0 ? [name substringWithRange:[name rangeOfComposedCharacterSequenceAtIndex:0]] : @"?";
    self.backgroundColor = IMAvatarSeedColor(name); // 与头像占位同一套稳定取色；首字取名字第一个字（应用名不是人名，不取末字）
    _image.image = nil;
    NSString *full = logoURL.length > 0 ? IMMediaFullURL(logoURL, host) : nil;
    _loadingURL = full;
    if (full.length == 0) { return; }
    __weak typeof(self) weak = self;
    [[IMImageLoader shared] loadImageURL:full completion:^(UIImage *img) {
        typeof(self) s = weak;
        if (s && [s->_loadingURL isEqualToString:full]) { s->_image.image = img; } // 复用后不串图
    }];
}

@end

@implementation IMWorkbenchAppCell {
    IMWorkbenchAppIconView *_icon;
    UILabel *_name;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _icon = [[IMWorkbenchAppIconView alloc] initWithSide:52 radius:12];
        _name = [UILabel new];
        _name.translatesAutoresizingMaskIntoConstraints = NO;
        _name.font = [UIFont systemFontOfSize:12];
        _name.textColor = IMTheme.textPrimary;
        _name.textAlignment = NSTextAlignmentCenter;
        _name.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_icon];
        [self.contentView addSubview:_name];
        [NSLayoutConstraint activateConstraints:@[
            [_icon.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_icon.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_name.topAnchor constraintEqualToAnchor:_icon.bottomAnchor constant:6],
            [_name.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:2],
            [_name.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-2],
        ]];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}

- (void)configureWithApp:(NSDictionary *)app host:(NSString *)host {
    NSString *name = IMJSONString(app[@"name"]);
    NSString *logo = IMJSONString(app[@"logo_url"]);
    _name.text = name;
    self.accessibilityLabel = name;
    [_icon setName:name logoURL:logo host:host];
}

@end

@interface IMWorkbenchBannerCell () <UIScrollViewDelegate>
@end

@implementation IMWorkbenchBannerCell {
    UIScrollView *_scroll;
    UIStackView *_dots;
    NSArray<NSDictionary *> *_banners;
    NSArray<UIImageView *> *_pages;
    NSTimer *_timer;
    NSInteger _page;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.layer.cornerRadius = 12;
        self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        self.contentView.clipsToBounds = YES;
        self.contentView.backgroundColor = UIColor.tertiarySystemFillColor;
        _scroll = [UIScrollView new];
        _scroll.translatesAutoresizingMaskIntoConstraints = NO;
        _scroll.pagingEnabled = YES;
        _scroll.showsHorizontalScrollIndicator = NO;
        _scroll.delegate = self;
        [self.contentView addSubview:_scroll];
        _dots = [UIStackView new];
        _dots.translatesAutoresizingMaskIntoConstraints = NO;
        _dots.axis = UILayoutConstraintAxisHorizontal;
        _dots.spacing = 5;
        _dots.alignment = UIStackViewAlignmentCenter;
        [self.contentView addSubview:_dots];
        [NSLayoutConstraint activateConstraints:@[
            [_scroll.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_scroll.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
            [_scroll.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_scroll.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_dots.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_dots.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
        ]];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)];
        [_scroll addGestureRecognizer:tap];
    }
    return self;
}

- (void)configureWithBanners:(NSArray<NSDictionary *> *)banners host:(NSString *)host {
    if ([banners isEqualToArray:_banners]) { return; } // 刷新回来数据没变：不重建图片、不跳回第一页
    _banners = [banners copy];
    for (UIView *v in _pages) { [v removeFromSuperview]; }
    NSMutableArray *pages = [NSMutableArray array];
    for (NSDictionary *b in banners) {
        UIImageView *iv = [UIImageView new];
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        [_scroll addSubview:iv];
        [pages addObject:iv];
        NSString *url = IMMediaFullURL([b[@"image_url"] isKindOfClass:NSString.class] ? b[@"image_url"] : @"", host);
        [[IMImageLoader shared] loadImageURL:url completion:^(UIImage *img) { iv.image = img; }];
    }
    _pages = pages;
    _page = 0;
    [self rebuildDots];
    [self setNeedsLayout];
    [self restartTimer];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.contentView.bounds.size;
    [_pages enumerateObjectsUsingBlock:^(UIImageView *iv, NSUInteger i, BOOL *stop) {
        iv.frame = CGRectMake(size.width * i, 0, size.width, size.height);
    }];
    _scroll.contentSize = CGSizeMake(size.width * _pages.count, size.height);
    _scroll.contentOffset = CGPointMake(size.width * _page, 0);
}

- (void)rebuildDots {
    for (UIView *v in _dots.arrangedSubviews) { [v removeFromSuperview]; }
    _dots.hidden = _banners.count < 2;
    for (NSInteger i = 0; i < (NSInteger)_banners.count; i++) {
        UIView *d = [UIView new];
        d.translatesAutoresizingMaskIntoConstraints = NO;
        d.layer.cornerRadius = 3;
        d.backgroundColor = [UIColor colorWithWhite:1 alpha:(i == _page ? 1 : 0.55)];
        [d.heightAnchor constraintEqualToConstant:6].active = YES;
        [d.widthAnchor constraintEqualToConstant:(i == _page ? 16 : 6)].active = YES;
        [_dots addArrangedSubview:d];
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self restartTimer]; // 不在屏上（切到别的 Tab / 推了新页）就停表
}

- (void)restartTimer {
    [_timer invalidate];
    _timer = nil;
    if (_banners.count < 2 || !self.window) { return; }
    __weak typeof(self) weak = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:4 repeats:YES block:^(NSTimer *t) { [weak advance]; }];
}

- (void)advance {
    _page = (_page + 1) % (NSInteger)_banners.count;
    [_scroll setContentOffset:CGPointMake(self.contentView.bounds.size.width * _page, 0) animated:YES];
    [self rebuildDots];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    CGFloat w = self.contentView.bounds.size.width;
    if (w <= 0) { return; }
    _page = (NSInteger)lround(scrollView.contentOffset.x / w);
    [self rebuildDots];
    [self restartTimer]; // 手动翻过后重新计时，不立刻又被自动翻走
}

- (void)tapped {
    if (_page < (NSInteger)_banners.count && self.onTap) { self.onTap(_banners[_page]); }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [_timer invalidate];
    _timer = nil;
    _banners = nil; // 复用后必须重新布置
}

- (void)dealloc { [_timer invalidate]; }

@end

@implementation IMWorkbenchEmptyCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UILabel *title = [UILabel new];
        title.text = IMLocalized(@"workbench.empty_title");
        title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        UILabel *hint = [UILabel new];
        hint.text = IMLocalized(@"workbench.empty_hint");
        hint.font = [UIFont systemFontOfSize:15];
        hint.textColor = IMTheme.textSecondary;
        hint.numberOfLines = 0;
        hint.textAlignment = NSTextAlignmentCenter;
        UIButtonConfiguration *cfg = [UIButtonConfiguration tintedButtonConfiguration];
        cfg.title = IMLocalized(@"workbench.go_store");
        cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        UIButton *go = [UIButton buttonWithConfiguration:cfg primaryAction:nil];
        go.accessibilityIdentifier = @"workbench.empty.goStore";
        [go addTarget:self action:@selector(goTapped) forControlEvents:UIControlEventTouchUpInside];
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, hint, go]];
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        stack.axis = UILayoutConstraintAxisVertical;
        stack.alignment = UIStackViewAlignmentCenter;
        stack.spacing = 8;
        [stack setCustomSpacing:16 afterView:hint];
        [self.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [stack.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:32],
        ]];
    }
    return self;
}

- (void)goTapped { if (self.onGoStore) { self.onGoStore(); } }

@end

@implementation IMWorkbenchHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _label = [UILabel new];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = [UIFont systemFontOfSize:13];
        _label.textColor = IMTheme.textSecondary;
        [self addSubview:_label];
        [NSLayoutConstraint activateConstraints:@[
            [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
            [_label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-6],
        ]];
    }
    return self;
}

@end

@implementation IMWorkbenchCardBackground

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = IMTheme.cardBackground;
        self.layer.cornerRadius = 10;
        self.layer.cornerCurve = kCACornerCurveContinuous;
    }
    return self;
}

@end
