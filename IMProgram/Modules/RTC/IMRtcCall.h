//  IMRtcCall.h
//  im-rtc 通话的宿主侧接入点（**只在主线程调用**）。
//
//  · startWithUserID:  进入主界面（IM 已登录）时调用——建引擎、接 Kit；登录由 Kit 负责（`IMCallKitConfig.tokenProvider`，
//                      im-rtc 2.2.0：取票登录、失败退避重试、拨号前补登录、续票、票失效重登）。幂等。
//  · stop              退出 / 被踢离开主界面时调用——销毁引擎、断开 im-rtc。不停的话换账号会有两条连接，服务端踢掉其中一条。
//  · placeSingle… / placeGroup…  业务入口，界面全部由 Kit 接管。
//
//  票从哪来只在 +signTokenWithCompletion: 一处（交给 Kit 的 tokenProvider 调）（调 IMServer POST /api/v1/rtc/token 代为向
//  im-rtc-server 换票，本端不知道任何签名密钥）。对端：im-android `rtc/RtcCall.kt`、im-web `src/rtc/rtcEngine.ts`。

#import <Foundation/Foundation.h>
#import "IMCallHistoryRecord.h"

@class IMGroupInfo;
@class IMCallEvent;

NS_ASSUME_NONNULL_BEGIN

/// 通话界面阶段（SDK `IMCallKitPhase` 的原始值）算不算「正在通话」：来电 / 拨出 / 接通中 / 通话中算，
/// 空闲与「已结束」（纯展示的结束页）不算。抽成纯函数是为了能单测，`isInCall` 只是把当前阶段喂给它。
FOUNDATION_EXPORT BOOL IMRtcCallPhaseCountsAsInCall(NSInteger kitPhase);


@interface IMRtcCall : NSObject

+ (instancetype)shared;

/// 引擎已建好（不代表握手已成功，连接态看日志）。**不是「正在通话」**——登录后只要通话服务配置齐全
/// 它就恒为 YES；要问"是不是在通话"用 `isInCall`。
@property (nonatomic, readonly) BOOL isStarted;

/// 正在音视频通话中（来电响铃 / 拨出中 到 挂断之间）。**通知判定 `IMAlertDecide` 的 `inCall` 读它**
/// （NOTIFICATIONS_DESIGN §3.1：通话中不响不振不弹横幅）。对端：im-android `RtcCall.inCall`。
///
/// 2026-09-30 之前 `inCall` 误读的是 `isStarted`：通话服务一配好，应用内提示音 / 振动 / 横幅就
/// 全部永久静默（没配通话服务的环境里 `isStarted` 恒 NO，所以一直没暴露）。
@property (nonatomic, readonly) BOOL isInCall;

/// 配置不全或 uid 不合规只记日志，入口点击时会给出原因。同一账号重复调用是空操作。
- (void)startWithUserID:(NSString *)uid;
- (void)stop;

/// 来电横幅（离线推送）上点了「接听」/「拒绝」（AppDelegate 收到通知响应时调，PUSH_M5_DESIGN §3.8）。
/// 这通已经在响就当场照做；还没到（App 刚被拉起、还没连上）就记下来，等来电到了再做。
- (void)applyNotificationActionForCallID:(NSString *)callID accept:(BOOL)accept;

/// 单聊一对一通话。返回 nil 表示已交给 Kit；否则是给用户看的原因。
- (nullable NSString *)placeSingleCallToPeer:(NSString *)peerUID video:(BOOL)video;

/// 群通话：`groupID` 是 IM 的群号，`calleeUIDs` 是选中的成员（不含自己）。以视频通话发起（群通话摄像头默认关）。
- (nullable NSString *)placeGroupCallInGroup:(NSString *)groupID callees:(NSArray<NSString *> *)calleeUIDs;

/// 群资料页加载成员时顺手喂给通话（群通话按群成员表取名字与头像）；通话服务没起来时是空操作。
- (void)feedGroup:(IMGroupInfo *)group;

#pragma mark - 通话历史（设置 ▸ 最近通话）

/// 查自己的通话记录，按发起时间倒序，游标翻页（`cursor` 首页传 nil；下一页传上一页回调的 `nextCursor`）。
/// SDK 的 `fetchCallHistory` 没标 `@objc`（返回体是纯 Swift struct），本方法内部经 `IMRtcCallHistoryBridge`
/// （Swift shim，把 struct 拍平成字典）转成 `IMCallHistoryRecord`；调用方（`IMCallHistoryPaginator`）
/// 不需要知道这层桥接。引擎未启动、或本次调用期间 `stop`/`startWithUserID:` 被调用过（generation 已变）
/// 都会回调错误，不会崩溃、不会把结果套到已经不存在的引擎上。`completion` 恒在主线程回调。
- (void)fetchCallHistoryWithLimit:(NSInteger)limit cursor:(nullable NSNumber *)cursor
                       completion:(void (^)(NSArray<IMCallHistoryRecord *> *_Nullable records,
                                             NSNumber *_Nullable nextCursor, NSError *_Nullable error))completion;

/// 供页面级消费者监听 SDK 事件（如「最近通话」页收到 `IMCallEventNameCallEnd` 后重拉首页）。
/// 引擎未启动时返回 nil，调用方据此判定订阅不可用（同 `unavailableReason` 的降级口径）。
/// 回调恒在主线程；`stop`/`startWithUserID:` 重建引擎后旧 token 自然失效（无需也不该再收到事件）。
- (nullable NSUUID *)addEventObserver:(void (^)(IMCallEvent *event))block;
- (void)removeEventObserver:(nullable NSUUID *)token;

@end

NS_ASSUME_NONNULL_END
