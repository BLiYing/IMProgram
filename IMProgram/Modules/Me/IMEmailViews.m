//  IMEmailViews.m

#import "IMEmailViews.h"

UIView *IMEmailHeroView(NSString *title, BOOL emailStyle, NSString *subtitle, NSString *note) {
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"envelope.fill"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:64 weight:UIImageSymbolWeightRegular]]];
    icon.tintColor = UIColor.systemBlueColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.isAccessibilityElement = NO;
    UILabel *t = [UILabel new];
    t.text = title;
    t.font = emailStyle ? [UIFont systemFontOfSize:17 weight:UIFontWeightRegular] : [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    t.textColor = UIColor.labelColor;
    t.textAlignment = NSTextAlignmentCenter;
    t.numberOfLines = 0;
    t.lineBreakMode = NSLineBreakByCharWrapping; // 长邮箱不撑破布局：按字符换行
    t.accessibilityIdentifier = @"email.hero.title";
    NSMutableArray *views = [NSMutableArray arrayWithObjects:icon, t, nil];
    for (NSString *text in @[subtitle ?: @"", note ?: @""]) {
        if (text.length == 0) { continue; }
        UILabel *s = [UILabel new];
        s.text = text;
        s.font = [UIFont systemFontOfSize:13];
        s.textColor = UIColor.secondaryLabelColor;
        s.textAlignment = NSTextAlignmentCenter;
        s.numberOfLines = 0;
        [views addObject:s];
    }
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:views];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 8;
    [stack setCustomSpacing:12 afterView:icon];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *host = [UIView new];
    [host addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:32],
        [stack.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-32],
        [stack.topAnchor constraintEqualToAnchor:host.topAnchor constant:24],
        [stack.bottomAnchor constraintEqualToAnchor:host.bottomAnchor constant:-16],
    ]];
    return host;
}

UITextField *IMEmailMakeField(NSString *placeholder) {
    UITextField *f = [UITextField new];
    f.translatesAutoresizingMaskIntoConstraints = NO;
    f.placeholder = placeholder;
    f.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; // 17pt
    f.textColor = UIColor.labelColor;
    f.keyboardType = UIKeyboardTypeEmailAddress;
    f.textContentType = UITextContentTypeEmailAddress;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.spellCheckingType = UITextSpellCheckingTypeNo;
    f.smartQuotesType = UITextSmartQuotesTypeNo;
    f.smartDashesType = UITextSmartDashesTypeNo;
    f.returnKeyType = UIReturnKeyNext;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.accessibilityIdentifier = @"email.field";
    return f;
}

UILabel *IMEmailLinkLabel(NSString *text, UIColor *color) {
    UILabel *l = [UILabel new];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    l.text = text;
    l.font = [UIFont systemFontOfSize:15];
    l.textColor = color;
    l.textAlignment = NSTextAlignmentCenter;
    l.numberOfLines = 0;
    return l;
}

UIView *IMEmailLinkRow(UILabel *label) {
    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
        [label.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16],
        [label.topAnchor constraintEqualToAnchor:row.topAnchor constant:10],
        [label.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-10],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:44],
    ]];
    return row;
}
