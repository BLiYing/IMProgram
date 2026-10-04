//
//  IMReadTickTests.m —— 已读勾图标：尺寸比例 / template / 缓存 / 富文本结构。
//

#import <XCTest/XCTest.h>
#import "IMReadTick.h"

@interface IMReadTickTests : XCTestCase
@end

@implementation IMReadTickTests

- (void)testSizesFollowViewBoxRatio {
    UIImage *one = [IMReadTick imageDouble:NO height:10];
    UIImage *two = [IMReadTick imageDouble:YES height:10];
    XCTAssertEqualWithAccuracy(one.size.width, 13, 0.01);
    XCTAssertEqualWithAccuracy(two.size.width, 18, 0.01);
    XCTAssertEqualWithAccuracy(two.size.height, 10, 0.01);
}

- (void)testTemplateAndCached {
    UIImage *a = [IMReadTick imageDouble:YES height:9.5];
    XCTAssertEqual(a.renderingMode, UIImageRenderingModeAlwaysTemplate);
    XCTAssertTrue(a == [IMReadTick imageDouble:YES height:9.5], @"同参数应命中缓存");
}

- (void)testMetaStructure {
    UIFont *f = [UIFont systemFontOfSize:10];
    NSAttributedString *s = [IMReadTick metaWithTime:@"12:30" read:YES font:f
                                           timeColor:UIColor.grayColor tickColor:UIColor.blueColor];
    XCTAssertEqual(s.length, 6u); // 5 字符时间 + 1 个附件
    XCTAssertEqualObjects([s.string substringToIndex:5], @"12:30");
    NSTextAttachment *att = [s attribute:NSAttachmentAttributeName atIndex:5 effectiveRange:NULL];
    XCTAssertNotNil(att);
    XCTAssertEqualWithAccuracy(att.bounds.size.height, 9.5, 0.4);
    XCTAssertEqualWithAccuracy(att.bounds.size.width, 17.1, 0.4);
    XCTAssertEqualObjects([s attribute:NSKernAttributeName atIndex:4 effectiveRange:NULL], @(kIMReadTickGap));
    XCTAssertNil([s attribute:NSKernAttributeName atIndex:0 effectiveRange:NULL]);
}

- (void)testEmptyTimeOnlyTick {
    NSAttributedString *s = [IMReadTick metaWithTime:nil read:NO font:[UIFont systemFontOfSize:11]
                                           timeColor:UIColor.grayColor tickColor:UIColor.grayColor];
    XCTAssertEqual(s.length, 1u);
}

@end
