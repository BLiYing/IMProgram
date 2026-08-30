//  IMGroupManageRowIcon.h
//  群管理页系行图标（与「我」页设置项同款：纯色圆角方块 + 居中白色 SF 符号）。
//  原为 IMGroupManageViewController.m 里的静态函数，管理员二级页也要用同一款图标，故提出来共用。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 30×30 圆角 7 的 tint 纯色方块 + 居中白色 SF 符号（15pt Semibold，字形等比缩到 ≤18pt）。
FOUNDATION_EXPORT UIImage *IMGroupManageRowIconTinted(NSString *symbolName, UIColor *tint);

/// 同上，底色取 IMTheme.accent（本页绝大多数行）。转让群组那种不可逆动作传 IMTheme.danger 走上面那个。
FOUNDATION_EXPORT UIImage *IMGroupManageRowIcon(NSString *symbolName);

NS_ASSUME_NONNULL_END
