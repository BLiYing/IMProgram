//  IMWorkbenchCells.h
//  工作台首页的格子（交互稿 WORKBENCH_UX_SKETCH I-1 / I-6）：应用格、轮播、空态、分段表头、卡片底色。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const IMWorkbenchCardBackgroundKind;

/// 应用图标：logo_url 加载失败 / 为空时用名字首字 + 色块。
@interface IMWorkbenchAppIconView : UIView
- (instancetype)initWithSide:(CGFloat)side radius:(CGFloat)radius;
- (void)setName:(NSString *)name logoURL:(nullable NSString *)logoURL host:(NSString *)host;
@end

/// 宫格里的一格：图标 52×52 r12 + 名称 12pt 单行。
@interface IMWorkbenchAppCell : UICollectionViewCell
- (void)configureWithApp:(NSDictionary *)app host:(NSString *)host;
@end

/// 轮播：350×140 r12（宽度随屏），4 秒自动翻页，页点 6×6、当前 16×6。点击回调对应轮播图字典。
@interface IMWorkbenchBannerCell : UICollectionViewCell
@property (nonatomic, copy, nullable) void (^onTap)(NSDictionary *banner);
- (void)configureWithBanners:(NSArray<NSDictionary *> *)banners host:(NSString *)host;
@end

/// 空态：「还没有应用」+ 说明 +「去应用商店」。
@interface IMWorkbenchEmptyCell : UICollectionViewCell
@property (nonatomic, copy, nullable) void (^onGoStore)(void);
@end

/// 分段表头：SYS Grouped 表头 13pt secondaryLabel。
@interface IMWorkbenchHeaderView : UICollectionReusableView
@property (nonatomic, strong, readonly) UILabel *label;
@end

/// 宫格卡片底色（InsetGrouped：secondarySystemGroupedBackground，r10）。
@interface IMWorkbenchCardBackground : UICollectionReusableView
@end

NS_ASSUME_NONNULL_END
