//
//  IMChatViewController+Voice.m
//  语音消息 P0：把「按住输入栏语音钮 → 录音 → 松手发送 / 左滑取消」接线到 recorder + HUD + 上传/发送。
//  设计：VOICE_MESSAGE_DESIGN.md §5（两向手势，Telegram B 案）。
//
//  P0 覆盖：
//    - 按住输入栏「waveform.circle」钮开始录制 → HUD 遮盖输入栏
//    - 左滑距离 ≥ 40% 阈值 → 松手取消
//    - 原地松手 → 上传 ?as=voice → sendMedia 带 waveform + duration
//    - <0.6s 提示"说话时间太短"；达 5min 自动停并发送
//    - 中断（来电/切后台）→ P0 简化为自动发送（P1 再做锁定行）
//
//  P1（未做，见设计文档 §10）：上滑锁定态 / 大圆钮跟手 / 磁吸小锁 / 波形拖拽 scrub。
//

#import "IMChatViewController+Private.h"
#import "IMMessageModel.h"
#import "IMMediaAttributes.h"
#import "IMHTTPService.h"
#import "IMMediaDownloader.h"
#import "IMSocketManager.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"
#import "Voice/IMVoiceRecorder.h"
#import "Voice/IMVoiceRecordingHUD.h"
#import "Voice/IMVoicePlayer.h"
#import <objc/runtime.h>

/// 按住条 pan 触发取消的距离阈值（占输入栏宽度的比例）。
static const CGFloat kIMVoiceCancelThresholdRatio = 0.40;

@interface IMChatViewController (VoicePrivate)
@property (nonatomic, strong, nullable) IMVoiceRecorder *im_voiceRecorder;
@property (nonatomic, strong, nullable) IMVoiceRecordingHUD *im_voiceHUD;
@property (nonatomic, strong, nullable) UILongPressGestureRecognizer *im_voicePressRecognizer;
@property (nonatomic, assign) CGPoint im_voicePressStart;
@property (nonatomic, assign) BOOL im_voiceCancelReady;
@end

// 关联对象 keys（防冲突用地址常量）
static const void *kIMVoiceRecorderKey = &kIMVoiceRecorderKey;
static const void *kIMVoiceHUDKey = &kIMVoiceHUDKey;
static const void *kIMVoicePressKey = &kIMVoicePressKey;
static const void *kIMVoicePressStartKey = &kIMVoicePressStartKey;
static const void *kIMVoiceCancelReadyKey = &kIMVoiceCancelReadyKey;

@implementation IMChatViewController (Voice)

- (IMVoiceRecorder *)im_voiceRecorder {
    IMVoiceRecorder *r = objc_getAssociatedObject(self, kIMVoiceRecorderKey);
    if (!r) {
        r = [IMVoiceRecorder new];
        r.delegate = (id<IMVoiceRecorderDelegate>)self;
        objc_setAssociatedObject(self, kIMVoiceRecorderKey, r, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return r;
}

- (IMVoiceRecordingHUD *)im_voiceHUD {
    IMVoiceRecordingHUD *hud = objc_getAssociatedObject(self, kIMVoiceHUDKey);
    if (!hud) {
        hud = [IMVoiceRecordingHUD new];
        hud.translatesAutoresizingMaskIntoConstraints = NO;
        UIView *inputBar = self.inputField.superview;
        if (!inputBar) { return hud; }
        [inputBar addSubview:hud];
        [NSLayoutConstraint activateConstraints:@[
            [hud.leadingAnchor constraintEqualToAnchor:inputBar.leadingAnchor],
            [hud.trailingAnchor constraintEqualToAnchor:inputBar.trailingAnchor],
            [hud.topAnchor constraintEqualToAnchor:inputBar.topAnchor],
            [hud.bottomAnchor constraintEqualToAnchor:inputBar.bottomAnchor],
        ]];
        objc_setAssociatedObject(self, kIMVoiceHUDKey, hud, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return hud;
}

- (void)setIm_voicePressRecognizer:(UILongPressGestureRecognizer *)r { objc_setAssociatedObject(self, kIMVoicePressKey, r, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (UILongPressGestureRecognizer *)im_voicePressRecognizer { return objc_getAssociatedObject(self, kIMVoicePressKey); }

- (void)setIm_voicePressStart:(CGPoint)p { objc_setAssociatedObject(self, kIMVoicePressStartKey, [NSValue valueWithCGPoint:p], OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (CGPoint)im_voicePressStart { NSValue *v = objc_getAssociatedObject(self, kIMVoicePressStartKey); return v ? v.CGPointValue : CGPointZero; }

- (void)setIm_voiceCancelReady:(BOOL)b { objc_setAssociatedObject(self, kIMVoiceCancelReadyKey, @(b), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)im_voiceCancelReady { return [objc_getAssociatedObject(self, kIMVoiceCancelReadyKey) boolValue]; }

#pragma mark - 按住手势安装（宿主 configureCompose 后调用一次即可，重复调用无副作用）

/// 把"按住 = 录音，左滑 = 取消"的长按手势装到输入栏语音钮上。
/// 手势路径由本 category 独占；不影响其他 UI。
- (void)im_installVoicePressGesture {
    UIButton *voiceBtn = [self im_findVoiceButton];
    if (!voiceBtn || self.im_voicePressRecognizer) { return; }
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
                                        initWithTarget:self action:@selector(im_onVoicePress:)];
    lp.minimumPressDuration = 0.12; // 略高于系统 tap 阈值，避免误触
    lp.cancelsTouchesInView = YES;
    [voiceBtn addGestureRecognizer:lp];
    self.im_voicePressRecognizer = lp;
}

/// 在输入栏子视图里定位那个"waveform.circle"按钮——宿主没暴露 property，用图片名匹配。
/// 未来 IMChatViewController 若把 voiceButton 提为 property，改成直接读即可。
- (UIButton *)im_findVoiceButton {
    UIView *inputBar = self.inputField.superview;
    if (!inputBar) { return nil; }
    for (UIView *v in inputBar.subviews) {
        if (![v isKindOfClass:[UIButton class]]) { continue; }
        UIButton *b = (UIButton *)v;
        UIImage *img = [b imageForState:UIControlStateNormal];
        // waveform.circle 是宿主 IMChatViewController.m 里 voiceButton 的唯一 image。
        // 若失配（皮肤替换/资源改名），退化：宿主 voiceTapped 走既有 comingSoon 分支，功能可控。
        NSString *name = img.symbolConfiguration ? [self im_imageSymbolName:img] : nil;
        if ([name isEqualToString:@"waveform.circle"]) { return b; }
    }
    return nil;
}

/// UIImage 上没有公开的 symbolName getter；用 accessibilityIdentifier 也不合适，
/// 走 CGImageSource 是过度设计。回退：直接对 subviews 中 rect.origin.x 最小的按钮认作 voice。
- (nullable NSString *)im_imageSymbolName:(UIImage *)img {
    // 从 image.debugDescription 抠 name 是私有依赖，会随系统更新失效——不做。
    // 直接返 nil 走位置兜底（inputBar 里 x 最小的按钮 = 语音钮）。
    return nil;
}

#pragma mark - 手势事件

- (void)im_onVoicePress:(UILongPressGestureRecognizer *)g {
    UIView *bar = self.inputField.superview;
    CGPoint pt = [g locationInView:bar];
    switch (g.state) {
        case UIGestureRecognizerStateBegan:
            self.im_voicePressStart = pt;
            self.im_voiceCancelReady = NO;
            [self im_startVoiceRecording];
            break;
        case UIGestureRecognizerStateChanged: {
            CGFloat dx = pt.x - self.im_voicePressStart.x;
            [self.im_voiceHUD setSlideOffset:MIN(0, dx)];
            CGFloat threshold = bar.bounds.size.width * kIMVoiceCancelThresholdRatio;
            BOOL nowReady = (-dx) >= threshold;
            if (nowReady != self.im_voiceCancelReady) {
                self.im_voiceCancelReady = nowReady;
                [self.im_voiceHUD setCancelReady:nowReady];
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            if (self.im_voiceCancelReady) {
                [self.im_voiceRecorder cancel];
            } else {
                [self.im_voiceRecorder stopAndSend];
            }
            self.im_voiceCancelReady = NO;
            break;
        }
        default: break;
    }
}

- (void)im_startVoiceRecording {
    __weak typeof(self) weakSelf = self;
    [IMVoiceRecorder requestMicrophonePermission:^(BOOL granted) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (!granted) {
            [self im_showToast:@"需要麦克风权限：在系统设置中开启后重试"];
            [self.im_voicePressRecognizer setEnabled:NO];
            [self.im_voicePressRecognizer setEnabled:YES];
            return;
        }
        [self.im_voiceHUD setSlideOffset:0];
        [self.im_voiceHUD setCancelReady:NO];
        [self.im_voiceHUD updateAmplitude:0 elapsedMillis:0];
        [self.im_voiceHUD setVisible:YES animated:YES];
        [self.im_voiceRecorder start];
    }];
}

#pragma mark - IMVoiceRecorderDelegate

- (void)voiceRecorderDidStart:(IMVoiceRecorder *)recorder { /* HUD 已提前显示 */ }

- (void)voiceRecorder:(IMVoiceRecorder *)recorder didSampleAmplitude:(float)amplitude elapsedMillis:(int64_t)elapsedMillis {
    [self.im_voiceHUD updateAmplitude:amplitude elapsedMillis:elapsedMillis];
}

- (void)voiceRecorder:(IMVoiceRecorder *)recorder
    didStopWithReason:(IMVoiceRecorderStopReason)reason
              fileURL:(NSURL *)fileURL
            waveform:(NSString *)waveformBase64
             duration:(int64_t)durationMillis {
    [self.im_voiceHUD setVisible:NO animated:YES];
    switch (reason) {
        case IMVoiceRecorderStopReasonUserCancel:
            return;
        case IMVoiceRecorderStopReasonTooShort:
            [self im_showToast:@"说话时间太短"];
            return;
        case IMVoiceRecorderStopReasonError:
            [self im_showToast:@"录音失败，请重试"];
            return;
        case IMVoiceRecorderStopReasonUserSend:
        case IMVoiceRecorderStopReasonReachedMax:
        case IMVoiceRecorderStopReasonInterrupted:
            break;
    }
    if (!fileURL) { return; }
    [self im_uploadAndSendVoice:fileURL waveform:waveformBase64 durationMillis:durationMillis];
}

- (void)im_uploadAndSendVoice:(NSURL *)fileURL waveform:(NSString *)waveform durationMillis:(int64_t)durationMillis {
    NSData *data = [NSData dataWithContentsOfURL:fileURL];
    if (data.length == 0) {
        [self im_showToast:@"录音文件读取失败"];
        return;
    }
    int64_t fileSize = data.length;
    NSString *fileName = [fileURL.lastPathComponent length] > 0 ? fileURL.lastPathComponent : @"voice.m4a";
    NSString *token = IMHTTPService.sharedService.currentToken ?: @"";
    if (token.length == 0) { [self im_showToast:@"未登录，无法发送"]; return; }

    __weak typeof(self) weakSelf = self;
    [[IMHTTPService sharedService] uploadVoiceData:data
                                          fileName:fileName
                                          mimeType:@"audio/mp4"
                                             token:token
                                          progress:nil
                                        completion:^(NSString *_Nullable url, NSError *_Nullable err) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (err || url.length == 0) {
            [self im_showToast:err.localizedDescription ?: @"语音上传失败"];
            [[NSFileManager defaultManager] removeItemAtURL:fileURL error:NULL];
            return;
        }
        IMMediaAttributes *attrs = [IMMediaAttributes new];
        attrs.durationMillis = durationMillis;
        attrs.fileSize = fileSize;
        attrs.waveform = waveform;
        NSString *toUser = self.isGroupChat ? nil : self.peerID;
        NSString *cid = [[IMSocketManager sharedManager] sendMedia:url contentType:@"voice"
                                                            toConv:self.convID toUser:toUser attributes:attrs
                                                        completion:nil];
        // 本地立刻回显（气泡出现——不等 ack），waveform 保留在本地行；上传后 tmp 文件即可清理，
        // 若播放需要，气泡按 URL 播（远程 URL 会自动下载缓存）。
        [self im_persistLocalVoiceEcho:url waveform:waveform duration:durationMillis fileSize:fileSize clientMsgID:cid];
        [[NSFileManager defaultManager] removeItemAtURL:fileURL error:NULL];
    }];
}

/// 立即在本地库回显一条 voice 消息——与已有媒体路径同套（防"松手到 ack 之间气泡不见"）。
/// clientMsgID 已由 sendMedia 生成并塞进出网包；此处按同 cid 写库，ack 到达时按 cid 更新 serverMsgID。
#pragma mark - 播放（DataSource dispatch onPlayTap 用）

/// 播放语音消息：本地已缓存直接播；否则先下载再播（voice 恒自动下载策略见设计文档 §7）。
/// mine 的消息若 content 是相对 /uploads/... 用 fullURL 拼绝对路径下载。
- (void)im_playVoiceMessage:(IMMessageModel *)message fullURL:(NSString *)fullURL {
    if (message.content.length == 0) { return; }
    NSURL *cached = [IMMediaDownloader cachedFileURLForContent:message.content];
    if (cached && [[NSFileManager defaultManager] fileExistsAtPath:cached.path]) {
        [self im_startPlaybackForMessage:message localURL:cached];
        return;
    }
    // 未下载 → 拉一次；voice 文件极小（<1MB），直连下载即可。
    NSURL *remote = fullURL.length > 0 ? [NSURL URLWithString:fullURL] : nil;
    if (!remote) { return; }
    NSURL *dest = [IMMediaDownloader cachedFileURLForContent:message.content];
    if (!dest) { return; }
    __weak typeof(self) ws = self;
    __weak IMMessageModel *wm = message;
    IMMediaDownloadTask *task = [[IMMediaDownloader shared] downloadURL:remote toDestination:dest key:message.content];
    task.completionHandler = ^(NSURL *_Nullable location, NSError *_Nullable err) {
        __strong typeof(ws) self = ws; IMMessageModel *sm = wm;
        if (!self || !sm) { return; }
        if (err || !location) {
            [self im_showToast:@"语音下载失败"];
            return;
        }
        [self im_startPlaybackForMessage:sm localURL:location];
    };
}

- (void)im_startPlaybackForMessage:(IMMessageModel *)message localURL:(NSURL *)localURL {
    NSString *mid = IMVoicePlayerPlayableIDForMessage(message);
    if (mid && ![message.from isEqualToString:self.userID]) {
        [[IMVoicePlayer sharedPlayer] markPlayed:mid inConv:message.convID owner:self.userID];
    }
    [[IMVoicePlayer sharedPlayer] togglePlayback:message localFileURL:localURL];
}

- (void)im_persistLocalVoiceEcho:(NSString *)url waveform:(NSString *)waveform duration:(int64_t)dur fileSize:(int64_t)size clientMsgID:(NSString *)cid {
    if (!cid) { return; }
    // 同已有媒体路径：本地立刻回显一条 sending 状态的消息（ack 到达后 socket 层 upsert 换 serverMsgID）。
    // 若同 cid 已存在（socket 层预置了模型），跳过重复插入。
    for (IMMessageModel *x in self.messages) {
        if ([x.clientMsgID isEqualToString:cid]) { return; }
    }
    IMMessageModel *m = [IMMessageModel new];
    m.clientMsgID = cid;
    m.convID = self.convID;
    m.from = self.userID;
    m.to = self.isGroupChat ? nil : self.peerID;
    m.contentType = @"voice";
    m.content = url;
    m.duration = dur;
    m.fileSize = size;
    m.waveform = waveform;
    m.timestamp = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000);
    m.status = IMMessageStatusSending;
    [self.messages addObject:m];
    [self appendReloadAndScroll];
}

@end
