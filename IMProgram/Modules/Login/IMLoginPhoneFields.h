//  IMLoginPhoneFields.h
//  登录页「国家码 + 手机号 + 验证码（行内获取验证码）」一组输入（交互稿 1-1 / 1-4）：验证码登录与忘记密码各一份。
//  国家码框宽 76、与号码框间距 8；只开放一个地区时显示固定的 +86、不可点。字段 RoundedRect 高 44、17pt；
//  手机号 phonePad，验证码 numberPad + oneTimeCode；行内发码按钮 accent，倒计时 tertiaryLabel 不可点。
//  发码倒计时按号码计：号码或国家码一变就清掉上一个号码的截止时刻（IMResendClock.followTarget:）。

#import <UIKit/UIKit.h>
#import "IMSMSCodeField.h"

NS_ASSUME_NONNULL_BEGIN

@class IMLoginConfig;

/// 地区选择 ActionSheet（登录页验证码登录 / 忘记密码、绑定手机号页共用）：开放地区不多于一个时什么都不做；
/// 选中回调 onPick(国家码)，取消不回调。sourceView 供 iPad popover 锚定。
FOUNDATION_EXPORT void IMPresentSMSRegionPicker(UIViewController *host, IMLoginConfig *_Nullable config, UIView *sourceView,
                                                void (^onPick)(NSString *code));

@interface IMLoginPhoneFields : UIView

@property (nonatomic, strong, readonly) UIButton *countryButton;
@property (nonatomic, strong, readonly) UITextField *phoneField;
@property (nonatomic, strong, readonly) IMSMSCodeField *codeField;
/// 当前国家码（不带 +）。改它会刷新按钮并重置倒计时归属。
@property (nonatomic, copy) NSString *countryCode;
/// 多地区时国家码可点。
@property (nonatomic, assign) BOOL regionPickable;
/// 发给服务端的号码（IMPhoneNationalNumber：去空格 / 短横线，粘贴的「+当前国家码」前缀去掉）。
@property (nonatomic, copy, readonly) NSString *normalizedPhone;
/// 倒计时归属键（国家码:号码）。
@property (nonatomic, copy, readonly) NSString *targetKey;

@property (nonatomic, copy, nullable) void (^onRegionTap)(void);
/// 号码 / 验证码有输入（用于「用户已动过」判定与清红字）。
@property (nonatomic, copy, nullable) void (^onEdit)(void);

- (instancetype)initWithIdentifierPrefix:(NSString *)prefix;
/// 清空号码与验证码（退出 / 被踢回登录页时不留上一个人的号码）。
- (void)clearInputs;

@end

NS_ASSUME_NONNULL_END
