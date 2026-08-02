//  IMDropletHeaderMorph.h
//  共享「水滴头部」形变驱动（Zone①）。IMChatDetailViewController 与 IMSettingsViewController 共用，
//  详情页的头部效果改一处即自动同步到「我」页。只负责 Zone①（头像吸附 + name/成员迁移进标题栏 + 松手临界吸附），
//  Zone②（详情页页签贴顶）与 pills 停靠等页面专有逻辑仍留在各自 VC。

#import <UIKit/UIKit.h>

@class IMTelegramAvatarEffectsView, IMTelegramAvatarMaskView, IMLiquidNavigationBar;

NS_ASSUME_NONNULL_BEGIN

@interface IMDropletHeaderMorph : NSObject

/// 静态坐标容器：承载头像 + 灵动岛 171pt 遮罩/覆盖层，mask 挂到它本身（不是缩小中的头像）。
@property (nonatomic, weak) UIView *container;
/// 头像视图（详情页 IMDetailAvatarView / 我页 UILabel 均可，只按 UIView 处理 frame/圆角）。
@property (nonatomic, weak) UIView *avatar;
@property (nonatomic, weak) UIView *bottomCover;                 ///< 灵动岛下方黑底（Telegram bottomCoverNode）
@property (nonatomic, weak) IMTelegramAvatarEffectsView *topCover;///< 顶部 blur+gradient+fade（topCoverNode）
@property (nonatomic, weak) IMTelegramAvatarMaskView *mask;      ///< 171pt Lottie（挂到 container.maskView）
@property (nonatomic, weak) UILabel *name;                       ///< 圆头像下名字（会迁移进标题栏充当 title）
@property (nonatomic, weak) UILabel *meta;                       ///< 名字下方副标题（成员数 / 手机号·uid）
@property (nonatomic, weak) IMLiquidNavigationBar *bar;          ///< 自持液态导航栏

/// 状态栏高度（灵动岛机型 ≈ 59）。头像 restCenterY = topInset+72，restDiameter=100。
@property (nonatomic, assign) CGFloat topInset;
/// name / meta 的 rest 字号（详情 26/15，我页 28/17），用于计算缩放端点（→17/13pt）。
@property (nonatomic, assign) CGFloat nameRestFont;
@property (nonatomic, assign) CGFloat metaRestFont;
/// meta 是否随迁移进度淡出（`alpha = 1 - migrate`）。默认 NO（跟随 name 进标题栏当副标题，如详情页成员数）；
/// 「我」页置 YES → 手机号·uid 迁移途中渐进淡出，锁定时完全不可见。
@property (nonatomic, assign) BOOL metaFades;
/// 头部完全收拢（态H）所需上滑距离：此时 name/成员进标题栏、pills 恰好停到标题栏下方。默认 144。
@property (nonatomic, assign) CGFloat collapseOffset;

/// 每帧连续形变：off = contentOffset.y（下拉橡皮筋请由调用方钳到 ≥ 下限后再传入）。
- (void)applyForOffset:(CGFloat)off width:(CGFloat)W;

/// 松手临界吸附（纯函数）：返回应吸附到的目标 offset；若 off 不在 (0, H) 收拢带内返回 -1（不吸附）。
/// velocity 为 scrollViewWillEndDragging 的 velocity.y（points/ms，>0 表示继续上滑）。
/// 快速甩动无视位置直接补完；慢速松手按位置过半判定。
+ (CGFloat)snapTargetForOffset:(CGFloat)off velocity:(CGFloat)velocity collapseOffset:(CGFloat)H;

@end

NS_ASSUME_NONNULL_END
