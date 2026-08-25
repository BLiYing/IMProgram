//  IMLinkPreviewView.m
//  实现见 .h。缓存/抓取通路复用 IMLinkCardCell + IMHTTPService，避免两处分叉。

#import "IMLinkPreviewView.h"
#import "IMLinkCardCell.h"        // +previewCache（进程内 NSCache，与纯 URL 气泡共享）
#import "IMHTTPService.h"
#import "IMImageLoader.h"
#import "IMMediaUtil.h"           // IMMediaFullURL
#import "IMTheme.h"

@implementation IMLinkPreviewView {
    UIImageView *_thumb;
    NSLayoutConstraint *_thumbHeight; // 有图 130、无图 0
    UILabel *_title;
    UILabel *_desc;
    UILabel *_host;
    NSString *_url;                  // 当前配置的 URL（防串图：异步回调命中已换页时忽略）
    BOOL _hasContent;                // 有 og:title 或 og:image → YES
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        // 与 IMLinkCardCell 的 _card 视觉一致：tertiary fill 底 + 圆角，嵌在气泡内不与气泡底融合。
        self.backgroundColor = UIColor.tertiarySystemFillColor;
        self.layer.cornerRadius = IMTheme.radiusBubble;
        self.clipsToBounds = YES;
        self.userInteractionEnabled = YES;
        self.hidden = YES;

        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];

        _thumb = [UIImageView new];
        _thumb.translatesAutoresizingMaskIntoConstraints = NO;
        _thumb.contentMode = UIViewContentModeScaleAspectFill;
        _thumb.clipsToBounds = YES;
        _thumb.backgroundColor = UIColor.tertiarySystemFillColor;
        [self addSubview:_thumb];

        _title = [UILabel new];
        _title.translatesAutoresizingMaskIntoConstraints = NO;
        _title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _title.numberOfLines = 2;
        _title.textColor = IMTheme.textPrimary;
        [self addSubview:_title];

        _desc = [UILabel new];
        _desc.translatesAutoresizingMaskIntoConstraints = NO;
        _desc.font = [UIFont systemFontOfSize:12];
        _desc.numberOfLines = 2;
        _desc.textColor = IMTheme.textSecondary;
        [self addSubview:_desc];

        _host = [UILabel new];
        _host.translatesAutoresizingMaskIntoConstraints = NO;
        _host.font = [UIFont systemFontOfSize:11];
        _host.textColor = IMTheme.textSecondary;
        [self addSubview:_host];

        _thumbHeight = [_thumb.heightAnchor constraintEqualToConstant:0];
        [NSLayoutConstraint activateConstraints:@[
            [_thumb.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_thumb.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_thumb.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            _thumbHeight,
            [_title.topAnchor constraintEqualToAnchor:_thumb.bottomAnchor constant:8],
            [_title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_title.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [_desc.topAnchor constraintEqualToAnchor:_title.bottomAnchor constant:3],
            [_desc.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_desc.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [_host.topAnchor constraintEqualToAnchor:_desc.bottomAnchor constant:5],
            [_host.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_host.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [_host.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
        ]];
    }
    return self;
}

- (BOOL)hasContent { return _hasContent; }

- (void)configureWithURL:(NSString *)url {
    _url = url;
    _hasContent = NO;
    self.hidden = YES;
    _thumb.image = nil;
    _thumbHeight.constant = 0;
    _title.text = nil; _desc.text = nil; _host.text = nil;

    if (url.length == 0) { return; }
    if (!([url hasPrefix:@"http://"] || [url hasPrefix:@"https://"])) { return; }

    // 与 IMLinkCardCell 共用同一 NSCache（key=url）。命中同步渲染，不回调 onContentSizeResolved。
    NSDictionary *cached = [[IMLinkCardCell previewCache] objectForKey:url];
    if (cached) { [self applyPreview:cached forURL:url notifyResize:NO]; return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService linkPreviewWithToken:token url:url completion:^(NSDictionary *preview, NSError *error) {
        if (!preview) { return; }
        [[IMLinkCardCell previewCache] setObject:preview forKey:url];
        __strong typeof(ws) self = ws;
        if (self && [self->_url isEqualToString:url]) { [self applyPreview:preview forURL:url notifyResize:YES]; }
    }];
}

- (void)applyPreview:(NSDictionary *)p forURL:(NSString *)url notifyResize:(BOOL)notify {
    NSString *title = [p[@"title"] isKindOfClass:NSString.class] ? p[@"title"] : @"";
    NSString *desc = [p[@"description"] isKindOfClass:NSString.class] ? p[@"description"] : @"";
    NSString *site = [p[@"site_name"] isKindOfClass:NSString.class] ? p[@"site_name"] : @"";
    NSString *image = [p[@"image"] isKindOfClass:NSString.class] ? p[@"image"] : @"";
    if (title.length == 0 && image.length == 0) { return; } // 无 og → 保持隐藏（正文里高亮 URL 承载点击）
    _hasContent = YES;
    self.hidden = NO;
    _title.text = title.length ? title : url;
    _desc.text = desc;
    _host.text = site;
    if (image.length) {
        _thumbHeight.constant = 130;
        __weak typeof(self) ws = self;
        NSString *imageURL = IMMediaFullURL(image, IMHTTPService.sharedService.host);
        [[IMImageLoader shared] loadImageURL:imageURL completion:^(UIImage *img) {
            __strong typeof(ws) self = ws;
            if (self && [self->_url isEqualToString:url]) { self->_thumb.image = img; }
        }];
    } else {
        _thumbHeight.constant = 0;
    }
    // 抓到 og → 卡片从"隐藏"变"展开"，宿主要刷新行高。同 IMLinkCardCell.applyPreview 的守卫：
    // 若本方法同步跑在 cellForRow 内（命中缓存路径），此刻回调会重入 tableView begin/endUpdates。
    // 通过 notify 参数区分：命中缓存不通知（宿主初次配置时按 hasContent 直接算高），异步回来才通知。
    if (notify && self.onContentSizeResolved) {
        void (^resolved)(void) = self.onContentSizeResolved;
        dispatch_async(dispatch_get_main_queue(), resolved);
    }
}

- (void)tapped { if (_onTap && _url) { _onTap(_url); } }

@end
