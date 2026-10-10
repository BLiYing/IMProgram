//  IMChatInputTextView.m

#import "IMChatInputTextView.h"

const CGFloat kIMChatInputMinHeight = 36;
const NSInteger kIMChatInputMaxLines = 5;

static const CGFloat kInsetV = 8;
static const CGFloat kInsetLeft = 12;
static const CGFloat kInsetRight = 38; // 右侧给内嵌的 😀 按钮让位

@implementation IMChatInputTextView {
    UILabel *_placeholderLabel;
    CGFloat _lastHeight;
    CGFloat _lastWidth;
}

- (instancetype)initWithFrame:(CGRect)frame textContainer:(NSTextContainer *)textContainer {
    self = [super initWithFrame:frame textContainer:textContainer];
    if (self) {
        self.textContainerInset = UIEdgeInsetsMake(kInsetV, kInsetLeft, kInsetV, kInsetRight);
        self.textContainer.lineFragmentPadding = 0;
        self.scrollEnabled = NO;            // 未封顶时靠自增高显示全部；封顶后再打开
        self.showsVerticalScrollIndicator = NO;
        self.backgroundColor = UIColor.clearColor;
        self.returnKeyType = UIReturnKeySend;
        // 不开 enablesReturnKeyAutomatically：只有待发粘贴图（文本为空）时回车也要能发送
        _lastHeight = kIMChatInputMinHeight;

        _placeholderLabel = [UILabel new];
        _placeholderLabel.textColor = UIColor.placeholderTextColor;
        _placeholderLabel.userInteractionEnabled = NO;
        _placeholderLabel.numberOfLines = 1;
        [self addSubview:_placeholderLabel];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textChanged)
                                                     name:UITextViewTextDidChangeNotification object:self];
    }
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

#pragma mark - 占位 / 状态

- (void)setPlaceholder:(NSString *)placeholder {
    _placeholder = [placeholder copy];
    _placeholderLabel.text = placeholder;
    [self setNeedsLayout];
}

- (BOOL)isEnabled { return self.editable; }
- (void)setEnabled:(BOOL)enabled {
    self.editable = enabled;
    self.selectable = enabled;
}

- (void)setFont:(UIFont *)font {
    [super setFont:font];
    _placeholderLabel.font = font;
    [self setNeedsLayout];
    [self updateHeight];
}

- (void)setText:(NSString *)text {
    [super setText:text];
    [self textChanged];   // 程序化改 text 不发通知，这里补上
}

- (void)textChanged {
    _placeholderLabel.hidden = self.text.length > 0;
    [self updateHeight];
}

#pragma mark - 高度

- (CGFloat)maxHeight {
    return ceil(self.font.lineHeight * kIMChatInputMaxLines) + kInsetV * 2;
}

- (void)updateHeight {
    CGFloat w = self.bounds.size.width;
    if (w <= 0) { return; }   // 尚未布局：layoutSubviews 里宽度确定后再算
    CGFloat fit = round([self sizeThatFits:CGSizeMake(w, CGFLOAT_MAX)].height); // round 而非 ceil：单行 36.3 取 ceil 会变 37，空/非空之间抖动
    CGFloat h = MIN(MAX(fit, kIMChatInputMinHeight), [self maxHeight]);
    BOOL capped = fit > h;
    if (self.scrollEnabled != capped) {
        self.scrollEnabled = capped;
        if (capped) { [self scrollRangeToVisible:self.selectedRange]; }
    }
    if (fabs(h - _lastHeight) < 0.5) { return; }
    _lastHeight = h;
    if (self.onHeightChange) { self.onHeightChange(h); }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize s = [_placeholderLabel sizeThatFits:CGSizeMake(self.bounds.size.width - kInsetLeft - kInsetRight, CGFLOAT_MAX)];
    _placeholderLabel.frame = CGRectMake(kInsetLeft, kInsetV, MAX(0, self.bounds.size.width - kInsetLeft - kInsetRight), s.height);
    if (fabs(self.bounds.size.width - _lastWidth) > 0.5) {
        _lastWidth = self.bounds.size.width;
        [self updateHeight];
    }
}

#pragma mark - 粘贴图片

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(paste:) && UIPasteboard.generalPasteboard.hasImages) { return YES; }
    return [super canPerformAction:action withSender:sender];
}

- (void)paste:(id)sender {
    if (UIPasteboard.generalPasteboard.hasImages) {
        UIImage *img = UIPasteboard.generalPasteboard.image;
        if (img && self.onPasteImage) { self.onPasteImage(img); return; }
    }
    [super paste:sender];
}

@end
