//  IMTwoStep.h
//  两步验证（TOTP + 恢复码）的纯规则：输入清洗、恢复码归一化、4 位分组、错误码 → 文案、状态页行文案、leave 拦截条件。
//  设计 ../IMServer/docs/design/TWO_STEP_VERIFICATION_DESIGN.md，契约 PROTOCOL §7.1。全部是无副作用的纯函数，页面只做渲染。
//  **日志红线**：本文件处理的验证码 / 密钥 / 恢复码 / ticket 一律不得写日志。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 业务错误码（PROTOCOL §7.1；一经发布永不改）。
FOUNDATION_EXPORT NSInteger const IMErrCodeTwoStepRequired;       ///< 200020 密码对但需要第二步（data.ticket）
FOUNDATION_EXPORT NSInteger const IMErrCodeTwoStepCodeInvalid;    ///< 200021 码不对（登录第二步带 data.attempts_left）
FOUNDATION_EXPORT NSInteger const IMErrCodeTwoStepTicketInvalid;  ///< 200022 ticket / 待确认密钥超时
FOUNDATION_EXPORT NSInteger const IMErrCodeTwoStepNotEnabled;     ///< 200023
FOUNDATION_EXPORT NSInteger const IMErrCodeTwoStepAlreadyEnabled; ///< 200024
FOUNDATION_EXPORT NSInteger const IMErrCodeTwoStepUnavailable;    ///< 200025 服务端未配置密钥

/// 恢复码长度（不含连字符），输入框含连字符最长 12 字符。
FOUNDATION_EXPORT NSUInteger const IMTwoStepRecoveryCodeLength;
FOUNDATION_EXPORT NSUInteger const IMTwoStepRecoveryInputMaxLength;

#pragma mark - 输入清洗

/// 6 位动态码清洗：只留 ASCII 数字（含全角数字折算），截 6 位。「123 456」「12-34-56」均可洗成 123456。
FOUNDATION_EXPORT NSString *IMTwoStepSanitizeCode(NSString *_Nullable raw);
/// 恰好 6 位数字。
FOUNDATION_EXPORT BOOL IMTwoStepCodeIsComplete(NSString *_Nullable code);
/// 恢复码归一化（提交时才做，输入过程不改写文本）：小写 + 去掉连字符 / 空白。
FOUNDATION_EXPORT NSString *IMTwoStepNormalizeRecovery(NSString *_Nullable raw);
/// 归一化后正好是一个恢复码长度。
FOUNDATION_EXPORT BOOL IMTwoStepRecoveryIsComplete(NSString *_Nullable raw);
/// 从一段粘贴文本里取第一个合法恢复码（10 位、字符集 abcdefghjkmnpqrstuvwxyz23456789，大小写不敏感）；
/// 原文可带连字符 / 空格 / 换行 / 「1.」之类前缀 / 整份清单（复制全部 = 10 行，取第一个）。取不到返回 nil。返回归一化小写 10 位。
FOUNDATION_EXPORT NSString *_Nullable IMTwoStepExtractRecoveryCode(NSString *_Nullable text);
/// 归一化的 10 位恢复码 → 展示形态 xxxxx-xxxxx（长度不对原样返回）。
FOUNDATION_EXPORT NSString *IMTwoStepFormatRecovery(NSString *_Nullable normalized);
/// 这次编辑是不是「粘贴」：替换串长度 >1、含换行、或会让内容超过最长输入。
FOUNDATION_EXPORT BOOL IMTwoStepEditLooksLikePaste(NSString *_Nullable current, NSRange range, NSString *_Nullable replacement);
/// 恢复码框是否接受这次编辑（只拒绝超长，不改写；输入法组词期间 marked=YES 一律放行）。
FOUNDATION_EXPORT BOOL IMTwoStepRecoveryAllowsEdit(NSString *_Nullable current, NSRange range,
                                                    NSString *_Nullable replacement, BOOL marked);

#pragma mark - 展示

/// 密钥分组展示：每 groupSize 位一组、空格分隔；groupsPerLine>0 时每行 N 组、换行分隔。输入里已有的空格 / 连字符会先去掉。
FOUNDATION_EXPORT NSString *IMTwoStepGroupSecret(NSString *_Nullable secret, NSUInteger groupSize, NSUInteger groupsPerLine);
/// 状态页「恢复码」行右值：剩余 N 个。
FOUNDATION_EXPORT NSString *IMTwoStepRecoveryRemainingText(NSInteger remaining);
/// 剩余 ≤2 → 右值变橙色并带 footer。
FOUNDATION_EXPORT BOOL IMTwoStepRecoveryIsLow(NSInteger remaining);
/// 状态页「恢复码」行所在组的 footer；不低时 nil。
FOUNDATION_EXPORT NSString *_Nullable IMTwoStepRecoveryFooter(NSInteger remaining);
/// 隐私页行右值：未加载（nil）→ nil（留空）；已加载 → 开启 / 关闭。
FOUNDATION_EXPORT NSString *_Nullable IMTwoStepRowValueText(NSNumber *_Nullable enabled);
/// 恢复码文件正文（标题行 + 空行 + 每行一个码）。
FOUNDATION_EXPORT NSString *IMTwoStepRecoveryFileText(NSArray<NSString *> *codes);
/// 复制全部的正文（每行一个码）。
FOUNDATION_EXPORT NSString *IMTwoStepRecoveryClipboardText(NSArray<NSString *> *codes);
/// 解析 recovery_codes：丢掉非字符串与空串。
FOUNDATION_EXPORT NSArray<NSString *> *IMTwoStepParseRecoveryCodes(id _Nullable raw);

#pragma mark - 错误文案

typedef NS_ENUM(NSInteger, IMTwoStepErrorContext) {
    IMTwoStepErrorContextPassword,  ///< 验证密码（setup）
    IMTwoStepErrorContextBind,      ///< 绑定认证器（enable）
    IMTwoStepErrorContextManage,    ///< 关闭 / 重新生成（密码 + 码）
    IMTwoStepErrorContextLogin,     ///< 登录第二步
};

/// 业务码 → 界面文案。attemptsLeft<0 表示服务端没给；仅登录第二步且 1…2 时才显示「还可尝试 N 次」。
/// recentlyEnabled：刚用某个码开启过（同一 30 秒窗口的码不能再用，防重放）→ 200021 追加「请等待认证器刷新…」。
/// 没有专属文案的码返回 fallback（通常是服务端 / 通用文案）。
FOUNDATION_EXPORT NSString *IMTwoStepErrorMessage(NSInteger code, IMTwoStepErrorContext context,
                                                  NSInteger attemptsLeft, BOOL recentlyEnabled, NSString *_Nullable fallback);
/// 这个错误意味着「当前流程已作废，要回到起点」：待确认密钥超时（Bind 的 200022）/ ticket 失效（Login 的 200022）。
FOUNDATION_EXPORT BOOL IMTwoStepErrorEndsFlow(NSInteger code, IMTwoStepErrorContext context);

#pragma mark - 状态机 / 交互条件

/// 登录第二步失败后的界面动作。
typedef NS_ENUM(NSInteger, IMTwoStepLoginAction) {
    IMTwoStepLoginActionShowError,   ///< 只显示红字（恢复码框保留输入）
    IMTwoStepLoginActionRetryCode,   ///< 红字 + 清空 6 位框并重新聚焦（输满自动提交，不清空就无法再次触发）
    IMTwoStepLoginActionExpired,     ///< ticket 作废：丢弃 ticket，回密码页并显示「已超时，请重新登录」
};
/// 失败码 → 动作。数字框清空是「其余表单一律不清空」之外的唯一例外。
FOUNDATION_EXPORT IMTwoStepLoginAction IMTwoStepLoginActionForError(NSInteger code, BOOL recoveryMode);

/// 登录二步页：满 6 位且当前没有在途请求 → 自动提交。
FOUNDATION_EXPORT BOOL IMTwoStepShouldAutoSubmit(NSString *_Nullable code, BOOL busy);
/// 保存恢复码页：只要在这页且还没点「完成」，返回 / 关闭都要拦截并二次确认（恢复码只显示一次）。
FOUNDATION_EXPORT BOOL IMTwoStepShouldInterceptLeave(BOOL onCodesPage, BOOL completed);
/// 「完成」可点：已勾选「我已保存恢复码」。
FOUNDATION_EXPORT BOOL IMTwoStepCanFinish(BOOL savedChecked);
/// 验证页（关闭 / 重新生成）提交按钮可点：动态码满 6 位，或恢复码满长（身份确认在弹层里，不看密码）。
FOUNDATION_EXPORT BOOL IMTwoStepCanSubmitVerify(NSString *_Nullable code, BOOL useRecovery);
/// 刚开启过两步验证的「防重放提示」窗口（秒）：略大于一个时间步。
FOUNDATION_EXPORT NSTimeInterval const IMTwoStepReplayHintWindow;

/// 记录 / 查询「刚用一个动态码开启了两步验证」（仅内存；窗口内再用码会被服务端当重放拒绝）。
FOUNDATION_EXPORT void IMTwoStepMarkEnabledNow(void);
FOUNDATION_EXPORT BOOL IMTwoStepRecentlyEnabled(NSDate *now);

#pragma mark - 状态模型

@interface IMTwoStepState : NSObject
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, strong, nullable) NSDate *enabledAt;
@property (nonatomic, assign) NSInteger recoveryRemaining; ///< 未提供为 -1
/// 解析 GET /users/me/two-step 的 data；非字典返回 nil。
+ (nullable instancetype)stateFromJSON:(nullable id)json;
/// 状态页副标题「{date} 开启」；无时间返回 nil。
- (nullable NSString *)enabledSinceText;
@end

NS_ASSUME_NONNULL_END
