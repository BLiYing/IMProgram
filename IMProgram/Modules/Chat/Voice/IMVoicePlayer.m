//
//  IMVoicePlayer.m
//

#import "IMVoicePlayer.h"
#import "IMMessageModel.h"
#import <AVFoundation/AVFoundation.h>

NSNotificationName const IMVoicePlayerDidChangeStateNotification = @"IMVoicePlayerDidChangeStateNotification";
NSNotificationName const IMVoicePlayerDidMarkPlayedNotification = @"IMVoicePlayerDidMarkPlayedNotification";

NSString *_Nullable IMVoicePlayerPlayableIDForMessage(IMMessageModel *m) {
    if (m.serverMsgID.length > 0) { return m.serverMsgID; }
    if (m.clientMsgID.length > 0) { return m.clientMsgID; }
    return nil;
}

/// 已播集合本地键：per-uid + per-conv，键值合入一个 NSSet<messageID>。
/// per-uid 隔离防"账号 A 播过的被账号 B 视为已播"，per-conv 只是索引便捷（可省略）。
static NSString *_Nonnull IMVoicePlayerPlayedKey(NSString *ownerUID, NSString *convID) {
    return [NSString stringWithFormat:@"im.voice.played.%@.%@", ownerUID ?: @"anon", convID ?: @"na"];
}

@interface IMVoicePlayer () <AVAudioPlayerDelegate>
@property (nonatomic, strong, nullable) AVAudioPlayer *player;
@property (nonatomic, copy, nullable) NSString *currentID;
@property (nonatomic, copy, nullable) NSString *currentConvID;
@property (nonatomic, copy, nullable) NSString *currentOwner;
@property (nonatomic, strong, nullable) CADisplayLink *progressLink;
@property (nonatomic, assign) IMVoicePlayerState currentState;
@end

@implementation IMVoicePlayer

+ (instancetype)sharedPlayer {
    static IMVoicePlayer *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [IMVoicePlayer new]; });
    return inst;
}

- (void)togglePlayback:(IMMessageModel *)message localFileURL:(NSURL *)localFileURL {
    NSString *mid = IMVoicePlayerPlayableIDForMessage(message);
    if (!mid || !localFileURL) { return; }

    // 已经在播这条 → 暂停/继续；否则先停当前的再切到新条。
    if ([self.currentID isEqualToString:mid] && self.player) {
        if (self.player.isPlaying) {
            [self.player pause];
            self.currentState = IMVoicePlayerStatePaused;
            [self stopProgressLink];
            [self broadcastStateForID:mid convID:self.currentConvID state:IMVoicePlayerStatePaused];
        } else {
            [self activateSessionForPlayback];
            [self.player play];
            self.currentState = IMVoicePlayerStatePlaying;
            [self startProgressLink];
            [self broadcastStateForID:mid convID:self.currentConvID state:IMVoicePlayerStatePlaying];
        }
        return;
    }

    // 切到新条：先停旧的。
    [self stop];

    NSError *err = nil;
    self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:localFileURL error:&err];
    if (!self.player || err) { return; }
    self.player.delegate = self;
    [self.player prepareToPlay];

    self.currentID = mid;
    self.currentConvID = message.convID;
    self.currentOwner = nil; // 由 markPlayed 传入
    self.currentState = IMVoicePlayerStatePlaying;

    [self activateSessionForPlayback];
    [self.player play];
    [self startProgressLink];
    [self broadcastStateForID:mid convID:self.currentConvID state:IMVoicePlayerStatePlaying];
}

- (void)stop {
    if (!self.player) { return; }
    [self.player stop];
    [self stopProgressLink];
    NSString *oldID = self.currentID;
    NSString *oldConv = self.currentConvID;
    self.player = nil;
    self.currentID = nil;
    self.currentConvID = nil;
    self.currentState = IMVoicePlayerStateIdle;
    if (oldID) { [self broadcastStateForID:oldID convID:oldConv state:IMVoicePlayerStateIdle]; }
}

- (IMVoicePlayerState)stateForMessageID:(NSString *)messageID {
    if (!messageID || ![messageID isEqualToString:self.currentID]) { return IMVoicePlayerStateIdle; }
    return self.currentState;
}

- (double)progressForMessageID:(NSString *)messageID {
    if (!messageID || ![messageID isEqualToString:self.currentID] || !self.player) { return 0; }
    NSTimeInterval total = self.player.duration;
    if (total <= 0) { return 0; }
    return MAX(0, MIN(1, self.player.currentTime / total));
}

- (BOOL)hasPlayed:(NSString *)messageID inConv:(NSString *)convID owner:(NSString *)ownerUID {
    if (!messageID) { return NO; }
    NSArray *arr = [[NSUserDefaults standardUserDefaults] arrayForKey:IMVoicePlayerPlayedKey(ownerUID, convID)];
    return [arr isKindOfClass:[NSArray class]] && [arr containsObject:messageID];
}

- (void)markPlayed:(NSString *)messageID inConv:(NSString *)convID owner:(NSString *)ownerUID {
    if (!messageID) { return; }
    NSString *key = IMVoicePlayerPlayedKey(ownerUID, convID);
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSArray *arr = [ud arrayForKey:key];
    NSMutableArray *set = [arr isKindOfClass:[NSArray class]] ? [arr mutableCopy] : [NSMutableArray array];
    if (![set containsObject:messageID]) {
        [set addObject:messageID];
        // 保守封顶 5000 条防 defaults 膨胀；对语音密集会话足够，超出按 FIFO 剔除。
        if (set.count > 5000) { [set removeObjectsInRange:NSMakeRange(0, set.count - 5000)]; }
        [ud setObject:set forKey:key];
    }
    self.currentOwner = ownerUID;
    [[NSNotificationCenter defaultCenter] postNotificationName:IMVoicePlayerDidMarkPlayedNotification object:self
        userInfo:@{@"messageID": messageID, @"convID": convID ?: @""}];
}

#pragma mark - Session / Progress

- (void)activateSessionForPlayback {
    AVAudioSession *s = [AVAudioSession sharedInstance];
    // 用 playback（扬声器）；听筒切换（贴近耳朵）留 P1。
    NSError *e = nil;
    [s setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeSpokenAudio options:0 error:&e];
    if (e) { return; }
    [s setActive:YES error:NULL];
}

- (void)startProgressLink {
    [self stopProgressLink];
    self.progressLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onProgressTick)];
    self.progressLink.preferredFramesPerSecond = 30; // 波形填充不需要 60fps
    [self.progressLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopProgressLink {
    [self.progressLink invalidate];
    self.progressLink = nil;
}

- (void)onProgressTick {
    if (!self.player || !self.currentID) { return; }
    [self broadcastStateForID:self.currentID convID:self.currentConvID state:self.currentState];
}

- (void)broadcastStateForID:(NSString *)mid convID:(NSString *)convID state:(IMVoicePlayerState)state {
    if (!mid) { return; }
    double prog = [self progressForMessageID:mid];
    [[NSNotificationCenter defaultCenter] postNotificationName:IMVoicePlayerDidChangeStateNotification object:self
        userInfo:@{
            @"messageID": mid,
            @"convID": convID ?: @"",
            @"state": @(state),
            @"progress": @(prog),
        }];
}

#pragma mark - AVAudioPlayerDelegate

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    NSString *oldID = self.currentID;
    NSString *oldConv = self.currentConvID;
    [self stopProgressLink];
    self.player = nil;
    self.currentID = nil;
    self.currentConvID = nil;
    self.currentState = IMVoicePlayerStateIdle;
    // 归还 audio session 给其他 app（正在听音乐的场景，不还就"发完语音音乐没了"）。
    NSError *e = nil;
    [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&e];
    if (oldID) { [self broadcastStateForID:oldID convID:oldConv state:IMVoicePlayerStateIdle]; }
}

@end
