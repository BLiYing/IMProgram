//  IMGroupTextViewController.m

#import "IMGroupTextViewController.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"

@interface IMGroupTextViewController ()
@property (nonatomic, copy) NSString *headline;
@property (nonatomic, copy, nullable) NSString *subline;
@property (nonatomic, copy) NSString *body;
@end

@implementation IMGroupTextViewController

+ (void)presentFrom:(UIViewController *)host
              title:(NSString *)title
           subtitle:(nullable NSString *)subtitle
               body:(NSString *)body {
    IMGroupTextViewController *vc = [IMGroupTextViewController new];
    vc.headline = title ?: @"";
    vc.subline = subtitle;
    vc.body = body ?: @"";
    vc.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = vc.sheetPresentationController;
        sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                          UISheetPresentationControllerDetent.largeDetent];
        sheet.prefersGrabberVisible = YES;
        sheet.preferredCornerRadius = 20;
    }
    [host presentViewController:vc animated:YES completion:nil];
}

+ (nullable NSString *)announceSubtitleForMillis:(int64_t)ms {
    if (ms <= 0) { return nil; }
    static NSDateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [NSDateFormatter new];
        f.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
        f.dateFormat = @"M月d日 HH:mm";
    });
    NSString *s = [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)ms / 1000.0]];
    return [s stringByAppendingString:@" 发布"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = IMTheme.groupedBackground;

    // 顶部：标题 + 关闭
    UILabel *title = [UILabel new];
    title.text = self.headline;
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    title.textColor = IMTheme.textPrimary;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    close.tintColor = IMTheme.textTertiary;
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];

    // 副标题（发布者·时间），简介为 nil 时不占位
    UILabel *sub = [UILabel new];
    sub.text = self.subline ?: @"";
    sub.hidden = (self.subline.length == 0);
    sub.font = [UIFont systemFontOfSize:12];
    sub.textColor = IMTheme.textSecondary;
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:sub];

    // 正文：只读、可滚动、可选中复制
    UITextView *text = [UITextView new];
    text.editable = NO;
    text.scrollEnabled = YES;
    text.backgroundColor = UIColor.clearColor;
    text.textContainerInset = UIEdgeInsetsMake(0, 0, 0, 0);
    text.textContainer.lineFragmentPadding = 0;
    text.font = [UIFont systemFontOfSize:15];
    text.textColor = IMTheme.textPrimary;
    text.text = self.body;
    text.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:text];

    // 复制按钮
    UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
    [copy setTitle:@"复制全文" forState:UIControlStateNormal];
    copy.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [copy setTitleColor:IMTheme.accent forState:UIControlStateNormal];
    copy.translatesAutoresizingMaskIntoConstraints = NO;
    [copy addTarget:self action:@selector(copyTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:copy];

    UIView *hairline = [UIView new];
    hairline.backgroundColor = IMTheme.separator;
    hairline.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:hairline];

    UILayoutGuide *g = self.view.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:22],
        [title.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:close.leadingAnchor constant:-8],

        [close.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [close.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [close.widthAnchor constraintEqualToConstant:28],
        [close.heightAnchor constraintEqualToConstant:28],

        [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],
        [sub.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [sub.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],

        [text.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:14],
        [text.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [text.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [text.bottomAnchor constraintEqualToAnchor:hairline.topAnchor constant:-12],

        [hairline.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [hairline.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [hairline.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
        [hairline.bottomAnchor constraintEqualToAnchor:copy.topAnchor constant:-6],

        [copy.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [copy.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
        [copy.heightAnchor constraintEqualToConstant:40],
    ]];
}

- (void)copyTapped {
    UIPasteboard.generalPasteboard.string = self.body;
    [self im_showToast:@"已复制"];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
