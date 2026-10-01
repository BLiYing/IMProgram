//  IMAvatarPlaceholderTests.m
//  首字母占位头像（通知扩展没有可用头像时用，PUSH_M5_DESIGN §3.6）：尺寸对、底色与 App 内同一种子同色。

#import <XCTest/XCTest.h>
#import "IMAvatarPlaceholder.h"
#import "IMTheme.h"

@interface IMAvatarPlaceholderTests : XCTestCase
@end

@implementation IMAvatarPlaceholderTests

/// 左上角像素的 RGB（0–255）。
- (NSArray<NSNumber *> *)cornerRGB:(UIImage *)image {
    uint8_t px[4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, 1, 1, 8, 4, space, kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(ctx, CGRectMake(0, 0, CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage)), image.CGImage);
    CGContextRelease(ctx);
    CGColorSpaceRelease(space);
    return @[ @(px[0]), @(px[1]), @(px[2]) ];
}

- (NSArray<NSNumber *> *)rgbOf:(UIColor *)color {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return @[ @(lround(r * 255)), @(lround(g * 255)), @(lround(b * 255)) ];
}

- (void)testRendersSquareImageOfRequestedSide {
    UIImage *image = [UIImage imageWithData:IMAvatarPlaceholderPNG(@"用户9865", @"1000156391", 256)];
    XCTAssertNotNil(image);
    XCTAssertEqual(CGImageGetWidth(image.CGImage), 256u);
    XCTAssertEqual(CGImageGetHeight(image.CGImage), 256u);
}

/// 底色与 App 内头像圈同一种子同色：通知里看到的颜色和会话列表里的一致。
- (void)testBackgroundIsTheSeedColorUsedInApp {
    for (NSString *seed in @[ @"1000156391", @"g_f87fa35c240b73bd", @"5205766476" ]) {
        UIImage *image = [UIImage imageWithData:IMAvatarPlaceholderPNG(@"名字", seed, 64)];
        NSArray *corner = [self cornerRGB:image];
        NSArray *expected = [self rgbOf:[IMTheme avatarColorForSeed:seed]];
        for (NSUInteger i = 0; i < 3; i++) {
            XCTAssertEqualWithAccuracy([corner[i] doubleValue], [expected[i] doubleValue], 2, @"seed %@", seed);
        }
    }
}

- (void)testInvalidSideGivesNil {
    XCTAssertNil(IMAvatarPlaceholderPNG(@"a", @"b", 0));
}

/// 没有名字也画得出来（用种子取字），不因此退回 App 图标。
- (void)testMissingNameStillRenders {
    XCTAssertNotNil(IMAvatarPlaceholderPNG(nil, @"1000156391", 32));
}

@end
