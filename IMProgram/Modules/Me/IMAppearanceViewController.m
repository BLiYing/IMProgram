//  IMAppearanceViewController.m
//  Telegram 风格外观中心：聊天预览、主题/壁纸选择、字号/圆角预览和应用图标网格。

#import "IMAppearanceViewController.h"

#import "IMAppearance.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"

static NSArray<NSString *> *IMThemeIDs(void) {
    return @[@"classic", @"ocean", @"violet", @"midnight"];
}

static NSArray<NSString *> *IMThemeNames(void) {
    return @[@"经典", @"海洋", @"紫晶", @"深海"];
}

static NSArray<NSString *> *IMWallpaperIDs(void) {
    return @[@"doodle", @"gradient", @"plain"];
}

static NSArray<NSString *> *IMWallpaperNames(void) {
    return @[@"涂鸦", @"渐变", @"纯色"];
}

static NSString *IMCurrentThemeName(void) {
    NSUInteger index = [IMThemeIDs() indexOfObject:IMAppearance.shared.themeID];
    return index == NSNotFound ? IMThemeNames().firstObject : IMThemeNames()[index];
}

static NSString *IMCurrentWallpaperName(void) {
    NSUInteger index = [IMWallpaperIDs() indexOfObject:IMAppearance.shared.wallpaperID];
    return index == NSNotFound ? IMWallpaperNames().firstObject : IMWallpaperNames()[index];
}

static NSString *IMCurrentModeName(void) {
    return @[@"跟随系统", @"浅色", @"深色"][IMAppearance.shared.mode];
}

static UIImage *IMThumbnailImage(UIImage *image, CGSize size) {
    if (!image) { return nil; }
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height)
                                    cornerRadius:size.width * 0.225] addClip];
        [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    }];
}

#pragma mark - Shared visual components

@interface IMBubblePreviewLabel : UILabel
@property (nonatomic, assign) UIEdgeInsets contentInsets;
@end

@implementation IMBubblePreviewLabel
- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    return CGSizeMake(size.width + self.contentInsets.left + self.contentInsets.right,
                      size.height + self.contentInsets.top + self.contentInsets.bottom);
}
- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:UIEdgeInsetsInsetRect(rect, self.contentInsets)];
}
@end

@interface IMAppearanceChatPreview : UIView
@property (nonatomic, copy) NSString *themeID;
@property (nonatomic, copy) NSString *wallpaperID;
@property (nonatomic, assign) CGFloat fontSize;
@property (nonatomic, assign) CGFloat bubbleRadius;
@property (nonatomic, assign) BOOL expanded;
- (void)refresh;
@end

@implementation IMAppearanceChatPreview {
    CAGradientLayer *_gradient;
    UILabel *_pattern;
    UILabel *_title;
    UILabel *_day;
    IMBubblePreviewLabel *_incoming;
    IMBubblePreviewLabel *_outgoing;
    IMBubblePreviewLabel *_incomingSecond;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = YES;
        _themeID = IMAppearance.shared.themeID;
        _wallpaperID = IMAppearance.shared.wallpaperID;
        _fontSize = IMAppearance.shared.chatFontSize;
        _bubbleRadius = IMAppearance.shared.bubbleRadius;
        _gradient = [CAGradientLayer layer];
        [self.layer addSublayer:_gradient];

        _pattern = [UILabel new];
        _pattern.translatesAutoresizingMaskIntoConstraints = NO;
        _pattern.text = @"♡   ✦   ☺   ✎   ◌   ♫   ✧   ☕\n  ☂   ☆   ⚡   ♡   ◇   ✦   ☺\n✎   ◌   ♫   ☕   ☆   ⚡   ♡";
        _pattern.numberOfLines = 0;
        _pattern.font = [UIFont systemFontOfSize:34 weight:UIFontWeightLight];
        _pattern.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_pattern];

        _title = [UILabel new];
        _title.translatesAutoresizingMaskIntoConstraints = NO;
        _title.text = @"聊天预览";
        _title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        _title.textAlignment = NSTextAlignmentCenter;
        _title.textColor = IMTheme.textPrimary;
        [self addSubview:_title];

        _day = [UILabel new];
        _day.translatesAutoresizingMaskIntoConstraints = NO;
        _day.text = @"今天";
        _day.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        _day.textColor = UIColor.whiteColor;
        _day.backgroundColor = [UIColor colorWithWhite:0 alpha:0.22];
        _day.textAlignment = NSTextAlignmentCenter;
        _day.layer.cornerRadius = 11;
        _day.clipsToBounds = YES;
        [self addSubview:_day];

        _incoming = [self bubbleWithText:@"你看到新的外观了吗？"];
        _outgoing = [self bubbleWithText:@"看到了，很有 Telegram 的感觉 ✓✓"];
        _incomingSecond = [self bubbleWithText:@"字号和圆角也可以实时预览。"];
        [self addSubview:_incoming];
        [self addSubview:_outgoing];
        [self addSubview:_incomingSecond];

        [NSLayoutConstraint activateConstraints:@[
            [_pattern.topAnchor constraintEqualToAnchor:self.topAnchor constant:30],
            [_pattern.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
            [_pattern.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:-10],
            [_pattern.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:10],
            [_title.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
            [_title.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_day.topAnchor constraintEqualToAnchor:_title.bottomAnchor constant:16],
            [_day.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_day.widthAnchor constraintEqualToConstant:48],
            [_day.heightAnchor constraintEqualToConstant:22],
            [_incoming.topAnchor constraintEqualToAnchor:_day.bottomAnchor constant:14],
            [_incoming.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_incoming.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor multiplier:0.72],
            [_outgoing.topAnchor constraintEqualToAnchor:_incoming.bottomAnchor constant:10],
            [_outgoing.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
            [_outgoing.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor multiplier:0.84],
            [_incomingSecond.topAnchor constraintEqualToAnchor:_outgoing.bottomAnchor constant:10],
            [_incomingSecond.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_incomingSecond.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor multiplier:0.76],
        ]];
        [self refresh];
    }
    return self;
}

- (IMBubblePreviewLabel *)bubbleWithText:(NSString *)text {
    IMBubblePreviewLabel *label = [IMBubblePreviewLabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.numberOfLines = 0;
    label.contentInsets = UIEdgeInsetsMake(9, 13, 9, 13);
    label.textColor = UIColor.labelColor;
    label.clipsToBounds = YES;
    return label;
}

- (void)setExpanded:(BOOL)expanded {
    _expanded = expanded;
    _title.hidden = expanded;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _gradient.frame = self.bounds;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self refresh];
    }
}

- (void)refresh {
    NSArray<UIColor *> *colors = [IMAppearance.shared wallpaperColorsForThemeID:self.themeID];
    UIColor *top = [colors.firstObject resolvedColorWithTraitCollection:self.traitCollection];
    UIColor *bottom = [colors.lastObject resolvedColorWithTraitCollection:self.traitCollection];
    _gradient.colors = @[(id)top.CGColor, (id)bottom.CGColor];
    _gradient.hidden = [self.wallpaperID isEqualToString:@"plain"];
    self.backgroundColor = [self.wallpaperID isEqualToString:@"plain"] ? top : UIColor.clearColor;
    _pattern.hidden = ![self.wallpaperID isEqualToString:@"doodle"];
    _pattern.textColor = [[UIColor whiteColor] colorWithAlphaComponent:
        self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 0.05 : 0.15];

    UIColor *accent = [IMAppearance.shared accentColorForThemeID:self.themeID];
    _incoming.backgroundColor = IMTheme.bubbleThem;
    _incomingSecond.backgroundColor = IMTheme.bubbleThem;
    _outgoing.backgroundColor = [IMAppearance.shared bubbleMeColorForThemeID:self.themeID];
    for (IMBubblePreviewLabel *bubble in @[_incoming, _outgoing, _incomingSecond]) {
        bubble.font = [UIFont systemFontOfSize:self.fontSize];
        bubble.layer.cornerRadius = self.bubbleRadius;
        bubble.layer.cornerCurve = kCACornerCurveContinuous;
    }
    _day.backgroundColor = [accent colorWithAlphaComponent:0.64];
}

@end

@interface IMSettingRow : UIControl
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIImageView *chevron;
@property (nonatomic, strong, nullable) UIView *trailingView;
- (instancetype)initWithTitle:(NSString *)title;
@end

@implementation IMSettingRow
- (instancetype)initWithTitle:(NSString *)title {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self.heightAnchor constraintEqualToConstant:56].active = YES;
        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.text = title;
        _titleLabel.font = [UIFont systemFontOfSize:17];
        _titleLabel.textColor = IMTheme.textPrimary;
        [self addSubview:_titleLabel];
        _detailLabel = [UILabel new];
        _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _detailLabel.font = [UIFont systemFontOfSize:15];
        _detailLabel.textColor = IMTheme.textSecondary;
        [self addSubview:_detailLabel];
        _chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        _chevron.translatesAutoresizingMaskIntoConstraints = NO;
        _chevron.tintColor = IMTheme.textTertiary;
        [self addSubview:_chevron];
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_chevron.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [_chevron.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_chevron.widthAnchor constraintEqualToConstant:8],
            [_detailLabel.trailingAnchor constraintEqualToAnchor:_chevron.leadingAnchor constant:-10],
            [_detailLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_detailLabel.leadingAnchor constant:-10],
        ]];
    }
    return self;
}

- (void)setTrailingView:(UIView *)trailingView {
    [_trailingView removeFromSuperview];
    _trailingView = trailingView;
    if (!trailingView) { return; }
    trailingView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:trailingView];
    _detailLabel.hidden = YES;
    _chevron.hidden = YES;
    [NSLayoutConstraint activateConstraints:@[
        [trailingView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [trailingView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
}
@end

static UIView *IMSeparator(void) {
    UIView *separator = [UIView new];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.backgroundColor = IMTheme.separator;
    [separator.heightAnchor constraintEqualToConstant:0.5].active = YES;
    return separator;
}

static UIView *IMCardWithRows(NSArray<IMSettingRow *> *rows) {
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    for (NSUInteger index = 0; index < rows.count; index++) {
        [stack addArrangedSubview:rows[index]];
        if (index + 1 < rows.count) {
            UIView *separator = IMSeparator();
            [stack addArrangedSubview:separator];
        }
    }
    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = IMTheme.cardBackground;
    card.layer.cornerRadius = 24;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
    ]];
    return card;
}

@interface IMThemeMiniButton : UIControl
@property (nonatomic, copy) NSString *themeID;
@property (nonatomic, strong) CAGradientLayer *gradient;
@property (nonatomic, strong) UIView *incoming;
@property (nonatomic, strong) UIView *outgoing;
@property (nonatomic, strong) UILabel *nameLabel;
- (void)configureThemeID:(NSString *)themeID name:(NSString *)name selected:(BOOL)selected;
@end

@implementation IMThemeMiniButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _gradient = [CAGradientLayer layer];
        [self.layer addSublayer:_gradient];
        self.layer.cornerRadius = 16;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;
        _incoming = [UIView new];
        _outgoing = [UIView new];
        for (UIView *bubble in @[_incoming, _outgoing]) {
            bubble.userInteractionEnabled = NO;
            bubble.layer.cornerRadius = 9;
            [self addSubview:bubble];
        }
        _nameLabel = [UILabel new];
        _nameLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        _nameLabel.textAlignment = NSTextAlignmentCenter;
        _nameLabel.textColor = UIColor.whiteColor;
        _nameLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.30];
        _nameLabel.layer.cornerRadius = 8;
        _nameLabel.clipsToBounds = YES;
        [self addSubview:_nameLabel];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _gradient.frame = self.bounds;
    _outgoing.frame = CGRectMake(self.bounds.size.width - 55, 13, 43, 18);
    _incoming.frame = CGRectMake(12, 39, 48, 18);
    _nameLabel.frame = CGRectMake(10, self.bounds.size.height - 24, self.bounds.size.width - 20, 17);
}
- (void)configureThemeID:(NSString *)themeID name:(NSString *)name selected:(BOOL)selected {
    self.themeID = themeID;
    NSArray *colors = [IMAppearance.shared wallpaperColorsForThemeID:themeID];
    _gradient.colors = @[(id)[colors.firstObject resolvedColorWithTraitCollection:self.traitCollection].CGColor,
                         (id)[colors.lastObject resolvedColorWithTraitCollection:self.traitCollection].CGColor];
    _incoming.backgroundColor = IMTheme.bubbleThem;
    _outgoing.backgroundColor = [IMAppearance.shared bubbleMeColorForThemeID:themeID];
    _nameLabel.text = name;
    self.layer.borderWidth = selected ? 3 : 0;
    self.layer.borderColor = [IMAppearance.shared accentColorForThemeID:themeID].CGColor;
}
@end

#pragma mark - Detail screens

typedef NS_ENUM(NSInteger, IMAppearanceGridKind) {
    IMAppearanceGridKindTheme,
    IMAppearanceGridKindWallpaper,
};

@interface IMAppearanceGridCell : UICollectionViewCell
@property (nonatomic, strong) IMAppearanceChatPreview *preview;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIImageView *check;
- (void)configureName:(NSString *)name themeID:(NSString *)themeID wallpaperID:(NSString *)wallpaperID selected:(BOOL)selected;
@end

@implementation IMAppearanceGridCell
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.backgroundColor = IMTheme.cardBackground;
        self.contentView.layer.cornerRadius = 20;
        self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        self.contentView.clipsToBounds = YES;
        _preview = [IMAppearanceChatPreview new];
        _preview.translatesAutoresizingMaskIntoConstraints = NO;
        _preview.userInteractionEnabled = NO;
        _preview.transform = CGAffineTransformMakeScale(0.72, 0.72);
        _nameLabel = [UILabel new];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _nameLabel.textAlignment = NSTextAlignmentCenter;
        _check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];
        _check.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_preview];
        [self.contentView addSubview:_nameLabel];
        [self.contentView addSubview:_check];
        [NSLayoutConstraint activateConstraints:@[
            [_preview.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_preview.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_preview.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_preview.heightAnchor constraintEqualToConstant:178],
            [_nameLabel.topAnchor constraintEqualToAnchor:_preview.bottomAnchor constant:10],
            [_nameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8],
            [_nameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
            [_nameLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
            [_check.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [_check.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
            [_check.widthAnchor constraintEqualToConstant:25],
            [_check.heightAnchor constraintEqualToConstant:25],
        ]];
    }
    return self;
}
- (void)configureName:(NSString *)name themeID:(NSString *)themeID wallpaperID:(NSString *)wallpaperID selected:(BOOL)selected {
    _nameLabel.text = name;
    _nameLabel.textColor = selected ? IMTheme.accent : IMTheme.textPrimary;
    _preview.themeID = themeID;
    _preview.wallpaperID = wallpaperID;
    _preview.fontSize = 12;
    _preview.bubbleRadius = 12;
    [_preview refresh];
    _check.hidden = !selected;
    _check.tintColor = IMTheme.accent;
}
@end

@interface IMAppearanceGridViewController : UICollectionViewController <UICollectionViewDelegateFlowLayout>
@property (nonatomic, assign) IMAppearanceGridKind kind;
- (instancetype)initWithKind:(IMAppearanceGridKind)kind;
@end

@implementation IMAppearanceGridViewController
- (instancetype)initWithKind:(IMAppearanceGridKind)kind {
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.sectionInset = UIEdgeInsetsMake(18, 16, 24, 16);
    layout.minimumInteritemSpacing = 12;
    layout.minimumLineSpacing = 14;
    self = [super initWithCollectionViewLayout:layout];
    if (self) { _kind = kind; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.kind == IMAppearanceGridKindTheme ? @"聊天主题" : @"聊天壁纸";
    self.collectionView.backgroundColor = IMTheme.groupedBackground;
    [self.collectionView registerClass:IMAppearanceGridCell.class forCellWithReuseIdentifier:@"appearance"];
}
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.kind == IMAppearanceGridKindTheme ? IMThemeIDs().count : IMWallpaperIDs().count;
}
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    IMAppearanceGridCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"appearance" forIndexPath:indexPath];
    if (self.kind == IMAppearanceGridKindTheme) {
        NSString *themeID = IMThemeIDs()[indexPath.item];
        [cell configureName:IMThemeNames()[indexPath.item] themeID:themeID
                wallpaperID:IMAppearance.shared.wallpaperID
                   selected:[themeID isEqualToString:IMAppearance.shared.themeID]];
    } else {
        NSString *wallpaperID = IMWallpaperIDs()[indexPath.item];
        [cell configureName:IMWallpaperNames()[indexPath.item] themeID:IMAppearance.shared.themeID
                wallpaperID:wallpaperID
                   selected:[wallpaperID isEqualToString:IMAppearance.shared.wallpaperID]];
    }
    return cell;
}
- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = floor((collectionView.bounds.size.width - 44) / 2);
    return CGSizeMake(width, 224);
}
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (self.kind == IMAppearanceGridKindTheme) {
        IMAppearance.shared.themeID = IMThemeIDs()[indexPath.item];
    } else {
        IMAppearance.shared.wallpaperID = IMWallpaperIDs()[indexPath.item];
    }
    [collectionView reloadData];
}
@end

@interface IMAppearanceModeViewController : UITableViewController
@end

@implementation IMAppearanceModeViewController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"显示模式";
    self.tableView.backgroundColor = IMTheme.groupedBackground;
    self.tableView.rowHeight = 58;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 3; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = @[@"跟随系统", @"浅色", @"深色"][indexPath.row];
    cell.imageView.image = [UIImage systemImageNamed:@[@"circle.lefthalf.filled", @"sun.max.fill", @"moon.stars.fill"][indexPath.row]];
    cell.imageView.tintColor = IMTheme.accent;
    cell.accessoryType = IMAppearance.shared.mode == indexPath.row ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    IMAppearance.shared.mode = indexPath.row;
    [tableView reloadData];
}
@end

typedef NS_ENUM(NSInteger, IMAppearanceSliderKind) {
    IMAppearanceSliderKindFont,
    IMAppearanceSliderKindRadius,
};

@interface IMAppearanceSliderViewController : UIViewController
@property (nonatomic, assign) IMAppearanceSliderKind kind;
@property (nonatomic, assign) CGFloat originalValue;
@property (nonatomic, strong) IMAppearanceChatPreview *preview;
@property (nonatomic, strong) UISlider *slider;
- (instancetype)initWithKind:(IMAppearanceSliderKind)kind;
@end

@implementation IMAppearanceSliderViewController
- (instancetype)initWithKind:(IMAppearanceSliderKind)kind {
    self = [super init];
    if (self) { _kind = kind; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.kind == IMAppearanceSliderKindFont ? @"字体大小" : @"信息框圆角";
    self.view.backgroundColor = IMTheme.groupedBackground;
    self.originalValue = self.kind == IMAppearanceSliderKindFont
        ? IMAppearance.shared.chatFontSize : IMAppearance.shared.bubbleRadius;
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"设置" style:UIBarButtonItemStyleDone target:self action:@selector(done)];

    _preview = [IMAppearanceChatPreview new];
    _preview.translatesAutoresizingMaskIntoConstraints = NO;
    _preview.expanded = YES;
    _preview.themeID = IMAppearance.shared.themeID;
    _preview.wallpaperID = IMAppearance.shared.wallpaperID;
    _preview.fontSize = IMAppearance.shared.chatFontSize;
    _preview.bubbleRadius = IMAppearance.shared.bubbleRadius;
    [_preview refresh];
    [self.view addSubview:_preview];

    UIView *panel = [UIView new];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.backgroundColor = IMTheme.cardBackground;
    panel.layer.cornerRadius = 28;
    panel.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    [self.view addSubview:panel];
    UILabel *small = [UILabel new];
    small.translatesAutoresizingMaskIntoConstraints = NO;
    small.text = @"A";
    small.font = [UIFont systemFontOfSize:14];
    small.textColor = IMTheme.textSecondary;
    UILabel *large = [UILabel new];
    large.translatesAutoresizingMaskIntoConstraints = NO;
    large.text = @"A";
    large.font = [UIFont systemFontOfSize:30];
    large.textColor = IMTheme.textSecondary;
    _slider = [UISlider new];
    _slider.translatesAutoresizingMaskIntoConstraints = NO;
    _slider.minimumValue = self.kind == IMAppearanceSliderKindFont ? 14 : 6;
    _slider.maximumValue = self.kind == IMAppearanceSliderKindFont ? 22 : 24;
    _slider.value = self.originalValue;
    _slider.minimumTrackTintColor = IMTheme.accent;
    [_slider addTarget:self action:@selector(valueChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:small];
    [panel addSubview:_slider];
    [panel addSubview:large];
    [NSLayoutConstraint activateConstraints:@[
        [_preview.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_preview.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_preview.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_preview.bottomAnchor constraintEqualToAnchor:panel.topAnchor],
        [panel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [panel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [panel.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [panel.heightAnchor constraintEqualToConstant:138],
        [small.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:22],
        [small.centerYAnchor constraintEqualToAnchor:_slider.centerYAnchor],
        [large.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-22],
        [large.centerYAnchor constraintEqualToAnchor:_slider.centerYAnchor],
        [_slider.leadingAnchor constraintEqualToAnchor:small.trailingAnchor constant:16],
        [_slider.trailingAnchor constraintEqualToAnchor:large.leadingAnchor constant:-16],
        [_slider.topAnchor constraintEqualToAnchor:panel.topAnchor constant:36],
    ]];
}
- (void)valueChanged:(UISlider *)slider {
    CGFloat value = round(slider.value);
    if (self.kind == IMAppearanceSliderKindFont) {
        IMAppearance.shared.chatFontSize = value;
        self.preview.fontSize = value;
    } else {
        IMAppearance.shared.bubbleRadius = value;
        self.preview.bubbleRadius = value;
    }
    [self.preview refresh];
}
- (void)cancel {
    if (self.kind == IMAppearanceSliderKindFont) { IMAppearance.shared.chatFontSize = self.originalValue; }
    else { IMAppearance.shared.bubbleRadius = self.originalValue; }
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

#pragma mark - Main appearance screen

@interface IMAppearanceViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) IMAppearanceChatPreview *preview;
@property (nonatomic, strong) UIStackView *themeStrip;
@property (nonatomic, strong) UILabel *themeDetail;
@property (nonatomic, strong) UILabel *wallpaperDetail;
@property (nonatomic, strong) UILabel *modeDetail;
@property (nonatomic, strong) UILabel *fontDetail;
@property (nonatomic, strong) UILabel *radiusDetail;
@property (nonatomic, strong) UISwitch *animationSwitch;
@property (nonatomic, strong) UIStackView *iconGrid;
@end

@implementation IMAppearanceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"外观";
    self.view.backgroundColor = IMTheme.groupedBackground;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"还原" style:UIBarButtonItemStylePlain target:self action:@selector(resetTapped)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appearanceChanged)
                                               name:IMAppearanceDidChangeNotification object:nil];
    [self buildLayout];
    [self refreshAll];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (UILabel *)sectionLabel:(NSString *)text {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont systemFontOfSize:14];
    label.textColor = IMTheme.textSecondary;
    label.textAlignment = NSTextAlignmentLeft;
    return label;
}

- (void)buildLayout {
    _scrollView = [UIScrollView new];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:_scrollView];
    _contentStack = [UIStackView new];
    _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    _contentStack.axis = UILayoutConstraintAxisVertical;
    _contentStack.alignment = UIStackViewAlignmentFill;
    _contentStack.spacing = 12;
    [_scrollView addSubview:_contentStack];
    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_contentStack.topAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.topAnchor constant:18],
        [_contentStack.bottomAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.bottomAnchor constant:-30],
        [_contentStack.leadingAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.leadingAnchor constant:16],
        [_contentStack.trailingAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.trailingAnchor constant:-16],
    ]];

    [_contentStack addArrangedSubview:[self sectionLabel:@"主题颜色"]];
    [_contentStack addArrangedSubview:[self buildThemeCard]];
    [_contentStack setCustomSpacing:26 afterView:_contentStack.arrangedSubviews.lastObject];
    [_contentStack addArrangedSubview:[self sectionLabel:@"显示模式"]];
    [_contentStack addArrangedSubview:[self buildModeCard]];
    [_contentStack setCustomSpacing:26 afterView:_contentStack.arrangedSubviews.lastObject];
    [_contentStack addArrangedSubview:[self sectionLabel:@"聊天外观"]];
    [_contentStack addArrangedSubview:[self buildChatOptionsCard]];
    [_contentStack setCustomSpacing:26 afterView:_contentStack.arrangedSubviews.lastObject];
    [_contentStack addArrangedSubview:[self sectionLabel:@"应用图标"]];
    [_contentStack addArrangedSubview:[self buildIconCard]];
}

- (UIView *)buildThemeCard {
    UIView *card = [UIView new];
    card.backgroundColor = IMTheme.cardBackground;
    card.layer.cornerRadius = 28;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;
    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    [card addSubview:stack];
    _preview = [IMAppearanceChatPreview new];
    [_preview.heightAnchor constraintEqualToConstant:238].active = YES;
    [stack addArrangedSubview:_preview];

    UIView *stripHost = [UIView new];
    [stripHost.heightAnchor constraintEqualToConstant:112].active = YES;
    _themeStrip = [UIStackView new];
    _themeStrip.translatesAutoresizingMaskIntoConstraints = NO;
    _themeStrip.axis = UILayoutConstraintAxisHorizontal;
    _themeStrip.spacing = 10;
    _themeStrip.distribution = UIStackViewDistributionFillEqually;
    [stripHost addSubview:_themeStrip];
    for (NSUInteger index = 0; index < IMThemeIDs().count; index++) {
        IMThemeMiniButton *button = [IMThemeMiniButton new];
        button.tag = index;
        [button addTarget:self action:@selector(themeMiniTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_themeStrip addArrangedSubview:button];
    }
    [NSLayoutConstraint activateConstraints:@[
        [_themeStrip.topAnchor constraintEqualToAnchor:stripHost.topAnchor constant:12],
        [_themeStrip.bottomAnchor constraintEqualToAnchor:stripHost.bottomAnchor constant:-12],
        [_themeStrip.leadingAnchor constraintEqualToAnchor:stripHost.leadingAnchor constant:12],
        [_themeStrip.trailingAnchor constraintEqualToAnchor:stripHost.trailingAnchor constant:-12],
    ]];
    [stack addArrangedSubview:stripHost];
    [stack addArrangedSubview:IMSeparator()];

    IMSettingRow *theme = [[IMSettingRow alloc] initWithTitle:@"聊天主题"];
    _themeDetail = theme.detailLabel;
    [theme addTarget:self action:@selector(openThemes) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:theme];
    UIView *separator = IMSeparator();
    [stack addArrangedSubview:separator];
    IMSettingRow *wallpaper = [[IMSettingRow alloc] initWithTitle:@"聊天壁纸"];
    _wallpaperDetail = wallpaper.detailLabel;
    [wallpaper addTarget:self action:@selector(openWallpapers) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:wallpaper];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
    ]];
    return card;
}

- (UIView *)buildModeCard {
    IMSettingRow *night = [[IMSettingRow alloc] initWithTitle:@"夜间模式"];
    UISwitch *toggle = [UISwitch new];
    toggle.on = IMAppearance.shared.mode == IMAppearanceModeDark;
    [toggle addTarget:self action:@selector(nightSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    night.trailingView = toggle;
    IMSettingRow *automatic = [[IMSettingRow alloc] initWithTitle:@"自动夜间模式"];
    _modeDetail = automatic.detailLabel;
    [automatic addTarget:self action:@selector(openMode) forControlEvents:UIControlEventTouchUpInside];
    return IMCardWithRows(@[night, automatic]);
}

- (UIView *)buildChatOptionsCard {
    IMSettingRow *font = [[IMSettingRow alloc] initWithTitle:@"字号"];
    _fontDetail = font.detailLabel;
    [font addTarget:self action:@selector(openFont) forControlEvents:UIControlEventTouchUpInside];
    IMSettingRow *radius = [[IMSettingRow alloc] initWithTitle:@"信息框圆角"];
    _radiusDetail = radius.detailLabel;
    [radius addTarget:self action:@selector(openRadius) forControlEvents:UIControlEventTouchUpInside];
    IMSettingRow *animation = [[IMSettingRow alloc] initWithTitle:@"动画"];
    _animationSwitch = [UISwitch new];
    [_animationSwitch addTarget:self action:@selector(animationChanged:) forControlEvents:UIControlEventValueChanged];
    animation.trailingView = _animationSwitch;
    return IMCardWithRows(@[font, radius, animation]);
}

- (UIView *)buildIconCard {
    UIView *card = [UIView new];
    card.backgroundColor = IMTheme.cardBackground;
    card.layer.cornerRadius = 28;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    _iconGrid = [UIStackView new];
    _iconGrid.translatesAutoresizingMaskIntoConstraints = NO;
    _iconGrid.axis = UILayoutConstraintAxisHorizontal;
    _iconGrid.distribution = UIStackViewDistributionFillEqually;
    _iconGrid.spacing = 12;
    NSArray *names = @[@"默认", @"蓝色", @"紫色", @"深色"];
    NSArray *assetNames = @[@"AppearanceIconDefault", @"AppearanceIconOcean",
                            @"AppearanceIconViolet", @"AppearanceIconMidnight"];
    for (NSUInteger index = 0; index < names.count; index++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = index;
        [button addTarget:self action:@selector(iconTapped:) forControlEvents:UIControlEventTouchUpInside];
        button.backgroundColor = UIColor.clearColor;
        button.layer.cornerRadius = 18;
        button.layer.cornerCurve = kCACornerCurveContinuous;
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        UIImage *icon = [UIImage imageNamed:assetNames[index]];
        config.image = IMThumbnailImage(icon, CGSizeMake(52, 52));
        config.imagePlacement = NSDirectionalRectEdgeTop;
        config.imagePadding = 7;
        config.title = names[index];
        config.baseForegroundColor = IMTheme.textPrimary;
        config.titleTextAttributesTransformer =
            ^NSDictionary *(NSDictionary *attributes) {
                NSMutableDictionary *result = [attributes mutableCopy];
                result[NSFontAttributeName] = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
                return result;
            };
        button.configuration = config;
        [button.heightAnchor constraintEqualToConstant:92].active = YES;
        [_iconGrid addArrangedSubview:button];
    }
    [card addSubview:_iconGrid];
    [NSLayoutConstraint activateConstraints:@[
        [_iconGrid.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [_iconGrid.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
        [_iconGrid.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [_iconGrid.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
    ]];
    return card;
}

- (void)refreshAll {
    _preview.themeID = IMAppearance.shared.themeID;
    _preview.wallpaperID = IMAppearance.shared.wallpaperID;
    _preview.fontSize = IMAppearance.shared.chatFontSize;
    _preview.bubbleRadius = IMAppearance.shared.bubbleRadius;
    [_preview refresh];
    _themeDetail.text = IMCurrentThemeName();
    _wallpaperDetail.text = IMCurrentWallpaperName();
    _modeDetail.text = IMCurrentModeName();
    _fontDetail.text = [NSString stringWithFormat:@"%.0f", IMAppearance.shared.chatFontSize];
    _radiusDetail.text = [NSString stringWithFormat:@"%.0f", IMAppearance.shared.bubbleRadius];
    _animationSwitch.on = IMAppearance.shared.animationsEnabled;

    for (NSUInteger index = 0; index < _themeStrip.arrangedSubviews.count; index++) {
        IMThemeMiniButton *button = (IMThemeMiniButton *)_themeStrip.arrangedSubviews[index];
        [button configureThemeID:IMThemeIDs()[index] name:IMThemeNames()[index]
                       selected:[IMThemeIDs()[index] isEqualToString:IMAppearance.shared.themeID]];
    }
    NSArray *iconNames = @[@"", @"AppIconOcean", @"AppIconViolet", @"AppIconMidnight"];
    NSString *currentIcon = UIApplication.sharedApplication.alternateIconName ?: @"";
    for (NSUInteger index = 0; index < _iconGrid.arrangedSubviews.count; index++) {
        UIButton *button = (UIButton *)_iconGrid.arrangedSubviews[index];
        BOOL selected = [iconNames[index] isEqualToString:currentIcon];
        button.layer.borderWidth = selected ? 3 : 0;
        button.layer.borderColor = selected ? IMTheme.accent.CGColor : UIColor.clearColor.CGColor;
    }
}

- (void)appearanceChanged {
    self.view.backgroundColor = IMTheme.groupedBackground;
    [self refreshAll];
}

- (void)themeMiniTapped:(IMThemeMiniButton *)sender {
    IMAppearance.shared.themeID = IMThemeIDs()[sender.tag];
}

- (void)nightSwitchChanged:(UISwitch *)sender {
    IMAppearance.shared.mode = sender.on ? IMAppearanceModeDark : IMAppearanceModeSystem;
}

- (void)animationChanged:(UISwitch *)sender {
    IMAppearance.shared.animationsEnabled = sender.on;
}

- (void)openThemes {
    [self.navigationController pushViewController:
        [[IMAppearanceGridViewController alloc] initWithKind:IMAppearanceGridKindTheme] animated:YES];
}

- (void)openWallpapers {
    [self.navigationController pushViewController:
        [[IMAppearanceGridViewController alloc] initWithKind:IMAppearanceGridKindWallpaper] animated:YES];
}

- (void)openMode {
    [self.navigationController pushViewController:[IMAppearanceModeViewController new] animated:YES];
}

- (void)presentSlider:(IMAppearanceSliderKind)kind {
    IMAppearanceSliderViewController *controller = [[IMAppearanceSliderViewController alloc] initWithKind:kind];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)openFont { [self presentSlider:IMAppearanceSliderKindFont]; }
- (void)openRadius { [self presentSlider:IMAppearanceSliderKindRadius]; }

- (void)iconTapped:(UIButton *)sender {
    if (!UIApplication.sharedApplication.supportsAlternateIcons) {
        [self im_showToast:@"当前系统不支持切换图标"];
        return;
    }
    NSArray *names = @[[NSNull null], @"AppIconOcean", @"AppIconViolet", @"AppIconMidnight"];
    id selected = names[sender.tag];
    NSString *name = selected == NSNull.null ? nil : selected;
    NSString *current = UIApplication.sharedApplication.alternateIconName;
    if ((!name && !current) || [name isEqualToString:current]) { return; }
    __weak typeof(self) weakSelf = self;
    [UIApplication.sharedApplication setAlternateIconName:name completionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) { [weakSelf im_showToast:error.localizedDescription]; }
            [weakSelf refreshAll];
        });
    }];
}

- (void)resetTapped {
    [IMAppearance.shared resetToDefaults];
    if (UIApplication.sharedApplication.supportsAlternateIcons) {
        [UIApplication.sharedApplication setAlternateIconName:nil completionHandler:nil];
    }
}

@end
