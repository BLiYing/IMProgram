//  IMTwoStepViews.h
//  两步验证各页共用的小控件工厂（输入框 / 眼睛按钮 / 头图 / 二维码卡 / 恢复码网格）。
//  取值（TWO_STEP_VERIFICATION_DESIGN §5.1）：输入 17pt Regular 左右缩进 16；6 位框 28pt 等宽 Semibold 字距 8 居中；
//  二维码 200pt 白底 + 12pt 内边距 + 圆角 12（深色也保持白底）；头图 SF Symbol lock.shield.fill 64pt systemBlue。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 密码框右侧的眼睛按钮：自带切换逻辑（切换时短暂 resign 再 become，规避光标跳动老 bug）。
@interface IMTwoStepEyeButton : UIButton
@property (nonatomic, weak) UITextField *field;
@end

/// 密码框：密文 + 眼睛；不自动大写 / 纠正。
FOUNDATION_EXPORT UITextField *IMTwoStepMakePasswordField(NSString *placeholder);
/// 6 位动态码框：数字键盘 + oneTimeCode，28pt 等宽 Semibold、字距 8、居中。占位是 6 个中点（不是文案）。
FOUNDATION_EXPORT UITextField *IMTwoStepMakeCodeField(NSString *accessibilityLabel);
/// 恢复码框：等宽 17pt，关闭自动大写 / 纠正 / 拼写检查（归一化只在提交时做）。
FOUNDATION_EXPORT UITextField *IMTwoStepMakeRecoveryField(NSString *placeholder);

/// 恢复码框的粘贴处理：非组词期间，粘贴（IMTwoStepEditLooksLikePaste）里能提取出恢复码就整体替换为 xxxxx-xxxxx 并发 EditingChanged，
/// 返回 YES 表示已处理（调用方 shouldChange 返回 NO）；提取不到返回 NO，走原有只拒超长的规则。
FOUNDATION_EXPORT BOOL IMTwoStepHandleRecoveryPaste(UITextField *field, NSRange range, NSString *replacement);

/// 把输入框包进一行（左右缩进 16，最小高度 minHeight）。
FOUNDATION_EXPORT UIView *IMTwoStepFieldRow(UITextField *field, CGFloat minHeight);
/// 居中文字行（蓝色链接 / 红色危险项）。
FOUNDATION_EXPORT UIView *IMTwoStepCenteredTextRow(NSString *text, UIColor *color);
/// 左文右值的行（右值可着色）；showsChevron 与系统 cell 的指示一致。
FOUNDATION_EXPORT UIView *IMTwoStepValueRow(NSString *title, NSString *_Nullable value, UIColor *valueColor, BOOL showsChevron);
/// 头图：图标 64pt systemBlue + 标题 .title3 Semibold + 副文 13pt secondaryLabel（可空），整体居中。
FOUNDATION_EXPORT UIView *IMTwoStepHeroView(NSString *title, NSString *_Nullable subtitle);
/// 二维码卡：200×200 白底圆角 12，内边距 12；本地由 IMQRImage 绘制，nil 内容画空白。
FOUNDATION_EXPORT UIView *IMTwoStepQRCard(NSString *_Nullable content);
/// 恢复码网格：两列、行距 12、卡片内边距 16，17pt 等宽；每个码可选中复制由调用方处理。
FOUNDATION_EXPORT UIView *IMTwoStepRecoveryGrid(NSArray<NSString *> *codes);
/// 勾选行（圆形勾选框 + 文案）；点击由所在 cell 的 onTap 处理，这里只负责外观刷新。
@interface IMTwoStepCheckRow : UIView
@property (nonatomic, assign) BOOL checked;
- (instancetype)initWithText:(NSString *)text;
@end

NS_ASSUME_NONNULL_END
