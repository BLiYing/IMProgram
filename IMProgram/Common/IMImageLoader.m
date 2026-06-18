//  IMImageLoader.m

#import "IMImageLoader.h"

@implementation IMImageLoader {
    NSCache<NSString *, UIImage *> *_cache;
    NSURLSession *_session;
}

+ (instancetype)shared {
    static IMImageLoader *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IMImageLoader new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [NSCache new];
        _cache.countLimit = 200;
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 15;
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

- (void)loadImageURL:(NSString *)urlString completion:(void (^)(UIImage *_Nullable))completion {
    NSString *key = urlString.length ? urlString : @"";
    void (^finish)(UIImage *_Nullable) = ^(UIImage *_Nullable img) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(img); });
    };
    if (key.length == 0) { finish(nil); return; }

    UIImage *cached = [_cache objectForKey:key];
    if (cached) { finish(cached); return; }

    // data:image/...;base64,XXXX —— 本地解码，不走网络。
    if ([urlString hasPrefix:@"data:image/"]) {
        NSRange comma = [urlString rangeOfString:@","];
        if (comma.location == NSNotFound) { finish(nil); return; }
        NSString *b64 = [urlString substringFromIndex:comma.location + 1];
        NSData *data = [[NSData alloc] initWithBase64EncodedString:b64
                                                          options:NSDataBase64DecodingIgnoreUnknownCharacters];
        UIImage *img = data ? [UIImage imageWithData:data] : nil;
        if (img) { [self->_cache setObject:img forKey:key]; }
        finish(img);
        return;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url || (![url.scheme isEqualToString:@"http"] && ![url.scheme isEqualToString:@"https"])) {
        finish(nil);
        return;
    }
    NSCache<NSString *, UIImage *> *cache = _cache; // 单例缓存，强捕获无循环引用
    NSURLSessionDataTask *task = [_session dataTaskWithURL:url
            completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable resp, NSError *_Nullable err) {
        if (err || !data) { finish(nil); return; }
        UIImage *img = [UIImage imageWithData:data];
        if (!img) { finish(nil); return; }
        [cache setObject:img forKey:key];
        finish(img);
    }];
    [task resume];
}

@end
