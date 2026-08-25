//  IMLinkRowView.m
//  实现见 .h。从 IMDetailLinkCell 的内容排版原样搬出来，作为通用 UIView 供三处消费。

#import "IMLinkRowView.h"
#import "IMLinkCardCell.h"        // +previewCache（跨 cell/view 共享）
#import "IMHTTPService.h"
#import "IMMediaUtil.h"
#import "IMTheme.h"

@implementation IMLinkRowView {
    UILabel *_favicon; // 36×36 圆角 8，首字母（host 首字母大写），品牌色底
    UILabel *_t1;      // og:title 或 host（16pt Regular, textPrimary），1 行截断
    UILabel *_t2;      // host+path（12pt mono, textSecondary），1 行截断，省略 scheme
    UILabel *_t3;      // 时间（12pt Regular, textTertiary）
    NSString *_url;    // 当前配置的 URL，异步 preview 回调按此比对防串图
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _favicon = [UILabel new];
        _favicon.translatesAutoresizingMaskIntoConstraints = NO;
        _favicon.textAlignment = NSTextAlignmentCenter;
        _favicon.textColor = IMTheme.accent;
        _favicon.backgroundColor = IMTheme.accentSoft;
        _favicon.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
        _favicon.layer.cornerRadius = 8;
        _favicon.clipsToBounds = YES;
        [self addSubview:_favicon];

        _t1 = [UILabel new];
        _t1.translatesAutoresizingMaskIntoConstraints = NO;
        _t1.font = [UIFont systemFontOfSize:16];
        _t1.textColor = IMTheme.textPrimary;
        _t1.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_t1];

        _t2 = [UILabel new];
        _t2.translatesAutoresizingMaskIntoConstraints = NO;
        _t2.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        _t2.textColor = IMTheme.textSecondary;
        _t2.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_t2];

        _t3 = [UILabel new];
        _t3.translatesAutoresizingMaskIntoConstraints = NO;
        _t3.font = [UIFont systemFontOfSize:12];
        _t3.textColor = IMTheme.textTertiary;
        [self addSubview:_t3];

        // 与 IMDetailFileCell 一致：图标 36×36 · 图标到文字 12 · t1→t2 = t2→t3 = 2pt
        // 外沿留白由宿主 cell 自选（详情/收藏页各有不同边距诉求），View 自身不设 padding。
        [NSLayoutConstraint activateConstraints:@[
            [_favicon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_favicon.topAnchor constraintEqualToAnchor:self.topAnchor constant:1],
            [_favicon.widthAnchor constraintEqualToConstant:36],
            [_favicon.heightAnchor constraintEqualToConstant:36],

            [_t1.leadingAnchor constraintEqualToAnchor:_favicon.trailingAnchor constant:12],
            [_t1.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_t1.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],

            [_t2.leadingAnchor constraintEqualToAnchor:_t1.leadingAnchor],
            [_t2.topAnchor constraintEqualToAnchor:_t1.bottomAnchor constant:2],
            [_t2.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],

            [_t3.leadingAnchor constraintEqualToAnchor:_t1.leadingAnchor],
            [_t3.topAnchor constraintEqualToAnchor:_t2.bottomAnchor constant:2],
            [_t3.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],
            [_t3.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (void)configureWithURL:(NSString *)url timeText:(NSString *)timeText {
    _url = url;
    NSURL *parsed = [NSURL URLWithString:url ?: @""];
    NSString *host = parsed.host ?: (url ?: @"");
    NSString *hostAndPath = parsed.path.length > 0
        ? [NSString stringWithFormat:@"%@%@", host, parsed.path]
        : host;

    NSString *letter = @"?";
    if (host.length > 0) { letter = [[host substringToIndex:1] uppercaseString]; }
    _favicon.text = letter;
    _t2.text = hostAndPath;
    _t3.text = timeText ?: @"";

    NSDictionary *cached = [[IMLinkCardCell previewCache] objectForKey:url ?: @""];
    NSString *cachedTitle = [cached[@"title"] isKindOfClass:NSString.class] ? cached[@"title"] : nil;
    if (cachedTitle.length > 0) {
        _t1.text = cachedTitle;
        return;
    }
    _t1.text = host; // 兜底：host（首字母已大写形式）足够辨识
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0 || url.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService linkPreviewWithToken:token url:url completion:^(NSDictionary *preview, NSError *error) {
        if (!preview) { return; }
        [[IMLinkCardCell previewCache] setObject:preview forKey:url];
        __strong typeof(ws) self = ws;
        if (!self || ![self->_url isEqualToString:url]) { return; } // 复用防串图
        NSString *title = [preview[@"title"] isKindOfClass:NSString.class] ? preview[@"title"] : nil;
        if (title.length > 0) { self->_t1.text = title; }
    }];
}

@end
