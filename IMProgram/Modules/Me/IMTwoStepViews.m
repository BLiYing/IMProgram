//  IMTwoStepViews.m

#import "IMTwoStepViews.h"
#import "IMQRImage.h"
#import "IMTwoStep.h"

@implementation IMTwoStepEyeButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:CGRectMake(0, 0, 34, 34)];
    if (self) {
        self.tintColor = UIColor.secondaryLabelColor;
        [self setImage:[UIImage systemImageNamed:@"eye.slash.fill"] forState:UIControlStateNormal]; // 默认密文
        [self setImage:[UIImage systemImageNamed:@"eye.fill"] forState:UIControlStateSelected];
        self.accessibilityIdentifier = @"twostep.eye";
        [self addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)toggle {
    self.selected = !self.selected;
    UITextField *f = self.field;
    BOOL wasFirst = f.isFirstResponder;
    if (wasFirst) { [f resignFirstResponder]; }
    f.secureTextEntry = !self.selected;
    if (wasFirst) { [f becomeFirstResponder]; }
}

@end

static UITextField *IMTwoStepBaseField(NSString *placeholder) {
    UITextField *f = [UITextField new];
    f.translatesAutoresizingMaskIntoConstraints = NO;
    f.placeholder = placeholder;
    f.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; // 17pt
    f.textColor = UIColor.labelColor;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.spellCheckingType = UITextSpellCheckingTypeNo;
    f.smartQuotesType = UITextSmartQuotesTypeNo;
    f.smartDashesType = UITextSmartDashesTypeNo;
    return f;
}

UITextField *IMTwoStepMakePasswordField(NSString *placeholder) {
    UITextField *f = IMTwoStepBaseField(placeholder);
    f.secureTextEntry = YES;
    f.returnKeyType = UIReturnKeyNext;
    f.accessibilityIdentifier = @"twostep.password";
    IMTwoStepEyeButton *eye = [[IMTwoStepEyeButton alloc] initWithFrame:CGRectZero];
    eye.field = f;
    f.rightView = eye;
    f.rightViewMode = UITextFieldViewModeAlways;
    return f;
}

UITextField *IMTwoStepMakeCodeField(NSString *accessibilityLabel) {
    UITextField *f = IMTwoStepBaseField(nil);
    UIFont *font = [UIFont monospacedSystemFontOfSize:28 weight:UIFontWeightSemibold];
    NSMutableParagraphStyle *para = [NSMutableParagraphStyle new];
    para.alignment = NSTextAlignmentCenter;
    f.defaultTextAttributes = @{ NSFontAttributeName: font, NSKernAttributeName: @8,
                                 NSForegroundColorAttributeName: UIColor.labelColor, NSParagraphStyleAttributeName: para };
    f.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"······"
        attributes:@{ NSFontAttributeName: font, NSKernAttributeName: @8,
                      NSForegroundColorAttributeName: UIColor.tertiaryLabelColor, NSParagraphStyleAttributeName: para }];
    f.textAlignment = NSTextAlignmentCenter;
    f.keyboardType = UIKeyboardTypeNumberPad;
    f.textContentType = UITextContentTypeOneTimeCode;
    f.accessibilityLabel = accessibilityLabel;
    f.accessibilityIdentifier = @"twostep.code";
    return f;
}

UITextField *IMTwoStepMakeRecoveryField(NSString *placeholder) {
    UITextField *f = IMTwoStepBaseField(placeholder);
    f.font = [UIFont monospacedSystemFontOfSize:17 weight:UIFontWeightRegular];
    f.keyboardType = UIKeyboardTypeASCIICapable;
    f.returnKeyType = UIReturnKeyDone;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.accessibilityIdentifier = @"twostep.recovery";
    return f;
}

BOOL IMTwoStepHandleRecoveryPaste(UITextField *field, NSRange range, NSString *replacement) {
    if (field.markedTextRange != nil) { return NO; } // 输入法组词期间不改写
    if (!IMTwoStepEditLooksLikePaste(field.text, range, replacement)) { return NO; }
    NSString *code = IMTwoStepExtractRecoveryCode(replacement);
    if (!code) { return NO; }
    field.text = IMTwoStepFormatRecovery(code);
    [field sendActionsForControlEvents:UIControlEventEditingChanged];
    return YES;
}

UIView *IMTwoStepFieldRow(UITextField *field, CGFloat minHeight) {
    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [field.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
        [field.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16],
        [field.topAnchor constraintEqualToAnchor:row.topAnchor],
        [field.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:minHeight],
    ]];
    return row;
}

UIView *IMTwoStepCenteredTextRow(NSString *text, UIColor *color) {
    UILabel *l = [UILabel new];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    l.text = text;
    l.textColor = color;
    l.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    l.textAlignment = NSTextAlignmentCenter;
    l.numberOfLines = 0;
    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:l];
    [NSLayoutConstraint activateConstraints:@[
        [l.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
        [l.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16],
        [l.topAnchor constraintEqualToAnchor:row.topAnchor constant:11],
        [l.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-11],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:44],
    ]];
    return row;
}

UIView *IMTwoStepValueRow(NSString *title, NSString *value, UIColor *valueColor, BOOL showsChevron) {
    UILabel *t = [UILabel new];
    t.translatesAutoresizingMaskIntoConstraints = NO;
    t.text = title;
    t.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    t.textColor = UIColor.labelColor;
    UILabel *v = [UILabel new];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    v.text = value;
    v.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    v.textColor = valueColor;
    v.textAlignment = NSTextAlignmentRight;
    [v setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:t];
    [row addSubview:v];
    CGFloat trailing = showsChevron ? -40 : -16; // 给系统 disclosure 指示留位
    [NSLayoutConstraint activateConstraints:@[
        [t.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
        [t.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [v.leadingAnchor constraintGreaterThanOrEqualToAnchor:t.trailingAnchor constant:8],
        [v.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:trailing],
        [v.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:44],
    ]];
    return row;
}

UIView *IMTwoStepHeroView(NSString *title, NSString *subtitle) {
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.shield.fill"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:64 weight:UIImageSymbolWeightRegular]]];
    icon.tintColor = UIColor.systemBlueColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.isAccessibilityElement = NO;
    UILabel *t = [UILabel new];
    t.text = title;
    t.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold]; // .title3
    t.textColor = UIColor.labelColor;
    t.textAlignment = NSTextAlignmentCenter;
    t.numberOfLines = 0;
    NSMutableArray *views = [NSMutableArray arrayWithObjects:icon, t, nil];
    if (subtitle.length > 0) {
        UILabel *s = [UILabel new];
        s.text = subtitle;
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
        [stack.bottomAnchor constraintEqualToAnchor:host.bottomAnchor constant:-8],
    ]];
    return host;
}

UIView *IMTwoStepQRCard(NSString *content) {
    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.whiteColor; // 深色模式也保持白底，否则扫不出
    card.layer.cornerRadius = 12;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.masksToBounds = YES;
    card.accessibilityIdentifier = @"twostep.qr";
    UIImageView *iv = [UIImageView new];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.backgroundColor = UIColor.whiteColor;
    iv.image = content.length > 0 ? [IMQRImage imageForString:content size:176] : nil;
    iv.isAccessibilityElement = NO;
    [card addSubview:iv];
    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:card];
    [NSLayoutConstraint activateConstraints:@[
        [card.widthAnchor constraintEqualToConstant:200], [card.heightAnchor constraintEqualToConstant:200],
        [card.centerXAnchor constraintEqualToAnchor:row.centerXAnchor],
        [card.topAnchor constraintEqualToAnchor:row.topAnchor constant:16],
        [card.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-16],
        [iv.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [iv.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [iv.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
        [iv.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12],
    ]];
    return row;
}

UIView *IMTwoStepRecoveryGrid(NSArray<NSString *> *codes) {
    UIStackView *rows = [UIStackView new];
    rows.axis = UILayoutConstraintAxisVertical;
    rows.spacing = 12;
    rows.translatesAutoresizingMaskIntoConstraints = NO;
    UIFont *mono = [UIFont monospacedSystemFontOfSize:17 weight:UIFontWeightRegular];
    for (NSUInteger i = 0; i < codes.count; i += 2) {
        UIStackView *pair = [UIStackView new];
        pair.distribution = UIStackViewDistributionFillEqually;
        for (NSUInteger j = i; j < MIN(i + 2, codes.count); j++) {
            UILabel *l = [UILabel new];
            l.text = codes[j];
            l.font = mono;
            l.textColor = UIColor.labelColor;
            l.adjustsFontSizeToFitWidth = YES;
            l.minimumScaleFactor = 0.8;
            [pair addArrangedSubview:l];
        }
        if (codes.count - i == 1) { [pair addArrangedSubview:[UIView new]]; }
        [rows addArrangedSubview:pair];
    }
    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.accessibilityIdentifier = @"twostep.codes";
    [card addSubview:rows];
    [NSLayoutConstraint activateConstraints:@[
        [rows.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [rows.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [rows.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [rows.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
    ]];
    return card;
}

@implementation IMTwoStepCheckRow {
    UIImageView *_box;
}

- (instancetype)initWithText:(NSString *)text {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _box = [UIImageView new];
        _box.translatesAutoresizingMaskIntoConstraints = NO;
        _box.contentMode = UIViewContentModeScaleAspectFit;
        UILabel *l = [UILabel new];
        l.translatesAutoresizingMaskIntoConstraints = NO;
        l.text = text;
        l.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        l.textColor = UIColor.labelColor;
        l.numberOfLines = 0;
        [self addSubview:_box];
        [self addSubview:l];
        [NSLayoutConstraint activateConstraints:@[
            [_box.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [_box.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_box.widthAnchor constraintEqualToConstant:24], [_box.heightAnchor constraintEqualToConstant:24],
            [l.leadingAnchor constraintEqualToAnchor:_box.trailingAnchor constant:12],
            [l.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [l.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
            [l.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        ]];
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = text;
        self.accessibilityIdentifier = @"twostep.saved_check";
        [self applyChecked];
    }
    return self;
}

- (void)setChecked:(BOOL)checked {
    _checked = checked;
    [self applyChecked];
}

- (void)applyChecked {
    _box.image = [UIImage systemImageNamed:_checked ? @"checkmark.circle.fill" : @"circle"];
    _box.tintColor = _checked ? UIColor.systemBlueColor : UIColor.tertiaryLabelColor;
    self.accessibilityTraits = _checked ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
}

@end
