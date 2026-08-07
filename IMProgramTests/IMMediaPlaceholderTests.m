#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>

#import "../IMProgram/Common/IMMediaPlaceholder.h"

/// 磨砂占位渲染器（M4-7）的解码 + 代理放大契约。
/// 用运行时现造的一张已知 JPEG dataURI（避免内嵌魔法 blob），验证：
///  - 合法 thumb（横/竖）→ 解出非空、代理最长边 == 48（renderFrosted 的等比放大目标）；
///  - 空 / 无逗号 / 非法 base64 → 回调 nil，不 crash。
/// 锁住的正是「解码路径回 nil→退灰底」这类静默回归（曾因 dataWithContentsOfURL 对 data: 不可靠而怀疑）。
/// 注：**不断言 NSCache 命中** —— NSCache 不保证保留，随时可能被系统回收，断言其保留会偶发假失败。
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

/// 合法 thumb → 解出非空磨砂图，且等比放大到「最长边 == 48」的代理尺寸（横竖两种朝向都测）。
- (void)frostAndAssertLongestSide48ForWidth:(CGFloat)w height:(CGFloat)h label:(NSString *)label {
    NSString *thumb = [self jpegDataURIWithWidth:w height:h];
    XCTestExpectation *exp = [self expectationWithDescription:label];
    [IMMediaPlaceholder frostedForThumb:thumb completion:^(UIImage *blurred) {
        XCTAssertNotNil(blurred, @"%@：合法 thumb 必须解出磨砂图（回 nil 即退灰底的静默回归）", label);
        XCTAssertEqualWithAccuracy(MAX(blurred.size.width, blurred.size.height), 48.0, 1.0,
                                   @"%@：代理最长边应为 48", label);
        XCTAssertGreaterThan(MIN(blurred.size.width, blurred.size.height), 0, @"%@：短边应 > 0", label);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testFrostedLandscapeScalesLongestSideTo48 {
    [self frostAndAssertLongestSide48ForWidth:20 height:15 label:@"横图 20x15→代理48x36"];
}

- (void)testFrostedPortraitScalesLongestSideTo48 {
    [self frostAndAssertLongestSide48ForWidth:9 height:20 label:@"竖图 9x20→代理22x48"];
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
