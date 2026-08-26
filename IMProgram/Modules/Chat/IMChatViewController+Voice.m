//
//  IMChatViewController+Voice.m
//  语音消息 P0：把「按住输入栏语音钮 → 录音 → 松手发送 / 左滑取消」接线到 recorder + HUD + 上传/发送。
//  设计：VOICE_MESSAGE_DESIGN.md §5（两向手势，Telegram B 案）。
//
//  覆盖（P0+P1，2026-08-26 全量补齐）：
//    - 按住语音钮 → 大圆钮跟手 + 振幅呼吸环 + 磁吸小锁（IMVoicePressOverlay）+ HUD 录制行
//    - 左滑距离 ≥ 40% 阈值 → 松手取消；上滑进小锁 34pt 磁吸圈 → 锁定行（免提，删/停/发）
//    - 原地松手 → 上传 ?as=voice → sendMedia（带 waveform+duration）+ 本地落库回显 + ack 回写 convSeq
//    - <0.6s 提示"说话时间太短"；达 5min 自动停并发送
//    - 中断（来电/切后台）→ 自动转锁定暂停态（§5.4）；锁定态删除 >10s 二次确认
//    - 转文字（收端本地 SFSpeech）/ 接力连播 / 倍速与 scrub（cell 侧）
//

#import "IMChatViewController+Private.h"
#import <AVFoundation/AVFoundation.h>
#import "IMMessageModel.h"
#import "IMMediaAttributes.h"
#import "IMHTTPService.h"
#import "IMDatabase.h"
#import "IMMediaDownloader.h"
#import "IMSocketManager.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"
#import "Voice/IMVoiceRecorder.h"
#import "Voice/IMVoiceRecordingHUD.h"
#import "Voice/IMVoicePressOverlay.h"
#import "Voice/IMVoiceLockedBar.h"
#import "Voice/IMVoicePlayer.h"
#import "Voice/IMVoiceTranscriber.h"
#import "Voice/IMVoiceBubbleCell.h"
#import "IMLog.h"
#import <objc/runtime.h>

/// 按住条 pan 触发取消的距离阈值（占输入栏宽度的比例）。
/// 上滑锁定不再用固定位移阈值——改为 IMVoicePressOverlay 的磁吸小锁（70pt 高亮 / 34pt 到位即锁，设计 §5.2）。
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
static const void *kIMVoiceLockedBarKey = &kIMVoiceLockedBarKey;
static const void *kIMVoicePressKey = &kIMVoicePressKey;
static const void *kIMVoicePressStartKey = &kIMVoicePressStartKey;
static const void *kIMVoiceCancelReadyKey = &kIMVoiceCancelReadyKey;
static const void *kIMVoiceLockedKey = &kIMVoiceLockedKey;
static const void *kIMVoiceOverlayKey = &kIMVoiceOverlayKey;

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

- (IMVoiceLockedBar *)im_voiceLockedBar {
    IMVoiceLockedBar *bar = objc_getAssociatedObject(self, kIMVoiceLockedBarKey);
    if (!bar) {
        bar = [IMVoiceLockedBar new];
        bar.translatesAutoresizingMaskIntoConstraints = NO;
        UIView *inputBar = self.inputField.superview;
        if (!inputBar) { return bar; }
        [inputBar addSubview:bar];
        [NSLayoutConstraint activateConstraints:@[
            [bar.leadingAnchor constraintEqualToAnchor:inputBar.leadingAnchor],
            [bar.trailingAnchor constraintEqualToAnchor:inputBar.trailingAnchor],
            [bar.topAnchor constraintEqualToAnchor:inputBar.topAnchor],
            [bar.bottomAnchor constraintEqualToAnchor:inputBar.bottomAnchor],
        ]];
        __weak typeof(self) ws = self;
        bar.onDelete = ^{
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            // 设计 §5.3：已录 >10s 才二次确认——短的直接删，不为几秒钟打断用户。
            if (self.im_voiceRecorder.elapsedMillis > 10000) {
                UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"删除这段录音？"
                                                                            message:nil preferredStyle:UIAlertControllerStyleAlert];
                [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                [ac addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive
                                                     handler:^(UIAlertAction *a) { [self.im_voiceRecorder cancel]; }]];
                [self presentViewController:ac animated:YES completion:nil];
            } else {
                [self.im_voiceRecorder cancel];
            }
        };
        bar.onPauseResume = ^(BOOL toPause) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (toPause) {
                // 录制中 → 试听态：pause 收尾当前段，锁定条切"迷你播放器"，波形展当前 amplitudes；
                // 提前 setPausedIcon 让 setPreviewMode 内部拿到正确 pausedState，避免图标一帧闪跳
                //（曾先渲染 pause.fill 再改红色 record.circle，code-review 2026-08-27）。
                [self.im_voiceRecorder pause];
                [self.im_voiceLockedBar setPausedIcon:YES]; // 先写 pausedState=YES
                [self.im_voiceLockedBar setPreviewMode:YES amplitudes:self.im_voiceRecorder.currentAmplitudes];
                [self im_installPreviewObserverIfNeeded]; // 按需装观察者
            } else {
                // 试听态 → 继续录制：只停 preview 播放（不打断同页别的语音）；然后 resume 新段。
                [self im_stopPreviewPlaybackIfNeeded];
                [self.im_voiceRecorder resume];
                [self.im_voiceLockedBar setPausedIcon:NO];
                [self.im_voiceLockedBar setPreviewMode:NO amplitudes:nil];
            }
        };
        bar.onPreviewToggle = ^{ [ws im_toggleLockedPreview]; };
        bar.onSend = ^{
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            // 若在试听，只停 preview（不 stop 别人的接力播放）——曾无条件 [IMVoicePlayer stop]（code-review 2026-08-27）。
            [self im_stopPreviewPlaybackIfNeeded];
            [self.im_voiceRecorder stopAndSend];
        };
        objc_setAssociatedObject(self, kIMVoiceLockedBarKey, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return bar;
}

/// 大圆钮 + 磁吸小锁浮层（设计 §5.2）：懒建并加到 self.view（不进输入栏，避免被裁剪/遮挡）。
- (IMVoicePressOverlay *)im_voiceOverlay {
    IMVoicePressOverlay *ov = objc_getAssociatedObject(self, kIMVoiceOverlayKey);
    if (!ov) {
        ov = [[IMVoicePressOverlay alloc] initWithFrame:self.view.bounds];
        ov.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:ov];
        objc_setAssociatedObject(self, kIMVoiceOverlayKey, ov, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [self.view bringSubviewToFront:ov]; // 输入栏/键盘布局变动后仍浮在最上
    return ov;
}

- (BOOL)im_voiceLocked { return [objc_getAssociatedObject(self, kIMVoiceLockedKey) boolValue]; }
- (void)setIm_voiceLocked:(BOOL)v { objc_setAssociatedObject(self, kIMVoiceLockedKey, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

- (void)setIm_voicePressRecognizer:(UILongPressGestureRecognizer *)r { objc_setAssociatedObject(self, kIMVoicePressKey, r, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (UILongPressGestureRecognizer *)im_voicePressRecognizer { return objc_getAssociatedObject(self, kIMVoicePressKey); }

- (void)setIm_voicePressStart:(CGPoint)p { objc_setAssociatedObject(self, kIMVoicePressStartKey, [NSValue valueWithCGPoint:p], OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (CGPoint)im_voicePressStart { NSValue *v = objc_getAssociatedObject(self, kIMVoicePressStartKey); return v ? v.CGPointValue : CGPointZero; }

- (void)setIm_voiceCancelReady:(BOOL)b { objc_setAssociatedObject(self, kIMVoiceCancelReadyKey, @(b), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)im_voiceCancelReady { return [objc_getAssociatedObject(self, kIMVoiceCancelReadyKey) boolValue]; }

#pragma mark - 按住手势安装（宿主 configureCompose 后调用一次即可，重复调用无副作用）

/// 把"按住 = 录音，左滑 = 取消"的长按手势装到输入栏语音钮上。
/// 手势路径由本 category 独占；不影响其他 UI。
- (void)im_installVoiceRelayObserver {
    // 幂等：同一 VC 只装一次。observer 生命周期跟随 VC，dealloc 时 NotificationCenter 自动清理。
    static const void *k = &k;
    if (objc_getAssociatedObject(self, k)) { return; }
    objc_setAssociatedObject(self, k, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak typeof(self) ws = self;
    [[NSNotificationCenter defaultCenter] addObserverForName:IMVoicePlayerDidFinishNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        [ws im_relayAfterMessageID:n.userInfo[@"messageID"] convID:n.userInfo[@"convID"]];
    }];
    // 注：preview 状态观察者不在这里装——它只在进入锁定试听态时按需装（code-review 2026-08-27 efficiency）；
    // 否则聊天页任何语音每 tick 30 次都会走一次 im_previewStateChanged 空判断，属净增热路径。
}

static NSString *const kIMLockedPreviewID = @"__voice_preview__";

/// preview 观察者按需装/拆——只在锁定试听态期间挂 IMVoicePlayerDidChangeStateNotification。
- (void)im_installPreviewObserverIfNeeded {
    static const void *k = &k;
    if (objc_getAssociatedObject(self, k)) { return; }
    __weak typeof(self) ws = self;
    id token = [[NSNotificationCenter defaultCenter] addObserverForName:IMVoicePlayerDidChangeStateNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        [ws im_previewStateChanged:n];
    }];
    objc_setAssociatedObject(self, k, token, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)im_uninstallPreviewObserverIfNeeded {
    static const void *k = &k;
    id token = objc_getAssociatedObject(self, k);
    if (!token) { return; }
    [[NSNotificationCenter defaultCenter] removeObserver:token];
    objc_setAssociatedObject(self, k, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

/// 只停 preview 播放（不打断同页别的接力/普通语音）；同时拆观察者，回到"零净增热路径"。
- (void)im_stopPreviewPlaybackIfNeeded {
    IMVoicePlayerState st = [[IMVoicePlayer sharedPlayer] stateForMessageID:kIMLockedPreviewID];
    if (st == IMVoicePlayerStatePlaying || st == IMVoicePlayerStatePaused) {
        [[IMVoicePlayer sharedPlayer] stop];
    }
    [self im_uninstallPreviewObserverIfNeeded];
}

/// 找到 currentMid 在当前会话消息列表中的位置 + 之后**同会话**的第一条**未播放的 voice**（跨发送者也连）；
/// 遇到非 voice 消息即 break——遵设计文档 §6.4 的"话题边界即停"。
- (void)im_relayAfterMessageID:(NSString *)currentMid convID:(NSString *)convID {
    if (![convID isEqualToString:self.convID]) { return; } // 只对本页会话生效
    NSInteger startIdx = -1;
    for (NSInteger i = 0; i < (NSInteger)self.messages.count; i++) {
        NSString *mid = IMVoicePlayerPlayableIDForMessage(self.messages[i]);
        if ([mid isEqualToString:currentMid]) { startIdx = i; break; }
    }
    if (startIdx < 0) { return; }
    for (NSInteger i = startIdx + 1; i < (NSInteger)self.messages.count; i++) {
        IMMessageModel *m = self.messages[i];
        // 遇到非 voice（含 msg_op 等系统事件）即停——话题边界。
        if (![m.contentType isEqualToString:@"voice"]) { return; }
        if (m.recalledAt > 0 || m.deletedAt > 0) { continue; } // 撤回/删的跳过
        NSString *nextMid = IMVoicePlayerPlayableIDForMessage(m);
        BOOL mine = [m.from isEqualToString:self.userID];
        // 自己发的语音不进接力（自己听自己没意义，符合直觉）；对方消息按已播集合过滤。
        if (mine) { continue; }
        if ([[IMVoicePlayer sharedPlayer] hasPlayed:nextMid inConv:m.convID owner:self.userID]) { continue; }
        // 找到下一条候选 → 触发播放（复用 im_playVoiceMessage 路径，含下载兜底）。
        NSString *fullURL = [self fullMediaURL:m.content];
        [self im_playVoiceMessage:m fullURL:fullURL];
        return;
    }
}

- (void)im_installVoicePressGesture {
    UIButton *voiceBtn = self.voiceButton; // v2.3 起宿主直接持有；旧的 action 扫描 fallback 属死代码已删
    if (!voiceBtn || self.im_voicePressRecognizer) { return; }
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
                                        initWithTarget:self action:@selector(im_onVoicePress:)];
    lp.minimumPressDuration = 0.12; // 略高于系统 tap 阈值，避免误触
    lp.cancelsTouchesInView = YES;
    [voiceBtn addGestureRecognizer:lp];
    self.im_voicePressRecognizer = lp;
}

#pragma mark - 手势事件

- (void)im_onVoicePress:(UILongPressGestureRecognizer *)g {
    UIView *bar = self.inputField.superview;
    CGPoint ptBar = [g locationInView:bar];
    CGPoint ptView = [g locationInView:self.view];
    switch (g.state) {
        case UIGestureRecognizerStateBegan: {
            if (!self.voiceButton.enabled) { return; } // 禁言等 composer 锁定态：入口即拦（disabled 不拦手势识别，需显式早退）
            self.im_voicePressStart = ptBar;
            self.im_voiceCancelReady = NO;
            [self im_startVoiceRecording];
            // 大圆钮 + 磁吸小锁浮层（设计 §5.2）：**仅录音真正启动时弹**——权限被拒/请求中 recorder 未开录，
            // 此时弹浮层会引导用户"锁定"一个不存在的录音（LockedBar 三键全 no-op 且无 didStop 复位 → 永久卡死）。
            if (self.im_voiceRecorder.recording) {
                CGPoint anchor = [self.voiceButton.superview convertPoint:self.voiceButton.center toView:self.view];
                [self.im_voiceOverlay presentAtAnchor:anchor fingerPoint:ptView];
            }
            break;
        }
        case UIGestureRecognizerStateChanged: {
            if (self.im_voiceLocked) { return; } // 已锁定，忽略后续手势
            // 未真正开录（权限请求中/被拒）→ 不做磁吸/取消判定（同上：防锁定不存在的录音）。
            if (!self.im_voiceRecorder.recording && !self.im_voiceRecorder.paused) { return; }
            // 磁吸小锁：手指进入锁钮 70pt 高亮、34pt 内到位即锁（无需松手；替代旧的固定 80pt 位移阈值）。
            IMVoiceLockPhase phase = [self.im_voiceOverlay updateFingerPoint:ptView];
            if (phase == IMVoiceLockPhaseLocked) {
                self.im_voiceLocked = YES;
                g.enabled = NO; // 取消手势 = 触发 Cancelled，但状态机会识别 locked 走"不结束录制"分支
                [self.im_voiceOverlay dismissLocked];
                [self.im_voiceHUD setVisible:NO animated:YES];
                [self.im_voiceLockedBar setPausedIcon:NO];
                [self.im_voiceLockedBar setVisible:YES animated:YES];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ g.enabled = YES; });
                return;
            }
            CGFloat dx = ptBar.x - self.im_voicePressStart.x;
            [self.im_voiceHUD setSlideOffset:MIN(0, dx)];
            CGFloat threshold = bar.bounds.size.width * kIMVoiceCancelThresholdRatio;
            BOOL nowReady = (-dx) >= threshold;
            if (nowReady != self.im_voiceCancelReady) {
                self.im_voiceCancelReady = nowReady;
                [self.im_voiceHUD setCancelReady:nowReady];
                [self.im_voiceOverlay setCancelHint:nowReady]; // 过阈值大圆钮转红（松手=取消）
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            // 若刚被 lock 逻辑主动取消了手势 → 保留录制（recorder 继续跑，LockedBar 接管）。
            // dismiss 幂等（磁吸路径已走 dismissLocked、此调用 no-op）；兜底中断置锁等旁路进入的锁定态。
            if (self.im_voiceLocked) { self.im_voiceCancelReady = NO; [self.im_voiceOverlay dismiss]; return; }
            [self.im_voiceOverlay dismiss];
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
    // 权限**同步查询**：只有 granted 才立刻开录；undetermined 触发系统请求但**不启动本次录音**——
    // 否则用户第一次按住松手后，permission 回调才 fire，会在没有按住的情况下无声开始录音（无止境）。
    // 请求返回后弹提示："已授权，再次按住说话"；下次按住时权限已 granted → 立即开录。
    AVAudioSession *session = [AVAudioSession sharedInstance];
    AVAudioSessionRecordPermission perm = session.recordPermission;
    if (perm == AVAudioSessionRecordPermissionDenied) {
        [self im_showToast:@"需要麦克风权限：在系统设置中开启后重试"];
        return;
    }
    if (perm == AVAudioSessionRecordPermissionUndetermined) {
        __weak typeof(self) weakSelf = self;
        [IMVoiceRecorder requestMicrophonePermission:^(BOOL granted) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            if (!granted) {
                [self im_showToast:@"未授权：在系统设置中开启麦克风"];
                return;
            }
            // granted 后如果用户仍按住语音钮，直接开录；否则提示"再次按住"。
            UIGestureRecognizerState st = self.im_voicePressRecognizer.state;
            BOOL stillPressing = (st == UIGestureRecognizerStateBegan || st == UIGestureRecognizerStateChanged);
            if (stillPressing) {
                [self.im_voiceHUD setSlideOffset:0];
                [self.im_voiceHUD setCancelReady:NO];
                [self.im_voiceHUD updateAmplitude:0 elapsedMillis:0];
                [self.im_voiceHUD setVisible:YES animated:YES];
                [self.im_voiceRecorder start];
                if (self.im_voiceRecorder.recording) { // 授权后仍按住：浮层此刻补弹（Began 时因未授权没弹）
                    CGPoint anchor = [self.voiceButton.superview convertPoint:self.voiceButton.center toView:self.view];
                    CGPoint finger = [self.im_voicePressRecognizer locationInView:self.view];
                    [self.im_voiceOverlay presentAtAnchor:anchor fingerPoint:finger];
                }
            } else {
                [self im_showToast:@"已授权，再次按住说话"];
            }
        }];
        return;
    }
    [self.im_voiceHUD setSlideOffset:0];
    [self.im_voiceHUD setCancelReady:NO];
    [self.im_voiceHUD updateAmplitude:0 elapsedMillis:0];
    [self.im_voiceHUD setVisible:YES animated:YES];
    [self.im_voiceRecorder start];
}

#pragma mark - IMVoiceRecorderDelegate

- (void)voiceRecorderDidStart:(IMVoiceRecorder *)recorder { /* HUD 已提前显示 */ }

/// 中断（来电/切后台）→ 自动转锁定暂停态（设计 §5.4）：录制条还在，回来可 发送/删除/继续。
- (void)voiceRecorderWasInterrupted:(IMVoiceRecorder *)recorder {
    self.im_voiceLocked = YES;
    // 中断可发生在按住态：浮层必须在这里收——随后系统取消手势时 Cancelled 分支因 locked 早退，不会再收。
    [self.im_voiceOverlay dismiss];
    [self.im_voiceHUD setVisible:NO animated:YES];
    // 中断=已 pause+finalize 当前段，直接进试听态（recorder.currentAmplitudes 有值）。
    [self.im_voiceLockedBar setPreviewMode:YES amplitudes:recorder.currentAmplitudes];
    [self.im_voiceLockedBar setPausedIcon:YES];
    [self.im_voiceLockedBar setVisible:YES animated:YES];
}

/// §12 达 5min 上限硬闸：锁定态自动发送；按住态转磁吸锁定 + pause（等用户决定发/删/续）。
/// 不再靠 AVAudioRecorder.recordForDuration 系统闸（实测容差到 5:21，2026-08-27 用户报）。
- (void)voiceRecorderDidReachMaxDuration:(IMVoiceRecorder *)recorder {
    if (self.im_voiceLocked) {
        [self.im_voiceRecorder stopAndSend];
        return;
    }
    // 按住态：模拟磁吸锁定 → LockedBar 显 + overlay 收 + HUD 隐 + recorder.pause 进试听。
    self.im_voiceLocked = YES;
    [self.im_voiceOverlay dismissLocked];
    [self.im_voiceHUD setVisible:NO animated:YES];
    [self.im_voiceRecorder pause];
    [self.im_voiceLockedBar setPreviewMode:YES amplitudes:recorder.currentAmplitudes];
    [self.im_voiceLockedBar setPausedIcon:YES];
    [self.im_voiceLockedBar setVisible:YES animated:YES];
    // gesture 释放（下一 runloop 让 press 结束但 locked 分支不走 stopAndSend）
    if (self.im_voicePressRecognizer.isEnabled) {
        self.im_voicePressRecognizer.enabled = NO;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            self.im_voicePressRecognizer.enabled = YES;
        });
    }
}

/// §14 点锁定条中间胶囊 → 播/暂试听。走 IMVoicePlayer 共享单例（同页只播一条自动生效）。
- (void)im_toggleLockedPreview {
    IMVoicePlayerState st = [[IMVoicePlayer sharedPlayer] stateForMessageID:kIMLockedPreviewID];
    if (st == IMVoicePlayerStatePlaying) {
        [[IMVoicePlayer sharedPlayer] stop];
        [self.im_voiceLockedBar applyPreviewPlaying:NO progress:0
                                       totalMillis:self.im_voiceRecorder.elapsedMillis];
        return;
    }
    __weak typeof(self) ws = self;
    [self.im_voiceRecorder providePreviewURL:^(NSURL *url, NSError *err) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (err || !url) { [self im_showToast:@"试听准备失败"]; return; }
        [self im_installPreviewObserverIfNeeded]; // 播放开始前装观察者
        // 造一条最小消息模型驱动 IMVoicePlayer（IMVoicePlayer 语义按消息，preview 复用同一 hack；
        // TODO: 加 IMVoicePlayer.playURL: 独立 API 让此 fake message 消失，见 code-review simplification）。
        IMMessageModel *fake = [IMMessageModel new];
        fake.serverMsgID = kIMLockedPreviewID; // 让 IMVoicePlayerPlayableIDForMessage 拿到稳定 key
        [[IMVoicePlayer sharedPlayer] togglePlayback:fake localFileURL:url];
    }];
}

/// 试听中 IMVoicePlayer 每 tick 广播 → 刷锁定条波形进度。观察者按需装（im_installPreviewObserverIfNeeded）。
- (void)im_previewStateChanged:(NSNotification *)n {
    if (![n.userInfo[@"messageID"] isEqualToString:kIMLockedPreviewID]) { return; }
    IMVoicePlayerState st = (IMVoicePlayerState)[n.userInfo[@"state"] integerValue];
    double progress = [n.userInfo[@"progress"] doubleValue];
    BOOL playing = (st == IMVoicePlayerStatePlaying);
    [self.im_voiceLockedBar applyPreviewPlaying:playing progress:progress
                                   totalMillis:self.im_voiceRecorder.elapsedMillis];
}

- (void)voiceRecorder:(IMVoiceRecorder *)recorder didSampleAmplitude:(float)amplitude elapsedMillis:(int64_t)elapsedMillis {
    if (self.im_voiceLocked) {
        [self.im_voiceLockedBar updateAmplitude:amplitude elapsedMillis:elapsedMillis];
    } else {
        [self.im_voiceHUD updateAmplitude:amplitude elapsedMillis:elapsedMillis];
        [self.im_voiceOverlay updateAmplitude:amplitude]; // 大圆钮呼吸环
    }
}

- (void)voiceRecorder:(IMVoiceRecorder *)recorder
    didStopWithReason:(IMVoiceRecorderStopReason)reason
              fileURL:(NSURL *)fileURL
            waveform:(NSString *)waveformBase64
             duration:(int64_t)durationMillis {
    [self.im_voiceHUD setVisible:NO animated:YES];
    [self.im_voiceLockedBar setVisible:NO animated:YES];
    // 复位 LockedBar 内部状态（previewMode/pausedIcon/amplitudes）——曾遗漏，下次录音复用 cell 时会以旧
    // previewMode=YES 状态出现（code-review 2026-08-27 CONFIRMED）。
    [self.im_voiceLockedBar setPreviewMode:NO amplitudes:nil];
    [self.im_voiceLockedBar setPausedIcon:NO];
    [self.im_voiceOverlay dismiss]; // 错误/太短等分支也要收浮层（正常路径已在手势 Ended 收过，幂等）
    self.im_voiceLocked = NO;
    // 停 preview 播放（如在播）+ 拆 preview 观察者——只在 preview 期间需要（efficiency 优化，避免全局 30fps 广播净增热路径）。
    [self im_stopPreviewPlaybackIfNeeded];
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
    if (!fileURL) {
        // 合并失败等（durationMillis 有值但 fileURL nil）——不能装作发出去，让用户重试。
        if (reason == IMVoiceRecorderStopReasonUserSend || reason == IMVoiceRecorderStopReasonReachedMax) {
            [self im_showToast:@"语音处理失败，请重试"];
        }
        return;
    }
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

    // 2026-08-27 修 #1「发送语音有不显示的 bug」——原实现要等 upload 完成后才 im_sendVoiceURL→回显，
    // 网络稍慢即感知为"发出去没了"。改为松手立即插入 Sending 占位气泡（临时 cid），upload 成功后
    // 摘掉占位、走 sendMedia 拿真实 cid 再回显；失败则占位就地转 Failed（红❗+ 点击 im_resendVoiceMessage）。
    NSString *placeholderCID = [NSString stringWithFormat:@"cli_voice_pending_%@", [[NSUUID UUID] UUIDString]];
    IMMessageModel *placeholder = [self im_persistLocalVoiceEcho:@"" waveform:waveform duration:durationMillis fileSize:fileSize clientMsgID:placeholderCID];
    IMLogUI(@"voice_upload_begin cid=%@ bytes=%lld dur_ms=%lld placeholder=%d", placeholderCID, fileSize, durationMillis, placeholder != nil);
    IMDatabaseAccountContext *dbCtx = [IMDatabase.sharedDatabase currentAccountContext];

    // 强持有 self（刻意，非泄漏）：录完松手立即退出聊天页时，上传→发送→落库链条仍须完成，
    // 否则消息无声丢失；上传结束块释放即断引用。完整方案=接入 IMMediaSendService 常驻队列（记 P2）。
    __weak typeof(self) ws = self;
    [[IMHTTPService sharedService] uploadVoiceData:data
                                          fileName:fileName
                                          mimeType:@"audio/mp4"
                                             token:token
                                          progress:nil
                                        completion:^(NSString *_Nullable url, NSError *_Nullable err) {
        // 回主线程：上传回调线程无保证；echo 赋值与 ack 回调统一在 main 串行，消除"极快 ack 先于
        // echo 赋值"的竞态窗口。
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err || url.length == 0) {
                // 占位就地转失败（红❗气泡长按/点击可 im_resendVoiceMessage 重传）。
                placeholder.status = IMMessageStatusFailed;
                placeholder.note = err.localizedDescription ?: @"语音上传失败";
                placeholder.content = fileURL.absoluteString; // 保留本地路径供重录复用（虽然目前重传走 URL 路径）
                if (dbCtx) {
                    [IMDatabase.sharedDatabase performWithAccountContext:dbCtx block:^(IMDatabase *db) { [db saveMessage:placeholder]; }];
                }
                __strong typeof(ws) self = ws;
                if (self) {
                    [self.tableView reloadData];
                    [self im_showToast:placeholder.note];
                }
                [[NSFileManager defaultManager] removeItemAtURL:fileURL error:NULL];
                return;
            }
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            // 摘掉占位（内存 + DB），走既有 sendMedia + 新 echo 路径（拿到真实 cid 后 upsert 落库）。
            NSUInteger idx = [self.messages indexOfObjectIdenticalTo:placeholder];
            if (idx != NSNotFound) { [self.messages removeObjectAtIndex:idx]; }
            if (dbCtx) {
                [IMDatabase.sharedDatabase performWithAccountContext:dbCtx block:^(IMDatabase *db) { [db deleteMessage:placeholder]; }];
            }
            [self im_sendVoiceURL:url waveform:waveform durationMillis:durationMillis fileSize:fileSize];
            [[NSFileManager defaultManager] removeItemAtURL:fileURL error:NULL]; // tmp 清理；播放走 URL（自动下载缓存）
        });
    }];
}

/// 按已上传的 URL 发送语音（上传完成与失败重试共用）：sendMedia + 本地落库回显 + ack 回写。主线程调用。
- (void)im_sendVoiceURL:(NSString *)url waveform:(NSString *)waveform durationMillis:(int64_t)durationMillis fileSize:(int64_t)fileSize {
    IMMediaAttributes *attrs = [IMMediaAttributes new];
    attrs.durationMillis = durationMillis;
    attrs.fileSize = fileSize;
    attrs.waveform = waveform;
    NSString *toUser = self.isGroupChat ? nil : self.peerID;
    // ack 回写（2026-08-26 修）：曾 completion:nil → 本地行 convSeq 永远 0——长按菜单所有项都被
    // convSeq>0 过滤（"长按无反应"）、详情页语音 tab 不收录、DB 行永远 Sending。
    // DB 更新不依赖 self（页面可能已退出）：捕获账号上下文直写库；UI 刷新才走 weak self。
    IMDatabaseAccountContext *dbCtx = [IMDatabase.sharedDatabase currentAccountContext];
    __weak typeof(self) wsAck = self;
    __block IMMessageModel *echo = nil; // 主线程先赋值、completion 异步回主队列后读——无竞态
    NSString *cid = [[IMSocketManager sharedManager] sendMedia:url contentType:@"voice"
                                                        toConv:self.convID toUser:toUser attributes:attrs
                                                    completion:^(BOOL success, NSError *error, int64_t convSeq) {
        dispatch_async(dispatch_get_main_queue(), ^{
            IMMessageModel *m = echo;
            IMLogUI(@"voice_send_ack cid=%@ ok=%d conv_seq=%lld echo=%d", m.clientMsgID ?: @"-", success, convSeq, m != nil);
            if (!m) { return; }
            m.status = success ? IMMessageStatusSent : IMMessageStatusFailed;
            m.convSeq = convSeq;
            if (dbCtx) {
                [IMDatabase.sharedDatabase performWithAccountContext:dbCtx block:^(IMDatabase *db) {
                    [db saveMessage:m]; // 按 clientMsgID upsert：sending → sent/failed 覆盖
                }];
            }
            __strong typeof(wsAck) self = wsAck;
            if (!self) { return; }
            if (convSeq > 0) { [self.seenConvSeqs addObject:@(convSeq)]; } // 防 sync 重复回显
            [self.tableView reloadData]; // failed 时气泡红 ! 标识随 reload 出现
        });
    }];
    // 本地立刻回显 + 落库（气泡出现——不等 ack）。
    echo = [self im_persistLocalVoiceEcho:url waveform:waveform duration:durationMillis fileSize:fileSize clientMsgID:cid];
}

/// 发送失败重试（§5.5：**不重录**——音频已在服务器，按原 URL 重新 send_msg）。
/// 旧 failed 行删除（内存+DB），按新 clientMsgID 重新走回显+ack 链。
- (void)im_resendVoiceMessage:(IMMessageModel *)m {
    if (m.status != IMMessageStatusFailed || m.content.length == 0) { return; }
    NSString *url = m.content;
    NSString *wave = m.waveform;
    int64_t dur = m.duration;
    int64_t size = m.fileSize;
    [self performDatabaseOperation:^(IMDatabase *db) { [db deleteMessage:m]; }];
    NSUInteger idx = [self.messages indexOfObjectIdenticalTo:m];
    if (idx != NSNotFound) { [self.messages removeObjectAtIndex:idx]; }
    [self im_sendVoiceURL:url waveform:wave durationMillis:dur fileSize:size];
}

/// 立即在本地库回显一条 voice 消息——与已有媒体路径同套（防"松手到 ack 之间气泡不见"）。
/// clientMsgID 已由 sendMedia 生成并塞进出网包；此处按同 cid 写库，ack 到达时按 cid 更新 serverMsgID。
#pragma mark - 播放（DataSource dispatch onPlayTap 用）

/// 播放语音消息：走 IMVoicePlayer 共享入口（缓存命中直接 toggle / 未缓存先下载；voice 恒自动下载见 §7）。
/// fullURL 参数保留签名兼容（共享入口内部按 host 拼 URL）。
- (void)im_playVoiceMessage:(IMMessageModel *)message fullURL:(NSString *)fullURL {
    __weak typeof(self) ws = self;
    [[IMVoicePlayer sharedPlayer] toggleEnsuringLocal:message host:self.host completion:^(NSError *err) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (err) { [self im_showToast:@"语音下载失败"]; return; }
        // 对方语音进入播放即消未播红点（本机语义，见 §7）。
        NSString *mid = IMVoicePlayerPlayableIDForMessage(message);
        if (mid && ![message.from isEqualToString:self.userID]) {
            [[IMVoicePlayer sharedPlayer] markPlayed:mid inConv:message.convID owner:self.userID];
        }
    }];
}

#pragma mark - 转文字（P1）

- (void)im_transcribeVoiceMessage:(IMMessageModel *)message {
    NSString *mid = IMVoicePlayerPlayableIDForMessage(message);
    if (!mid) { return; }
    // 缓存命中直接展开；未命中先确保音频在本地，再启动识别。
    NSString *cached = [[IMVoiceTranscriber sharedTranscriber] cachedTextForMessageID:mid convID:message.convID owner:self.userID];
    if (cached) {
        [self im_applyTranscriptText:cached loading:NO forMessageID:mid];
        return;
    }
    // 先订阅识别状态推送——一次性 observer，收到 final 或 unavailable 就摘掉。
    __block id token = [[NSNotificationCenter defaultCenter]
        addObserverForName:IMVoiceTranscriberDidChangeNotification object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *note) {
            NSString *notedID = note.userInfo[@"messageID"];
            if (![notedID isEqualToString:mid]) { return; }
            IMVoiceTranscribeStatus st = (IMVoiceTranscribeStatus)[note.userInfo[@"status"] integerValue];
            NSString *text = note.userInfo[@"text"];
            if (st == IMVoiceTranscribeStatusUnavailable) {
                // 权限被拒/受限 → 引导设置；其余走 unavailableReasonDescription 分辨（无网 / 语言包未就绪等）——
                // 用户 2026-08-27 报"给了权限仍暂不可用"，此前通用文案让人以为还要开权限，误导。
                NSString *tip = [IMVoiceTranscriber isAuthorizationDeniedOrRestricted]
                    ? @"转文字需要语音识别权限（请在「设置 → 隐私 → 语音识别」中打开）"
                    : [IMVoiceTranscriber unavailableReasonDescription];
                [self im_applyTranscriptText:tip loading:NO forMessageID:mid];
                [[NSNotificationCenter defaultCenter] removeObserver:token];
                token = nil;
                return;
            }
            [self im_applyTranscriptText:text loading:(st == IMVoiceTranscribeStatusRecognizing) forMessageID:mid];
            if (st == IMVoiceTranscribeStatusDone) {
                [[NSNotificationCenter defaultCenter] removeObserver:token];
                token = nil;
            }
        }];

    // 保底 UI：立刻展 "识别中…"（避免用户等待期间没反馈）。
    [self im_applyTranscriptText:nil loading:YES forMessageID:mid];

    // 拿本地音频 → 有则直接识别，无则先下再识别。voice 恒自动下载，一般已在缓存。
    NSURL *cachedURL = [IMMediaDownloader cachedFileURLForContent:message.content];
    if (cachedURL && [[NSFileManager defaultManager] fileExistsAtPath:cachedURL.path]) {
        [[IMVoiceTranscriber sharedTranscriber] transcribeMessageID:mid convID:message.convID owner:self.userID audioURL:cachedURL];
        return;
    }
    NSURL *remote = [NSURL URLWithString:[self fullMediaURL:message.content]];
    if (!remote || !cachedURL) {
        [self im_applyTranscriptText:@"转文字失败：音频不可用" loading:NO forMessageID:mid];
        return;
    }
    IMMediaDownloadTask *task = [[IMMediaDownloader shared] downloadURL:remote toDestination:cachedURL key:message.content];
    __weak typeof(self) ws = self;
    task.completionHandler = ^(NSURL *location, NSError *err) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (err || !location) {
            [self im_applyTranscriptText:@"转文字失败：语音下载失败" loading:NO forMessageID:mid];
            return;
        }
        [[IMVoiceTranscriber sharedTranscriber] transcribeMessageID:mid convID:message.convID owner:self.userID audioURL:location];
    };
}

/// 在可见 cell 上应用转写文本。cell 已被复用/滚出视口则忽略——下次再触发时会重新展开缓存。
- (void)im_applyTranscriptText:(nullable NSString *)text loading:(BOOL)loading forMessageID:(NSString *)mid {
    for (UITableViewCell *cell in self.tableView.visibleCells) {
        if (![cell isKindOfClass:[IMVoiceBubbleCell class]]) { continue; }
        NSIndexPath *ip = [self.tableView indexPathForCell:cell];
        if (ip.row >= (NSInteger)self.messages.count) { continue; }
        IMMessageModel *m = self.messages[ip.row];
        NSString *cellID = IMVoicePlayerPlayableIDForMessage(m);
        if ([cellID isEqualToString:mid]) {
            [(IMVoiceBubbleCell *)cell applyTranscriptText:text loading:loading];
            break;
        }
    }
}

- (IMMessageModel *)im_persistLocalVoiceEcho:(NSString *)url waveform:(NSString *)waveform duration:(int64_t)dur fileSize:(int64_t)size clientMsgID:(NSString *)cid {
    if (!cid) { return nil; }
    // 若同 cid 已存在（理论不至于），返回既有行防重复插入。
    for (IMMessageModel *x in self.messages) {
        if ([x.clientMsgID isEqualToString:cid]) { return x; }
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
    // 顺序（2026-08-27 修 #5「发送后必须退出会话再进入才显示」加固）：
    // ① 先 addObject 内存数组 + appendReloadAndScroll（用户即时看到气泡）；
    // ② 再落库（同 clientMsgID upsert，ack 到达后覆盖 sending→sent；也让"重进会话从 DB 自愈"生效）。
    // 之前"先落库再 addObject"存在窄窗口：saveMessage 之后如果 sync/new_msg fan-back 恰好触发内存
    // messages 重建（socket 层 processIncoming 走 addObject 而非 upsert 到已有引用），会与后续
    // addObject 生成两个数组分支，视觉上就是"发出去的气泡没了、直到重进会话才从 DB 拿回"。
    [self.messages addObject:m];
    [self appendReloadAndScroll];
    [self performDatabaseOperation:^(IMDatabase *db) { [db saveMessage:m]; }];
    // 诊断（2026-08-27，用户三报"发送后气泡不显示、滑动/重进才出现"，代码审读未定位）：
    // 打齐插入后的表状态——rows/offset/contentH/贴底与否。若下轮复现，此行 + ack 行可对账出
    // 是"没插入"“插入了没滚到位"还是"插入即被外力顶掉"。
    IMLogUI(@"voice_echo_inserted cid=%@ rows=%lu tv_rows=%ld offset_y=%.1f content_h=%.1f bounds_h=%.1f near_bottom=%d",
            cid, (unsigned long)self.messages.count, (long)[self.tableView numberOfRowsInSection:0],
            self.tableView.contentOffset.y, self.tableView.contentSize.height,
            self.tableView.bounds.size.height, [self isNearBottom]);
    return m;
}

@end
