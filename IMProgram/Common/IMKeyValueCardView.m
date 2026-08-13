//  IMKeyValueCardView.m

#import "IMKeyValueCardView.h"
#import "IMTheme.h"

@implementation IMKeyValueCardView

+ (UIStackView *)cardWithRows:(NSArray<NSArray *> *)rows {
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.backgroundColor = IMTheme.cardBackground;
    stack.layer.cornerRadius = 12;
    stack.layoutMargins = UIEdgeInsetsMake(2, 14, 2, 14);
    stack.layoutMarginsRelativeArrangement = YES;

    for (NSUInteger i = 0; i < rows.count; i++) {
        NSArray *r = rows[i];
        NSString *key = r.count > 0 ? r[0] : @"";
        NSString *value = r.count > 1 ? r[1] : @"";
        UIColor *valueColor = (r.count > 2 && [r[2] isKindOfClass:UIColor.class]) ? r[2] : IMTheme.textSecondary;
        [stack addArrangedSubview:[self rowWithKey:key value:value valueColor:valueColor showSeparator:(i > 0)]];
    }
    return stack;
}

+ (UIView *)rowWithKey:(NSString *)key value:(NSString *)value valueColor:(UIColor *)valueColor showSeparator:(BOOL)sep {
    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *k = [UILabel new];
    k.text = key;
    k.font = [UIFont systemFontOfSize:14];
    k.textColor = IMTheme.textPrimary;
    k.translatesAutoresizingMaskIntoConstraints = NO;
    [k setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [row addSubview:k];

    UILabel *v = [UILabel new];
    v.text = value;
    v.font = [UIFont systemFontOfSize:13];
    v.textColor = valueColor ?: IMTheme.textSecondary;
    v.textAlignment = NSTextAlignmentRight;
    v.numberOfLines = 0;
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:v];

    NSMutableArray<NSLayoutConstraint *> *cons = [NSMutableArray arrayWithArray:@[
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [k.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [k.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [v.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [v.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [v.leadingAnchor constraintGreaterThanOrEqualToAnchor:k.trailingAnchor constant:12],
        [v.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor constant:9],
        [v.bottomAnchor constraintLessThanOrEqualToAnchor:row.bottomAnchor constant:-9],
    ]];
    if (sep) {
        UIView *line = [UIView new];
        line.backgroundColor = IMTheme.separator;
        line.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:line];
        [cons addObjectsFromArray:@[
            [line.topAnchor constraintEqualToAnchor:row.topAnchor],
            [line.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [line.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [line.heightAnchor constraintEqualToConstant:0.5],
        ]];
    }
    [NSLayoutConstraint activateConstraints:cons];
    return row;
}

@end
