//  IMKeyValueCardView.h
//  通用「键值信息卡」：一列「标签 — 值」行 + 行间 0.5pt 分隔线，圆角卡片。
//  扫码登录确认页与设备详情页共用（原先各写一份近乎相同的 buildInfoCard/kvRowKey）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMKeyValueCardView : NSObject

/// 生成一张键值卡（竖向 stack，卡片底色 + 圆角 + 行间细分隔线）。
/// rows 每项：`@[key, value]` 或 `@[key, value, valueColor]`（缺省用 textSecondary）。
/// 返回值 `translatesAutoresizingMaskIntoConstraints=NO`，调用方 addSubview 后约束 leading/trailing/top 即可。
+ (UIStackView *)cardWithRows:(NSArray<NSArray *> *)rows;

@end

NS_ASSUME_NONNULL_END
