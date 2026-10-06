//  IMEntryCell.m

#import "IMEntryCell.h"
#import "IMTheme.h"

const CGFloat IMEntryCellSlotWidth = 40;
const CGFloat IMEntryCellTextLeading = 68;
const CGFloat IMEntryCellMinHeight = 56;

static const CGFloat kCircleSize = 32;
static const CGFloat kPlusSize = 16;
static const CGFloat kSymbolSize = 22;

@implementation IMEntryCell {
    UIView *_slot;
    UIImageView *_symbol;
    UIView *_circle;
    UILabel *_title;
    UILabel *_detail;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) { return nil; }
    [self buildViews];
    self.separatorInset = UIEdgeInsetsMake(0, IMEntryCellTextLeading, 0, 0);
    return self;
}

/// 分割线起点 = 文字左缘（槽左缘 + 40 + 12），与下方成员 / 例外行同一条线。
/// 左边距跟 contentView.layoutMarginsGuide（与头像同一 guide；insetGrouped 下实测 20，故文字左缘 72 而非规格写的 68）。
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat x = self.contentView.layoutMargins.left + IMEntryCellSlotWidth + IMTheme.space3;
    if (fabs(self.separatorInset.left - x) > 0.5) { self.separatorInset = UIEdgeInsetsMake(0, x, 0, 0); }
}

- (UIView *)slotView { return _slot; }
- (UIView *)iconView { return _circle.hidden ? (UIView *)_symbol : _circle; }
- (UILabel *)titleLabel { return _title; }
- (UILabel *)detailLabel { return _detail; }

- (void)buildViews {
    _slot = [UIView new];
    _slot.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_slot];

    _symbol = [UIImageView new];
    _symbol.translatesAutoresizingMaskIntoConstraints = NO;
    _symbol.contentMode = UIViewContentModeCenter;
    [_slot addSubview:_symbol];

    _circle = [UIView new];
    _circle.translatesAutoresizingMaskIntoConstraints = NO;
    _circle.layer.cornerRadius = kCircleSize / 2;
    _circle.layer.masksToBounds = YES;
    _circle.hidden = YES;
    [_slot addSubview:_circle];
    UIImageView *plus = [UIImageView new];
    plus.translatesAutoresizingMaskIntoConstraints = NO;
    plus.contentMode = UIViewContentModeCenter;
    plus.tintColor = UIColor.whiteColor;
    plus.image = [UIImage systemImageNamed:@"plus" withConfiguration:
                  [UIImageSymbolConfiguration configurationWithPointSize:kPlusSize weight:UIImageSymbolWeightSemibold]];
    [_circle addSubview:plus];

    _title = [UILabel new];
    _title.font = [UIFont systemFontOfSize:16];
    _detail = [UILabel new];
    _detail.numberOfLines = 0;
    _detail.hidden = YES;
    UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[_title, _detail]];
    texts.axis = UILayoutConstraintAxisVertical;
    texts.spacing = 4;
    texts.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:texts];

    UILayoutGuide *g = self.contentView.layoutMarginsGuide;
    NSLayoutConstraint *minH = [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:IMEntryCellMinHeight];
    minH.priority = UILayoutPriorityRequired - 1; // 外部定高（满员提示）时让位，不报约束冲突
    [NSLayoutConstraint activateConstraints:@[
        [_slot.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [_slot.widthAnchor constraintEqualToConstant:IMEntryCellSlotWidth],
        [_slot.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_slot.heightAnchor constraintEqualToConstant:IMEntryCellSlotWidth],
        [_symbol.centerXAnchor constraintEqualToAnchor:_slot.centerXAnchor],
        [_symbol.centerYAnchor constraintEqualToAnchor:_slot.centerYAnchor],
        [_circle.centerXAnchor constraintEqualToAnchor:_slot.centerXAnchor],
        [_circle.centerYAnchor constraintEqualToAnchor:_slot.centerYAnchor],
        [_circle.widthAnchor constraintEqualToConstant:kCircleSize],
        [_circle.heightAnchor constraintEqualToConstant:kCircleSize],
        [plus.centerXAnchor constraintEqualToAnchor:_circle.centerXAnchor],
        [plus.centerYAnchor constraintEqualToAnchor:_circle.centerYAnchor],
        [texts.leadingAnchor constraintEqualToAnchor:_slot.trailingAnchor constant:IMTheme.space3],
        [texts.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [texts.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [texts.topAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.topAnchor constant:8],
        [self.contentView.bottomAnchor constraintGreaterThanOrEqualToAnchor:texts.bottomAnchor constant:8],
        minH,
    ]];
}

- (void)resetState {
    _detail.attributedText = nil;
    _detail.hidden = YES;
    self.accessoryType = UITableViewCellAccessoryNone;
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
}

- (void)configureWithSymbol:(NSString *)symbolName title:(NSString *)title
                 titleColor:(UIColor *)titleColor iconTint:(UIColor *)iconTint disclosure:(BOOL)disclosure {
    [self resetState];
    _circle.hidden = YES;
    _symbol.hidden = NO;
    _symbol.image = [UIImage systemImageNamed:symbolName withConfiguration:
                     [UIImageSymbolConfiguration configurationWithPointSize:kSymbolSize weight:UIImageSymbolWeightRegular]];
    _symbol.tintColor = iconTint ?: IMTheme.accent;
    _title.text = title;
    _title.textColor = titleColor ?: IMTheme.accent;
    self.accessoryType = disclosure ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
}

- (void)configureAddCircleWithTitle:(NSString *)title {
    [self resetState];
    _symbol.hidden = YES;
    _circle.hidden = NO;
    _circle.backgroundColor = IMTheme.accent; // 草图 --app-accent：随外观页主题色
    _title.text = title;
    _title.textColor = IMTheme.accent;
}

- (void)setDetailAttributedText:(NSAttributedString *)text {
    _detail.attributedText = text;
    _detail.textColor = IMTheme.textSecondary;
    _detail.hidden = text.length == 0;
}

@end
