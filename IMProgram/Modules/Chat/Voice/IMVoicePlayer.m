//
//  IMVoicePlayer.m
//

#import "IMVoicePlayer.h"
#import "IMMessageModel.h"
#import "IMMediaDownloader.h" // toggleEnsuringLocal: 未缓存时直连下载
#import "IMMediaUtil.h"       // IMMediaFullURL
#import <UIKit/UIKit.h>   // UIApplicationDidEnterBackgroundNotification
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

NSNotificationName const IMVoicePlayerDidChangeStateNotification = @"IMVoicePlayerDidChangeStateNotification";
NSNotificationName const IMVoicePlayerDidMarkPlayedNotification = @"IMVoicePlayerDidMarkPlayedNotification";
NSNotificationName const IMVoicePlayerDidFinishNotification = @"IMVoicePlayerDidFinishNotification";

NSString *_Nullable IMVoicePlayerPlayableIDForMessage(IMMessageModel *m) {
    if (m.serverMsgID.length > 0) { return m.serverMsgID; }
    if (m.clientMsgID.length > 0) { return m.clientMsgID; }
    return nil;
}

BOOL IMVoiceFileIsPlayable(NSURL *_Nullable fileURL, int64_t *_Nullable outDurationMillis) {
    if (outDurationMillis) { *outDurationMillis = 0; }
    if (!fileURL.isFileURL) { return NO; }
    AudioFileID file = NULL;
    if (AudioFileOpenURL((__bridge CFURLRef)fileURL, kAudioFileReadPermission, 0, &file) != noErr) { return NO; }
    AudioStreamBasicDescription asbd = {0};
    UInt32 size = sizeof(asbd);
    OSStatus st = AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &size, &asbd);
    Float64 seconds = 0;
    if (st == noErr) {
        UInt32 dsize = sizeof(seconds);
        if (AudioFileGetProperty(file, kAudioFilePropertyEstimatedDuration, &dsize, &seconds) != noErr) { seconds = 0; }
    }
    AudioFileClose(file);
    if (st != noErr) { return NO; }
    // AVAudioPlayer 用「总帧数 ÷ 每包帧数」算时长与播放位点：任一为 0 就是**除零**——
    // 崩在 AVFAudio 内部（EXC_ARITHMETIC / SIGFPE），@try 拦不住，只能事前挡。
    // 真实案例（2026-08-30）：Chrome 录的 **MP4/Opus**（`audio/mp4` 容器塞 Opus 编码）
    // framesPerPacket/bytesPerPacket 全 0，iOS 也解不了 Opus → 点开即整个 App 崩。
    if (asbd.mSampleRate <= 0 || asbd.mFramesPerPacket == 0 || asbd.mChannelsPerFrame == 0) { return NO; }
    if (outDurationMillis && seconds > 0 && seconds < 24 * 3600) { *outDurationMillis = (int64_t)(seconds * 1000.0); }
    return YES;
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
/// 已播集合的内存镜像：key = IMVoicePlayerPlayedKey(owner, conv)，value = NSMutableSet<messageID>。
/// 滚动时每个语音 cell 都要查一次"是否已播"，直接读 NSUserDefaults 是「磁盘 IO + 最多 5000 元素
/// 线性 containsObject」——语音消息一多列表就卡（2026-08-27 修，与 IMVoiceTranscriber 同一类问题）。
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *playedCache;
@end

@implementation IMVoicePlayer

+ (instancetype)sharedPlayer {
    static IMVoicePlayer *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [IMVoicePlayer new]; });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // App 切后台即暂停：本 App **没有**开启后台音频能力（Info.plist 无 audio background mode），
        // 系统本来就会掐掉声音，但播放器的状态还停在 Playing——回到前台气泡仍显"播放中"、
        // 进度条不动，用户只能再点两下才恢复。这里主动转成 Paused，让 UI 与实际一致，
        // 且保留位点（回来接着听），故用 pause 而不是 stop。
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleEnterBackground:)
                                                   name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)handleEnterBackground:(NSNotification *)note { [self pause]; }

- (void)togglePlayback:(IMMessageModel *)message localFileURL:(NSURL *)localFileURL {
    NSString *mid = IMVoicePlayerPlayableIDForMessage(message);
    if (!mid || !localFileURL) { return; }
    // 解不了的音频**在建 AVAudioPlayer 之前**就挡掉——否则 AVFAudio 内部除零崩整个 App（见 IMVoiceFileIsPlayable）。
    // 已在播的那条走上面的暂停/继续分支，不必重复校验（能播到现在就说明格式没问题）。
    BOOL isCurrent = [self.currentID isEqualToString:mid] && self.player != nil;
    if (!isCurrent && !IMVoiceFileIsPlayable(localFileURL, NULL)) { return; }

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
    self.player.enableRate = YES; // 允许 rate 变速（AVAudioPlayer 默认关闭）
    [self.player prepareToPlay];

    self.currentID = mid;
    self.currentConvID = message.convID;
    self.currentOwner = nil; // 由 markPlayed 传入
    self.currentState = IMVoicePlayerStatePlaying;
    // 应用会话级倍速偏好（默认 1.0）。
    self.player.rate = [self rateForConvID:message.convID];

    [self activateSessionForPlayback];
    [self.player play];
    [self startProgressLink];
    [self broadcastStateForID:mid convID:self.currentConvID state:IMVoicePlayerStatePlaying];
}

- (void)toggleEnsuringLocal:(IMMessageModel *)message host:(NSString *)host completion:(void (^)(NSError *))completion {
    if (message.content.length == 0) {
        if (completion) { completion([NSError errorWithDomain:@"IMVoicePlayer" code:-1
                                                     userInfo:@{NSLocalizedDescriptionKey: @"语音内容为空"}]); }
        return;
    }
    NSURL *cached = [IMMediaDownloader cachedFileURLForContent:message.content];
    if (cached && [[NSFileManager defaultManager] fileExistsAtPath:cached.path]) {
        NSError *bad = [self unplayableErrorIfNeeded:message localFileURL:cached];
        if (bad) { if (completion) { completion(bad); } return; }
        [self togglePlayback:message localFileURL:cached];
        if (completion) { completion(nil); }
        return;
    }
    NSURL *remote = [NSURL URLWithString:IMMediaFullURL(message.content, host)];
    if (!remote || !cached) {
        if (completion) { completion([NSError errorWithDomain:@"IMVoicePlayer" code:-2
                                                     userInfo:@{NSLocalizedDescriptionKey: @"语音地址无效"}]); }
        return;
    }
    __weak typeof(self) ws = self;
    IMMediaDownloadTask *task = [[IMMediaDownloader shared] downloadURL:remote toDestination:cached key:message.content];
    // message 强持有（刻意）：下载期间列表重建导致外部模型释放时，完成后仍能播放（曾 __weak 静默 no-op）。
    task.completionHandler = ^(NSURL *location, NSError *err) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (err || !location) {
            if (completion) { completion(err ?: [NSError errorWithDomain:@"IMVoicePlayer" code:-3
                                                                userInfo:@{NSLocalizedDescriptionKey: @"语音下载失败"}]); }
            return;
        }
        NSError *bad = [self unplayableErrorIfNeeded:message localFileURL:location];
        if (bad) { if (completion) { completion(bad); } return; }
        [self togglePlayback:message localFileURL:location];
        if (completion) { completion(nil); }
    };
}

/// 本地文件能不能交给 AVAudioPlayer；不能则给调用方一个**可读的**错误（别静默 no-op，
/// 用户点了没反应比报错更难查）。正在播的那条直接放行（能播到现在就说明格式没问题）。
- (nullable NSError *)unplayableErrorIfNeeded:(IMMessageModel *)message localFileURL:(NSURL *)url {
    NSString *mid = IMVoicePlayerPlayableIDForMessage(message);
    if (mid && [self.currentID isEqualToString:mid] && self.player) { return nil; }
    if (IMVoiceFileIsPlayable(url, NULL)) { return nil; }
    return [NSError errorWithDomain:@"IMVoicePlayer" code:-4
                           userInfo:@{NSLocalizedDescriptionKey: @"该语音格式无法播放"}];
}

- (void)pause {
    if (!self.player || !self.player.isPlaying) { return; }
    [self.player pause];
    self.currentState = IMVoicePlayerStatePaused;
    [self stopProgressLink];
    [self broadcastStateForID:self.currentID convID:self.currentConvID state:IMVoicePlayerStatePaused];
}

- (void)pauseOnLeavingScreen { [self pause]; }

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

/// 已播集合（内存镜像，懒加载自 NSUserDefaults）——滚动热路径只碰内存 NSSet。
- (NSMutableSet<NSString *> *)playedSetForKey:(NSString *)key {
    if (!self.playedCache) { self.playedCache = [NSMutableDictionary dictionary]; }
    NSMutableSet<NSString *> *s = self.playedCache[key];
    if (!s) {
        NSArray *arr = [[NSUserDefaults standardUserDefaults] arrayForKey:key];
        s = [arr isKindOfClass:[NSArray class]] ? [NSMutableSet setWithArray:arr] : [NSMutableSet set];
        self.playedCache[key] = s;
    }
    return s;
}

- (BOOL)hasPlayed:(NSString *)messageID inConv:(NSString *)convID owner:(NSString *)ownerUID {
    if (!messageID) { return NO; }
    return [[self playedSetForKey:IMVoicePlayerPlayedKey(ownerUID, convID)] containsObject:messageID];
}

- (void)markPlayed:(NSString *)messageID inConv:(NSString *)convID owner:(NSString *)ownerUID {
    if (!messageID) { return; }
    NSString *key = IMVoicePlayerPlayedKey(ownerUID, convID);
    NSMutableSet<NSString *> *cached = [self playedSetForKey:key];
    if (![cached containsObject:messageID]) {
        [cached addObject:messageID];
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        NSArray *arr = [ud arrayForKey:key];
        NSMutableArray *set = [arr isKindOfClass:[NSArray class]] ? [arr mutableCopy] : [NSMutableArray array];
        [set addObject:messageID]; // 落盘保序（FIFO 剔除依赖顺序），内存侧用 NSSet 只为查得快
        // 保守封顶 5000 条防 defaults 膨胀；对语音密集会话足够，超出按 FIFO 剔除。
        if (set.count > 5000) {
            NSArray *dropped = [set subarrayWithRange:NSMakeRange(0, set.count - 5000)];
            [set removeObjectsInRange:NSMakeRange(0, set.count - 5000)];
            [cached minusSet:[NSSet setWithArray:dropped]]; // 内存镜像同步剔除，别和磁盘漂移
        }
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
    if (oldID) {
        [self broadcastStateForID:oldID convID:oldConv state:IMVoicePlayerStateIdle];
        // 自然播完（≠ 主动 stop）→ 广播 Finish，接力连播据此触发下一条。
        [[NSNotificationCenter defaultCenter] postNotificationName:IMVoicePlayerDidFinishNotification object:self
            userInfo:@{@"messageID": oldID, @"convID": oldConv ?: @""}];
    }
}

#pragma mark - Scrub + Rate (P1)

- (void)seek:(double)progress forMessageID:(NSString *)messageID {
    if (!messageID || ![messageID isEqualToString:self.currentID] || !self.player) { return; }
    NSTimeInterval total = self.player.duration;
    if (total <= 0) { return; }
    self.player.currentTime = MAX(0, MIN(total, progress * total));
    [self broadcastStateForID:self.currentID convID:self.currentConvID state:self.currentState];
}

/// 会话级倍速偏好 key：per uid（避免账号切换污染）+ per conv。
static NSString *IMVoicePlayerRateKey(NSString *convID) {
    return [NSString stringWithFormat:@"im.voice.rate.%@", convID ?: @"na"];
}

- (float)rateForConvID:(NSString *)convID {
    NSNumber *v = [[NSUserDefaults standardUserDefaults] objectForKey:IMVoicePlayerRateKey(convID)];
    if (![v isKindOfClass:[NSNumber class]]) { return 1.0f; }
    float r = v.floatValue;
    if (r <= 0.5f || r > 3.0f) { return 1.0f; }
    return r;
}

- (void)setRate:(float)rate forConvID:(NSString *)convID {
    // 规范化到 {1.0, 1.5, 2.0} 三档——收端 UI 只提供这三档，其他值属程序化脏数据，兜底成 1.0。
    if (fabsf(rate - 1.5f) < 0.05f) rate = 1.5f;
    else if (fabsf(rate - 2.0f) < 0.05f) rate = 2.0f;
    else rate = 1.0f;
    [[NSUserDefaults standardUserDefaults] setObject:@(rate) forKey:IMVoicePlayerRateKey(convID)];
    if (self.player && [convID isEqualToString:self.currentConvID]) {
        self.player.rate = rate;
    }
}

@end
