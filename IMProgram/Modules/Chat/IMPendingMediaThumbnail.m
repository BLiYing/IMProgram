//  IMPendingMediaThumbnail.m

#import "IMPendingMediaThumbnail.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>

UIImage *IMPendingVideoThumbnail(NSString *path) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    gen.appliesPreferredTrackTransform = YES;
    gen.maximumSize = CGSizeMake(600, 600);
    CGImageRef cg = [gen copyCGImageAtTime:CMTimeMakeWithSeconds(0.1, 600) actualTime:NULL error:NULL];
    if (!cg) { return nil; }
    UIImage *thumb = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return thumb;
}

UIImage *IMPendingImageThumbnail(NSString *path) {
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!src) { return nil; }
    CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)@{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (id)kCGImageSourceShouldCacheImmediately: @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize: @(1024),
    });
    CFRelease(src);
    if (!cg) { return nil; }
    UIImage *thumb = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return thumb;
}
