//  IMTextReaderViewController.m

#import "IMTextReaderViewController.h"
#import "IMTheme.h"
#import "IMBubbleCell.h" // 复用 charCountLabelForText: / attributedContent:（字数标签 + @高亮唯一入口）
#import "UIViewController+IMToast.h"

@implementation IMTextReaderViewController {
    NSString                              *_text;
    NSDictionary<NSString *, NSString *>  *_mentions; // @昵称 → uid（nil=不高亮）
    NSArray<IMMentionSpan *>              *_spans;    // @ 片段（优先；不查成员表，见 IMBubbleCell 的片段版）
    UITextView                            *_textView;
    NSInteger                              _fontStep; // 字号档：-1 / 0 / 1 / 2 / 3（相对基准字号）
    UIButton                              *_smaller;
    UIButton                              *_bigger;
}

+ (instancetype)readerWithText:(NSString *)text mentions:(NSDictionary<NSString *, NSString *> *)mentions spans:(NSArray<IMMentionSpan *> *)spans {
    IMTextReaderViewController *vc = [IMTextReaderViewController new];
    vc->_text = [text copy] ?: @"";
    vc->_mentions = [mentions copy];
    vc->_spans = [spans copy];
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
    // 点 @昵称 → 跳资料：TextKit 反查 tap 落点的字符属性（不走已弃用的 link 代理，全版本可用）。
    [_textView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTextTap:)]];
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
    // 旧式 UIButton（setTitle:forState: 系列，未用 UIButtonConfiguration）→ contentEdgeInsets 仍生效；
    // iOS15 起该属性被标记弃用（仅在 configuration 按钮上被忽略），此处按住弃用告警即可。
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [b setContentEdgeInsets:UIEdgeInsetsMake(0, 6, 0, 6)];
#pragma clang diagnostic pop
    return b;
}

/// 阅读器字号 = 聊天正文字号 + 档位；档位越界时置灰对应按钮。
/// 用富文本承载正文，以便 @昵称 高亮随字号一起重建（改字号即重算 attributedText）。
- (void)applyFont {
    CGFloat size = IMTheme.chatFontSize + (CGFloat)_fontStep;
    NSDictionary *base = @{ NSFontAttributeName: [UIFont systemFontOfSize:size],
                            NSForegroundColorAttributeName: IMTheme.textPrimary };
    _textView.attributedText = [IMBubbleCell attributedContent:_text base:base mentionColor:IMTheme.accent mentions:_mentions spans:_spans];
    _smaller.enabled = _fontStep > -1;
    _bigger.enabled = _fontStep < 3;
}

/// TextKit 反查：tap 落在挂了 IMMentionUIDAttributeName 的 token 上 → dismiss 自己并回调 uid。
- (void)handleTextTap:(UITapGestureRecognizer *)gr {
    if (_textView.attributedText.length == 0) { return; }
    CGPoint loc = [gr locationInView:_textView];
    loc.x -= _textView.textContainerInset.left;
    loc.y -= _textView.textContainerInset.top;
    NSLayoutManager *lm = _textView.layoutManager;
    NSTextContainer *tc = _textView.textContainer;
    NSUInteger glyphIdx = [lm glyphIndexForPoint:loc inTextContainer:tc];
    CGRect glyphRect = [lm boundingRectForGlyphRange:NSMakeRange(glyphIdx, 1) inTextContainer:tc];
    if (!CGRectContainsPoint(glyphRect, loc)) { return; } // 点在字外
    NSUInteger charIdx = [lm characterIndexForGlyphAtIndex:glyphIdx];
    if (charIdx >= _textView.attributedText.length) { return; }
    NSString *uid = [_textView.attributedText attribute:IMMentionUIDAttributeName atIndex:charIdx effectiveRange:NULL];
    if (uid.length == 0) { return; }
    void (^cb)(NSString *) = self.onTapMentionUID;
    [self dismissViewControllerAnimated:YES completion:^{ if (cb) { cb(uid); } }];
}

- (void)fontBigger  { if (_fontStep < 3)  { _fontStep++; [self applyFont]; } }
- (void)fontSmaller { if (_fontStep > -1) { _fontStep--; [self applyFont]; } }

- (void)copyAll {
    UIPasteboard.generalPasteboard.string = _text ?: @"";
    [self im_showToast:@"已复制全文"];
}

- (void)dismissSelf { [self dismissViewControllerAnimated:YES completion:nil]; }

@end
