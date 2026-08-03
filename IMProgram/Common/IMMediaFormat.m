//  IMMediaFormat.m

#import "IMMediaFormat.h"

const CGFloat kIMMediaFallbackSide = 180;

NSString *IMFormatMediaDuration(int64_t millis) {
    if (millis <= 0) { return nil; }
    int64_t totalSeconds = (millis + 999) / 1000; // 向上取整：0.4s 的视频也显 0:01，不显 0:00
    int64_t hours = totalSeconds / 3600;
    int64_t minutes = (totalSeconds % 3600) / 60;
    int64_t seconds = totalSeconds % 60;
    if (hours > 0) {
        return [NSString stringWithFormat:@"%lld:%02lld:%02lld", hours, minutes, seconds];
    }
    return [NSString stringWithFormat:@"%lld:%02lld", minutes, seconds];
}

NSString *IMFormatByteSize(int64_t bytes) {
    if (bytes <= 0) { return nil; }
    if (bytes < 1024) { return [NSString stringWithFormat:@"%lld B", bytes]; }
    double kb = (double)bytes / 1024.0;
    if (kb < 1024) { return [NSString stringWithFormat:@"%.0f KB", kb]; }
    double mb = kb / 1024.0;
    if (mb < 1024) { return [NSString stringWithFormat:@"%.1f MB", mb]; }
    return [NSString stringWithFormat:@"%.1f GB", mb / 1024.0];
}

NSString *IMFormatUploadProgress(double fraction, int64_t totalBytes) {
    if (fraction <= 0) { return @"等待中"; }
    double clamped = MIN(fraction, 1.0);
    if (totalBytes <= 0) { return [NSString stringWithFormat:@"%d%%", (int)(clamped * 100)]; }
    int64_t sent = (int64_t)llround(clamped * (double)totalBytes);
    return [NSString stringWithFormat:@"%@ / %@", IMFormatByteSize(sent) ?: @"0 B", IMFormatByteSize(totalBytes)];
}

CGSize IMMediaDisplaySize(CGFloat pixelW, CGFloat pixelH, CGSize maxBox, CGFloat minSide) {
    if (maxBox.width <= 0 || maxBox.height <= 0) { return CGSizeZero; }
    if (pixelW <= 0 || pixelH <= 0) {
        CGFloat side = MIN(MIN(maxBox.width, maxBox.height), kIMMediaFallbackSide);
        return CGSizeMake(side, side);
    }
    CGFloat k = MIN(MIN(maxBox.width / pixelW, maxBox.height / pixelH), 1.0); // 不放大超过 1pt/px
    CGSize out = CGSizeMake(round(pixelW * k), round(pixelH * k));
    CGFloat shortSide = MIN(out.width, out.height);
    if (minSide > 0 && shortSide > 0 && shortSide < minSide) {
        CGFloat up = minSide / shortSide;
        out = CGSizeMake(MIN(round(out.width * up), maxBox.width),
                         MIN(round(out.height * up), maxBox.height));
    }
    return out;
}
