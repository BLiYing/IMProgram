//  IMContactCardTests.m
//  个人名片（content_type=contact）纯逻辑单测：content 解析 / 构造 / 预览，
//  以及详情页页签与收藏分类的归类口径。app-hosted 测试，头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMContactCard.h"
#import "../IMProgram/Common/IMMediaUtil.h"
#import "../IMProgram/Models/IMMessageModel.h"
#import "../IMProgram/Models/IMPinnedMessage.h"
#import "../IMProgram/Modules/Detail/IMChatDetailTabs.h"
#import "../IMProgram/Modules/Me/IMFavoritesCategories.h"

@interface IMContactCardTests : XCTestCase
@end

@implementation IMContactCardTests

#pragma mark - 解析

- (void)testParseFull {
    IMContactCard *c = IMContactCardParse(@"{\"u\":\"1002\",\"n\":\"小明\",\"a\":\"/avatars/ab12.jpg\"}");
    XCTAssertNotNil(c);
    XCTAssertEqualObjects(c.userID, @"1002");
    XCTAssertEqualObjects(c.nickname, @"小明");
    XCTAssertEqualObjects(c.avatarURL, @"/avatars/ab12.jpg");
}

- (void)testParseOnlyUID {
    IMContactCard *c = IMContactCardParse(@"{\"u\":\"1002\"}");
    XCTAssertNotNil(c);
    XCTAssertNil(c.nickname);
    XCTAssertNil(c.avatarURL);
}

/// 缺 u / 非法 JSON / 非对象 / 空白 u 一律 nil —— 调用方据此把脏名片挡在列表之外。
- (void)testParseRejects {
    XCTAssertNil(IMContactCardParse(@"{\"n\":\"小明\"}"));
    XCTAssertNil(IMContactCardParse(@"{\"u\":\"   \"}"));
    XCTAssertNil(IMContactCardParse(@"not json"));
    XCTAssertNil(IMContactCardParse(@"[\"1002\"]"));
    XCTAssertNil(IMContactCardParse(@""));
    XCTAssertNil(IMContactCardParse(nil));
    XCTAssertNil(IMContactCardParse(@"{\"u\":123}"));   // u 非字符串
}

- (void)testParseTrimsWhitespace {
    IMContactCard *c = IMContactCardParse(@"{\"u\":\" 1002 \",\"n\":\"  \"}");
    XCTAssertEqualObjects(c.userID, @"1002");
    XCTAssertNil(c.nickname); // 全空白归一化成"无"
}

#pragma mark - 构造

- (void)testBuildRoundTrip {
    NSString *json = IMContactCardBuild(@"1002", nil, @"小明", @"/a.jpg");
    IMContactCard *c = IMContactCardParse(json);
    XCTAssertEqualObjects(c.userID, @"1002");
    XCTAssertEqualObjects(c.nickname, @"小明");
    XCTAssertEqualObjects(c.avatarURL, @"/a.jpg");
}

/// 空昵称/头像不写进 JSON（服务端 omitempty 同款），避免下发一堆空键。
- (void)testBuildOmitsEmpty {
    NSString *json = IMContactCardBuild(@"1002", nil, @"", nil);
    XCTAssertFalse([json containsString:@"\"n\""]);
    XCTAssertFalse([json containsString:@"\"a\""]);
    XCTAssertNil(IMContactCardBuild(@"", nil, @"小明", nil));
    XCTAssertNil(IMContactCardBuild(@"   ", nil, nil, nil));
}

/// **本设计最容易写错的一行**：快照里的 n 必须是真实昵称，绝不能是备注（displayName）。
/// 这里锁的是调用契约——build 拿到什么就写什么，故调用方传 nickname 时必须显式取 card.nickname。
- (void)testBuildStoresWhateverNicknameGiven {
    NSString *json = IMContactCardBuild(@"1002", nil, @"王建国", nil);   // 真实昵称
    XCTAssertEqualObjects(IMContactCardParse(json).nickname, @"王建国");
    XCTAssertFalse([json containsString:@"老王"]);                  // 备注不该出现在快照里
}

#pragma mark - 预览

- (void)testPreview {
    XCTAssertEqualObjects(IMContactCardPreview(@"{\"u\":\"1002\",\"n\":\"小明\"}"), @"[个人名片] 小明");
    // 无昵称 → 退 @username；**绝不回落 userID**（那是 10 位随机数字内部 ID，
    // 这条预览会出现在会话列表/引用条上，与服务端 contactReplySnapshot 同口径）。
    XCTAssertEqualObjects(IMContactCardPreview(@"{\"u\":\"4820571639\",\"un\":\"xiaoming\"}"), @"[个人名片] @xiaoming");
    XCTAssertEqualObjects(IMContactCardPreview(@"{\"u\":\"4820571639\"}"), @"[个人名片]");  // 两者皆无 → 不带任何 ID
    XCTAssertEqualObjects(IMContactCardPreview(@"{\"u\":\"截断"), @"[个人名片]");            // 非法 JSON 不崩
    XCTAssertEqualObjects(IMContactCardPreview(nil), @"[个人名片]");
}

/// 引用快照：本端生成走 IMReplySnippet；服务端下发的裸 [contact] 由本地化兜底（老服务端窗口）。
- (void)testReplySnippetAndLocalize {
    IMMessageModel *m = [IMMessageModel new];
    m.contentType = @"contact";
    m.content = @"{\"u\":\"1002\",\"n\":\"小明\"}";
    XCTAssertEqualObjects(IMReplySnippet(m), @"[个人名片] 小明");
    XCTAssertEqualObjects(IMLocalizeReplySnippet(@"[contact]"), @"[个人名片]");
    // 服务端预本地化的形态原样透出，不再二次加工。
    XCTAssertEqualObjects(IMLocalizeReplySnippet(@"[个人名片] 小明"), @"[个人名片] 小明");
}

- (void)testPinnedPreview {
    IMPinnedMessage *p = [IMPinnedMessage new];
    p.contentType = @"contact";
    p.content = @"{\"u\":\"1002\",\"n\":\"小明\"}";
    XCTAssertEqualObjects(p.previewText, @"[个人名片] 小明");
}

/// 合并转发卡片里的名片条目预览。
- (void)testRecordItemPreview {
    XCTAssertEqualObjects(IMRecordItemPreview(@{@"ct": @"contact", @"c": @"{\"u\":\"1002\",\"n\":\"小明\"}"}),
                          @"[个人名片] 小明");
}

#pragma mark - 详情页「名片」页签

static IMMessageModel *contactMsg(NSString *content) {
    IMMessageModel *m = [IMMessageModel new];
    m.contentType = @"contact";
    m.content = content;
    m.convSeq = 1;                     // 未确认消息不计入任何页签（2026-08-25 规则）
    m.status = IMMessageStatusSent;
    return m;
}

- (void)testContactsTabAppearsLastAfterLinks {
    IMMessageModel *link = [IMMessageModel new];
    link.contentType = @"text"; link.content = @"看看 https://example.com"; link.convSeq = 1; link.status = IMMessageStatusSent;
    NSArray<IMChatDetailTab *> *tabs =
        [IMChatDetailTabs tabsForMessages:@[contactMsg(@"{\"u\":\"1002\"}"), link] isGroup:NO];
    XCTAssertEqual(tabs.count, 2u);
    XCTAssertEqual(tabs[0].kind, IMDetailTabKindLinks);   // 名片置末，不打乱既有签的顺序
    XCTAssertEqual(tabs[1].kind, IMDetailTabKindContacts);
    XCTAssertEqualObjects(tabs[1].title, @"名片");
}

- (void)testRecalledContactDoesNotProduceTab {
    IMMessageModel *m = contactMsg(@"{\"u\":\"1002\"}");
    m.recalledAt = 1;
    XCTAssertEqual([IMChatDetailTabs tabsForMessages:@[m] isGroup:NO].count, 0u);
}

/// 脏名片（解析不出）不计入页签——否则页签里会多出一行点不动的空白。
- (void)testDirtyContactNotCounted {
    XCTAssertFalse([IMChatDetailTabs message:contactMsg(@"{\"n\":\"小明\"}") matchesKind:IMDetailTabKindContacts]);
    XCTAssertFalse([IMChatDetailTabs message:contactMsg(@"garbage") matchesKind:IMDetailTabKindContacts]);
    XCTAssertEqual([IMChatDetailTabs tabsForMessages:@[contactMsg(@"garbage")] isGroup:NO].count, 0u);
    XCTAssertTrue([IMChatDetailTabs message:contactMsg(@"{\"u\":\"1002\"}") matchesKind:IMDetailTabKindContacts]);
}

/// 名片不该被别的页签抢走（它的 content 是 JSON，链接签按"含 URL"匹配，别误伤）。
- (void)testContactNotClassifiedAsLinkOrFile {
    IMMessageModel *m = contactMsg(@"{\"u\":\"1002\",\"a\":\"https://cdn.example.com/a.png\"}");
    XCTAssertFalse([IMChatDetailTabs message:m matchesKind:IMDetailTabKindLinks]);
    XCTAssertFalse([IMChatDetailTabs message:m matchesKind:IMDetailTabKindFiles]);
    XCTAssertFalse([IMChatDetailTabs message:m matchesKind:IMDetailTabKindMedia]);
}

#pragma mark - 收藏页「名片」分类

- (void)testFavoriteContactCategory {
    NSDictionary *fav = @{ @"content_type": @"contact", @"content": @"{\"u\":\"1002\",\"n\":\"小明\"}" };
    XCTAssertTrue([IMFavoritesCategories favorite:fav matchesCategory:IMFavoriteCategoryContact]);
    XCTAssertTrue([IMFavoritesCategories favorite:fav matchesCategory:IMFavoriteCategoryAll]);
    XCTAssertFalse([IMFavoritesCategories favorite:fav matchesCategory:IMFavoriteCategoryText]);
    XCTAssertFalse([IMFavoritesCategories favorite:fav matchesCategory:IMFavoriteCategoryLinks]);
    XCTAssertFalse([IMFavoritesCategories favorite:fav matchesCategory:IMFavoriteCategoryRecord]);
}

- (void)testFavoriteContactCategoryIsLast {
    NSArray<IMFavoriteCategoryTab *> *cats = [IMFavoritesCategories categoriesForFavorites:@[
        @{ @"content_type": @"contact", @"content": @"{\"u\":\"1002\"}" },
        @{ @"content_type": @"text", @"content": @"hello" },
    ] includeAll:NO];
    XCTAssertEqual(cats.count, 2u);
    XCTAssertEqual(cats[0].kind, IMFavoriteCategoryText);
    XCTAssertEqual(cats.lastObject.kind, IMFavoriteCategoryContact);
    XCTAssertEqualObjects(cats.lastObject.title, @"名片");
}

/// 脏名片收藏不成一类（与详情页页签同口径）。
- (void)testDirtyFavoriteContactNotCounted {
    NSDictionary *bad = @{ @"content_type": @"contact", @"content": @"{\"n\":\"小明\"}" };
    XCTAssertFalse([IMFavoritesCategories favorite:bad matchesCategory:IMFavoriteCategoryContact]);
}

@end

@interface IMContactCardUsernameTests : XCTestCase
@end

@implementation IMContactCardUsernameTests

/// un（username 快照）：构造带上、解析读出、老消息缺席时为 nil（副标题留空，向后兼容）。
- (void)testUsernameRoundTripAndBackwardCompat {
    NSString *json = IMContactCardBuild(@"4820571639", @"xiaoming", @"小明", @"/a.jpg");
    XCTAssertNotNil(json);
    IMContactCard *c = IMContactCardParse(json);
    XCTAssertEqualObjects(c.userID, @"4820571639");
    XCTAssertEqualObjects(c.username, @"xiaoming");
    XCTAssertEqualObjects(c.nickname, @"小明");

    // 老消息（没有 un）→ username 为 nil，其余照常解析，不报错不降级整张卡。
    IMContactCard *old = IMContactCardParse(@"{\"u\":\"4820571639\",\"n\":\"小明\"}");
    XCTAssertNotNil(old);
    XCTAssertNil(old.username);
    XCTAssertEqualObjects(old.nickname, @"小明");

    // 空 username 不写进 JSON（omitempty 语义），避免留空键。
    NSString *noUn = IMContactCardBuild(@"4820571639", @"", @"小明", nil);
    XCTAssertFalse([noUn containsString:@"\"un\""]);
}

@end
