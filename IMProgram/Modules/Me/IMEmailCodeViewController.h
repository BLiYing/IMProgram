//  IMEmailCodeViewController.h
//  验证码页：6 位码输入（复用两步验证的 IMTwoStepMakeCodeField / IMTwoStepSanitizeCode，满 6 位自动提交）、
//  「重新发送」60 秒倒计时（Timer 随页面生命周期，离开即销毁；服务端给 retry_after_sec 时按它重建）、「更换邮箱」回上一步。
//  重发需要当前密码（send-code 要验密码）：密码只在本页内存里保留，页面销毁即丢。

#import "IMTwoStepFormViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMEmailCodeViewController : IMTwoStepFormViewController
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID
                       email:(NSString *)email password:(NSString *)password resendDeadline:(NSDate *)deadline;
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID NS_UNAVAILABLE;
@property (nonatomic, strong, readonly) UITextField *codeField;
@property (nonatomic, strong, readonly) UILabel *resendLabel;
/// 重发倒计时的截止时刻（测试可读）。
@property (nonatomic, strong, readonly, nullable) NSDate *resendDeadline;
/// 倒计时 Timer 是否在跑（离开页面应为 NO）。
@property (nonatomic, assign, readonly, getter=isCountdownRunning) BOOL countdownRunning;
@end

NS_ASSUME_NONNULL_END
