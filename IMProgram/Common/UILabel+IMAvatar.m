//  UILabel+IMAvatar.m

#import "UILabel+IMAvatar.h"
#import "IMImageLoader.h"
#import "IMMediaUtil.h"
#import "IMHTTPService.h"
#import "IMTheme.h"
#import <objc/runtime.h>
#import "IMAccountIdentity.h"
#import "IMRemarkStore.h"
#import "IMLocalization.h"

static const void *kIMAvatarImageViewKey = &kIMAvatarImageViewKey;
static const void *kIMAvatarTokenKey = &kIMAvatarTokenKey;

/// 系统通知头像 = 当前桌面图标（外观 ▸ 应用图标选了哪个就跟哪个）。备用图标名 → 外观页同款 256px 缩略图；
/// 默认图标（alternateIconName=nil）仍用 LaunchLogo。每次渲染现读，会话列表 viewWillAppear 重刷即生效。
static UIImage *IMSystemAvatarImage(void) {
    NSString *alt = UIApplication.sharedApplication.alternateIconName;
    NSDictionary<NSString *, NSString *> *map = @{@"AppIconOcean": @"AppearanceIconOcean",
                                                  @"AppIconViolet": @"AppearanceIconViolet",
                                                  @"AppIconMidnight": @"AppearanceIconMidnight"};
    NSString *name = alt.length > 0 ? map[alt] : nil;
    return [UIImage imageNamed:name ?: @"LaunchLogo"];
}

UIImage *IMDeletedUserAvatarImage(void) {
    static UIImage *image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGFloat side = 160;
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
        image = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [[UIColor colorWithWhite:0.62 alpha:1] setFill];
            UIRectFill(CGRectMake(0, 0, side, side));
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:side * 0.56 weight:UIImageSymbolWeightRegular];
            UIImage *glyph = [[UIImage systemImageNamed:@"person.fill" withConfiguration:cfg] imageWithTintColor:UIColor.whiteColor
                                                                                                renderingMode:UIImageRenderingModeAlwaysOriginal];
            [glyph drawAtPoint:CGPointMake((side - glyph.size.width) / 2, (side - glyph.size.height) / 2 + side * 0.03)];
        }];
    });
    return image;
}

@implementation UILabel (IMAvatar)

- (void)im_setAvatarURL:(nullable NSString *)url seed:(NSString *)seed displayName:(nullable NSString *)displayName {
    // 系统通知会话（seed=system）：头像走应用 logo（LaunchLogo）——服务端 avatar_url 恒空。
    // 见 docs/design/SYSTEM_NOTICE_SESSION_DESIGN.md §2.1。
    if (IMIsSystemUserID(seed)) { // 系统账号回退渲染 app logo
        self.text = @"";
        self.backgroundColor = UIColor.systemBackgroundColor;
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
        iv.layer.cornerRadius = self.layer.cornerRadius;
        iv.image = IMSystemAvatarImage();
        iv.hidden = NO;
        // token 前进，避免旧异步回调（若之前是普通头像）覆盖上来。
        NSUInteger token = [objc_getAssociatedObject(self, kIMAvatarTokenKey) unsignedIntegerValue] + 1;
        objc_setAssociatedObject(self, kIMAvatarTokenKey, @(token), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    // 已注销用户：不显示（可能是旧缓存里的）头像图，首字母圈用「已注销用户」——名字与头像在每个调用点都自动一致。
    if ([IMRemarkStore.sharedStore isDeletedUser:seed]) {
        [self im_showDeletedUserAvatar];
        return;
    }
    // 1) 立即渲染首字母 + 稳定取色底（回退态，无空白闪烁）。
    NSString *name = displayName.length ? displayName : seed;
    self.text = IMAvatarInitials(name);
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

    // 统一在全局头像方法内把相对 URL（/avatars、/uploads）解析为完整地址——调用方只需传原始
    // avatar_url，无需各自 IMMediaFullURL。绝对 http(s)/data URL 幂等原样返回。
    NSString *full = IMMediaFullURL(url, IMHTTPService.sharedService.host);

    // 命中内存缓存 → 直接同步显图，**不先清空回退首字母**（消除 reloadData 逐格闪动）。
    UIImage *cached = full.length ? [[IMImageLoader shared] cachedImageForURL:full] : nil;
    if (cached) { iv.image = cached; iv.hidden = NO; return; }
    iv.image = nil;
    iv.hidden = YES;

    if (full.length == 0) { return; }
    __weak typeof(self) ws = self;
    [[IMImageLoader shared] loadImageURL:full completion:^(UIImage *_Nullable img) {
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

/// 已注销：灰底人形默认头像，覆盖在首字母圈上；token 前进以作废在途的旧头像加载。
- (void)im_showDeletedUserAvatar {
    self.text = @"";
    self.backgroundColor = [UIColor colorWithWhite:0.62 alpha:1];
    UIImageView *iv = objc_getAssociatedObject(self, kIMAvatarImageViewKey);
    if (!iv) {
        iv = [UIImageView new];
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        [self addSubview:iv];
        [NSLayoutConstraint activateConstraints:@[
            [iv.leadingAnchor constraintEqualToAnchor:self.leadingAnchor], [iv.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [iv.topAnchor constraintEqualToAnchor:self.topAnchor], [iv.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
        objc_setAssociatedObject(self, kIMAvatarImageViewKey, iv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    iv.layer.cornerRadius = self.layer.cornerRadius;
    iv.image = IMDeletedUserAvatarImage();
    iv.hidden = NO;
    NSUInteger token = [objc_getAssociatedObject(self, kIMAvatarTokenKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(self, kIMAvatarTokenKey, @(token), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)im_clearAvatarImage {
    // 自增 token → 任何在途异步加载的完成回调都会因 token 不匹配而丢弃（防晚到的旧照片覆盖上来）。
    NSUInteger token = [objc_getAssociatedObject(self, kIMAvatarTokenKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(self, kIMAvatarTokenKey, @(token), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIImageView *iv = objc_getAssociatedObject(self, kIMAvatarImageViewKey);
    iv.image = nil;
    iv.hidden = YES;
}

@end
