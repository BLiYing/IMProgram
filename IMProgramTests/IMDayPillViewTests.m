//  IMDayPillViewTests.m
//  聊天流日期分隔胶囊：新群首条是系统消息时 iOS 曾整天不画日期（系统/撤回/群通话/图片/相册/链接/名片/记录卡行
//  都提前 return 没走 dayHeader）。这里钉住共用胶囊视图与 IMSystemCell 的显隐/复位。

#import <XCTest/XCTest.h>

#import "IMDayPillView.h"
#import "IMSystemCell.h"
#import "IMMessageCell.h"
#import "IMImageCell.h"
#import "IMAlbumCell.h"
#import "IMLinkCardCell.h"
#import "IMContactCardCell.h"
#import "IMChatRecordCell.h"
#import "IMCallRecordCell.h"

@interface IMDayPillViewTests : XCTestCase
@end

@implementation IMDayPillViewTests

static CGFloat FittingHeight(UIView *v) {
    return [v systemLayoutSizeFittingSize:CGSizeMake(390, UILayoutFittingCompressedSize.height)
             withHorizontalFittingPriority:UILayoutPriorityRequired
                   verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
}

- (void)test_无文案收起为零高并隐藏 {
    IMDayPillView *v = [IMDayPillView new];
    [v applyText:nil];
    XCTAssertTrue(v.hidden);
    XCTAssertEqualWithAccuracy(FittingHeight(v), 0, 0.5);
    [v applyText:@""];
    XCTAssertTrue(v.hidden);
}

- (void)test_有文案显示且高度是上边距加胶囊高 {
    IMDayPillView *v = [IMDayPillView new];
    [v applyText:@"今天"];
    XCTAssertFalse(v.hidden);
    XCTAssertEqualWithAccuracy(FittingHeight(v), 32, 0.5); // 8 + 24
}

- (void)test_系统行加日期后变高_复用后复位 {
    IMSystemCell *c = [[IMSystemCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"system"];
    [c configureWithText:@"我 创建了群聊"];
    CGFloat plain = FittingHeight(c.contentView);
    [c applyDayHeader:@"今天"];
    XCTAssertGreaterThan(FittingHeight(c.contentView), plain + 28, @"日期胶囊应让行多出约 32pt");
    [c prepareForReuse];
    [c configureWithText:@"我 创建了群聊"];
    XCTAssertEqualWithAccuracy(FittingHeight(c.contentView), plain, 0.5, @"复用后不得残留上一行的日期");
}

/// 基类 IMMessageCell 带的日期胶囊：六个子类都要能显示、复用后复位（它们的 prepareForReuse 必须调 super）。
- (void)test_消息cell子类都能显示日期且复用后复位 {
    NSArray<Class> *classes = @[IMImageCell.class, IMAlbumCell.class, IMLinkCardCell.class,
                                IMContactCardCell.class, IMChatRecordCell.class, IMCallRecordCell.class];
    for (Class cls in classes) {
        IMMessageCell *c = [[cls alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"x"];
        UIView *pill = [c valueForKey:@"_dayPill"];
        XCTAssertTrue(pill.hidden, @"%@ 初始不显示日期", cls);
        [c applyDayHeader:@"今天"];
        XCTAssertFalse(pill.hidden, @"%@ 应能显示日期胶囊", cls);
        [c prepareForReuse];
        XCTAssertTrue(pill.hidden, @"%@ 复用后日期必须复位（prepareForReuse 要调 super）", cls);
    }
}

@end
