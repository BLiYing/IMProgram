//  IMRecordParseTests.m
//  两处「服务端字典 → 模型」的脏数据安全解析：通话记录（IMRtcCall）与收藏项的转发媒体属性（IMFavoritesViewController）。
//
//  错法：脏字段让记录页错位/崩溃；语音收藏 duration 为 0 → 发出去**整条被服务端拒收**（100001）；
//  媒体缩略/封面/尺寸丢了 → 转发出去的图在对端只剩一块空磨砂。所以按「会怎么错」钉。

#import <XCTest/XCTest.h>

#import "IMCallHistoryRecord.h"
#import "IMFavoritesViewController.h"
#import "IMMediaAttributes.h"
#import "IMRtcCall.h"

@interface IMRtcCall (RecordParseHooks)
+ (IMCallHistoryRecord *)historyRecordFromDictionary:(NSDictionary *)d;
@end

@interface IMRecordParseTests : XCTestCase
@end

@implementation IMRecordParseTests

/// 宏参数里字典字面量的逗号会被预处理器拆开：包一层函数（圆括号保护逗号）。
static IMMediaAttributes *Fav(NSDictionary *f) { return [IMFavoritesViewController mediaAttributesFromFavorite:f]; }
static IMCallHistoryRecord *Rec(NSDictionary *d) { return [IMRtcCall historyRecordFromDictionary:d]; }

#pragma mark - 通话记录

- (void)test_通话记录_完整字段 {
    IMCallHistoryRecord *r = [IMRtcCall historyRecordFromDictionary:@{
        @"call_id": @"c1", @"room_id": @"r1", @"caller": @"u9", @"media_type": @"video", @"is_group": @YES,
        @"reason": @"hangup", @"ended_by": @"u8", @"duration_sec": @75, @"started_at_ms": @1000, @"connected_at_ms": @2000,
        @"ended_at_ms": @3000, @"user_data": @"ud", @"chat_group_id": @"g7",
        @"members": @[ @{ @"uid": @"u1", @"state": @"x" }, @{ @"uid": @"u2" } ] }];
    XCTAssertEqualObjects(r.callID, @"c1");
    XCTAssertEqualObjects(r.caller, @"u9");
    XCTAssertTrue(r.video);
    XCTAssertTrue(r.group);
    XCTAssertEqualObjects(r.reason, @"hangup");
    XCTAssertEqual(r.durationSec, 75);
    XCTAssertEqual(r.startedAtMs, 1000);
    XCTAssertEqual(r.connectedAtMs, 2000);
    XCTAssertEqual(r.endedAtMs, 3000);
    XCTAssertEqualObjects(r.chatGroupID, @"g7");
    XCTAssertEqualObjects(r.memberUIDs, (@[@"u1", @"u2"]));
}

/// 全空字典：全部取默认值，不抛。语音通话（media_type 非 video）、非群。
- (void)test_通话记录_空字典取默认值 {
    IMCallHistoryRecord *r = [IMRtcCall historyRecordFromDictionary:@{}];
    XCTAssertEqualObjects(r.callID, @"");
    XCTAssertFalse(r.video);
    XCTAssertFalse(r.group);
    XCTAssertEqual(r.durationSec, 0);
    XCTAssertEqual(r.memberUIDs.count, 0u);
}

/// 脏类型：字符串字段给了数字 / 数字字段给了垃圾 / members 里夹着非字典与空 uid。
- (void)test_通话记录_脏类型安全 {
    IMCallHistoryRecord *r = [IMRtcCall historyRecordFromDictionary:@{
        @"call_id": @5, @"caller": NSNull.null, @"media_type": @"audio", @"is_group": @"x",
        @"duration_sec": [NSNull null], @"started_at_ms": @"123",
        @"members": @[ @"junk", @{ @"uid": @"" }, @{ @"uid": @7 }, @{ @"uid": @"ok" }, NSNull.null ] }];
    XCTAssertEqualObjects(r.callID, @"");
    XCTAssertEqualObjects(r.caller, @"");
    XCTAssertFalse(r.video, @"media_type 只有等于 video 才算视频");
    XCTAssertEqual(r.durationSec, 0);
    XCTAssertEqual(r.startedAtMs, 123, @"字符串数字可取");
    XCTAssertEqualObjects(r.memberUIDs, @[@"ok"]);
    // members 不是数组：空列表，不崩。
    XCTAssertEqual(Rec(@{ @"members": @"x" }).memberUIDs.count, 0u);
}

#pragma mark - 收藏项 → 转发媒体属性

/// 纯文本且无图说：没有任何媒体元数据可带，返回 nil（调用方据此走纯文本发送）。
- (void)test_收藏_纯文本无图说返回nil {
    XCTAssertNil(Fav(@{ @"content_type": @"text" }));
    XCTAssertNil(Fav(@{ @"content_type": @"file", @"file_size": @10 }));
    XCTAssertNil(Fav(@{ @"caption": @"" }), @"空图说算没有");
}

/// 缺 content_type 按 text；非文本却带图说（文件+图说）：只带 caption。
- (void)test_收藏_文件带图说只带caption {
    IMMediaAttributes *a = Fav(@{ @"content_type": @"file", @"caption": @"说明" });
    XCTAssertEqualObjects(a.caption, @"说明");
    XCTAssertEqual(a.fileSize, 0);
    XCTAssertEqual(a.pixelWidth, 0);
}

/// 图片：缩略/封面/时长/像素尺寸/字节数全带上（丢了对端只剩一块空磨砂）。
- (void)test_收藏_图片带全部元数据 {
    IMMediaAttributes *a = Fav(@{
        @"content_type": @"image", @"thumb": @"data:image/jpeg;base64,AA==", @"poster": @"/p.jpg", @"duration": @0,
        @"media_w": @800, @"media_h": @600, @"file_size": @12345, @"caption": @"风景" });
    XCTAssertEqualObjects(a.thumb, @"data:image/jpeg;base64,AA==");
    XCTAssertEqualObjects(a.poster, @"/p.jpg");
    XCTAssertEqual(a.pixelWidth, 800);
    XCTAssertEqual(a.pixelHeight, 600);
    XCTAssertEqual(a.fileSize, 12345);
    XCTAssertEqualObjects(a.caption, @"风景");
}

/// 视频：时长（毫秒）与封面必带。
- (void)test_收藏_视频带时长与封面 {
    IMMediaAttributes *a = Fav(@{
        @"content_type": @"video", @"duration": @8500, @"poster": @"/v.jpg", @"media_w": @1920, @"media_h": @1080 });
    XCTAssertEqual(a.durationMillis, 8500);
    XCTAssertEqualObjects(a.poster, @"/v.jpg");
}

/// 语音：duration / waveform / file_size 带上；`audio` 是 `voice` 的别名。空波形按「没有」（收端退化条纹）。
- (void)test_收藏_语音与audio别名 {
    for (NSString *ct in @[@"voice", @"audio"]) {
        IMMediaAttributes *a = Fav(@{
            @"content_type": ct, @"duration": @3200, @"waveform": @"AAECAw==", @"file_size": @999 });
        XCTAssertEqual(a.durationMillis, 3200, @"%@", ct);
        XCTAssertEqualObjects(a.waveform, @"AAECAw==");
        XCTAssertEqual(a.fileSize, 999);
    }
    XCTAssertNil(Fav(@{ @"content_type": @"voice", @"duration": @1, @"waveform": @"" }).waveform);
}

/// 语音 duration 缺失得到 0：这是**会让整条被服务端拒发（100001）**的值——这里只钉「如实给 0」，由发送侧拦截；
/// 若哪天改成给默认值要先确认服务端口径。
- (void)test_收藏_语音缺duration为0 {
    IMMediaAttributes *a = Fav(@{ @"content_type": @"voice" });
    XCTAssertNotNil(a);
    XCTAssertEqual(a.durationMillis, 0);
}

/// 脏类型不崩：数字字段给了 NSNull、字符串字段给了数字。
- (void)test_收藏_脏类型安全 {
    IMMediaAttributes *a = Fav(@{
        @"content_type": @"image", @"thumb": @5, @"poster": NSNull.null, @"media_w": NSNull.null, @"file_size": @"77" });
    XCTAssertNil(a.thumb);
    XCTAssertNil(a.poster);
    XCTAssertEqual(a.pixelWidth, 0);
    XCTAssertEqual(a.fileSize, 77);
    XCTAssertNotNil(Fav(@{ @"content_type": @9, @"caption": @"x" }), @"content_type 不是字符串按 text，有图说仍返回");
}

@end
