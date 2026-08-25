//  IMDetailLinkCell.m
//  实现见 .h。visual specs 参见草图 §C UI 规格表。

#import "IMDetailLinkCell.h"
#import "IMMessageModel.h"
#import "IMLinkCardCell.h"        // +previewCache（跨 cell 共享，同一 URL 全站只抓一次）
#import "IMHTTPService.h"
#import "IMMediaUtil.h"           // IMFormatFileDateTime
#import "IMTheme.h"

@implementation IMDetailLinkCell {
    UILabel *_favicon; // 36×36 圆角 8，首字母（host 首字母大写），品牌色底
    UILabel *_t1;      // og:title 或 host（16pt Regular, textPrimary），1 行截断
    UILabel *_t2;      // host+path（12pt mono, textSecondary），1 行截断，省略 scheme
    UILabel *_t3;      // 时间（12pt Regular, textTertiary）
    NSString *_url;    // 当前配置的 URL，异步 preview 回调按此比对防串图
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        _favicon = [UILabel new];
        _favicon.translatesAutoresizingMaskIntoConstraints = NO;
        _favicon.textAlignment = NSTextAlignmentCenter;
        _favicon.textColor = IMTheme.accent;
        _favicon.backgroundColor = IMTheme.accentSoft;
        _favicon.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
        _favicon.layer.cornerRadius = 8;
        _favicon.clipsToBounds = YES;
        [self.contentView addSubview:_favicon];

        _t1 = [UILabel new];
        _t1.translatesAutoresizingMaskIntoConstraints = NO;
        _t1.font = [UIFont systemFontOfSize:16];
        _t1.textColor = IMTheme.textPrimary;
        _t1.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_t1];

        _t2 = [UILabel new];
        _t2.translatesAutoresizingMaskIntoConstraints = NO;
        _t2.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        _t2.textColor = IMTheme.textSecondary;
        _t2.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_t2];

        _t3 = [UILabel new];
        _t3.translatesAutoresizingMaskIntoConstraints = NO;
        _t3.font = [UIFont systemFontOfSize:12];
        _t3.textColor = IMTheme.textTertiary;
        [self.contentView addSubview:_t3];

        // 与 IMDetailFileCell 一致：L 16 · R 16 · T/B 9 · 图标 36×36 · 图标到文字 12 · t1→t2/t2→t3 均 2pt
        [NSLayoutConstraint activateConstraints:@[
            [_favicon.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_favicon.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [_favicon.widthAnchor constraintEqualToConstant:36],
            [_favicon.heightAnchor constraintEqualToConstant:36],

            [_t1.leadingAnchor constraintEqualToAnchor:_favicon.trailingAnchor constant:12],
            [_t1.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:9],
            [_t1.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16],

            [_t2.leadingAnchor constraintEqualToAnchor:_t1.leadingAnchor],
            [_t2.topAnchor constraintEqualToAnchor:_t1.bottomAnchor constant:2],
            [_t2.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16],

            [_t3.leadingAnchor constraintEqualToAnchor:_t1.leadingAnchor],
            [_t3.topAnchor constraintEqualToAnchor:_t2.bottomAnchor constant:2],
            [_t3.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_t3.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-9],
        ]];
    }
    return self;
}

- (void)configureWithMessage:(IMMessageModel *)message {
    NSString *url = message.content ?: @"";
    _url = url;
    NSURL *parsed = [NSURL URLWithString:url];
    NSString *host = parsed.host ?: url;
    NSString *hostAndPath = parsed.path.length > 0
        ? [NSString stringWithFormat:@"%@%@", host, parsed.path]
        : host;

    // Favicon 兜底：host 首字母大写；实际站点 favicon 抓取未做（草图 P2）。
    NSString *letter = @"?";
    if (host.length > 0) { letter = [[host substringToIndex:1] uppercaseString]; }
    _favicon.text = letter;

    // t1 优先 og:title（命中缓存同步取）；未命中先兜底 host，异步抓到后就地替换。
    _t2.text = hostAndPath;
    _t3.text = IMFormatFileDateTime(message.timestamp);

    NSDictionary *cached = [[IMLinkCardCell previewCache] objectForKey:url];
    NSString *cachedTitle = [cached[@"title"] isKindOfClass:NSString.class] ? cached[@"title"] : nil;
    if (cachedTitle.length > 0) {
        _t1.text = cachedTitle;
        return;
    }
    _t1.text = host; // 兜底：host 首字母大写形式已够辨识（Wikipedia → en.wikipedia.org）
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

- (void)prepareForReuse {
    [super prepareForReuse];
    _favicon.text = nil;
    _t1.text = nil; _t2.text = nil; _t3.text = nil;
    _url = nil;
}

@end
