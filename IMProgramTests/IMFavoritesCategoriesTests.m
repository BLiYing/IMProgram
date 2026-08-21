//  IMFavoritesCategoriesTests.m
//  收藏页分类推导单测：动态按 content_type 生成、「全部」恒首位且默认、Telegram 式过滤
//  （text 形如 URL 归「链接」，否则归「文本」）。归类口径与 IMChatDetailTabs 对齐。
//  app-hosted 测试，头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Modules/Me/IMFavoritesCategories.h"

@interface IMFavoritesCategoriesTests : XCTestCase
@end

@implementation IMFavoritesCategoriesTests

/// 造一条收藏字典。
static NSDictionary *fav(NSString *type, NSString *content) {
    return @{ @"content_type": type, @"content": content };
}

/// 取分类的 kind 数组，便于断言顺序。
static NSArray<NSNumber *> *kinds(NSArray<IMFavoriteCategoryTab *> *tabs) {
    NSMutableArray *k = [NSMutableArray array];
    for (IMFavoriteCategoryTab *t in tabs) { [k addObject:@(t.kind)]; }
    return k;
}

- (void)testAllAlwaysFirstAndDefault {
    // 空收藏也应只有「全部」。
    NSArray<IMFavoriteCategoryTab *> *tabs = [IMFavoritesCategories categoriesForFavorites:@[]];
    XCTAssertEqualObjects(kinds(tabs), @[ @(IMFavoriteCategoryAll) ]);
    XCTAssertEqualObjects(tabs.firstObject.title, @"全部");
}

- (void)testDynamicPresentOnlyInOrder {
    // 存在 媒体 + 文件 + 文本；无 链接/语音 → 不出现。顺序：全部→媒体→文件→文本。
    NSArray *favs = @[ fav(@"image", @"/uploads/a.jpg"),
                       fav(@"file", @"/uploads/b.pdf"),
                       fav(@"text", @"随手记一笔") ];
    NSArray<NSNumber *> *k = kinds([IMFavoritesCategories categoriesForFavorites:favs]);
    NSArray<NSNumber *> *want = @[ @(IMFavoriteCategoryAll), @(IMFavoriteCategoryMedia),
                                   @(IMFavoriteCategoryFiles), @(IMFavoriteCategoryText) ];
    XCTAssertEqualObjects(k, want);
}

- (void)testFullOrderMediaFilesLinksVoiceText {
    NSArray *favs = @[ fav(@"video", @"/uploads/v.mp4"),
                       fav(@"file", @"/uploads/b.pdf"),
                       fav(@"link", @"https://apple.com"),
                       fav(@"voice", @"/uploads/v.m4a"),
                       fav(@"text", @"纯文本") ];
    NSArray<NSNumber *> *k = kinds([IMFavoritesCategories categoriesForFavorites:favs]);
    NSArray<NSNumber *> *want = @[ @(IMFavoriteCategoryAll), @(IMFavoriteCategoryMedia), @(IMFavoriteCategoryFiles),
                                   @(IMFavoriteCategoryLinks), @(IMFavoriteCategoryVoice), @(IMFavoriteCategoryText) ];
    XCTAssertEqualObjects(k, want);
}

- (void)testUrlTextGoesToLinksNotText {
    // 形如 URL 的 text 归「链接」，不归「文本」。
    NSDictionary *urlText = fav(@"text", @"https://developer.apple.com/design/");
    XCTAssertTrue([IMFavoritesCategories favorite:urlText matchesCategory:IMFavoriteCategoryLinks]);
    XCTAssertFalse([IMFavoritesCategories favorite:urlText matchesCategory:IMFavoriteCategoryText]);

    // 仅 URL 文本时：出现「链接」而非「文本」。
    NSArray<NSNumber *> *k = kinds([IMFavoritesCategories categoriesForFavorites:@[ urlText ]]);
    XCTAssertEqualObjects(k, (@[ @(IMFavoriteCategoryAll), @(IMFavoriteCategoryLinks) ]));
}

- (void)testMatchesCategoryAllForNonEmpty {
    XCTAssertTrue([IMFavoritesCategories favorite:fav(@"text", @"x") matchesCategory:IMFavoriteCategoryAll]);
    // 空内容不计入任何类别（含「全部」）。
    XCTAssertFalse([IMFavoritesCategories favorite:fav(@"text", @"") matchesCategory:IMFavoriteCategoryAll]);
    XCTAssertFalse([IMFavoritesCategories favorite:fav(@"image", @"") matchesCategory:IMFavoriteCategoryMedia]);
}

- (void)testRecordCategoryAndNoAllVariant {
    // 聊天记录归「聊天记录」签、不归「文本」；B 方案 includeAll:NO 时无「全部」，顺序 …文本→聊天记录。
    NSDictionary *rec = fav(@"chat_record", @"{\"t\":\"设计组 的聊天记录\",\"items\":[]}");
    XCTAssertTrue([IMFavoritesCategories favorite:rec matchesCategory:IMFavoriteCategoryRecord]);
    XCTAssertFalse([IMFavoritesCategories favorite:rec matchesCategory:IMFavoriteCategoryText]);
    NSArray *favs = @[ fav(@"text", @"纯文本"), rec, fav(@"image", @"/a.jpg") ];
    NSArray<NSNumber *> *k = kinds([IMFavoritesCategories categoriesForFavorites:favs includeAll:NO]);
    XCTAssertEqualObjects(k, (@[ @(IMFavoriteCategoryMedia), @(IMFavoriteCategoryText), @(IMFavoriteCategoryRecord) ]));
    // 全空 + includeAll:NO → 空数组（调用方隐藏页签区）。
    XCTAssertEqualObjects([IMFavoritesCategories categoriesForFavorites:@[] includeAll:NO], @[]);
}

- (void)testVoiceMatchesAudioAndVoice {
    XCTAssertTrue([IMFavoritesCategories favorite:fav(@"audio", @"/a.m4a") matchesCategory:IMFavoriteCategoryVoice]);
    XCTAssertTrue([IMFavoritesCategories favorite:fav(@"voice", @"/a.m4a") matchesCategory:IMFavoriteCategoryVoice]);
}

@end
