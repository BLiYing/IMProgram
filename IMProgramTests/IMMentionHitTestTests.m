//  IMMentionHitTestTests.m
//  可点名字的 TextKit 反查命中（IMBubbleCell.mentionUIDInLabel:atPoint:range:）。
//
//  钉的是 2026-09-05 用户实测的那条：「群里邀请多名成员后，**最后一个**成员点不动」。
//  根因不在成员列表，在系统消息胶囊——那是个**居中**的 UILabel，而反查把富文本交给 TextKit 时
//  没把 textAlignment 一起带过去，TextKit 于是按左对齐排版。满行时两者恰好重合（居中==左对齐），
//  只有**没排满的那一行**被居中挪走；而"一串名字 + 加入群聊"里，最后一行正是唯一的短行。
//
//  app-hosted 测试：命中判定要求 label 已在 window 上（见被测方法的早退条件）。

#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>

#import "../IMProgram/Modules/Chat/Cells/IMBubbleCell.h"

@interface IMMentionHitTestTests : XCTestCase
@end

@implementation IMMentionHitTestTests {
    UIWindow *_window;
}

- (void)setUp {
    [super setUp];
    _window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 400, 200)];
    _window.hidden = NO;
}

- (void)tearDown {
    _window.hidden = YES;
    _window = nil;
    [super tearDown];
}

/// 造一个宽 400 的 label，内容是「A邀请B」，其中 B 挂 uid。
/// 文本远窄于 400 → 居中后整体右移一大截，正好放大对齐错位的影响。
- (UILabel *)labelWithAlignment:(NSTextAlignment)alignment uidRange:(NSRange *)outRange {
    UIFont *font = [UIFont systemFontOfSize:12];
    NSDictionary *plain = @{ NSFontAttributeName: font };
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:@"甲 邀请 " attributes:plain];
    NSUInteger start = as.length;
    NSMutableDictionary *named = [plain mutableCopy];
    named[IMMentionUIDAttributeName] = @"9876543210";
    [as appendAttributedString:[[NSAttributedString alloc] initWithString:@"乙" attributes:named]];
    if (outRange) { *outRange = NSMakeRange(start, 1); }
    [as appendAttributedString:[[NSAttributedString alloc] initWithString:@" 加入群聊" attributes:plain]];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 400, 20)];
    label.numberOfLines = 0;
    label.textAlignment = alignment;
    label.attributedText = as;
    [_window addSubview:label];
    [label layoutIfNeeded];
    return label;
}

/// 造一个含**两个**可点名字的居中 label（「甲 邀请 乙 和 丙 加入群聊」），供"连点两个名字"用例用。
- (UILabel *)labelWithTwoNamesFirstRange:(NSRange *)outFirst secondRange:(NSRange *)outSecond {
    UIFont *font = [UIFont systemFontOfSize:12];
    NSDictionary *plain = @{ NSFontAttributeName: font };
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:@"甲 邀请 " attributes:plain];
    NSMutableDictionary *n1 = [plain mutableCopy]; n1[IMMentionUIDAttributeName] = @"1111111111";
    NSUInteger s1 = as.length;
    [as appendAttributedString:[[NSAttributedString alloc] initWithString:@"乙" attributes:n1]];
    if (outFirst) { *outFirst = NSMakeRange(s1, 1); }
    [as appendAttributedString:[[NSAttributedString alloc] initWithString:@" 和 " attributes:plain]];
    NSMutableDictionary *n2 = [plain mutableCopy]; n2[IMMentionUIDAttributeName] = @"2222222222";
    NSUInteger s2 = as.length;
    [as appendAttributedString:[[NSAttributedString alloc] initWithString:@"丙" attributes:n2]];
    if (outSecond) { *outSecond = NSMakeRange(s2, 1); }
    [as appendAttributedString:[[NSAttributedString alloc] initWithString:@" 加入群聊" attributes:plain]];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 400, 20)];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.attributedText = as;
    [_window addSubview:label];
    [label layoutIfNeeded];
    return label;
}

/// 名字在 label 里的**渲染**中心（按居中偏移算），即用户手指真正会点的位置。
- (CGPoint)renderedCenterOfRange:(NSRange)range inLabel:(UILabel *)label {
    NSAttributedString *as = label.attributedText;
    CGFloat totalW = [as boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)
                                      options:NSStringDrawingUsesLineFragmentOrigin context:nil].size.width;
    CGFloat leftW = [[as attributedSubstringFromRange:NSMakeRange(0, range.location)]
                        boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)
                                     options:NSStringDrawingUsesLineFragmentOrigin context:nil].size.width;
    CGFloat nameW = [[as attributedSubstringFromRange:range]
                        boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)
                                     options:NSStringDrawingUsesLineFragmentOrigin context:nil].size.width;
    CGFloat originX = label.textAlignment == NSTextAlignmentCenter
        ? (label.bounds.size.width - totalW) / 2.0 : 0;
    return CGPointMake(originX + leftW + nameW / 2.0, label.bounds.size.height / 2.0);
}

/// **本次修复守的这一条**：居中 label 上，点名字的渲染位置要命中。
- (void)testCenteredLabelHitsNameAtRenderedPosition {
    NSRange nameRange = NSMakeRange(NSNotFound, 0);
    UILabel *label = [self labelWithAlignment:NSTextAlignmentCenter uidRange:&nameRange];
    CGPoint p = [self renderedCenterOfRange:nameRange inLabel:label];

    NSRange hit = NSMakeRange(NSNotFound, 0);
    NSString *uid = [IMBubbleCell mentionUIDInLabel:label atPoint:p range:&hit];
    XCTAssertEqualObjects(uid, @"9876543210", @"居中胶囊里点名字应命中——修复前 TextKit 按左对齐排，这里必空");
    XCTAssertEqual(hit.location, nameRange.location, @"回传的范围要是整个名字 token（点击高亮要用它）");
    XCTAssertEqual(hit.length, nameRange.length);
}

/// 反路：点在**左对齐才会出现名字**的那个位置（居中渲染下那里是空白），必须不命中。
/// 没有这条，上面那条在"整串都判成同一个 uid"的错误实现下也会绿。
- (void)testCenteredLabelDoesNotHitWhereTextIsNotRendered {
    NSRange nameRange = NSMakeRange(NSNotFound, 0);
    UILabel *label = [self labelWithAlignment:NSTextAlignmentCenter uidRange:&nameRange];
    CGPoint rendered = [self renderedCenterOfRange:nameRange inLabel:label];
    NSAttributedString *as = label.attributedText;
    CGFloat totalW = [as boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)
                                      options:NSStringDrawingUsesLineFragmentOrigin context:nil].size.width;
    CGFloat shift = (label.bounds.size.width - totalW) / 2.0;
    XCTAssertGreaterThan(shift, 40, @"用例前提：居中偏移要足够大，否则两点区分不开");
    CGPoint leftAligned = CGPointMake(rendered.x - shift, rendered.y); // 修复前会去这里找名字
    XCTAssertNil([IMBubbleCell mentionUIDInLabel:label atPoint:leftAligned range:NULL],
                 @"居中渲染下这里是左侧空白，不该命中任何名字");
}

/// 左对齐 label（气泡正文/图说 caption）行为不变——修复只补对齐，不该动它们。
- (void)testLeftAlignedLabelUnchanged {
    NSRange nameRange = NSMakeRange(NSNotFound, 0);
    UILabel *label = [self labelWithAlignment:NSTextAlignmentLeft uidRange:&nameRange];
    CGPoint p = [self renderedCenterOfRange:nameRange inLabel:label];
    XCTAssertEqualObjects([IMBubbleCell mentionUIDInLabel:label atPoint:p range:NULL], @"9876543210");
}

/// 点击回执：高亮加得上、约 0.22s 后自动还原（不留一块永久灰底）。
- (void)testFlashHighlightRestoresOriginalString {
    NSRange nameRange = NSMakeRange(NSNotFound, 0);
    UILabel *label = [self labelWithAlignment:NSTextAlignmentCenter uidRange:&nameRange];
    NSAttributedString *before = [label.attributedText copy];

    [IMBubbleCell flashMentionHighlightInLabel:label range:nameRange];
    XCTAssertNotNil([label.attributedText attribute:NSBackgroundColorAttributeName
                                            atIndex:nameRange.location effectiveRange:NULL],
                    @"点中后应立刻有背景高亮");

    XCTestExpectation *restored = [self expectationWithDescription:@"高亮自动还原"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        XCTAssertTrue([label.attributedText isEqualToAttributedString:before], @"应还原成原串");
        [restored fulfill];
    });
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

/// 复位窗口（0.22s）内先后点**两个不同的名字**：第二次不能把「已带第一次灰底」的串当成原串
/// 记下来，否则它的定时器会把第一次的灰底复位回去并**永久留在那儿**——用户看到一个洗不掉的
/// 灰底名字，直到该 cell 被复用。
///
/// ⚠️ 用两个**不同**的 range 才复现得出来：连点同一个名字时第二次算出的 hot 与第一次逐字节相等，
/// 第一个定时器就把它整个复位掉了，问题会自愈（第一版用例正是这么写的，改坏代码也照样绿）。
- (void)testFlashingTwoDifferentNamesLeavesNoStuckHighlight {
    NSRange firstRange = NSMakeRange(NSNotFound, 0);
    UILabel *label = [self labelWithTwoNamesFirstRange:&firstRange secondRange:NULL];
    NSRange secondRange = NSMakeRange(NSNotFound, 0);
    (void)[self labelWithTwoNamesFirstRange:NULL secondRange:&secondRange]; // 只为取第二个名字的 range
    NSAttributedString *pristine = [label.attributedText copy];

    [IMBubbleCell flashMentionHighlightInLabel:label range:firstRange];
    [IMBubbleCell flashMentionHighlightInLabel:label range:secondRange]; // 复位窗口内点了另一个名字

    XCTestExpectation *restored = [self expectationWithDescription:@"两次点击后仍还原成干净的原串"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        XCTAssertTrue([label.attributedText isEqualToAttributedString:pristine],
                      @"先后点两个名字后不能残留灰底：%@", label.attributedText);
        [restored fulfill];
    });
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

/// 越界/无效范围不该崩，也不该改内容（cell 复用时 range 可能已对不上新串）。
- (void)testFlashHighlightIgnoresInvalidRange {
    UILabel *label = [self labelWithAlignment:NSTextAlignmentCenter uidRange:NULL];
    NSAttributedString *before = [label.attributedText copy];
    [IMBubbleCell flashMentionHighlightInLabel:label range:NSMakeRange(NSNotFound, 0)];
    [IMBubbleCell flashMentionHighlightInLabel:label range:NSMakeRange(0, label.attributedText.length + 10)];
    XCTAssertTrue([label.attributedText isEqualToAttributedString:before]);
}

@end
