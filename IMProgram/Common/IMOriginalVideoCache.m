//  IMOriginalVideoCache.m

#import "IMOriginalVideoCache.h"
#import "IMLog.h"

@implementation IMOriginalVideoCache

+ (NSURL *)cacheURLForFullURL:(NSString *)fullURL {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
                     stringByAppendingPathComponent:@"im_original_videos"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    // 命名沿用查看器历史格式（<hash>.mp4），老缓存无缝命中。
    NSString *name = [NSString stringWithFormat:@"%lu.mp4", (unsigned long)fullURL.hash];
    return [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:name]];
}

+ (BOOL)hasCacheForFullURL:(NSString *)fullURL {
    if (fullURL.length == 0) { return NO; }
    return [[NSFileManager defaultManager] fileExistsAtPath:[self cacheURLForFullURL:fullURL].path];
}

+ (void)adoptFileAtPath:(NSString *)path forFullURL:(NSString *)fullURL {
    if (path.length == 0 || fullURL.length == 0) { return; }
    NSURL *dst = [self cacheURLForFullURL:fullURL];
    [[NSFileManager defaultManager] removeItemAtURL:dst error:NULL];
    NSError *err = nil;
    if ([[NSFileManager defaultManager] moveItemAtURL:[NSURL fileURLWithPath:path] toURL:dst error:&err]) {
        IMLogDebugWithTag(IMLogTagMedia, @"original_video_adopted url=%@", fullURL);
    } else {
        IMLogWarnWithTag(IMLogTagMedia, @"original_video_adopt_failed url=%@ error=%@",
                         fullURL, err.localizedDescription ?: @"-");
    }
}

@end
