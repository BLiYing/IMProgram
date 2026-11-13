//  IMLoginPhoneFields.m

#import "IMLoginPhoneFields.h"
#import "IMPhoneAuth.h"
#import "IMLocalization.h"
#import "IMTheme.h"

static CGFloat const kIMLoginCountryWidth = 76;
static CGFloat const kIMLoginFieldHeight = 44;

@interface IMLoginPhoneFields ()
@property (nonatomic, strong, readwrite) UIButton *countryButton;
@property (nonatomic, strong, readwrite) UITextField *phoneField;
@property (nonatomic, strong, readwrite) IMSMSCodeField *codeField;
@end

void IMPresentSMSRegionPicker(UIViewController *host, IMLoginConfig *config, UIView *sourceView, void (^onPick)(NSString *)) {
    if (!IMLoginShowsRegionPicker(config)) { return; }
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:IMLocalized(@"login.region.title") message:nil
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    for (IMSMSRegion *r in config.smsRegions) {
        [ac addAction:[UIAlertAction actionWithTitle:IMSMSRegionTitle(r, IMLocalization.shared.locale) style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a) { onPick(r.code); }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    ac.popoverPresentationController.sourceView = sourceView;
    [host presentViewController:ac animated:YES completion:nil];
}

@implementation IMLoginPhoneFields

- (instancetype)initWithIdentifierPrefix:(NSString *)prefix {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _countryCode = IMPhoneDefaultCountryCode;
        [self buildWithPrefix:prefix];
        [self refreshCountry];
        [self syncClock];
    }
    return self;
}

- (void)buildWithPrefix:(NSString *)prefix {
    UIButton *cc = [UIButton buttonWithType:UIButtonTypeSystem];
    cc.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    cc.layer.cornerRadius = 6;
    cc.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    cc.layer.borderColor = UIColor.separatorColor.CGColor;
    cc.titleLabel.font = [UIFont systemFontOfSize:17];
    [cc setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    [cc setTitleColor:UIColor.labelColor forState:UIControlStateDisabled];
    cc.accessibilityIdentifier = [prefix stringByAppendingString:@".country_code"];
    [cc addTarget:self action:@selector(regionTapped) forControlEvents:UIControlEventTouchUpInside];
    self.countryButton = cc;

    UITextField *phone = [UITextField new];
    phone.borderStyle = UITextBorderStyleRoundedRect;
    phone.placeholder = IMLocalized(@"login.phone.placeholder");
    phone.font = [UIFont systemFontOfSize:17];
    phone.keyboardType = UIKeyboardTypePhonePad;
    phone.textContentType = UITextContentTypeTelephoneNumber;
    phone.accessibilityIdentifier = [prefix stringByAppendingString:@".phone"];
    [phone addTarget:self action:@selector(phoneChanged) forControlEvents:UIControlEventEditingChanged];
    self.phoneField = phone;

    IMSMSCodeField *code = [[IMSMSCodeField alloc] initWithTint:IMTheme.accent];
    code.borderStyle = UITextBorderStyleRoundedRect;
    code.font = [UIFont systemFontOfSize:17];
    code.accessibilityIdentifier = [prefix stringByAppendingString:@".code"];
    code.sendButton.accessibilityIdentifier = [prefix stringByAppendingString:@".send_code"];
    [code addTarget:self action:@selector(edited) forControlEvents:UIControlEventEditingChanged];
    self.codeField = code;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[cc, phone]];
    row.spacing = 8;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[row, code]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [cc.widthAnchor constraintEqualToConstant:kIMLoginCountryWidth],
        [phone.heightAnchor constraintEqualToConstant:kIMLoginFieldHeight],
        [code.heightAnchor constraintEqualToConstant:kIMLoginFieldHeight],
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor], [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor], [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    self.countryButton.layer.borderColor = UIColor.separatorColor.CGColor; // CGColor 不随外观自动切换（UI_COLOR §1）
}

- (void)setCountryCode:(NSString *)countryCode {
    _countryCode = [countryCode copy] ?: IMPhoneDefaultCountryCode;
    [self refreshCountry];
    [self syncClock];
}

- (void)setRegionPickable:(BOOL)regionPickable {
    _regionPickable = regionPickable;
    [self refreshCountry];
}

- (void)refreshCountry {
    [self.countryButton setTitle:[@"+" stringByAppendingString:self.countryCode] forState:UIControlStateNormal];
    self.countryButton.enabled = self.regionPickable;
}

- (NSString *)normalizedPhone { return IMPhoneNationalNumber(self.countryCode, self.phoneField.text); }
- (NSString *)targetKey { return [NSString stringWithFormat:@"%@:%@", self.countryCode, self.normalizedPhone]; }

- (void)regionTapped { if (self.regionPickable && self.onRegionTap) { self.onRegionTap(); } }

- (void)syncClock {
    [self.codeField.clock followTarget:self.targetKey]; // 换号码（或国家码）就清上一个号码的截止时刻
    self.codeField.sendAllowed = self.normalizedPhone.length > 0;
}

- (void)phoneChanged {
    [self syncClock];
    [self edited];
}

- (void)edited { if (self.onEdit) { self.onEdit(); } }

- (void)clearInputs {
    self.phoneField.text = @"";
    self.codeField.text = @"";
    [self syncClock];
}

@end
