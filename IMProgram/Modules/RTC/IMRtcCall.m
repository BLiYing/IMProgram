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
#import "IMProgram-Swift.h" // IMRtcCallHistoryBridge（fetchCallHistory 的 Swift 桥接，见该文件头注释）
@import IMCallEngine;
@import IMCallEngineWebRTC;
@import IMCallKit;

/// im-rtc 2.1.0 Kit 内置多语言：宿主已解析好的界面语言（IMLocalization.language，非"跟系统"）
/// 直接映射到 SDK 的 IMLocale，不借 SDK 自带的 IMLocale.system()——两套"跟系统"判据并存会打架。
static IMLocale IMLocaleFromLanguage(NSString *language) {
    return [language isEqualToString:IMLanguagePrefEnglish] ? IMLocaleEn : IMLocaleZhCN;
}

BOOL IMRtcCallPhaseCountsAsInCall(NSInteger kitPhase) {
    switch ((IMCallKitPhase)kitPhase) {
        case IMCallKitPhaseIncoming:
        case IMCallKitPhaseOutgoing:
        case IMCallKitPhaseConnecting:
        case IMCallKitPhaseActive:
            return YES;
        case IMCallKitPhaseIdle:
        case IMCallKitPhaseEnded:
            return NO;
    }
    return NO; // SDK 以后新增的阶段：宁可多响一声，不可把提醒全部吞掉
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

- (BOOL)isInCall { return _kit != nil && IMRtcCallPhaseCountsAsInCall(_kit.controller.objcPhase); }

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

#pragma mark - 通话历史（设置 ▸ 最近通话）

- (void)fetchCallHistoryWithLimit:(NSInteger)limit cursor:(NSNumber *)cursor
                       completion:(void (^)(NSArray<IMCallHistoryRecord *> *_Nullable records,
                                             NSNumber *_Nullable nextCursor, NSError *_Nullable error))completion {
    if (!_engine) {
        completion(nil, nil, [NSError errorWithDomain:@"IMRtcCall" code:-1
                                              userInfo:@{ NSLocalizedDescriptionKey: [self unavailableReason] ?: @"通话未启动" }]);
        return;
    }
    NSUInteger gen = _generation;
    __weak typeof(self) ws = self;
    [IMRtcCallHistoryBridge fetchCallHistoryWithEngine:_engine limit:limit cursor:cursor
        completion:^(NSArray<NSDictionary *> *dicts, NSNumber *nextCursor, NSError *error) {
        typeof(self) self = ws;
        if (!self) { return; }
        // 换票以外的另一处 generation 防护：拉取在途时若 stop/重新 start 过（登出/切账号），
        // 这批结果已经对不上当前引擎，一律当失败处理，不回填到新状态里。
        if (gen != self->_generation) {
            completion(nil, nil, [NSError errorWithDomain:@"IMRtcCall" code:-2
                                                  userInfo:@{ NSLocalizedDescriptionKey: @"通话服务已重启，本次查询作废" }]);
            return;
        }
        if (error) { completion(nil, nil, error); return; }
        NSMutableArray<IMCallHistoryRecord *> *records = [NSMutableArray arrayWithCapacity:dicts.count];
        for (NSDictionary *d in dicts) { [records addObject:[IMRtcCall historyRecordFromDictionary:d]]; }
        completion(records, nextCursor, nil);
    }];
}

+ (IMCallHistoryRecord *)historyRecordFromDictionary:(NSDictionary *)d {
    IMCallHistoryRecord *r = [IMCallHistoryRecord new];
    r.callID = [d[@"call_id"] isKindOfClass:NSString.class] ? d[@"call_id"] : @"";
    r.roomID = [d[@"room_id"] isKindOfClass:NSString.class] ? d[@"room_id"] : @"";
    r.caller = [d[@"caller"] isKindOfClass:NSString.class] ? d[@"caller"] : @"";
    r.video = [d[@"media_type"] isEqual:@"video"];
    r.group = [d[@"is_group"] respondsToSelector:@selector(boolValue)] && [d[@"is_group"] boolValue];
    r.reason = [d[@"reason"] isKindOfClass:NSString.class] ? d[@"reason"] : @"";
    r.endedBy = [d[@"ended_by"] isKindOfClass:NSString.class] ? d[@"ended_by"] : @"";
    r.durationSec = [d[@"duration_sec"] respondsToSelector:@selector(integerValue)] ? [d[@"duration_sec"] integerValue] : 0;
    r.startedAtMs = [d[@"started_at_ms"] respondsToSelector:@selector(longLongValue)] ? [d[@"started_at_ms"] longLongValue] : 0;
    r.connectedAtMs = [d[@"connected_at_ms"] respondsToSelector:@selector(longLongValue)] ? [d[@"connected_at_ms"] longLongValue] : 0;
    r.endedAtMs = [d[@"ended_at_ms"] respondsToSelector:@selector(longLongValue)] ? [d[@"ended_at_ms"] longLongValue] : 0;
    r.userData = [d[@"user_data"] isKindOfClass:NSString.class] ? d[@"user_data"] : @"";
    r.chatGroupID = [d[@"chat_group_id"] isKindOfClass:NSString.class] ? d[@"chat_group_id"] : @"";
    NSMutableArray<NSString *> *members = [NSMutableArray array];
    if ([d[@"members"] isKindOfClass:NSArray.class]) {
        for (NSDictionary *m in d[@"members"]) {
            NSString *uid = [m isKindOfClass:NSDictionary.class] && [m[@"uid"] isKindOfClass:NSString.class] ? m[@"uid"] : nil;
            if (uid.length > 0) { [members addObject:uid]; }
        }
    }
    r.memberUIDs = members;
    return r;
}

- (nullable NSUUID *)addEventObserver:(void (^)(IMCallEvent *event))block {
    if (!_engine || !block) { return nil; }
    void (^wrapped)(IMCallEvent *) = ^(IMCallEvent *event) {
        dispatch_async(dispatch_get_main_queue(), ^{ block(event); });
    };
    return [_engine addEventObserver:wrapped];
}

- (void)removeEventObserver:(NSUUID *)token {
    if (_engine && token) { [_engine removeEventObserver:token]; }
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
