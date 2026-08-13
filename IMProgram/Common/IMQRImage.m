//  IMQRImage.m

#import "IMQRImage.h"
#import <CoreImage/CoreImage.h>

@implementation IMQRImage

+ (UIImage *)imageForString:(NSString *)string size:(CGFloat)size {
    if (string.length == 0 || size <= 0) { return nil; }
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    if (!filter) { return nil; }
    [filter setValue:data forKey:@"inputMessage"];
    [filter setValue:@"M" forKey:@"inputCorrectionLevel"]; // 中留白盖 logo 用，模块数不过高
    CIImage *ci = filter.outputImage;
    if (!ci) { return nil; }

    // 最近邻放大到目标像素（默认输出很小、直接拉伸会糊）。
    CGFloat scale = UIScreen.mainScreen.scale;
    CGFloat px = size * scale;
    CGFloat factor = px / CGRectGetWidth(ci.extent);
    CIImage *scaled = [ci imageByApplyingTransform:CGAffineTransformMakeScale(factor, factor)];

    CIContext *ctx = [CIContext contextWithOptions:nil];
    CGImageRef cg = [ctx createCGImage:scaled fromRect:scaled.extent];
    if (!cg) { return nil; }
    UIImage *img = [UIImage imageWithCGImage:cg scale:scale orientation:UIImageOrientationUp];
    CGImageRelease(cg);
    return img;
}

+ (NSArray<NSString *> *)decodeAllInImage:(UIImage *)image {
    CIImage *ci = image.CIImage;
    if (!ci && image.CGImage) { ci = [CIImage imageWithCGImage:image.CGImage]; }
    if (!ci) { return @[]; }
    CIContext *ctx = [CIContext contextWithOptions:nil];
    CIDetector *detector = [CIDetector detectorOfType:CIDetectorTypeQRCode context:ctx
                                              options:@{ CIDetectorAccuracy: CIDetectorAccuracyHigh }];
    NSArray<CIFeature *> *features = [detector featuresInImage:ci];

    // 面积大的通常是用户想扫的那张（截图里主码大、水印码小），据此排序后再去重。
    NSArray<CIFeature *> *sorted = [features sortedArrayUsingComparator:^NSComparisonResult(CIFeature *a, CIFeature *b) {
        CGFloat sa = CGRectGetWidth(a.bounds) * CGRectGetHeight(a.bounds);
        CGFloat sb = CGRectGetWidth(b.bounds) * CGRectGetHeight(b.bounds);
        if (sa > sb) { return NSOrderedAscending; }
        if (sa < sb) { return NSOrderedDescending; }
        return NSOrderedSame;
    }];

    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (CIFeature *f in sorted) {
        if (![f isKindOfClass:[CIQRCodeFeature class]]) { continue; }
        NSString *msg = ((CIQRCodeFeature *)f).messageString;
        if (msg.length > 0 && ![out containsObject:msg]) { [out addObject:msg]; }
    }
    return out;
}

@end
