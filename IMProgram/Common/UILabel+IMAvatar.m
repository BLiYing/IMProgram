//  UILabel+IMAvatar.m

#import "UILabel+IMAvatar.h"
#import "IMImageLoader.h"
#import "IMTheme.h"
#import <objc/runtime.h>

static const void *kIMAvatarImageViewKey = &kIMAvatarImageViewKey;
static const void *kIMAvatarTokenKey = &kIMAvatarTokenKey;

@implementation UILabel (IMAvatar)

- (void)im_setAvatarURL:(nullable NSString *)url seed:(NSString *)seed displayName:(nullable NSString *)displayName {
    // 1) 立即渲染首字母 + 稳定取色底（回退态，无空白闪烁）。
    NSString *name = displayName.length ? displayName : seed;
    self.text = name.length >= 2 ? [name substringFromIndex:name.length - 2] : name;
    self.backgroundColor = [IMTheme avatarColorForSeed:seed];

    // 2) 懒建覆盖用 UIImageView，铺满并与 label 同圆角裁剪。
    UIImageView *iv = objc_getAssociatedObject(self, kIMAvatarImageViewKey);
    if (!iv) {
        iv = [UIImageView new];
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        [self addSubview:iv];
        [NSLayoutConstraint activateConstraints:@[
            [iv.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [iv.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [iv.topAnchor constraintEqualToAnchor:self.topAnchor],
            [iv.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
        objc_setAssociatedObject(self, kIMAvatarImageViewKey, iv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    iv.layer.cornerRadius = self.layer.cornerRadius; // 跟随 label 已设的圆角
    // 3) cell 复用安全：每次配置自增 token，异步回调只认最新 token。
    NSUInteger token = [objc_getAssociatedObject(self, kIMAvatarTokenKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(self, kIMAvatarTokenKey, @(token), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 命中内存缓存 → 直接同步显图，**不先清空回退首字母**（消除 reloadData 逐格闪动）。
    UIImage *cached = url.length ? [[IMImageLoader shared] cachedImageForURL:url] : nil;
    if (cached) { iv.image = cached; iv.hidden = NO; return; }
    iv.image = nil;
    iv.hidden = YES;

    if (url.length == 0) { return; }
    __weak typeof(self) ws = self;
    [[IMImageLoader shared] loadImageURL:url completion:^(UIImage *_Nullable img) {
        if (!img) { return; }
        typeof(self) ss = ws;
        if (!ss) { return; }
        NSUInteger now = [objc_getAssociatedObject(ss, kIMAvatarTokenKey) unsignedIntegerValue];
        if (now != token) { return; } // 已被复用为别的头像，丢弃
        UIImageView *cur = objc_getAssociatedObject(ss, kIMAvatarImageViewKey);
        cur.image = img;
        cur.hidden = NO;
    }];
}

@end
