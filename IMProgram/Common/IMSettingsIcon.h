//  IMSettingsIcon.h
//  设置页的彩色圆角图标块（白色 SF Symbol + 底色），供 cell.imageView 放在行首。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 图标块边长（与 `IMSettingsIconSpacer` 同尺寸）。
FOUNDATION_EXPORT const CGFloat kIMSettingsIconSide;

/// 渲染成 UIImage 而非 accessoryView，才能落在 iOS 原生的行首图标位。**按 symbol 记忆化**：全页图标固定，
/// 避免每次 cellForRow / reloadData 重复光栅化。
FOUNDATION_EXPORT UIImage *IMSettingsIconImage(NSString *symbol, UIColor *bg);

/// 与图标块同尺寸的**透明占位图**：给无图标的行占住行首图标位，标题与上方带图标的行左对齐。
FOUNDATION_EXPORT UIImage *IMSettingsIconSpacer(void);

NS_ASSUME_NONNULL_END
