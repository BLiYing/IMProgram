//  IMUploadProgress.m

#import "IMUploadProgress.h"
#import "IMMediaFormat.h"

@implementation IMUploadProgress

+ (instancetype)progressWithFraction:(double)fraction totalBytes:(int64_t)totalBytes {
    IMUploadProgress *p = [IMUploadProgress new];
    p->_fraction = MAX(0, MIN(fraction, 1.0));
    p->_totalBytes = MAX(0, totalBytes);
    return p;
}

+ (instancetype)queuedWithTotalBytes:(int64_t)totalBytes {
    return [self progressWithFraction:0 totalBytes:totalBytes];
}

+ (instancetype)failedProgress {
    IMUploadProgress *p = [IMUploadProgress new];
    p->_failed = YES;
    return p;
}

- (NSString *)displayText {
    if (self.failed) { return @"发送失败"; }
    return IMFormatUploadProgress(self.fraction, self.totalBytes);
}

@end
