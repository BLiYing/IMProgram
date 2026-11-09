//  IMMediaPickLogic.m

#import "IMMediaPickLogic.h"

const NSInteger kIMMediaPickLimit = 9;
NSString * const kIMMediaPickAllBucketID = @"__all__";
const long long kIMMediaSizeUnknown = -1;

/// 调用方没给上限（<=0）时的兜底：服务端默认单文件上限 2 GiB。真实上限由调用方传入（服务端下发，S3a 可改），
/// 这里不引 IMServerConfigStore 以保持纯逻辑。
static const long long kIMMediaPickFallbackMaxBytes = 2048LL * 1024 * 1024;

static long long IMMediaPickEffectiveMax(long long maxBytes) {
    return maxBytes > 0 ? maxBytes : kIMMediaPickFallbackMaxBytes;
}

/// 每格目标宽度（pt）：regular 宽度（iPad / 横屏）下列数随宽度增加，保持格子大小与手机相近。
static const CGFloat kIMMediaPickTargetCellWidth = 100;
static const NSInteger kIMMediaPickMinColumns = 4;

@implementation IMMediaPickLogic

+ (nullable NSArray<NSString *> *)toggledSelection:(NSArray<NSString *> *)selected
                                          assetID:(NSString *)assetID
                                            limit:(NSInteger)limit {
    if ([selected containsObject:assetID]) {
        NSMutableArray<NSString *> *next = [selected mutableCopy];
        [next removeObject:assetID];
        return next;
    }
    if ((NSInteger)selected.count >= limit) { return nil; }
    return [selected arrayByAddingObject:assetID];
}

+ (NSInteger)numberOfAssetID:(NSString *)assetID inSelection:(NSArray<NSString *> *)selected {
    NSUInteger idx = [selected indexOfObject:assetID];
    return idx == NSNotFound ? 0 : (NSInteger)idx + 1;
}

+ (IMVideoTranscodeOutcome)transcodeOutcomeWanted:(BOOL)wanted exported:(BOOL)exported {
    if (!wanted) { return IMVideoTranscodeOutcomeSkipped; }
    return exported ? IMVideoTranscodeOutcomeDone : IMVideoTranscodeOutcomeFellBack;
}

+ (BOOL)isSelectableWithSizeBytes:(long long)sizeBytes maxBytes:(long long)maxBytes {
    // 只有「超上限」会不可选。体积未知与 0 都放行：PhotoKit 没有公开的大小 API，取不到（含给 0）是常态，
    // 读到的 0 已在 IMMediaPickerPhotos 里归为「未知」；真正的 0 字节坏文件留给发送时的 byteCount 校验标失败。
    return sizeBytes <= IMMediaPickEffectiveMax(maxBytes);
}

+ (BOOL)isTooLargeWithSizeBytes:(long long)sizeBytes maxBytes:(long long)maxBytes {
    return sizeBytes > IMMediaPickEffectiveMax(maxBytes);
}

+ (long long)totalBytesForSelection:(NSArray<NSString *> *)selected
                              sizes:(NSDictionary<NSString *, NSNumber *> *)sizes {
    long long total = 0;
    for (NSString *assetID in selected) {
        long long size = sizes[assetID].longLongValue;
        if (size > 0) { total += size; }
    }
    return total;
}

+ (NSString *)sizeLabelForBytes:(long long)bytes {
    if (bytes <= 0) { return @"0 B"; }
    if (bytes < 1024) { return [NSString stringWithFormat:@"%lld B", bytes]; }
    double v = (double)bytes;
    if (bytes < 1024LL * 1024) { return [NSString stringWithFormat:@"%.1f KB", v / 1024.0]; }
    if (bytes < 1024LL * 1024 * 1024) { return [NSString stringWithFormat:@"%.1f MB", v / 1024.0 / 1024.0]; }
    return [NSString stringWithFormat:@"%.2f GB", v / 1024.0 / 1024.0 / 1024.0];
}

+ (NSString *)durationLabelForSeconds:(NSTimeInterval)seconds {
    NSInteger total = (NSInteger)MAX(0, floor(seconds));
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(total / 60), (long)(total % 60)];
}

+ (NSInteger)columnCountForWidth:(CGFloat)width {
    NSInteger n = (NSInteger)floor(width / kIMMediaPickTargetCellWidth);
    return MAX(kIMMediaPickMinColumns, n);
}

@end
