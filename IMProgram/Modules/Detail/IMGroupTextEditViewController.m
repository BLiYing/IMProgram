//  IMGroupTextEditViewController.m

#import "IMGroupTextEditViewController.h"
#import "IMTheme.h"

@interface IMGroupTextEditViewController () <UITextViewDelegate>
@property (nonatomic, copy) NSString *initialText;
@property (nonatomic, copy) NSString *placeholder;
@property (nonatomic, assign) NSInteger maxChars;
@property (nonatomic, copy) NSString *commitTitle;
@property (nonatomic, assign) BOOL allowRetract;
@property (nonatomic, copy, nullable) NSString *footerText;
@property (nonatomic, copy) void (^onCommit)(NSString *text);

@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, strong) UILabel *counter;
@end

@implementation IMGroupTextEditViewController

+ (void)presentFrom:(UIViewController *)host
              title:(NSString *)title
               text:(NSString *)text
        placeholder:(NSString *)placeholder
           maxChars:(NSInteger)maxChars
        commitTitle:(NSString *)commitTitle
       allowRetract:(BOOL)allowRetract
             footer:(nullable NSString *)footer
           onCommit:(void (^)(NSString *))onCommit {
    IMGroupTextEditViewController *vc = [IMGroupTextEditViewController new];
    vc.title = title;
    vc.initialText = text ?: @"";
    vc.placeholder = placeholder ?: @"";
    vc.maxChars = maxChars;
    vc.commitTitle = commitTitle ?: @"保存";
    vc.allowRetract = allowRetract;
    vc.footerText = footer;
    vc.onCommit = onCommit;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [host presentViewController:nav animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = IMTheme.groupedBackground;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:self.commitTitle style:UIBarButtonItemStyleDone target:self action:@selector(commitTapped)];

    UIView *card = [UIView new];
    card.backgroundColor = IMTheme.cardBackground;
    card.layer.cornerRadius = 10;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:card];

    self.textView = [UITextView new];
    self.textView.backgroundColor = UIColor.clearColor;
    self.textView.font = [UIFont systemFontOfSize:16];
    self.textView.textColor = IMTheme.textPrimary;
    self.textView.text = self.initialText;
    self.textView.delegate = self;
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.textView];

    self.placeholderLabel = [UILabel new];
    self.placeholderLabel.text = self.placeholder;
    self.placeholderLabel.font = [UIFont systemFontOfSize:16];
    self.placeholderLabel.textColor = IMTheme.textTertiary;
    self.placeholderLabel.hidden = self.initialText.length > 0;
    self.placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.placeholderLabel];

    self.counter = [UILabel new];
    self.counter.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.counter.textColor = IMTheme.textSecondary;
    self.counter.textAlignment = NSTextAlignmentRight;
    self.counter.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.counter];

    UILabel *footer = [UILabel new];
    footer.text = self.footerText ?: @"";
    footer.hidden = (self.footerText.length == 0);
    footer.font = [UIFont systemFontOfSize:12];
    footer.textColor = IMTheme.textSecondary;
    footer.numberOfLines = 0;
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:footer];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    NSMutableArray<NSLayoutConstraint *> *cons = [NSMutableArray arrayWithArray:@[
        [card.topAnchor constraintEqualToAnchor:g.topAnchor constant:16],
        [card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [card.heightAnchor constraintEqualToConstant:160],

        [self.textView.topAnchor constraintEqualToAnchor:card.topAnchor constant:6],
        [self.textView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [self.textView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [self.textView.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-6],

        [self.placeholderLabel.topAnchor constraintEqualToAnchor:self.textView.topAnchor constant:8],
        [self.placeholderLabel.leadingAnchor constraintEqualToAnchor:self.textView.leadingAnchor constant:5],
        [self.placeholderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.textView.trailingAnchor],

        [self.counter.topAnchor constraintEqualToAnchor:card.bottomAnchor constant:6],
        [self.counter.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],

        [footer.topAnchor constraintEqualToAnchor:self.counter.bottomAnchor constant:8],
        [footer.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:2],
        [footer.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-2],
    ]];

    // 撤下公告（红色行，发空串）——仅公告且已有内容时显示。
    if (self.allowRetract) {
        UIButton *retract = [UIButton buttonWithType:UIButtonTypeSystem];
        [retract setTitle:@"撤下公告" forState:UIControlStateNormal];
        [retract setTitleColor:IMTheme.danger forState:UIControlStateNormal];
        retract.titleLabel.font = [UIFont systemFontOfSize:16];
        retract.backgroundColor = IMTheme.cardBackground;
        retract.layer.cornerRadius = 10;
        retract.translatesAutoresizingMaskIntoConstraints = NO;
        [retract addTarget:self action:@selector(retractTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:retract];
        [cons addObjectsFromArray:@[
            [retract.topAnchor constraintEqualToAnchor:footer.bottomAnchor constant:20],
            [retract.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
            [retract.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
            [retract.heightAnchor constraintEqualToConstant:48],
        ]];
    }
    [NSLayoutConstraint activateConstraints:cons];

    [self updateCounter];
    [self.textView becomeFirstResponder];
}

- (void)textViewDidChange:(UITextView *)tv {
    // 拼音候选未上屏（markedTextRange 非空）时不截断，否则输入中途被切。
    if (!tv.markedTextRange && (NSInteger)tv.text.length > self.maxChars) {
        NSRange r = [tv.text rangeOfComposedCharacterSequenceAtIndex:self.maxChars];
        tv.text = [tv.text substringToIndex:r.location];
    }
    self.placeholderLabel.hidden = tv.text.length > 0;
    [self updateCounter];
}

- (void)updateCounter {
    self.counter.text = [NSString stringWithFormat:@"%ld/%ld", (long)self.textView.text.length, (long)self.maxChars];
}

- (NSString *)trimmedText {
    return [self.textView.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

- (void)commitTapped {
    NSString *text = [self trimmedText];
    void (^cb)(NSString *) = self.onCommit;
    [self dismissViewControllerAnimated:YES completion:^{ if (cb) { cb(text); } }];
}

- (void)retractTapped {
    void (^cb)(NSString *) = self.onCommit;
    [self dismissViewControllerAnimated:YES completion:^{ if (cb) { cb(@""); } }];
}

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
