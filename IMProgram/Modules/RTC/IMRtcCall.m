#import "IMRtcCall.h"
#import "IMLocalization.h"
#import "IMDeviceIdentity.h"
#import "IMGroupInfo.h"
#import "IMLog.h"
#import "IMRtcCallRecordSender.h"
#import "IMRtcConfig.h"
#import "IMRtcInviteProvider.h"
#import "IMRtcProfileResolver.h"
@import IMCallEngine;
@import IMCallEngineWebRTC;
@import IMCallKit;

@implementation IMRtcCall {
    IMCallEngine *_engine;
    IMCallKit *_kit;
    IMRtcProfileResolver *_resolver;
    NSUUID *_observer;
    NSString *_uid;
    IMRtcConfig *_config;
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
    _config = config;
    _uid = [uid copy];
    NSUInteger gen = _generation;
    _engine = [IMCallEngine webRTCEngineWithURL:url deviceID:deviceID];
    _resolver = [IMRtcProfileResolver new];
    IMCallKitConfig *kitConfig = [IMCallKitConfig new];
    kitConfig.profileResolver = _resolver; // 弱引用，强引用由 _resolver 持有
    IMRtcInviteProvider *invite = [IMRtcInviteProvider new]; // Kit 强引用
    invite.selfUID = uid;
    kitConfig.inviteMemberProvider = invite;
    _kit = [[IMCallKit alloc] initWithEngine:_engine config:kitConfig];
    _resolver.kit = _kit;
    [_kit start]; // 必须在 login 之前
    __weak typeof(self) ws = self;
    _observer = [_engine addEventObserver:^(IMCallEvent *event) {
        dispatch_async(dispatch_get_main_queue(), ^{ [ws handleEvent:event generation:gen]; });
    }];

    NSString *token = [self signToken];
    IMLogWithTag(IMLogTagRTC, @"rtc_start uid=%@ app=%@ url=%@", uid, config.appID, config.wsURL);
    if (token.length == 0) { return; }
    [_engine login:token completionHandler:^(NSError *_Nullable error) {
        if (error) { IMLogWarnWithTag(IMLogTagRTC, @"rtc_login_failed code=%ld %@", (long)error.code, error.localizedDescription); }
    }];
}

- (void)stop {
    _generation++;
    IMCallEngine *old = _engine;
    if (!old) { return; }
    if (_observer) { [old removeEventObserver:_observer]; }
    _observer = nil;
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

/// 票的唯一来源。联调期本机签调试票；接了后台换票接口之后这里改成调接口。
- (NSString *)signToken {
#if DEBUG
    NSError *error = nil;
    NSString *token = [IMDebugToken tokenWithAppID:_config.appID keyID:_config.keyID secret:_config.debugSecret
                                               uid:_uid deviceID:IMDeviceIdentity.deviceID ttlSec:0 error:&error];
    if (!token) { IMLogWarnWithTag(IMLogTagRTC, @"rtc_sign_failed %@", error.localizedDescription); }
    return token ?: @"";
#else
    IMLogWarnWithTag(IMLogTagRTC, @"rtc_disabled reason=Release 构建没有调试签票，需要接后台换票接口");
    return @"";
#endif
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
            // 下一次重连生效，不打断当前通话。
            [_engine updateToken:[self signToken] expiresAtMS:0];
            IMLogWithTag(IMLogTagRTC, @"rtc_token_renewed");
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
