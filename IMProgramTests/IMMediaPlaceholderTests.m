#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>

#import "../IMProgram/Common/IMMediaPlaceholder.h"

/// 磨砂占位渲染器（M4-7）的解码 + 代理放大契约。
/// 用运行时现造的一张已知 JPEG dataURI（避免内嵌魔法 blob），验证：
///  - 合法 thumb → 解出非空、代理最长边 == 48（renderFrosted 的等比放大目标）；
///  - 解出后同步缓存命中；
///  - 空/无逗号/非法 base64 → 回调 nil，不 crash。
/// 锁住的正是「解码路径回 nil→退灰底」这类静默回归（曾因 dataWithContentsOfURL 对 data: 不可靠而怀疑）。
@interface IMMediaPlaceholderTests : XCTestCase
@end

@implementation IMMediaPlaceholderTests

/// 现造一张 wide×high 像素的纯色 JPEG 的 data:URI（scale=1，像素即点，便于断言代理尺寸）。
- (NSString *)jpegDataURIWithWidth:(CGFloat)w height:(CGFloat)h {
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.scale = 1; fmt.opaque = YES;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(w, h) format:fmt];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.systemRedColor setFill];
        [ctx fillRect:CGRectMake(0, 0, w, h)];
    }];
    NSData *jpeg = UIImageJPEGRepresentation(img, 0.6);
    XCTAssertGreaterThan(jpeg.length, 0, @"测试夹具本身应能编出 JPEG");
    return [NSString stringWithFormat:@"data:image/jpeg;base64,%@", [jpeg base64EncodedStringWithOptions:0]];
}

- (void)testFrostedDecodesAndScalesToProxyLongestSide48 {
    NSString *thumb = [self jpegDataURIWithWidth:20 height:15]; // 横图 → 代理 48×36
    XCTAssertNil([IMMediaPlaceholder cachedFrostedForThumb:thumb], @"首次应未缓存");

    XCTestExpectation *exp = [self expectationWithDescription:@"frosted"];
    [IMMediaPlaceholder frostedForThumb:thumb completion:^(UIImage *blurred) {
        XCTAssertNotNil(blurred, @"合法 thumb 必须解出磨砂图（回 nil 即退灰底的静默回归）");
        CGFloat longest = MAX(blurred.size.width, blurred.size.height);
        XCTAssertEqualWithAccuracy(longest, 48.0, 1.0, @"代理最长边应为 48");
        XCTAssertGreaterThan(MIN(blurred.size.width, blurred.size.height), 0, @"短边应 > 0");
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];

    XCTAssertNotNil([IMMediaPlaceholder cachedFrostedForThumb:thumb], @"渲染后应进缓存、同步可取");
}

- (void)testPortraitThumbAlsoCapsLongestSideTo48 {
    NSString *thumb = [self jpegDataURIWithWidth:9 height:20]; // 竖图 → 代理 22×48（近似）
    XCTestExpectation *exp = [self expectationWithDescription:@"portrait"];
    [IMMediaPlaceholder frostedForThumb:thumb completion:^(UIImage *blurred) {
        XCTAssertNotNil(blurred);
        XCTAssertEqualWithAccuracy(MAX(blurred.size.width, blurred.size.height), 48.0, 1.0);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testInvalidInputsYieldNilWithoutCrash {
    for (NSString *bad in @[ @"", @"not-a-data-uri-no-comma", @"data:image/jpeg;base64,@@@notbase64@@@" ]) {
        XCTestExpectation *exp = [self expectationWithDescription:bad];
        [IMMediaPlaceholder frostedForThumb:bad completion:^(UIImage *blurred) {
            XCTAssertNil(blurred, @"非法输入应回 nil：%@", bad);
            [exp fulfill];
        }];
        [self waitForExpectationsWithTimeout:5 handler:nil];
    }
    XCTAssertNil([IMMediaPlaceholder cachedFrostedForThumb:nil], @"nil 入参同步取缓存应为 nil");
    XCTAssertNil([IMMediaPlaceholder cachedFrostedForThumb:@""], @"空串同步取缓存应为 nil");
}

@end
