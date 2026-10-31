//  IMEmailLogin.h
//  邮箱登录（绑定已验证邮箱，邮箱作第二个登录名）的纯规则：邮箱预检 / 脱敏、错误码 → 文案 / 落点、重发倒计时、状态模型。
//  设计 ../IMServer/docs/design/EMAIL_LOGIN_DESIGN.md，契约 PROTOCOL §7.2。全部是无副作用的纯函数，页面只做渲染。
//  6 位验证码的清洗 / 满位判断**复用** IMTwoStep（IMTwoStepSanitizeCode / IMTwoStepCodeIsComplete），这里不另写。
//  **日志红线**：验证码 / 密码不得写日志；邮箱只能以 IMEmailMasked 脱敏形态出现在日志里。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 业务错误码（PROTOCOL §7.2；一经发布永不改）。
FOUNDATION_EXPORT NSInteger const IMErrCodeEmailInvalid;      ///< 200030
FOUNDATION_EXPORT NSInteger const IMErrCodeEmailTaken;        ///< 200031
FOUNDATION_EXPORT NSInteger const IMErrCodeEmailCodeInvalid;  ///< 200032（data.attempts_left）
FOUNDATION_EXPORT NSInteger const IMErrCodeEmailCodeExpired;  ///< 200033（data.retry_after_sec）
FOUNDATION_EXPORT NSInteger const IMErrCodeEmailNotBound;     ///< 200034
FOUNDATION_EXPORT NSInteger const IMErrCodeEmailUnchanged;    ///< 200035
FOUNDATION_EXPORT NSInteger const IMErrCodeEmailUnavailable;  ///< 200036
FOUNDATION_EXPORT NSInteger const IMErrCodeEmailSendFailed;   ///< 200037

/// 邮箱最大长度（含 @）。
FOUNDATION_EXPORT NSUInteger const IMEmailMaxLength;
/// 重发间隔默认秒数（服务端 send-code 回 resend_after 时以它为准）。
FOUNDATION_EXPORT NSInteger const IMEmailResendDefaultSeconds;

#pragma mark - 邮箱

/// 去首尾空白。
FOUNDATION_EXPORT NSString *IMEmailTrim(NSString *_Nullable raw);
/// 轻量预检（权威校验在服务端）：去首尾空白后长度 1…254、无任何空白、恰好一个 @、@ 前非空、@ 后有 . 且不以 . 开头 / 结尾。
FOUNDATION_EXPORT BOOL IMEmailPrecheck(NSString *_Nullable raw);
/// 日志 / 通知用的脱敏形态：local 保留首字符其余 `***`（local 只有 1 位则整个 `*`），domain 原样；不含 @ 的串整体 `***`。
FOUNDATION_EXPORT NSString *IMEmailMasked(NSString *_Nullable email);
/// 请求体 `lang`：当前 App 解析后的语言（`en` / `zh-Hans`）。
FOUNDATION_EXPORT NSString *IMEmailAPILang(void);

#pragma mark - 错误

/// 业务码 → 界面文案。attemptsLeft / retryAfterSec < 0 表示服务端没给；
/// 200032 仅在 attemptsLeft 为 1…2 时显示「还可尝试 N 次」；100002 有 retryAfterSec>0 才带秒数。没有专属文案的码返回 fallback。
FOUNDATION_EXPORT NSString *_Nullable IMEmailErrorMessage(NSInteger code, NSInteger attemptsLeft, NSInteger retryAfterSec,
                                                          NSString *_Nullable fallback);

/// 填邮箱 + 密码页：错误高亮哪个输入（输入一律不清空，只描红边）。
typedef NS_ENUM(NSInteger, IMEmailFormTarget) {
    IMEmailFormTargetNone,
    IMEmailFormTargetEmail,
    IMEmailFormTargetPassword,
};
FOUNDATION_EXPORT IMEmailFormTarget IMEmailFormTargetForError(NSInteger code);

/// 验证码页失败后的界面动作。
typedef NS_ENUM(NSInteger, IMEmailCodeAction) {
    IMEmailCodeActionShowError,        ///< 只显示红字
    IMEmailCodeActionClearAndRefocus,  ///< 红字 + 清空 6 位框并重新聚焦（满 6 位被拒，留着无意义；唯一允许清空的输入）
    IMEmailCodeActionExpired,          ///< 失效：红字 + 清空，焦点回「重新发送」，倒计时按 retry_after_sec
};
FOUNDATION_EXPORT IMEmailCodeAction IMEmailCodeActionForError(NSInteger code);

#pragma mark - 重发倒计时

/// 距截止时刻还剩多少整秒（向上取整，≤0 → 0）。截止时刻为 nil → 0。
FOUNDATION_EXPORT NSInteger IMEmailResendRemaining(NSDate *_Nullable deadline, NSDate *now);
/// 服务端给的秒数 → 截止时刻：seconds<0（没给）→ 默认 60；0 → now（可立即重发）。
FOUNDATION_EXPORT NSDate *IMEmailResendDeadline(NSInteger serverSeconds, NSDate *now);
/// 链接文案：remaining>0 → 「重新发送（59s）」，否则「重新发送」。
FOUNDATION_EXPORT NSString *IMEmailResendTitle(NSInteger remaining);
/// 验证码页：满 6 位且当前没有在途请求 → 自动提交。
FOUNDATION_EXPORT BOOL IMEmailShouldAutoSubmit(NSString *_Nullable code, BOOL busy);

#pragma mark - 状态模型

@interface IMEmailState : NSObject
@property (nonatomic, assign) BOOL available;   ///< false = 服务端未配置 SMTP（已绑定账号仍可解绑）
@property (nonatomic, assign) BOOL bound;
@property (nonatomic, copy, nullable) NSString *email;
@property (nonatomic, strong, nullable) NSDate *verifiedAt;
/// 解析 GET /users/me/email 的 data；非字典返回 nil。bound 但缺 email 视为未绑定。
+ (nullable instancetype)stateFromJSON:(nullable id)json;
/// verify 成功体 {email, verified_at} → 已绑定状态（available=YES）；缺 email 返回 nil。
+ (nullable instancetype)boundStateFromVerifyJSON:(nullable id)json;
/// 已绑定页副标题「绑定于 2026年10月30日」；无时间返回 nil。
- (nullable NSString *)boundSinceText;
@end

/// 隐私页行右值：未加载（nil）→ nil（留空）；已加载 → 邮箱地址 / 「未绑定」。
FOUNDATION_EXPORT NSString *_Nullable IMEmailRowValueText(IMEmailState *_Nullable state);
/// 毫秒 / 秒时间戳自适应（> 1e11 视为毫秒）。
FOUNDATION_EXPORT NSDate *IMEmailDateFromTimestamp(double ts);

NS_ASSUME_NONNULL_END
