//  IMUploadProgress.m

#import "IMUploadProgress.h"
#import "IMMediaFormat.h"

/// 转码/上传在总进度里的权重。转码快慢看设备、上传快慢看网络，谁都预估不了，
/// 与其算一个假的自适应值，不如给个稳定常数——视觉上只要"一直往前走"就够。
static const double kIMTranscodeWeight = 0.35;
static const double kIMUploadWeight = 0.65;

@implementation IMUploadProgress

+ (instancetype)progressWithPhase:(IMUploadPhase)phase fraction:(double)fraction totalBytes:(int64_t)totalBytes {
    IMUploadProgress *p = [IMUploadProgress new];
    p->_phase = phase;
    p->_fraction = MAX(0, MIN(fraction, 1.0));
    p->_totalBytes = MAX(0, totalBytes);
    p->_failed = phase == IMUploadPhaseFailed;
    return p;
}

+ (instancetype)queued { return [self progressWithPhase:IMUploadPhaseQueued fraction:0 totalBytes:0]; }

+ (instancetype)transcodingWithFraction:(double)fraction {
    return [self progressWithPhase:IMUploadPhaseTranscoding fraction:fraction totalBytes:0];
}

+ (instancetype)uploadingWithFraction:(double)fraction totalBytes:(int64_t)totalBytes previous:(IMUploadProgress *)previous {
    IMUploadProgress *p = [self progressWithPhase:IMUploadPhaseUploading fraction:fraction totalBytes:totalBytes];
    p->_afterTranscode = previous.phase == IMUploadPhaseTranscoding || previous.afterTranscode;
    return p;
}

+ (instancetype)failedProgress { return [self progressWithPhase:IMUploadPhaseFailed fraction:0 totalBytes:0]; }

- (double)overallFraction {
    switch (self.phase) {
        case IMUploadPhaseQueued:      return 0;
        case IMUploadPhaseFailed:      return 0;
        case IMUploadPhaseTranscoding: return kIMTranscodeWeight * self.fraction;
        case IMUploadPhaseUploading:
            // 转码过 → 接在转码段之后（0.35→1.0），环不会倒退；
            // 没转码（图片/直传视频）→ 整条刻度都归上传，不凭空从 35% 起跳。
            return self.afterTranscode ? kIMTranscodeWeight + kIMUploadWeight * self.fraction : self.fraction;
    }
}

- (NSString *)fileLineText {
    if (self.failed) { return @"发送失败"; }
    // 排队 = 尚未开始传输：文件面板相册路径此阶段还在从相册导出原件（大小未知），统一显「准备中…」。
    if (self.phase == IMUploadPhaseQueued) { return @"准备中…"; }
    if (self.phase == IMUploadPhaseTranscoding) { return [self displayText]; } // 文件不转码，防御回落
    // 上传/暂停均只显纯字节数（「已传」有歧义像传完了；暂停态由气泡在行首加 ⏸ 小图标，同媒体角标）。
    return IMFormatUploadProgress(self.fraction, self.totalBytes);
}

- (NSString *)displayText {
    switch (self.phase) {
        case IMUploadPhaseFailed:      return @"发送失败";
        case IMUploadPhaseQueued:      return @"等待中";
        case IMUploadPhaseTranscoding: return [NSString stringWithFormat:@"压缩中 %d%%", (int)(self.fraction * 100)];
        case IMUploadPhaseUploading:   return IMFormatUploadProgress(self.fraction, self.totalBytes);
    }
}

@end
