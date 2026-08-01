#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMMediaUtil.h"

@interface IMFileTypeIconTests : XCTestCase
@end

@implementation IMFileTypeIconTests

- (void)testMainstreamExtensionsMapToSharedIconKinds {
    NSDictionary<NSString *, NSString *> *cases = @{
        @"report.pdf": @"pdf", @"letter.docx": @"word", @"budget.xlsx": @"excel",
        @"deck.pptx": @"powerpoint", @"export.csv": @"csv", @"draft.pages": @"pages",
        @"forecast.numbers": @"numbers", @"talk.key": @"keynote", @"notes.txt": @"text",
        @"readme.md": @"markdown", @"layout.xml": @"xml", @"data.json": @"json",
        @"photo.heic": @"image", @"clip.mov": @"video", @"voice.flac": @"audio",
        @"bundle.7z": @"archive", @"screen.swift": @"code", @"cache.sqlite": @"database",
        @"face.woff2": @"font", @"book.epub": @"ebook", @"installer.dmg": @"package",
    };
    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *fileName, NSString *kind, BOOL *stop) {
        XCTAssertEqualObjects(IMFileTypeIdentifierForName(fileName), kind, @"%@", fileName);
    }];
}

- (void)testUploadedURLAndUnknownExtensionAreHandled {
    XCTAssertEqualObjects(IMFileTypeIdentifierForName(@"https://host/uploads/id__Quarterly%20Report.XLSX?token=1"), @"excel");
    XCTAssertEqualObjects(IMFileTypeIdentifierForName(@"mystery.custom-format"), @"unknown");
    XCTAssertEqualObjects(IMFileTypeIdentifierForName(nil), @"unknown");
}

- (void)testEveryMappedKindHasRenderableAsset {
    for (NSString *name in @[@"a.pdf", @"a.docx", @"a.xlsx", @"a.pptx", @"a.csv", @"a.pages",
                              @"a.numbers", @"a.key", @"a.txt", @"a.md", @"a.xml", @"a.json",
                              @"a.png", @"a.mp4", @"a.mp3", @"a.zip", @"a.swift", @"a.sqlite",
                              @"a.ttf", @"a.epub", @"a.dmg", @"a.unknown"]) {
        UIImage *icon = IMFileTypeIconForName(name, 32);
        XCTAssertNotNil(icon, @"%@", name);
        XCTAssertEqualWithAccuracy(icon.size.width, 32, 0.01, @"%@", name);
        XCTAssertEqualWithAccuracy(icon.size.height, 32, 0.01, @"%@", name);
    }
}

@end
