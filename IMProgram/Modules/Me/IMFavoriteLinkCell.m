//  IMFavoriteLinkCell.m
//  实现见 .h。约束按"顶部 IMLinkRowView"→"原文引用（可选）"→"来源行"三段纵向堆叠；
//  引用行有值时 hidden=NO 并激活其顶/底约束，无值时 hidden=YES 且约束停用（占 0 高，不留空隙）。

#import "IMFavoriteLinkCell.h"
#import "IMLinkRowView.h"
#import "IMTheme.h"

@implementation IMFavoriteLinkCell {
    IMLinkRowView *_row;
    UILabel *_quote;        // 原文引用（灰底两行截断）
    UIView *_quoteBox;      // 引用的灰底容器（有值时才显）
    UILabel *_source;       // "来自 X · 时间"（accent 小字）
    NSLayoutConstraint *_quoteTop;      // 有引用：接 row 底 8pt；无引用：无效
    NSLayoutConstraint *_sourceTopNoQuote;   // 无引用：source 直接接 row 底
    NSLayoutConstraint *_sourceTopWithQuote; // 有引用：source 接 quote 底
    NSArray<NSLayoutConstraint *> *_quoteConstraints; // 引用行整组：hidden 时停用
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _row = [IMLinkRowView new];
        _row.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_row];

        // 引用容器：灰底 + 圆角 + 左侧竖条，两行截断放里面。整个 box hidden 时靠约束二选一避免留白。
        _quoteBox = [UIView new];
        _quoteBox.translatesAutoresizingMaskIntoConstraints = NO;
        _quoteBox.backgroundColor = [IMTheme.separator colorWithAlphaComponent:0.35];
        _quoteBox.layer.cornerRadius = 6;
        _quoteBox.hidden = YES;
        [self.contentView addSubview:_quoteBox];

        _quote = [UILabel new];
        _quote.translatesAutoresizingMaskIntoConstraints = NO;
        _quote.font = [UIFont systemFontOfSize:12.5];
        _quote.textColor = IMTheme.textSecondary;
        _quote.numberOfLines = 2;
        _quote.lineBreakMode = NSLineBreakByTruncatingTail;
        [_quoteBox addSubview:_quote];

        _source = [UILabel new];
        _source.translatesAutoresizingMaskIntoConstraints = NO;
        _source.font = [UIFont systemFontOfSize:11];
        _source.textColor = IMTheme.accent;
        _source.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_source];

        // Row 外沿：L16/R16/T10；下方由 quote/source 之一撑底。
        _sourceTopNoQuote = [_source.topAnchor constraintEqualToAnchor:_row.bottomAnchor constant:6];
        _sourceTopWithQuote = [_source.topAnchor constraintEqualToAnchor:_quoteBox.bottomAnchor constant:6];
        _quoteTop = [_quoteBox.topAnchor constraintEqualToAnchor:_row.bottomAnchor constant:8];
        _quoteConstraints = @[
            _quoteTop,
            [_quoteBox.leadingAnchor constraintEqualToAnchor:_row.leadingAnchor constant:48], // 与 t1 起点对齐（16+36-4≈48 视觉对齐）
            [_quoteBox.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_quote.topAnchor constraintEqualToAnchor:_quoteBox.topAnchor constant:6],
            [_quote.leadingAnchor constraintEqualToAnchor:_quoteBox.leadingAnchor constant:10],
            [_quote.trailingAnchor constraintEqualToAnchor:_quoteBox.trailingAnchor constant:-10],
            [_quote.bottomAnchor constraintEqualToAnchor:_quoteBox.bottomAnchor constant:-6],
        ];

        [NSLayoutConstraint activateConstraints:@[
            [_row.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_row.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_row.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],

            [_source.leadingAnchor constraintEqualToAnchor:_row.leadingAnchor constant:48], // 同 quote 起点
            [_source.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_source.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
        ]];
        // 默认（无引用）：source 直接贴 row 底。configureWith 时按 quoteText 有无翻转。
        _sourceTopNoQuote.active = YES;
    }
    return self;
}

- (void)configureWithURL:(NSString *)url
               quoteText:(NSString *)quoteText
              sourceText:(NSString *)sourceText
                timeText:(NSString *)timeText {
    // 卡片本体：URL + 时间（t3 是时间，源信息不塞进 row，走独立 _source 行避免视觉挤在一起）
    [_row configureWithURL:url ?: @"" timeText:timeText];

    BOOL showQuote = quoteText.length > 0;
    _quoteBox.hidden = !showQuote;
    _quote.text = showQuote ? [NSString stringWithFormat:@"「%@」", quoteText] : nil;
    if (showQuote) {
        [NSLayoutConstraint activateConstraints:_quoteConstraints];
        _sourceTopNoQuote.active = NO;
        _sourceTopWithQuote.active = YES;
    } else {
        [NSLayoutConstraint deactivateConstraints:_quoteConstraints];
        _sourceTopWithQuote.active = NO;
        _sourceTopNoQuote.active = YES;
    }

    _source.text = sourceText.length > 0 ? [@"来自" stringByAppendingString:sourceText] : @"";
}

@end
