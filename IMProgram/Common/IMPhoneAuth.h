//  IMPhoneAuth.h
//  手机号与短信验证码的**纯规则与模型**（不依赖 UIKit，配 XCTest）：登录页页签 / 链接 / 地区、确认身份弹层页签与错误落点、
//  隐私与安全两行的可见性与去向、错误码 → 文案、发码倒计时（按号码计）、没用掉的短信验证码缓存、本机用户名可信判定。
//  设计 ../IMServer/docs/design/PHONE_AUTH_DESIGN.md §4 §6 §7，协议 PROTOCOL §7.3；三端同一张表（Web phoneAuthRules.ts / Android PhoneAuthRules.kt）。
//  **日志红线**：完整手机号、验证码、票据不得写日志；号码只以 IMPhoneMasked 打码形态出现。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 错误码（PROTOCOL §7.3；一经发布永不改）

FOUNDATION_EXPORT NSInteger const IMErrCodeRateLimited;        ///< 100002（data.retry_after_sec 可选）
FOUNDATION_EXPORT NSInteger const IMErrCodeWrongPassword;      ///< 200002
FOUNDATION_EXPORT NSInteger const IMErrCodeSMSUnavailable;     ///< 200040
FOUNDATION_EXPORT NSInteger const IMErrCodePhoneInvalid;       ///< 200041
FOUNDATION_EXPORT NSInteger const IMErrCodePhoneTaken;         ///< 200042
FOUNDATION_EXPORT NSInteger const IMErrCodeSMSCodeInvalid;     ///< 200043（data.attempts_left）
FOUNDATION_EXPORT NSInteger const IMErrCodeSMSCodeExpired;     ///< 200044（data.retry_after_sec）
FOUNDATION_EXPORT NSInteger const IMErrCodeSMSSendFailed;      ///< 200045
FOUNDATION_EXPORT NSInteger const IMErrCodeSMSDailyCap;        ///< 200046
FOUNDATION_EXPORT NSInteger const IMErrCodePhoneNotRegistered; ///< 200047
FOUNDATION_EXPORT NSInteger const IMErrCodePhoneTicketInvalid; ///< 200048
FOUNDATION_EXPORT NSInteger const IMErrCodeProofRequired;      ///< 200049：没带 proof 且本会话 10 分钟内没验证过（§15.2）

/// 200040–200048 → 本地化文案（转调 IMFriendlyMessageForCode，文案表在 HTTP 层）；其它码 nil（不落到通用码的映射）。
FOUNDATION_EXPORT NSString *_Nullable IMPhoneAuthFriendlyMessage(NSInteger code);

/// 验证码长度。
FOUNDATION_EXPORT NSUInteger const IMSMSCodeLength;
/// 服务端没给 resend_after 时的兜底倒计时。
FOUNDATION_EXPORT NSInteger const IMSMSResendDefaultSeconds;
/// 新密码最短长度（字节规则在服务端，端上只做长度预检）。
FOUNDATION_EXPORT NSUInteger const IMPasswordMinLength;
/// 默认国家码（老服务端 / 短信不可用时的占位）。
FOUNDATION_EXPORT NSString * const IMPhoneDefaultCountryCode;

#pragma mark - 身份证明（proof）

/// `proof`：密码或短信验证码二选一（PROTOCOL §7.3）。请求体里放 `JSONObject`。
@interface IMIdentityProof : NSObject
+ (instancetype)passwordProof:(NSString *)password;
+ (instancetype)smsProof:(NSString *)code;
/// 空证明（§15.2 最近验证过免确认）：请求体里既不带 `proof` 也不带旧的顶层密码字段（见 IMBodyWithProof）。
+ (instancetype)emptyProof;
@property (nonatomic, assign, readonly) BOOL isSMS;
@property (nonatomic, assign, readonly) BOOL isEmpty;
/// 能留在页面内存里给下一次请求复用：只有密码。验证码一次性（交过即用掉）；空证明靠的免确认窗口会过期。
@property (nonatomic, assign, readonly) BOOL isReusable;
/// 密码或验证码原文（只在内存，不得写日志）。
@property (nonatomic, copy, readonly) NSString *secret;
/// `{"password": …}` 或 `{"sms_code": …}`；空证明为 `{}`（请求体请走 IMBodyWithProof，空证明整个不带）。
- (NSDictionary<NSString *, NSString *> *)JSONObject;
@end

/// 带 proof 的请求体：body 加上 `"proof": proof.JSONObject`；空证明（§15.2）原样返回 body——不带 `proof`。
FOUNDATION_EXPORT NSDictionary *IMBodyWithProof(NSDictionary *body, IMIdentityProof *proof);

#pragma mark - 登录前配置（public-config）

@interface IMSMSRegion : NSObject
@property (nonatomic, copy, readonly) NSString *code; ///< 国家码，不带 +（如 "86"）
@property (nonatomic, copy, readonly) NSString *iso;  ///< ISO 3166 代码（如 "CN"），显示名由端上本地化
+ (instancetype)regionWithCode:(NSString *)code iso:(NSString *)iso;
@end

FOUNDATION_EXPORT NSString * const IMRegisterMethodUsername;
FOUNDATION_EXPORT NSString * const IMRegisterMethodPhone;

/// GET /api/v1/public-config 的 data。老服务端没有新字段 = 「短信不可用、可用户名注册」。
@interface IMLoginConfig : NSObject
@property (nonatomic, assign, readonly) BOOL registerEnabled;
@property (nonatomic, assign, readonly) BOOL smsAvailable;
@property (nonatomic, copy, readonly) NSArray<IMSMSRegion *> *smsRegions;
@property (nonatomic, copy, readonly) NSArray<NSString *> *registerMethods;
/// 解析信封响应体：code≠0 / 非 JSON / 缺字段一律走老服务端口径（registerEnabled=YES、smsAvailable=NO、registerMethods=[username]）。
+ (instancetype)configFromResponseData:(nullable NSData *)data;
/// 拉不到（离线 / 地址非法）时的口径：同老服务端。
+ (instancetype)fallbackConfig;
@end

#pragma mark - 隐私与安全状态（GET /users/me/security）

/// 资料里曾自填、还没绑定成登录手机号的号码（§15.1 `legacy_phone`，本人自己的号码，明文只用于预填、不写日志）。
@interface IMLegacyPhone : NSObject
@property (nonatomic, copy) NSString *countryCode;
@property (nonatomic, copy) NSString *phone;
@property (nonatomic, copy) NSString *masked;
/// 缺 country_code / phone（或不是非空字符串）返回 nil；缺 masked 时按 IMPhoneMasked 补。
+ (nullable instancetype)legacyPhoneFromJSON:(nullable id)json;
@end

@interface IMSecurityState : NSObject
@property (nonatomic, assign) BOOL phoneBound;
@property (nonatomic, copy, nullable) NSString *phoneMasked;
@property (nonatomic, assign) BOOL passwordSet;
@property (nonatomic, assign) BOOL smsAvailable;
/// 本会话「最近验证过免确认」还剩几秒（§15.2；缺省 / 老服务端 = 0 = 要确认）。
@property (nonatomic, assign) NSInteger recentAuthSec;
@property (nonatomic, strong, nullable) IMLegacyPhone *legacyPhone;
/// 非字典返回 nil；缺 password_set 时按 YES（老账号都有密码）。
+ (nullable instancetype)stateFromJSON:(nullable id)json;
@end

#pragma mark - 登录页

typedef NS_ENUM(NSInteger, IMLoginTab) {
    IMLoginTabNone = -1, ///< 没记过 / 不记（用户名注册、免密登录）
    IMLoginTabSMS = 0,
    IMLoginTabPassword = 1,
};

/// 可见页签：短信可用 → [验证码, 密码]；否则只有密码（不画页签条）。config 为 nil（还没取到）按老服务端口径。
FOUNDATION_EXPORT NSArray<NSNumber *> *IMLoginTabsForConfig(IMLoginConfig *_Nullable config);
/// 默认页签：记住的那个（仍可见时）；否则第一个（短信可用即验证码登录）。remembered = IMLoginTabNone 即没记过。
FOUNDATION_EXPORT IMLoginTab IMLoginInitialTab(NSArray<NSNumber *> *tabs, IMLoginTab remembered);
/// 配置到了（或换了服务器）之后的页签：用户已经动过（点过页签 / 开始输入）就不再自动切，除非当前页签已不可见。
FOUNDATION_EXPORT IMLoginTab IMLoginTabAfterConfig(IMLoginTab current, BOOL touched, NSArray<NSNumber *> *tabs, IMLoginTab remembered);
FOUNDATION_EXPORT BOOL IMLoginShowsForgotPassword(IMLoginConfig *_Nullable config);
/// 「用户名注册」链接：register_methods 含 username；config 为 nil 按可注册。
FOUNDATION_EXPORT BOOL IMLoginShowsUsernameRegister(IMLoginConfig *_Nullable config);
/// 「未注册的手机号验证后将自动注册」：register_methods 含 phone。
FOUNDATION_EXPORT BOOL IMLoginShowsAutoRegisterHint(IMLoginConfig *_Nullable config);
/// 地区多于一个才出选择器；只有一个时显示固定的 +86，不可点。
FOUNDATION_EXPORT BOOL IMLoginShowsRegionPicker(IMLoginConfig *_Nullable config);
/// 默认国家码：第一个开放地区；没有时 86。
FOUNDATION_EXPORT NSString *IMLoginDefaultCountryCode(IMLoginConfig *_Nullable config);
/// 重载配置后是否把已选国家码重置成默认：换了服务器，或已选的不在新的开放地区里（开放地区为空 = 不动）。
FOUNDATION_EXPORT BOOL IMLoginShouldResetCountryCode(BOOL hostChanged, NSString *current, IMLoginConfig *_Nullable config);
/// 重设密码成功后回密码登录页预填的登录名：默认地区填本地号码；其余地区带 `+国家码`；号码本身已以 `+` 开头（别的国家码）原样返回。
/// 号码先过 IMPhoneNationalNumber（粘贴的 `+当前国家码` 前缀去掉）。
FOUNDATION_EXPORT NSString *IMLoginIdentForReset(NSString *countryCode, NSString *phone, NSString *defaultCountryCode);
/// 记住页签：只有真正进入主界面后才保存（用户名注册、静默恢复不记）。读出 IMLoginTabNone = 没记过。
FOUNDATION_EXPORT IMLoginTab IMLoginRememberedTab(NSUserDefaults *defaults);
/// 只写验证码 / 密码两种；IMLoginTabNone（及其它值）不写、不动已记的值。
FOUNDATION_EXPORT void IMLoginRememberTab(NSUserDefaults *defaults, IMLoginTab tab);
/// 地区显示名：「中国 +86」（按 App 语言本地化 ISO）。
FOUNDATION_EXPORT NSString *IMSMSRegionTitle(IMSMSRegion *region, NSLocale *locale);

#pragma mark - 号码 / 验证码

/// 去掉空白与短横线。
FOUNDATION_EXPORT NSString *IMPhoneNormalize(NSString *_Nullable raw);
/// 发给服务端的本地号码：先 IMPhoneNormalize；粘贴进来的号码以 `+<当前国家码>` 开头时去掉这段前缀（打码显示才对）；
/// 以别的 `+国家码` 开头的原样保留（服务端能解析）。发码 / 验证码登录 / 重设密码 / 绑定取号码都走这一条。
FOUNDATION_EXPORT NSString *IMPhoneNationalNumber(NSString *_Nullable countryCode, NSString *_Nullable raw);
/// 打码：`+86 136****0001`（与服务端 phone_masked 同形：前 3 后 4）；号码不足 7 位整体以 * 代替。
FOUNDATION_EXPORT NSString *IMPhoneMasked(NSString *countryCode, NSString *_Nullable raw);
/// 验证码输入清洗：只留数字（全角折半角）、最多 6 位。转调 IMTwoStepSanitizeCode / IMTwoStepCodeIsComplete。
FOUNDATION_EXPORT NSString *IMSMSCodeSanitize(NSString *_Nullable raw);
FOUNDATION_EXPORT BOOL IMSMSCodeIsComplete(NSString *_Nullable code);
/// 新密码两遍的本地校验：返回 i18n 键，nil = 通过（reset.too_short / reset.mismatch）。
FOUNDATION_EXPORT NSString *_Nullable IMNewPasswordErrorKey(NSString *_Nullable password, NSString *_Nullable confirm);

#pragma mark - 错误 → 文案 / 落点

/// 错误自带文案（localizedDescription 非空）就用它，否则 fallback。
FOUNDATION_EXPORT NSString *IMErrorMessageOrFallback(NSError *_Nullable error, NSString *fallback);

/// 发码失败文案：100002 带 retryAfter>0 → 「请 N 秒后再试」，否则「发送过于频繁」；2000xx → err.2000xx；其余 fallback。
FOUNDATION_EXPORT NSString *_Nullable IMSMSSendErrorMessage(NSInteger code, NSInteger retryAfterSec, NSString *_Nullable fallback);
/// 带验证码的提交失败文案：200043 带 attemptsLeft≥0 → err.200043.left；其余同 IMPhoneAuthFriendlyMessage，再退 fallback。
FOUNDATION_EXPORT NSString *_Nullable IMSMSSubmitErrorMessage(NSInteger code, NSInteger attemptsLeft, NSString *_Nullable fallback);
/// 发码失败后倒计时从几秒开始：100002 / 200044 带 retry_after_sec>0 时用它；其余 -1（不动倒计时）。
FOUNDATION_EXPORT NSInteger IMSMSCountdownAfterFailure(NSInteger code, NSInteger retryAfterSec);
/// 确认身份弹层：这个错误留在弹层里重输（YES），还是收起交给页面（NO）。
/// field == "proof" → 弹层；field == "code" → 页面；无 field 时 200002 / 200043 / 200044 → 弹层；
/// 100002 一律页面；200040 不带 field → 页面；其余页面。
FOUNDATION_EXPORT BOOL IMProofErrorStaysInSheet(NSInteger code, NSString *_Nullable field);

#pragma mark - 确认身份弹层

/// 宿主的提交：拿到 proof 发请求，结束时调 finish(error)（nil = 成功）。
typedef void (^IMProofSubmitBlock)(IMIdentityProof *proof, void (^finish)(NSError *_Nullable error));
/// 弹层收尾：succeeded=YES 操作成功；NO + pageError 交给页面显示；NO + nil = 用户取消。
typedef void (^IMProofCompletion)(BOOL succeeded, NSError *_Nullable pageError);

/// 免确认至少还剩这么多秒才不弹层（§15.2：留出请求往返，边界上过期的回 200049 再弹）。
FOUNDATION_EXPORT NSInteger const IMProofRecentAuthMinSec;
/// 刚取到的安全状态说本会话最近验证过（recent_auth_sec ≥ 15）→ 不弹层，直接用空证明发请求。nil → NO。
FOUNDATION_EXPORT BOOL IMProofSkipsSheet(IMSecurityState *_Nullable state);
/// 免确认的分流（§15.2）：IMProofSkipsSheet(state) 为 NO → ask()（照常弹层）；为 YES → submit(空证明)：
/// 成功 → completion(YES, nil)；回 200049（边界上刚好过期）→ ask()；其它错 → completion(NO, error) 交给页面。
/// finish 只认第一次。
FOUNDATION_EXPORT void IMProofRunWithoutSheet(IMSecurityState *_Nullable state, IMProofSubmitBlock submit,
                                              void (^ask)(void), IMProofCompletion completion);

typedef NS_ENUM(NSInteger, IMProofTab) {
    IMProofTabPassword = 0,
    IMProofTabSMS = 1,
};
/// 弹层页签：有密码 + 能发短信「密码 / 短信验证码」；有密码不能发短信只有密码；没设密码只有验证码，
/// 没设密码又不能发短信（短信不可用或没绑手机）→ 空数组（弹层提示 proof.sms_unavailable、确认不可点）。
/// state 为 nil（取不到）→ 只有密码（老账号都有密码）。
FOUNDATION_EXPORT NSArray<NSNumber *> *IMProofTabsForState(IMSecurityState *_Nullable state);
/// 只有一种方式时不显示分段控件。
FOUNDATION_EXPORT BOOL IMProofShowsSegments(NSArray<NSNumber *> *tabs);
/// 确认可点：密码非空 / 验证码满 6 位，且不在提交中。
FOUNDATION_EXPORT BOOL IMProofCanConfirm(IMProofTab tab, NSString *_Nullable password, NSString *_Nullable code, BOOL busy);

/// 没用掉的短信验证码（内存）：下次打开弹层预填并落在短信页签。宿主页面持有一份，离开页面随之释放。
@interface IMProofCodeCache : NSObject
@property (nonatomic, copy, readonly, nullable) NSString *code;
/// 操作成功：清。
- (void)noteSucceeded;
/// 交的是验证码、失败但不是证明本身的错（交给页面）：码仍有效，记下；交的是密码 → 不动。
- (void)notePageErrorAfterProof:(IMIdentityProof *)proof;
/// 服务端判错过的码（证明本身的错，且交的是验证码）：作废。
- (void)noteProofRejected:(IMIdentityProof *)proof;
/// 用户取消：输入框里是完整 6 位才记，输了一半的不留；停在密码页签（tabWasSMS=NO）不动。
- (void)noteCancelledWithTypedCode:(nullable NSString *)typed tabWasSMS:(BOOL)tabWasSMS;
/// 重新获取了验证码：旧码作废。
- (void)noteResent;
@end

#pragma mark - 发码倒计时（按号码计）

/// 截止时刻按号码计：换号码（或国家码）就清本地截止时刻；以服务端 resend_after / retry_after_sec 为准。纯值对象，时间由调用方注入。
@interface IMResendClock : NSObject
@property (nonatomic, strong, readonly, nullable) NSDate *deadline;
@property (nonatomic, assign, readonly) BOOL sentOnce;
@property (nonatomic, copy, readonly, nullable) NSString *owner;
/// 号码变了：清掉上一个号码的截止时刻与「已发过」。同一个号码不动。
- (void)followTarget:(nullable NSString *)target;
- (NSInteger)secondsLeftAt:(NSDate *)now;
/// 发码成功：按 resend_after（<0 → 默认 60）起倒计时。
- (void)noteSentWithResendAfter:(NSInteger)resendAfter now:(NSDate *)now;
/// 发码失败：100002 / 200044 带 retry_after_sec 时按它重建；其余不动。
- (void)noteFailureCode:(NSInteger)code retryAfter:(NSInteger)retryAfter now:(NSDate *)now;
@end

/// 发码按钮文案：倒计时中「N 秒后重发」；发过一次「重新获取」；否则「获取验证码」。
FOUNDATION_EXPORT NSString *IMSMSSendButtonTitle(NSInteger secondsLeft, BOOL sentOnce);

#pragma mark - 隐私与安全

/// 「登录手机号」行：状态未知不显示；短信不可用且没绑定时不显示（没法绑）。
FOUNDATION_EXPORT BOOL IMSecurityShowsPhoneRow(IMSecurityState *_Nullable state);
FOUNDATION_EXPORT NSString *_Nullable IMSecurityPhoneRowValue(IMSecurityState *_Nullable state);
FOUNDATION_EXPORT NSString *_Nullable IMSecurityPasswordRowValue(IMSecurityState *_Nullable state);

typedef NS_ENUM(NSInteger, IMPhoneRowAction) {
    IMPhoneRowActionBind,
    IMPhoneRowActionChange,
    IMPhoneRowActionSMSUnavailable, ///< 已绑定但短信不可用：提示，换不了
};
FOUNDATION_EXPORT IMPhoneRowAction IMSecurityPhoneRowAction(IMSecurityState *state);
/// 「登录手机号」页的一次性提示（§15.1）：没绑定登录手机号且服务端下发了 legacy_phone 才有；否则 nil。
FOUNDATION_EXPORT IMLegacyPhone *_Nullable IMSecurityLegacyPhonePrompt(IMSecurityState *_Nullable state);

typedef NS_ENUM(NSInteger, IMPasswordProofMode) {
    IMPasswordProofModeOldPassword,
    IMPasswordProofModeSMS,
};
/// 「登录密码」点进去：没设密码 → 设置（YES）；有 / 未知 → 修改（NO）。
FOUNDATION_EXPORT BOOL IMSecurityPasswordPageIsSet(IMSecurityState *_Nullable state);
/// 修改密码页的「用短信验证码修改」链接：已绑定手机号且短信可用。
FOUNDATION_EXPORT BOOL IMSecurityCanChangePasswordBySMS(IMSecurityState *_Nullable state);
/// 实际用哪种证明：设置只能验证码；修改按页面上的切换（且仍可用短信时）。
FOUNDATION_EXPORT IMPasswordProofMode IMSecurityPasswordProofMode(BOOL setMode, BOOL switchedToSMS, IMSecurityState *_Nullable state);

#pragma mark - 本机用户名

/// 手机号形态的登录名（PROTOCOL §7.3）：`+` 开头，或 5–15 位纯数字（decimalDigitCharacterSet）。
/// HTTP 日志脱敏（IMHTTPLogFormatter）与本机用户名可信判定共用这一条。
FOUNDATION_EXPORT BOOL IMLooksLikePhoneIdentifier(NSString *_Nullable value);

/// 本机会话里的用户名可信吗：符合 `^[a-z0-9_]{5,32}$` 且不是 5–15 位纯数字（手机号形态）。
/// 只用于判断**存量本地值**；登录响应里服务端给的 username 一律直接采用。
FOUNDATION_EXPORT BOOL IMStoredUsernameIsTrusted(NSString *_Nullable username);

/// 收下一次登录成功响应后内存里该留的用户名：响应带 username → 用它；没带（/token/refresh 不带、老服务端）时，
/// 当前值就是本机存着的那个、且那个是服务端发的（storedFromServer）→ 保留（服务端发的纯数字老用户名也算）；
/// 否则按 IMStoredUsernameIsTrusted 过滤，不可信 → nil。
FOUNDATION_EXPORT NSString *_Nullable IMUsernameAfterLoginResponse(NSString *_Nullable current, NSString *_Nullable serverValue,
                                                                   NSString *_Nullable storedValue, BOOL storedFromServer);

NS_ASSUME_NONNULL_END
