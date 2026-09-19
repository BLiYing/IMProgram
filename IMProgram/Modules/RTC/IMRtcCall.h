//  IMRtcCall.h
//  im-rtc 通话的宿主侧接入点（**只在主线程调用**）。
//
//  · startWithUserID:  进入主界面（IM 已登录）时调用——建引擎、本机签调试票、登录 im-rtc，此后能拨也能接。幂等。
//  · stop              退出 / 被踢离开主界面时调用——销毁引擎、断开 im-rtc。不停的话换账号会有两条连接，服务端踢掉其中一条。
//  · placeSingle… / placeGroup…  业务入口，界面全部由 Kit 接管。
//
//  票从哪来只在 -signToken 一处，以后加「接口 / 调试」开关只改那里。对端：im-android `rtc/RtcCall.kt`、im-web `src/rtc/rtcEngine.ts`。

#import <Foundation/Foundation.h>

@class IMGroupInfo;

NS_ASSUME_NONNULL_BEGIN

@interface IMRtcCall : NSObject

+ (instancetype)shared;

/// 引擎已建好（不代表握手已成功，连接态看日志）。
@property (nonatomic, readonly) BOOL isStarted;

/// 配置不全或 uid 不合规只记日志，入口点击时会给出原因。同一账号重复调用是空操作。
- (void)startWithUserID:(NSString *)uid;
- (void)stop;

/// 单聊一对一通话。返回 nil 表示已交给 Kit；否则是给用户看的原因。
- (nullable NSString *)placeSingleCallToPeer:(NSString *)peerUID video:(BOOL)video;

/// 群通话：`groupID` 是 IM 的群号，`calleeUIDs` 是选中的成员（不含自己）。以视频通话发起（群通话摄像头默认关）。
- (nullable NSString *)placeGroupCallInGroup:(NSString *)groupID callees:(NSArray<NSString *> *)calleeUIDs;

/// 群资料页加载成员时顺手喂给通话（群通话按群成员表取名字与头像）；通话服务没起来时是空操作。
- (void)feedGroup:(IMGroupInfo *)group;

@end

NS_ASSUME_NONNULL_END
