//  IMSMSCodeField.h
//  6 位短信验证码输入框 + 行内「获取验证码」文字按钮（rightView，15 regular，右内 8；PHONE_AUTH_DESIGN §10、交互稿 1-1 / 1-6 / 1-9）。
//  倒计时期间按钮置灰（tertiaryLabel）不可点，文案「N 秒后重发」；倒计时按号码计（IMResendClock，宿主在号码变化时 followTarget:）。
//  登录页用 accent，安全类页面用 systemBlue（两类页面现有主色）。Timer 只在挂进窗口期间存在，离屏即停。
//  只负责显示与输入清洗；发码请求由宿主在 onSend 里发起，结束后调 finishSending 刷新。

#import <UIKit/UIKit.h>
#import "IMPhoneAuth.h"

@class IMSMSSendResult;

NS_ASSUME_NONNULL_BEGIN

@interface IMSMSCodeField : UITextField

- (instancetype)initWithTint:(UIColor *)tint;

/// 倒计时状态（按号码计）。默认自带一份；几个输入框共用同一个号码时由宿主注入同一个实例。
@property (nonatomic, strong) IMResendClock *clock;
/// 点「获取验证码」：只在可点时回调。宿主发请求前应先 beginSending，结束后 finishSending。
@property (nonatomic, copy, nullable) void (^onSend)(void);
/// 宿主额外条件（如号码非空）；NO 时按钮置灰。默认 YES。
@property (nonatomic, assign) BOOL sendAllowed;
@property (nonatomic, assign, readonly, getter=isSending) BOOL sending;
@property (nonatomic, strong, readonly) UIButton *sendButton;

- (void)beginSending;
/// 发码结束（成功或失败）：刷新按钮文案 / 可点状态，必要时开始倒计时。
- (void)finishSending;
/// 发码请求结束（四处发码共用的收尾）：sameTarget=YES 时成功按 resend_after 起倒计时、失败按 retry_after_sec 重建
/// （发码途中改了号码传 NO：结果不记到新号码头上）；最后 finishSending。
/// 返回失败文案（IMSMSSendErrorMessage，非短信专属码退回错误自带文案）；成功或没有错误时 nil。宿主只做各自特有的动作。
- (nullable NSString *)applySendResult:(nullable IMSMSSendResult *)result error:(nullable NSError *)error sameTarget:(BOOL)sameTarget;
/// 外部改了 clock / sendAllowed 后刷新按钮。
- (void)refreshSendButton;

@end

NS_ASSUME_NONNULL_END
