//  IMConversationEditBar.m

#import "IMConversationEditBar.h"
#import "IMGlass.h"
#import "IMTheme.h"
#import "IMLocalization.h"

const CGFloat kIMConversationEditBarContentHeight = 48;
static CGFloat const kIMEditBarButtonHeight = 36;
static CGFloat const kIMEditBarDisabledAlpha = 0.35;

@implementation IMConversationEditBar

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.systemBackgroundColor;
        UIView *line = [UIView new];
        line.translatesAutoresizingMaskIntoConstraints = NO;
        line.backgroundColor = IMTheme.separator;
        [self addSubview:line];

        _selectAllButton = [self capsuleButtonWithTitle:IMLocalized(@"common.select_all") color:IMTheme.accent];
        _readButton = [self capsuleButtonWithTitle:IMLocalized(@"conv.edit.mark_read") color:IMTheme.accent];
        _deleteButton = [self capsuleButtonWithTitle:IMLocalized(@"common.delete") color:UIColor.systemRedColor];

        UIStackView *right = [[UIStackView alloc] initWithArrangedSubviews:@[_readButton, _deleteButton]];
        right.axis = UILayoutConstraintAxisHorizontal;
        right.spacing = 12;
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_selectAllButton, right]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.distribution = UIStackViewDistributionEqualSpacing;
        row.alignment = UIStackViewAlignmentCenter;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:row];

        [NSLayoutConstraint activateConstraints:@[
            [line.topAnchor constraintEqualToAnchor:self.topAnchor],
            [line.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [line.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [line.heightAnchor constraintEqualToConstant:0.5],
            [row.topAnchor constraintEqualToAnchor:self.topAnchor],
            [row.heightAnchor constraintEqualToConstant:kIMConversationEditBarContentHeight],
            [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [row.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor],
        ]];
    }
    return self;
}

/// 36pt 高玻璃胶囊文字钮：iOS 26 = glassButtonConfiguration，旧系统 = grayButtonConfiguration（经 IMGlass.h）。
- (UIButton *)capsuleButtonWithTitle:(NSString *)title color:(UIColor *)color {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *cfg = IMGlassButtonConfiguration();
    cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    cfg.contentInsets = NSDirectionalEdgeInsetsMake(0, 14, 0, 14);
    cfg.baseForegroundColor = color;
    cfg.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightMedium] }];
    b.configuration = cfg;
    b.accessibilityLabel = title;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b.heightAnchor constraintEqualToConstant:kIMEditBarButtonHeight].active = YES;
    return b;
}

- (void)setTitle:(NSString *)title onButton:(UIButton *)button {
    UIButtonConfiguration *cfg = button.configuration;
    cfg.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightMedium] }];
    button.configuration = cfg;
    button.accessibilityLabel = title;
}

- (void)updateAllSelected:(BOOL)allSelected canSelectAll:(BOOL)canSelectAll canRead:(BOOL)canRead canDelete:(BOOL)canDelete {
    [self setTitle:IMLocalized(allSelected ? @"common.deselect_all" : @"common.select_all") onButton:self.selectAllButton];
    NSArray<NSArray *> *states = @[ @[self.selectAllButton, @(canSelectAll)], @[self.readButton, @(canRead)], @[self.deleteButton, @(canDelete)] ];
    for (NSArray *s in states) {
        UIButton *b = s[0];
        BOOL on = [s[1] boolValue];
        b.enabled = on;
        b.alpha = on ? 1 : kIMEditBarDisabledAlpha;
    }
}

@end
