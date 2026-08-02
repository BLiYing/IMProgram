//  IMDropletHeaderMorph.m

#import "IMDropletHeaderMorph.h"
#import "IMProgram-Swift.h"

static inline CGFloat IMHM_Clamp(CGFloat x, CGFloat a, CGFloat b) { return MIN(MAX(x, a), b); }
static inline CGFloat IMHM_Lerp(CGFloat a, CGFloat b, CGFloat t) { return a + (b - a) * t; }
static inline CGFloat IMHM_Smooth(CGFloat x) { x = IMHM_Clamp(x, 0, 1); return x * x * (3 - 2 * x); }

@implementation IMDropletHeaderMorph

- (instancetype)init {
    if ((self = [super init])) {
        _topInset = 59;
        _nameRestFont = 26;
        _metaRestFont = 15;
        _collapseOffset = 144;
    }
    return self;
}

- (void)applyForOffset:(CGFloat)off width:(CGFloat)W {
    if (W <= 0) { return; }
    off = MAX(0, off);
    CGFloat top = self.topInset;
    // Telegram PeerInfoHeaderNode：maskValue = off/120，titleCollapseFraction = off/128（略异步是原始节奏）。
    CGFloat q = IMHM_Clamp(off / 120.0, 0, 1);
    CGFloat tcf = IMHM_Clamp(off / 128.0, 0, 1);
    // 头像 rest 尺寸/圆心必须与固定 171pt Lottie 圆对齐：restD=100(=avatarSize)，restCY=top+72。
    CGFloat restD = 100;
    CGFloat restCY = top + 72;
    CGFloat avatarScale = IMHM_Lerp(1, 0.55, tcf);          // avatarMinScale=0.55
    CGFloat diameter = restD * avatarScale;
    CGFloat cy = restCY - off + 17 * tcf;                   // avatarOffset = 17·tcf

    // 静态容器：宽度铺满，高度覆盖遮罩带 + rest 头像。mask/covers 在容器坐标系内固定像素定位。
    CGRect containerFrame = CGRectMake(0, 0, W, MAX(restCY + restD / 2 + 8, 260));
    if (!CGRectEqualToRect(self.container.frame, containerFrame)) {
        self.container.frame = containerFrame;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.avatar.transform = CGAffineTransformIdentity;
    self.avatar.frame = CGRectMake(W / 2 - diameter / 2, cy - diameter / 2, diameter, diameter);
    self.avatar.layer.cornerRadius = diameter / 2;
    self.avatar.clipsToBounds = YES;

    // Telegram 遮罩：171×171，圆心 (W/2, 133)，即 Y=47.5..218.5（灵动岛正下方）。
    CGRect maskFrame = CGRectMake(W / 2 - 85.5, 47.5, 171, 171);
    self.bottomCover.frame = maskFrame;
    self.topCover.frame = maskFrame;
    self.mask.frame = maskFrame;

    if (q > 0.03) {
        self.bottomCover.hidden = NO;
        self.bottomCover.backgroundColor = [UIColor colorWithWhite:0 alpha:q];
        self.topCover.hidden = NO;
        [self.topCover setProgress:q];
        [self.mask setProgress:q];
        if (self.container.maskView != self.mask) { self.container.maskView = self.mask; }
    } else {
        self.bottomCover.hidden = YES;
        self.bottomCover.backgroundColor = [UIColor colorWithWhite:0 alpha:0];
        self.topCover.hidden = YES;
        [self.topCover setProgress:0];
        [self.mask setProgress:0];
        if (self.container.maskView != nil) { self.container.maskView = nil; }
    }
    [CATransaction commit];
    self.avatar.alpha = 1;

    // name / meta 迁移：以【更慢】速度上移（永远留在水滴下方），到 collapseOffset(H) 时锁进标题栏 title 中心。
    CGFloat H = MAX(1, self.collapseOffset);
    CGFloat nameH = self.nameRestFont + 6;      // 详情 26→32 / 我页 28→34
    CGFloat metaH = self.metaRestFont + 5;      // 详情 15→20 / 我页 17→22
    CGFloat staticRestNameTop = restCY + restD / 2 + 8;
    CGFloat staticRestNameCenterY = staticRestNameTop + nameH / 2;
    CGFloat kLockCenterY = top + 19;            // 液态导航栏 title 中心
    // 让 name 恰好在 off=H 时锁定：速度 = (rest→lock 距离)/H，天然 < 1（与头像拉开距离、留在水滴下方）。
    CGFloat kNameSpeed = (staticRestNameCenterY - kLockCenterY) / H;
    CGFloat nameCenterY = MAX(kLockCenterY, staticRestNameCenterY - kNameSpeed * off);
    CGFloat migrate = IMHM_Clamp((staticRestNameCenterY - nameCenterY) / (staticRestNameCenterY - kLockCenterY), 0, 1);

    CGFloat titleScale = IMHM_Lerp(1.0, 17.0 / self.nameRestFont, migrate);
    CGFloat metaScale  = IMHM_Lerp(1.0, 13.0 / self.metaRestFont, migrate);
    // name↔meta 间距：rest 舒适、锁定时收窄到 ≈ 标题栏副标题间距(中心距 18.5pt)，随 migrate 连续过渡。
    CGFloat restCenterDist = nameH / 2 + 6 + metaH / 2;     // rest 舒适间距
    CGFloat lockCenterDist = 18.5;                          // = bar title↔subtitle 中心距
    CGFloat centerDist = IMHM_Lerp(restCenterDist, lockCenterDist, migrate);
    CGFloat metaCenterY = nameCenterY + centerDist;

    // 每帧显式设置各自 center + 纯缩放（绕自身中心）：间距由 centerDist 精确控制，锁定时与标题栏一致。
    self.name.transform = CGAffineTransformIdentity;
    self.meta.transform = CGAffineTransformIdentity;
    self.name.frame = CGRectMake(0, nameCenterY - nameH / 2, W, nameH);
    self.meta.frame = CGRectMake(0, metaCenterY - metaH / 2, W, metaH);
    self.name.transform = CGAffineTransformMakeScale(titleScale, titleScale);
    self.meta.transform = CGAffineTransformMakeScale(metaScale, metaScale);
    self.name.alpha = 1;
    self.meta.alpha = 1;

    // 自持导航栏：name 标签本身承担 title（compactContentProgress=0 关掉胶囊内置标题，避免双标题）。
    self.bar.immersiveAppearanceProgress = 0;
    self.bar.backgroundEffectProgress = IMHM_Smooth((q - 0.28) / 0.72);
    self.bar.compactContentProgress = 0;
}

+ (CGFloat)snapTargetForOffset:(CGFloat)off velocity:(CGFloat)velocity collapseOffset:(CGFloat)H {
    if (off <= 0 || off >= H) { return -1; }            // 不在收拢带内：交给系统自然减速
    CGFloat vThresh = 0.3;                              // points/ms：快速甩动阈值
    if (velocity > vThresh) { return H; }               // 快速上甩 → 补完收拢
    if (velocity < -vThresh) { return 0; }              // 快速下甩 → 回弹展开
    return (off >= H * 0.5) ? H : 0;                    // 慢速松手：头像吸附过半→收拢，否则回弹
}

@end
