#import <XCTest/XCTest.h>

@interface IMTelegramAvatarMaskTests : XCTestCase
@end

@implementation IMTelegramAvatarMaskTests

- (void)testOriginalTelegramMaskResourceIsPackaged {
    NSURL *resourceURL = [NSBundle.mainBundle URLForResource:@"UserAvatarMask" withExtension:@"json"];
    XCTAssertNotNil(resourceURL);
    NSData *data = [NSData dataWithContentsOfURL:resourceURL];
    XCTAssertNotNil(data);
    NSError *error = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(json[@"v"], @"5.10.1");
    XCTAssertEqualObjects(json[@"nm"], @"Comp 2");
    XCTAssertEqualObjects(json[@"fr"], @60);
    XCTAssertEqualObjects(json[@"w"], @512);
    XCTAssertEqualObjects(json[@"h"], @512);
    XCTAssertEqualObjects(json[@"op"], @540);
    XCTAssertEqual([json[@"assets"] count], 1);
    XCTAssertEqual([json[@"layers"] count], 1);
    XCTAssertTrue([json[@"layers"] isKindOfClass:NSArray.class]);
}

@end
