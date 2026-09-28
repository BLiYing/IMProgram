#import "IMRtcCall.h"
#import "IMLocalization.h"
#import "IMDeviceIdentity.h"
#import "IMGroupInfo.h"
#import "IMHTTPService+RTC.h"
#import "IMLog.h"
#import "IMRtcCallRecordSender.h"
#import "IMRtcConfig.h"
#import "IMRtcInviteProvider.h"
#import "IMRtcProfileResolver.h"
@import IMCallEngine;
@import IMCallEngineWebRTC;
@import IMCallKit;

/// im-rtc 2.1.0 Kit 内置多语言：宿主已解析好的界面语言（IMLocalization.language，非"跟系统"）
/// 直接映射到 SDK 的 IMLocale，不借 SDK 自带的 IMLocale.system()——两套"跟系统"判据并存会打架。
static IMLocale IMLocaleFromLanguage(NSString *language) {
    return [language isEqualToString:IMLanguagePrefEnglish] ? IMLocaleEn : IMLocaleZhCN;
}

@implementation IMRtcCall {
    IMCallEngine *_engine;
    IMCallKit *_kit;
    IMRtcProfileResolver *_resolver;
    NSUUID *_observer;
    id _languageObserver;
    NSString *_uid;
    /// 每次 start / stop 加一：旧引擎迟到的回调一律不算数，别改动新一代的状态。
    NSUInteger _generation;
}

+ (instancetype)shared {
    static IMRtcCall *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [IMRtcCall new]; });
    return shared;
}

- (BOOL)isStarted { return _engine != nil; }

#pragma mark - 生命周期

- (void)startWithUserID:(NSString *)uid {
    NSString *deviceID = IMDeviceIdentity.deviceID;
    if (_engine && [_uid isEqualToString:uid]) { return; }
    [self stop];
    IMRtcConfig *config = IMRtcConfig.load;
    if (!config.isUsable) {
        IMLogWarnWithTag(IMLogTagRTC, @"rtc_disabled missing=%@", [config.missingKeys componentsJoinedByString:@","]);
        return;
    }
    NSString *problem = [IMRtcConfig problemForID:uid kind:@"uid"] ?: [IMRtcConfig problemForID:deviceID kind:@"device_id"];
    NSURL *url = [NSURL URLWithString:config.wsURL];
    if (!problem && !url) { problem = @"wsUrl 不是合法地址"; }
    if (problem) { IMLogWarnWithTag(IMLogTagRTC, @"rtc_disabled reason=%@", problem); return; }

    [self installSDKLog];
    _uid = [uid copy];
    NSUInteger gen = _generation;
    _engine = [IMCallEngine webRTCEngineWithURL:url deviceID:deviceID];
    _resolver = [IMRtcProfileResolver new];
    IMCallKitConfig *kitConfig = [IMCallKitConfig new];
    kitConfig.profileResolver = _resolver; // 弱引用，强引用由 _resolver 持有
    IMRtcInviteProvider *invite = [IMRtcInviteProvider new]; // Kit 强引用
    invite.selfUID = uid;
    kitConfig.inviteMemberProvider = invite;
    kitConfig.locale = IMLocaleFromLanguage(IMLocalization.shared.language);
    _kit = [[IMCallKit alloc] initWithEngine:_engine config:kitConfig];
    _resolver.kit = _kit;
    [_kit start]; // 必须在 login 之前
    __weak typeof(self) ws = self;
    _observer = [_engine addEventObserver:^(IMCallEvent *event) {
        dispatch_async(dispatch_get_main_queue(), ^{ [ws handleEvent:event generation:gen]; });
    }];
    // 通话中途切语言：config 是 Kit 持有的同一个实例，改了立刻对下一条文案生效，不用重建 Kit。
    _languageObserver = [NSNotificationCenter.defaultCenter addObserverForName:IMLanguageDidChangeNotification
                                                                         object:nil queue:NSOperationQueue.mainQueue
                                                                     usingBlock:^(NSNotification *note) {
        IMRtcCall *strongSelf = ws;
        if (!strongSelf) { return; }
        strongSelf->_kit.config.locale = IMLocaleFromLanguage(IMLocalization.shared.language);
    }];

    IMLogWithTag(IMLogTagRTC, @"rtc_start uid=%@ url=%@", uid, config.wsURL);
    [self signTokenWithCompletion:^(NSString *token) {
        // 换票是异步网络请求：这段时间里可能又 stop 了（登出/切账号），generation 变了就不该
        // 再对一个已经被销毁的 _engine 发 login（同 handleEvent:generation: 的防护思路）。
        if (gen != self->_generation || token.length == 0) { return; }
        [self->_engine login:token completionHandler:^(NSError *_Nullable error) {
            if (error) { IMLogWarnWithTag(IMLogTagRTC, @"rtc_login_failed code=%ld %@", (long)error.code, error.localizedDescription); }
        }];
    }];
}

- (void)stop {
    _generation++;
    IMCallEngine *old = _engine;
    if (!old) { return; }
    if (_observer) { [old removeEventObserver:_observer]; }
    _observer = nil;
    if (_languageObserver) { [NSNotificationCenter.defaultCenter removeObserver:_languageObserver]; }
    _languageObserver = nil;
    _engine = nil;
    _kit = nil;
    _resolver.kit = nil;
    _resolver = nil;
    [old destroyWithCompletionHandler:^{}];
    IMLogWithTag(IMLogTagRTC, @"rtc_stop uid=%@", _uid);
}

#pragma mark - 入口

- (NSString *)placeSingleCallToPeer:(NSString *)peerUID video:(BOOL)video {
    NSString *reason = [self unavailableReason] ?: [IMRtcConfig problemForID:peerUID kind:@"对方 id"];
    if (reason) { return reason; }
    _resolver.groupID = @"";
    [_kit.controller placeCall:@[peerUID] mediaType:(video ? @"video" : @"audio")
                       isGroup:NO chatGroupID:@"" userData:@"" timeoutSec:0];
    return nil;
}

- (NSString *)placeGroupCallInGroup:(NSString *)groupID callees:(NSArray<NSString *> *)calleeUIDs {
    NSString *reason = [self unavailableReason] ?: [IMRtcConfig problemForID:groupID kind:@"群号"];
    if (reason) { return reason; }
    if (calleeUIDs.count == 0) { return IMLocalized(@"rtc.error.no_callees"); }
    _resolver.groupID = groupID;
    [_kit.controller placeCall:calleeUIDs mediaType:@"video"
                       isGroup:YES chatGroupID:groupID userData:@"" timeoutSec:0];
    return nil;
}

- (void)feedGroup:(IMGroupInfo *)group {
    [_resolver putGroup:group];
}

- (nullable NSString *)unavailableReason {
    if (_engine) { return nil; }
    IMRtcConfig *config = IMRtcConfig.load;
    if (!config.isUsable) {
        return [@"通话未配置：IMRtcConfig.local.plist 缺 " stringByAppendingString:[config.missingKeys componentsJoinedByString:@"、"]];
    }
    return IMLocalized(@"rtc.error.not_started");
}

#pragma mark - 票

/// 票的唯一来源：调 IMServer 代为向 im-rtc-server 换票，本端不需要也不该知道任何签名密钥。
/// `token` 取自当前 IM 会话（`IMHTTPService.currentToken`，与项目里其它业务接口取 token 同一个
/// 入口）；未登录 IM 或换票失败都只记日志、回调 nil——调用方据此静默把通话入口当"不可用"处理，
/// 不打扰主流程。
- (void)signTokenWithCompletion:(void (^)(NSString *_Nullable token))completion {
    NSString *authToken = IMHTTPService.sharedService.currentToken;
    if (authToken.length == 0) {
        IMLogWarnWithTag(IMLogTagRTC, @"rtc_sign_failed reason=尚未登录IM，无法换取接入票");
        completion(nil);
        return;
    }
    [IMHTTPService.sharedService rtcTokenWithToken:authToken completion:^(NSDictionary *data, NSError *error) {
        NSString *token = [data[@"token"] isKindOfClass:NSString.class] ? data[@"token"] : nil;
        if (error || token.length == 0) {
            IMLogWarnWithTag(IMLogTagRTC, @"rtc_sign_failed code=%ld %@", (long)error.code, error.localizedDescription ?: @"响应缺少 token");
            completion(nil);
            return;
        }
        completion(token);
    }];
}

#pragma mark - 引擎事件

- (void)handleEvent:(IMCallEvent *)event generation:(NSUInteger)gen {
    if (gen != _generation) { return; }
    switch (event.name) {
        case IMCallEventNameConnected:
            IMLogWithTag(IMLogTagRTC, @"rtc_connected session=%@ resumed=%@",
                         event.payload[@"session_id"] ?: @"-", event.payload[@"resumed"] ?: @NO);
            break;
        case IMCallEventNameDisconnected:
            IMLogWarnWithTag(IMLogTagRTC, @"rtc_disconnected code=%@ reconnect=%@",
                             event.payload[@"code"] ?: @"-", event.payload[@"will_reconnect"] ?: @NO);
            break;
        case IMCallEventNameKickedOut: [self handleKickedOut:event]; break;
        case IMCallEventNameTokenWillExpire: {
            // 下一次重连生效，不打断当前通话。换票是异步的，回来时可能已经 stop 过（同上方
            // startWithUserID: 的 generation 防护）。
            [self signTokenWithCompletion:^(NSString *token) {
                if (gen != self->_generation || token.length == 0) { return; }
                [self->_engine updateToken:token expiresAtMS:0];
                IMLogWithTag(IMLogTagRTC, @"rtc_token_renewed");
            }];
            break;
        }
        case IMCallEventNameCallReceived: {
            // 来电：只记下这通是不是群通话、哪个群，好让解析器读对的成员表（不发任何请求）。
            BOOL isGroup = [event.payload[@"is_group"] boolValue];
            NSString *group = event.payload[@"chat_group_id"];
            _resolver.groupID = isGroup && [group isKindOfClass:NSString.class] ? group : @"";
            break;
        }
        case IMCallEventNameCallSummary:
            // 每通电话终局后恰好一次；只有主叫（role=caller）发通话记录消息，被叫不发。
            [IMRtcCallRecordSender handleSummaryPayload:event.payload selfUID:_uid ?: @""];
            break;
        case IMCallEventNameError:
            IMLogWarnWithTag(IMLogTagRTC, @"rtc_error %@", event.payload);
            break;
        default: break;
    }
}

- (void)handleKickedOut:(IMCallEvent *)event {
    NSInteger raw = [event.payload[@"reason"] integerValue];
    IMLogWarnWithTag(IMLogTagRTC, @"rtc_kicked_out reason=%ld", (long)raw);
    NSString *uid = _uid;
    switch ((IMKickedOutReason)raw) {
        // 票不好使：本机再签一张重来，用户无感。
        case IMKickedOutReasonAuthExpired:
            [self stop];
            [self startWithUserID:uid];
            break;
        // 别处登录 / 被吊销 / 参数被拒：换票救不了，也不自动重连，停下来等人看日志。
        default:
            [self stop];
            break;
    }
}

/// SDK 自己的日志默认只走 os.Logger。转给宿主的 IMLog：控制台能看到，Debug 构建还会回传到 IMServer。
- (void)installSDKLog {
    [IMRTCLogBridge installWithMinLevel:0 handler:^(NSInteger level, NSString *message) {
        NSString *line = [@"rtc-sdk " stringByAppendingString:message];
        if (level >= 3) { IMLogErrorWithTag(IMLogTagRTC, @"%@", line); }
        else if (level == 2) { IMLogWarnWithTag(IMLogTagRTC, @"%@", line); }
        else if (level == 1) { IMLogWithTag(IMLogTagRTC, @"%@", line); }
        else { IMLogDebugWithTag(IMLogTagRTC, @"%@", line); }
    }];
}

@end
