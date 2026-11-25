//  IMPushCall.h
//  App 在后台 / 被杀时的通话提醒（离线推送，PUSH_M5_DESIGN §3.8、PROTOCOL §6.14「通话提醒」）。
//
//  服务端按 im-rtc 的 webhook 推三种：来电横幅（call_kind=incoming，时效性 + 来电铃声 + 类别 IM_CALL）、
//  群通话未接（missed）、通话结束（ended，静默原地替换横幅）。同一通电话共用一个 apns-collapse-id，
//  所以替换都是服务端做的；本文件管 App 这一侧的三件事：
//   · 注册类别 IM_CALL 的「接听」「拒绝」两个按钮——**都先拉起 App**（App 连上之后服务端才开始振铃）；
//   · 记下用户点的是哪个按钮（或点了横幅本身 = 要看接听页），等那通来电真的到了再照做（IMPushCallPendingAction）；
//   · SDK 的来电界面接手 / 通话结束时，从通知中心拿掉这通电话的横幅（App 活着才删得掉）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 来电横幅的通知类别与两个按钮的 identifier（与服务端 apnsCallCategory 同值）。
FOUNDATION_EXPORT NSString *const IMPushCallCategory;
FOUNDATION_EXPORT NSString *const IMPushCallActionAccept;
FOUNDATION_EXPORT NSString *const IMPushCallActionReject;

/// 纯函数：通知 userInfo 里的 call_id（不是通话提醒返回 nil）。
FOUNDATION_EXPORT NSString *_Nullable IMPushCallIDFromUserInfo(NSDictionary *_Nullable userInfo);

/// 用户在来电横幅上做了什么：点「接听」/「拒绝」按钮，或点横幅本身（= 要看全屏接听页，BACKLOG B3）。
typedef NS_ENUM(NSInteger, IMPushCallTap) {
    IMPushCallTapNone = 0,   // 不是通话动作（未接 / 已结束提醒点开、清除等）：照常进会话
    IMPushCallTapAccept,
    IMPushCallTapReject,
    IMPushCallTapShow,
};

/// 纯函数：通知响应 → 要对那通来电做什么（与 Android `callTapOf` 同口径）。按钮看 actionIdentifier；
/// 点横幅本身只有**来电横幅**（call_kind=incoming）才算「要看接听页」，其余返回 None。
FOUNDATION_EXPORT IMPushCallTap IMPushCallTapFrom(NSString *_Nullable actionIdentifier, NSDictionary *_Nullable userInfo);

/// 注册 IM_CALL 类别（启动时、以及 App 内切换语言后各调一次：按钮文字是注册那一刻的语言）。与已注册的其它类别合并，不覆盖。
FOUNDATION_EXPORT void IMPushCallRegisterCategory(void);

/// 从通知中心移除这通电话的通知（来电横幅 / 结束替换后的那条；异步，任意线程可调）。
FOUNDATION_EXPORT void IMPushCallRemoveDeliveredNotifications(NSString *callID);

/// 用户在来电横幅上点了按钮 / 横幅本身，App 还没收到这通来电时先记在这里。
/// 只记一条；超过 120 秒（最长振铃时长）作废。时间由调用方传入，便于单测。
@interface IMPushCallPendingAction : NSObject
+ (instancetype)shared;
- (void)requestCallID:(NSString *)callID tap:(IMPushCallTap)tap nowMS:(int64_t)nowMS;
/// 这通来电有没有待执行的动作：有就取走（只执行一次），返回 IMPushCallTap 的值；没有返回 nil。
- (nullable NSNumber *)consumeCallID:(NSString *)callID nowMS:(int64_t)nowMS;
@end

NS_ASSUME_NONNULL_END
