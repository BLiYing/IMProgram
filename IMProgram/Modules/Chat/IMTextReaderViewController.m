//  IMTextReaderViewController.m

#import "IMTextReaderViewController.h"
#import "IMTheme.h"
#import "IMBubbleCell.h" // 复用 charCountLabelForText: / attributedContent:（字数标签 + @高亮唯一入口）
#import "UIViewController+IMToast.h"

@implementation IMTextReaderViewController {
    NSString              *_text;
    NSArray<NSString *>   *_mentionNames; // @昵称 高亮名单（nil=不高亮）
    UITextView            *_textView;
    NSInteger              _fontStep; // 字号档：-1 / 0 / 1 / 2 / 3（相对基准字号）
    UIButton              *_smaller;
    UIButton              *_bigger;
}

+ (instancetype)readerWithText:(NSString *)text mentionNames:(NSArray<NSString *> *)mentionNames {
    IMTextReaderViewController *vc = [IMTextReaderViewController new];
    vc->_text = [text copy] ?: @"";
    vc->_mentionNames = [mentionNames copy];
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    return vc;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = IMTheme.pageBackground;

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    // 顶栏：左 关闭；中 标题「全文 · 约N字」；右 A−／A＋／复制。底部一条分隔线。
    UIView *bar = [UIView new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = IMTheme.surface;
    [self.view addSubview:bar];

    UIView *sep = [UIView new];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    sep.backgroundColor = IMTheme.separator;
    [bar addSubview:sep];

    UIButton *close = [self barButtonWithSymbol:@"xmark" title:nil];
    [close addTarget:self action:@selector(dismissSelf) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:close];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    title.textColor = IMTheme.textPrimary;
    title.text = [NSString stringWithFormat:@"全文 · %@", [IMBubbleCell charCountLabelForText:_text]];
    [bar addSubview:title];

    UIButton *copy = [self barButtonWithSymbol:@"doc.on.doc" title:nil];
    [copy addTarget:self action:@selector(copyAll) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:copy];

    _bigger = [self barButtonWithSymbol:nil title:@"A＋"];
    [_bigger addTarget:self action:@selector(fontBigger) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:_bigger];

    _smaller = [self barButtonWithSymbol:nil title:@"A−"];
    [_smaller addTarget:self action:@selector(fontSmaller) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:_smaller];

    _textView = [UITextView new];
    _textView.translatesAutoresizingMaskIntoConstraints = NO;
    _textView.editable = NO;
    _textView.selectable = YES;              // 可选中复制
    _textView.backgroundColor = UIColor.clearColor;
    _textView.textColor = IMTheme.textPrimary;
    _textView.textContainerInset = UIEdgeInsetsMake(16, 14, 24, 14);
    _textView.alwaysBounceVertical = YES;
    [self applyFont]; // 用富文本承载正文（含 @高亮）
    [self.view addSubview:_textView];

    [NSLayoutConstraint activateConstraints:@[
        [bar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:safe.topAnchor constant:48],

        [sep.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [sep.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [sep.heightAnchor constraintEqualToConstant:0.5],

        [close.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:12],
        [close.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor constant:-6],
        [close.heightAnchor constraintEqualToConstant:36],

        [title.centerXAnchor constraintEqualToAnchor:bar.centerXAnchor],
        [title.centerYAnchor constraintEqualToAnchor:close.centerYAnchor],

        [copy.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-12],
        [copy.centerYAnchor constraintEqualToAnchor:close.centerYAnchor],
        [copy.heightAnchor constraintEqualToConstant:36],

        [_bigger.trailingAnchor constraintEqualToAnchor:copy.leadingAnchor constant:-8],
        [_bigger.centerYAnchor constraintEqualToAnchor:close.centerYAnchor],
        [_bigger.heightAnchor constraintEqualToConstant:36],

        [_smaller.trailingAnchor constraintEqualToAnchor:_bigger.leadingAnchor constant:-4],
        [_smaller.centerYAnchor constraintEqualToAnchor:close.centerYAnchor],
        [_smaller.heightAnchor constraintEqualToConstant:36],

        [_textView.topAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [_textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (UIButton *)barButtonWithSymbol:(NSString *)symbol title:(NSString *)title {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.tintColor = IMTheme.textPrimary;
    if (symbol) {
        UIImage *img = [UIImage systemImageNamed:symbol
                              withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightRegular]];
        [b setImage:img forState:UIControlStateNormal];
    } else {
        [b setTitle:title forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        [b setTitleColor:IMTheme.textPrimary forState:UIControlStateNormal];
        [b setTitleColor:IMTheme.textTertiary forState:UIControlStateDisabled];
    }
    [b setContentEdgeInsets:UIEdgeInsetsMake(0, 6, 0, 6)];
    return b;
}

/// 阅读器字号 = 聊天正文字号 + 档位；档位越界时置灰对应按钮。
/// 用富文本承载正文，以便 @昵称 高亮随字号一起重建（改字号即重算 attributedText）。
- (void)applyFont {
    CGFloat size = IMTheme.chatFontSize + (CGFloat)_fontStep;
    NSDictionary *base = @{ NSFontAttributeName: [UIFont systemFontOfSize:size],
                            NSForegroundColorAttributeName: IMTheme.textPrimary };
    _textView.attributedText = [IMBubbleCell attributedContent:_text base:base mentionColor:IMTheme.accent names:_mentionNames];
    _smaller.enabled = _fontStep > -1;
    _bigger.enabled = _fontStep < 3;
}

- (void)fontBigger  { if (_fontStep < 3)  { _fontStep++; [self applyFont]; } }
- (void)fontSmaller { if (_fontStep > -1) { _fontStep--; [self applyFont]; } }

- (void)copyAll {
    UIPasteboard.generalPasteboard.string = _text ?: @"";
    [self im_showToast:@"已复制全文"];
}

- (void)dismissSelf { [self dismissViewControllerAnimated:YES completion:nil]; }

@end
