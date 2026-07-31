#import <XCTest/XCTest.h>
#import "IMAppearance.h"
#import "IMTheme.h"

@interface IMAppearanceTests : XCTestCase
@property (nonatomic, assign) IMAppearanceMode savedMode;
@property (nonatomic, copy) NSString *savedTheme;
@property (nonatomic, copy) NSString *savedWallpaper;
@property (nonatomic, assign) CGFloat savedFontSize;
@property (nonatomic, assign) CGFloat savedRadius;
@property (nonatomic, assign) BOOL savedAnimations;
@end

@implementation IMAppearanceTests

- (void)setUp {
    [super setUp];
    IMAppearance *appearance = IMAppearance.shared;
    self.savedMode = appearance.mode;
    self.savedTheme = appearance.themeID;
    self.savedWallpaper = appearance.wallpaperID;
    self.savedFontSize = appearance.chatFontSize;
    self.savedRadius = appearance.bubbleRadius;
    self.savedAnimations = appearance.animationsEnabled;
}

- (void)tearDown {
    IMAppearance *appearance = IMAppearance.shared;
    appearance.mode = self.savedMode;
    appearance.themeID = self.savedTheme;
    appearance.wallpaperID = self.savedWallpaper;
    appearance.chatFontSize = self.savedFontSize;
    appearance.bubbleRadius = self.savedRadius;
    appearance.animationsEnabled = self.savedAnimations;
    [super tearDown];
}

- (void)testNumericPreferencesAreClamped {
    IMAppearance.shared.chatFontSize = 100;
    IMAppearance.shared.bubbleRadius = -10;

    XCTAssertEqualWithAccuracy(IMAppearance.shared.chatFontSize, 22, 0.001);
    XCTAssertEqualWithAccuracy(IMAppearance.shared.bubbleRadius, 6, 0.001);
    XCTAssertEqualWithAccuracy(IMTheme.chatFontSize, 22, 0.001);
    XCTAssertEqualWithAccuracy(IMTheme.radiusBubble, 6, 0.001);
}

- (void)testUnknownIdentifiersFallBackToDefaults {
    IMAppearance.shared.mode = (IMAppearanceMode)99;
    IMAppearance.shared.themeID = @"unknown";
    IMAppearance.shared.wallpaperID = @"unknown";

    XCTAssertEqual(IMAppearance.shared.mode, IMAppearanceModeDark);
    XCTAssertEqualObjects(IMAppearance.shared.themeID, @"classic");
    XCTAssertEqualObjects(IMAppearance.shared.wallpaperID, @"doodle");
}

- (void)testEveryBuiltInThemeProvidesPreviewPalette {
    for (NSString *themeID in @[@"classic", @"ocean", @"violet", @"midnight"]) {
        XCTAssertNotNil([IMAppearance.shared accentColorForThemeID:themeID]);
        XCTAssertNotNil([IMAppearance.shared bubbleMeColorForThemeID:themeID]);
        XCTAssertEqual([IMAppearance.shared wallpaperColorsForThemeID:themeID].count, 2);
    }
    NSArray<UIColor *> *fallback = [IMAppearance.shared wallpaperColorsForThemeID:@"unknown"];
    NSArray<UIColor *> *classic = [IMAppearance.shared wallpaperColorsForThemeID:@"classic"];
    UITraitCollection *light = [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleLight];
    XCTAssertEqualObjects([fallback.firstObject resolvedColorWithTraitCollection:light],
                          [classic.firstObject resolvedColorWithTraitCollection:light]);
}

@end
