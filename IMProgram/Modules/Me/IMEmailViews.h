//  IMEmailViews.h
//  邮箱登录各页共用的小控件工厂（头图 / 邮箱输入框 / 文字链行）。密码框、6 位码框、行容器复用两步验证那一套（IMTwoStepViews）。
//  取值（EMAIL_LOGIN_DESIGN §5.1）：头图 envelope.fill 64pt systemBlue；标题 .title3 20pt Semibold；已绑定邮箱 17pt Regular label；
//  副文 13pt secondaryLabel，左右 32；邮箱输入 17pt、EmailAddress 键盘、无自动大写 / 纠正 / 拼写；文字链 15pt。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 头图：信封图标 + 标题（emailStyle=YES 时 17pt Regular 可换行，用于已绑定页显示邮箱）+ 副文 + 可选第二行说明（均 13pt 灰）。
FOUNDATION_EXPORT UIView *IMEmailHeroView(NSString *title, BOOL emailStyle, NSString *_Nullable subtitle, NSString *_Nullable note);
/// 邮箱输入框：EmailAddress 键盘，无自动大写 / 纠正 / 拼写，textContentType = emailAddress。
FOUNDATION_EXPORT UITextField *IMEmailMakeField(NSString *placeholder);
/// 15pt 居中文字链标签（颜色由调用方设；用于重新发送 / 更换邮箱）。
FOUNDATION_EXPORT UILabel *IMEmailLinkLabel(NSString *text, UIColor *color);
/// 把文字链包进一行（上下各 10，最小高度 44）。
FOUNDATION_EXPORT UIView *IMEmailLinkRow(UILabel *label);

NS_ASSUME_NONNULL_END
