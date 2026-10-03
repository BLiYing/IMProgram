//  IMBubbleTextMetaLayoutTests.m
//  文本气泡的时间在**正文下方**、右对齐（对齐 Android 文本气泡；此前是行内紧跟正文末尾的占位）。
//  app-hosted：要真跑 Auto Layout。

#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>

#import "../IMProgram/Modules/Chat/Cells/IMBubbleCell.h"
#import "../IMProgram/Models/IMMessageModel.h"
#import "../IMProgram/Common/IMTheme.h"

@interface IMBubbleTextMetaLayoutTests : XCTestCase
@end

@implementation IMBubbleTextMetaLayoutTests

static void IMCollectLabels(UIView *v, NSMutableArray<UILabel *> *out) {
    if ([v isKindOfClass:UILabel.class]) { [out addObject:(UILabel *)v]; }
    for (UIView *s in v.subviews) { IMCollectLabels(s, out); }
}

- (IMBubbleCell *)laidOutCellWithText:(NSString *)text mine:(BOOL)mine window:(UIWindow *)window {
    IMBubbleCell *cell = [[IMBubbleCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"t"];
    IMMessageModel *m = [IMMessageModel new];
    m.clientMsgID = @"c1"; m.convID = @"conv"; m.contentType = @"text"; m.content = text;
    m.timestamp = 1700000000000; m.convSeq = 5; m.status = IMMessageStatusSent;
    [cell configureWithMessage:m mine:mine peerReadSeq:0 dayHeader:nil showsUnreadDivider:NO
                    senderName:nil senderRole:IMGroupRoleMember replyThumbURL:nil replyThumbData:nil
             replyThumbIsVideo:NO replyFromName:nil];
    cell.frame = CGRectMake(0, 0, 390, 400);
    [window addSubview:cell];
    [cell setNeedsLayout]; [cell layoutIfNeeded];
    return cell;
}

- (void)checkText:(NSString *)text mine:(BOOL)mine {
    UIWindow *w = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 400)];
    w.hidden = NO;
    IMBubbleCell *cell = [self laidOutCellWithText:text mine:mine window:w];
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    IMCollectLabels(cell.contentView, labels);
    NSString *time = [IMTheme timeStringFromMillis:1700000000000];
    UILabel *body = nil, *meta = nil;
    for (UILabel *l in labels) {
        if (l.hidden || l.attributedText.length == 0) { continue; }
        if ([l.attributedText.string hasPrefix:text]) { body = l; }
        if ([l.attributedText.string containsString:time]) { meta = l; }
    }
    XCTAssertNotNil(body); XCTAssertNotNil(meta);
    CGRect bf = [body convertRect:body.bounds toView:cell.contentView];
    CGRect mf = [meta convertRect:meta.bounds toView:cell.contentView];
    // 时间整体在正文下方（不与正文最后一行同行）
    XCTAssertGreaterThanOrEqual(CGRectGetMinY(mf), CGRectGetMaxY(bf) - 0.5, @"time must sit below the text: %@", text);
    // 右对齐：时间右缘 = 正文容器右缘（两者都钉气泡右内边距 12）
    XCTAssertEqualWithAccuracy(CGRectGetMaxX(mf), CGRectGetMaxX(bf), 0.5);
    w.hidden = YES;
}

- (void)testShortTextTimeBelow { [self checkText:@"好的" mine:YES]; }
- (void)testMultilineTextTimeBelowReceived { [self checkText:@"第一行\n第二行\n第三行" mine:NO]; }

@end
