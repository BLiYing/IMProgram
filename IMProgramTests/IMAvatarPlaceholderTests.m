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

/// 结尾是 emoji（辅助平面字符，UTF-16 用一对代理对表示，不是汉字）：退回取首字母，
/// 且取组合字符序列时不会把代理对拆成半个（拆了会是无效字符甚至抛异常）。
- (void)testTrailingEmojiFallsBackToFirstGraphemeSafely {
    NSString *name = @"小😀"; // 😀 = U+1F600，两个 UTF-16 code unit
    XCTAssertEqualObjects(IMAvatarInitials(name), @"小");
}

/// 扩展区汉字（辅助平面，代理对表示）同样要识别成汉字、取末字整体，不是半个代理对。
- (void)testSupplementaryPlaneHanCharacterIsRecognized {
    NSString *name = [@"小" stringByAppendingString:@"\U00020000"]; // U+20000，CJK 扩展 B 的第一个字
    XCTAssertEqualObjects(IMAvatarInitials(name), @"\U00020000");
}

/// 扩展 C 起更冷门的辅助平面汉字（如 U+2A700）同样要识别——范围覆盖到整个辅助表意平面，不只 B。
- (void)testSupplementaryPlaneExtensionCHanCharacterIsRecognized {
    NSString *name = [@"小" stringByAppendingString:@"\U0002A700"]; // U+2A700，CJK 扩展 C 的第一个字
    XCTAssertEqualObjects(IMAvatarInitials(name), @"\U0002A700");
}

/// 大写不能把一个字拆成两个——`-uppercaseString` 的完整 Unicode 大小写折叠会把德语 ß 变成两个字符
/// "SS"，画到头像圆里就是挤进两个字母。改用简单大写映射，没有大写形式就原样返回。
- (void)testUppercaseDoesNotSplitOneCharacterIntoTwo {
    NSString *result = IMAvatarInitials(@"ßtraße99");
    XCTAssertEqual(result.length, 1u);
    XCTAssertEqualObjects(result, @"ß"); // ß 没有「简单大写映射」，原样返回，不是 "SS"
}

@end
