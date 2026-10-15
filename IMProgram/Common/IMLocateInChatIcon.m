//  IMLocateInChatIcon.m

#import "IMLocateInChatIcon.h"

static const CGFloat kIMLocateViewBox = 24;
static const CGFloat kIMLocateStroke = 1.8;

@implementation IMLocateInChatIcon

/// 设计稿 path（SVG 坐标，y 向下与 UIKit 同向，故 sweep-flag=1 ↔ clockwise:YES）：
///   M6 4.5h12a2.5 2.5 0 0 1 2.5 2.5v7a2.5 2.5 0 0 1-2.5 2.5h-6.2L8 20v-3.5H6A2.5 2.5 0 0 1 3.5 14V7A2.5 2.5 0 0 1 6 4.5z
///   M9.5 13l5-5M10.5 8h4v4
+ (UIBezierPath *)pathInViewBox {
    const CGFloat r = 2.5;
    UIBezierPath *p = [UIBezierPath bezierPath];
    // 气泡轮廓（四角 r=2.5，左下带尾巴）
    [p moveToPoint:CGPointMake(6, 4.5)];
    [p addLineToPoint:CGPointMake(18, 4.5)];
    [p addArcWithCenter:CGPointMake(18, 7) radius:r startAngle:-M_PI_2 endAngle:0 clockwise:YES];
    [p addLineToPoint:CGPointMake(20.5, 14)];
    [p addArcWithCenter:CGPointMake(18, 14) radius:r startAngle:0 endAngle:M_PI_2 clockwise:YES];
    [p addLineToPoint:CGPointMake(11.8, 16.5)];
    [p addLineToPoint:CGPointMake(8, 20)];
    [p addLineToPoint:CGPointMake(8, 16.5)];
    [p addLineToPoint:CGPointMake(6, 16.5)];
    [p addArcWithCenter:CGPointMake(6, 14) radius:r startAngle:M_PI_2 endAngle:M_PI clockwise:YES];
    [p addLineToPoint:CGPointMake(3.5, 7)];
    [p addArcWithCenter:CGPointMake(6, 7) radius:r startAngle:M_PI endAngle:M_PI * 1.5 clockwise:YES];
    [p closePath];
    // 箭头：斜杆 + 直角箭头
    [p moveToPoint:CGPointMake(9.5, 13)];
    [p addLineToPoint:CGPointMake(14.5, 8)];
    [p moveToPoint:CGPointMake(10.5, 8)];
    [p addLineToPoint:CGPointMake(14.5, 8)];
    [p addLineToPoint:CGPointMake(14.5, 12)];
    p.lineWidth = kIMLocateStroke;
    p.lineCapStyle = kCGLineCapRound;
    p.lineJoinStyle = kCGLineJoinRound;
    return p;
}

+ (UIImage *)imageWithSide:(CGFloat)side {
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; });
    CGFloat scale = UIScreen.mainScreen.scale;
    NSString *key = [NSString stringWithFormat:@"%.2f|%.0f", side, scale];
    UIImage *hit = [cache objectForKey:key];
    if (hit) { return hit; }

    CGFloat k = side / kIMLocateViewBox;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.scale = scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:fmt];
    UIImage *img = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.blackColor setStroke];
        UIBezierPath *p = [self pathInViewBox];
        [p applyTransform:CGAffineTransformMakeScale(k, k)];
        p.lineWidth = kIMLocateStroke * k;
        [p stroke];
    }];
    img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [cache setObject:img forKey:key];
    return img;
}

@end
