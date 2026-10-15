//  IMPinnedMessageTests.m
//  置顶消息模型（G0）：JSON 解析容错 + 横幅预览文案 + 发送者名；
//  置顶面板（PINNED_PANEL_DESIGN）：渲染兜底顺序、长按取消只作用所长按那条、撤回摘除、无权限外框、
//  msg_op targets 批量摘除、定位图标左右规则。判据与 Web `src/pinned.test.ts` / Android `PinnedBannerTest` 对齐（parity）。

#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "IMPinnedMessage.h"
#import "IMPinnedPanelLogic.h"
#import "IMPinnedPanelViewController.h"
#import "IMPinnedPanelCellFactory.h"
#import "IMChatViewController.h"
#import "IMMsgOpApply.h"
#import "IMMessageModel.h"
#import "IMSocketManager.h"   // kIMMsgOp* 键
#import "IMProtocol.h"

/// 置顶面板的假宿主：记下回写，渲染方法给最小可用值（单聊、无库）。
@interface IMFakePinnedHost : NSObject <IMPinnedPanelHost>
@property (nonatomic, copy) NSString *convID;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, assign) BOOL isGroupChat;
@property (nonatomic, strong) IMMediaDownloadCoordinator *downloads;
@property (nonatomic, assign) BOOL allowPin;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *unpinned;
@property (nonatomic, copy, nullable) NSArray<IMPinnedMessage *> *lastChanged;
@end

@implementation IMFakePinnedHost
- (instancetype)init {
    if ((self = [super init])) { _convID = @"c1"; _userID = @"me"; _allowPin = YES; _unpinned = [NSMutableArray array]; }
    return self;
}
- (BOOL)canPinMessages { return self.allowPin; }
- (NSString *)senderNameForMessage:(IMMessageModel *)m { return m.from ?: @""; }
- (IMGroupRole)senderRoleForMessage:(IMMessageModel *)m { return IMGroupRoleMember; }
- (NSString *)senderAvatarURLForMessage:(IMMessageModel *)m { return @""; }
- (NSString *)fullMediaURL:(NSString *)content { return content ?: @""; }
- (NSDictionary<NSString *, NSString *> *)mentionMapForMessage:(IMMessageModel *)m { return @{}; }
- (NSDictionary<NSString *, NSString *> *)mentionMapForCaption:(IMMessageModel *)m { return @{}; }
- (NSArray<IMMentionSpan *> *)mentionSpansForMessage:(IMMessageModel *)m { return nil; }
- (NSArray<IMMentionSpan *> *)mentionSpansForCaption:(IMMessageModel *)m { return nil; }
- (NSString *)replyFromNameForUID:(NSString *)uid { return uid; }
- (BOOL)performDatabaseOperation:(void (^)(IMDatabase *))operation { return NO; } // 无本地库：走②/③档
- (void)jumpToPinnedConvSeq:(int64_t)convSeq {}
- (void)reloadPinnedBanner {}
- (void)pinnedPanel:(IMPinnedPanelViewController *)panel unpinConvSeq:(int64_t)convSeq { [self.unpinned addObject:@(convSeq)]; }
- (void)pinnedPanel:(IMPinnedPanelViewController *)panel didChangeItems:(NSArray<IMPinnedMessage *> *)items { self.lastChanged = items; }
@end

static IMPinnedMessage *PinnedItem(int64_t seq, NSString *from, int64_t ts, int64_t pinnedAt) {
    return [IMPinnedMessage fromJSON:@{ @"conv_seq": @(seq), @"sender": from, @"content_type": @"text",
                                        @"content": [NSString stringWithFormat:@"m%lld", seq],
                                        @"timestamp": @(ts), @"pinned_at": @(pinnedAt) }];
}

@interface IMPinnedMessageTests : XCTestCase
@end

@implementation IMPinnedMessageTests

- (IMPinnedMessage *)itemWithType:(NSString *)type content:(NSString *)content {
    return [IMPinnedMessage fromJSON:@{ @"conv_seq": @7, @"content_type": type, @"content": content }];
}

#pragma mark - JSON 解析

- (void)testParsesFullPayload {
    IMPinnedMessage *p = [IMPinnedMessage fromJSON:@{
        @"conv_seq": @12, @"server_msg_id": @"srv-1", @"sender": @"1002",
        @"from_nickname": @"小刚", @"content_type": @"text", @"content": @"共享盘链接",
        @"timestamp": @1700, @"pinned_at": @1800,
    }];
    XCTAssertEqual(p.convSeq, 12);
    XCTAssertEqualObjects(p.serverMsgID, @"srv-1");
    XCTAssertEqualObjects(p.from, @"1002");
    XCTAssertEqualObjects(p.fromNickname, @"小刚");
    XCTAssertEqualObjects(p.content, @"共享盘链接");
    XCTAssertEqual(p.timestamp, 1700);
    XCTAssertEqual(p.pinnedAt, 1800);
}

- (void)testRejectsItemsWithoutConvSeq {
    // 没有位点就无法跳转，这条对横幅毫无用处——解析层直接丢弃，别让它占一格空白。
    XCTAssertNil([IMPinnedMessage fromJSON:nil]);
    XCTAssertNil([IMPinnedMessage fromJSON:@{}]);
    XCTAssertNil([IMPinnedMessage fromJSON:@{ @"conv_seq": @0 }]);
    XCTAssertNil([IMPinnedMessage fromJSON:(NSDictionary *)@"not a dict"]);
}

- (void)testSurvivesDirtyTypes {
    // 脏字段一律回退默认值，不抛不崩（服务端字段类型变更时不能整条横幅废掉）。
    IMPinnedMessage *p = [IMPinnedMessage fromJSON:@{
        @"conv_seq": @3, @"sender": @42, @"content": @[], @"content_type": @{}, @"from_nickname": @"",
    }];
    XCTAssertNotNil(p);
    XCTAssertEqualObjects(p.from, @"");
    XCTAssertEqualObjects(p.content, @"");
    XCTAssertEqualObjects(p.contentType, @"text");
    XCTAssertNil(p.fromNickname, @"空昵称应归一为 nil，好让显示层直接回退 uid");
}

#pragma mark - 预览文案

- (void)testTextPreviewCollapsesWhitespace {
    // 横幅是单行省略号布局，换行会把它撑高。
    XCTAssertEqualObjects([[self itemWithType:@"text" content:@"第一行\n第二行   缩进"] previewText],
                          @"第一行 第二行 缩进");
}

- (void)testMediaPreviewShowsTypeWordNotURL {
    XCTAssertEqualObjects([[self itemWithType:@"image" content:@"https://x/a.png"] previewText], @"[图片]");
    XCTAssertEqualObjects([[self itemWithType:@"video" content:@"https://x/a.mp4"] previewText], @"[视频]");
    XCTAssertEqualObjects([[self itemWithType:@"audio" content:@"https://x/a.m4a"] previewText], @"[语音]");
    XCTAssertEqualObjects([[self itemWithType:@"file"  content:@"https://x/a.zip"] previewText], @"[文件]");
}

- (void)testVoicePreviewShowsTypeWordForBothTypeNames {
    // voice 是正式类型名（audio 只是落地前的旧命名）。曾只认 audio → 语音置顶横幅铺出一串 URL。
    XCTAssertEqualObjects([[self itemWithType:@"voice" content:@"/uploads/v/a.m4a"] previewText], @"[语音]");
}

- (void)testChatRecordPreviewShowsTitleNotRawJSON {
    // 合并转发卡片 content 是整段 JSON，直接显会把 {"t":…,"items":[…]} 铺满横幅。
    NSString *json = @"{\"t\":\"小刚 的聊天记录\",\"items\":[{\"n\":\"小刚\",\"ct\":\"text\",\"c\":\"在吗\"}]}";
    XCTAssertEqualObjects([[self itemWithType:@"chat_record" content:json] previewText], @"[聊天记录] 小刚 的聊天记录");
    XCTAssertEqualObjects([[self itemWithType:@"chat_record" content:@"garbled"] previewText], @"[聊天记录]",
                          @"非法 JSON 回落裸 token，不铺原文");
}

- (void)testPreviewNeverReturnsEmpty {
    XCTAssertEqualObjects([[self itemWithType:@"text" content:@"   "] previewText], @"（空消息）");
    XCTAssertEqualObjects([[self itemWithType:@"sticker" content:@""] previewText], @"[sticker]");
}

#pragma mark - 发送者名

- (void)testSenderLabelPrefersGroupNicknameAndOnlyInGroups {
    IMPinnedMessage *withNick = [IMPinnedMessage fromJSON:@{
        @"conv_seq": @1, @"sender": @"1002", @"from_nickname": @"小刚" }];
    IMPinnedMessage *noNick = [IMPinnedMessage fromJSON:@{ @"conv_seq": @1, @"sender": @"1002" }];
    XCTAssertEqualObjects([withNick senderLabelForGroup:YES], @"小刚");
    XCTAssertEqualObjects([noNick senderLabelForGroup:YES], @"1002", @"无昵称回退 uid");
    XCTAssertEqualObjects([withNick senderLabelForGroup:NO], @"", @"单聊不显示发送者");
}

#pragma mark - 面板：完整消息对象与兜底顺序（§4.0）

- (void)testParsesFullMessageObjectAndRejectsMismatchedSeq {
    IMPinnedMessage *p = [IMPinnedMessage fromJSON:@{ @"conv_seq": @5, @"content_type": @"image", @"content": @"/u/a.jpg",
        @"message": @{ @"conv_seq": @5, @"from": @"u2", @"content_type": @"image", @"content": @"/u/a.jpg",
                       @"media_w": @640, @"media_h": @480, @"timestamp": @1700 } }];
    XCTAssertNotNil(p.message);
    XCTAssertEqualObjects(p.message.from, @"u2");
    XCTAssertEqual(p.message.mediaW, 640, @"媒体元数据要随完整对象过来，真气泡才能按比例渲染");
    IMPinnedMessage *bad = [IMPinnedMessage fromJSON:@{ @"conv_seq": @5, @"message": @{ @"conv_seq": @6 } }];
    XCTAssertNil(bad.message, @"位点对不上的完整对象当没带，退回兜底档");
    IMPinnedMessage *junk = [IMPinnedMessage fromJSON:@{ @"conv_seq": @5, @"message": @"x" }];
    XCTAssertNil(junk.message);
}

- (void)testResolveOrderLocalThenRemoteThenTypeWord {
    IMPinnedMessage *item = [IMPinnedMessage fromJSON:@{ @"conv_seq": @9, @"sender": @"u2", @"content_type": @"image",
        @"content": @"/u/a.jpg", @"message": @{ @"conv_seq": @9, @"from": @"u2", @"content_type": @"image", @"content": @"/u/remote.jpg" } }];
    IMMessageModel *local = [IMMessageModel new];
    local.convSeq = 9; local.contentType = @"image"; local.content = @"/u/local.jpg";
    XCTAssertEqual(IMPinnedResolveMessage(item, local, @"c1"), local, @"① 本地库行优先");
    XCTAssertEqualObjects(IMPinnedResolveMessage(item, nil, @"c1").content, @"/u/remote.jpg", @"② 其次接口完整对象");
    XCTAssertEqualObjects(IMPinnedResolveMessage(item, nil, @"c1").convID, @"c1", @"完整对象缺 conv_id 时补上");
    IMPinnedMessage *old = [IMPinnedMessage fromJSON:@{ @"conv_seq": @9, @"content_type": @"image", @"content": @"/u/a.jpg" }];
    IMMessageModel *fb = IMPinnedResolveMessage(old, nil, @"c1");
    XCTAssertEqualObjects(fb.contentType, @"text");
    XCTAssertEqualObjects(fb.content, @"[图片]", @"③ 旧服务端：类型词纯文本气泡，不铺 URL");
    IMPinnedMessage *legacy = [IMPinnedMessage fromJSON:@{ @"conv_seq": @3, @"content_type": @"audio", @"content": @"/u/a.m4a",
        @"message": @{ @"conv_seq": @3, @"content_type": @"audio", @"content": @"/u/a.m4a" } }];
    XCTAssertEqualObjects(IMPinnedResolveMessage(legacy, nil, @"c1").content, @"[语音]", @"认不出的类型一律类型词兜底");
    XCTAssertEqualObjects(IMPinnedResolveMessage(PinnedItem(4, @"u2", 1, 1), nil, @"c1").content, @"m4", @"文本兜底保留原文");
}

- (void)testLatestItemIsMaxPinnedAt {
    NSArray *items = @[ PinnedItem(1, @"a", 1, 100), PinnedItem(2, @"a", 1, 300), PinnedItem(3, @"a", 1, 200) ];
    XCTAssertEqual(IMPinnedLatestItem(items).convSeq, 2, @"横幅恒显 pinned_at 最大的那条（不轮转）");
    XCTAssertNil(IMPinnedLatestItem(@[]));
}

#pragma mark - 面板：长按取消置顶只作用于所长按那条

- (void)testLongPressUnpinOnlyAffectsPressedItem {
    IMFakePinnedHost *host = [IMFakePinnedHost new];
    NSArray *items = @[ PinnedItem(9, @"u2", 1000, 30), PinnedItem(7, @"u2", 1000, 20), PinnedItem(3, @"me", 1000, 10) ];
    IMPinnedPanelViewController *panel = [[IMPinnedPanelViewController alloc] initWithHost:host items:items];
    [panel unpinConvSeq:7];
    XCTAssertEqualObjects(host.unpinned, @[ @7 ], @"只给所长按那条发 pin(false)，一次");
    XCTAssertEqual(panel.items.count, 2u);
    XCTAssertEqual(panel.items[0].convSeq, 9);
    XCTAssertEqual(panel.items[1].convSeq, 3, @"其余条目原序保留");
    XCTAssertEqual(host.lastChanged.count, 2u, @"横幅同步到同一集合");
}

#pragma mark - 面板：开着时被别端「取消所有置顶」清空不得崩溃

/// 回归：面板已加载并显示着 N 行，集合被一次清空——此前 rows 置空后只 dismiss 不 reloadData，
/// 表格仍按旧行数向数据源要 cell，cellForRow 数组越界崩溃。
- (void)testEmptyingItemsWhilePanelOpenDoesNotCrash {
    IMFakePinnedHost *host = [IMFakePinnedHost new];
    NSArray *items = @[ PinnedItem(9, @"u2", 1000, 30), PinnedItem(7, @"u2", 1000, 20), PinnedItem(3, @"me", 1000, 10) ];
    IMPinnedPanelViewController *panel = [[IMPinnedPanelViewController alloc] initWithHost:host items:items];
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    window.rootViewController = panel;
    [window makeKeyAndVisible];
    [panel.view layoutIfNeeded];
    UITableView *table = nil;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:panel.view];
    while (stack.count > 0 && !table) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([v isKindOfClass:UITableView.class]) { table = (UITableView *)v; break; }
        [stack addObjectsFromArray:v.subviews];
    }
    XCTAssertNotNil(table);
    XCTAssertGreaterThan([table numberOfRowsInSection:0], 0, @"前置：清空前表格有行");
    XCTAssertNoThrow([panel applyPinnedItems:@[]]);
    // 真实场景里 dismiss 动画期间会触发表格重排；这里显式模拟。
    XCTAssertNoThrow({ [table setNeedsLayout]; [table layoutIfNeeded]; [table.superview layoutIfNeeded]; }, @"清空后的布局不得再向数据源要旧行");
    XCTAssertEqual([table numberOfRowsInSection:0], 0, @"表格行数与 rows 对齐");
    XCTAssertEqual(panel.items.count, 0u);
}

#pragma mark - 面板：撤回后摘除

- (void)testRecallDropsItemFromBannerAndPanel {
    NSArray *items = @[ PinnedItem(9, @"u2", 1000, 30), PinnedItem(7, @"u2", 1000, 20) ];
    IMMsgOpPatch *recall = [IMMsgOpPatch patchFromPayload:@{ @"op": kIMMsgOpRecall, @"conv_id": @"c1", @"target_conv_seq": @7 } nowMillis:5];
    IMChatMsgOpBannerAction a = IMChatMsgOpBannerPlan([recall appliedUserInfo], items);
    XCTAssertTrue(a.dropTargetLocally);
    NSArray<IMPinnedMessage *> *kept = IMChatPinnedItemsDroppingSeq(items, 7);
    IMFakePinnedHost *host = [IMFakePinnedHost new];
    IMPinnedPanelViewController *panel = [[IMPinnedPanelViewController alloc] initWithHost:host items:items];
    [panel applyPinnedItems:kept];
    XCTAssertEqual(panel.items.count, 1u);
    XCTAssertEqual(panel.items.firstObject.convSeq, 9);
    // 竞态：集合还没更新但本地库已是撤回墓碑 → 该行直接不出（不出墓碑行）。
    IMMessageModel *tomb = [IMMessageModel new];
    tomb.convSeq = 7; tomb.contentType = @"text"; tomb.recalledAt = 99;
    XCTAssertNil(IMPinnedResolveMessage(items[1], tomb, @"c1"));
    NSArray<IMPinnedPanelRow *> *rows = IMPinnedPanelBuildRows(items, ^IMMessageModel *(IMPinnedMessage *it) {
        return IMPinnedResolveMessage(it, it.convSeq == 7 ? tomb : nil, @"c1");
    }, @"me", ^NSString *(int64_t ms) { return @"d"; }, ^BOOL(int64_t x, int64_t y) { return YES; });
    NSUInteger messages = 0;
    for (IMPinnedPanelRow *r in rows) { if (r.item) { messages++; XCTAssertNotEqual(r.item.convSeq, 7); } }
    XCTAssertEqual(messages, 1u);
}

#pragma mark - 面板：无权限 → 无取消项 / 无底栏 / 无副标题

- (void)testNoPermissionHidesUnpinMenuFooterAndHint {
    XCTAssertEqualObjects(IMPinnedPanelMenuActionIDs(@"text", @"hi", NO), (@[ IMPinnedMenuActionCopy, IMPinnedMenuActionLocate ]));
    XCTAssertEqualObjects(IMPinnedPanelMenuActionIDs(@"text", @"hi", YES),
                          (@[ IMPinnedMenuActionUnpin, IMPinnedMenuActionCopy, IMPinnedMenuActionLocate ]));
    XCTAssertEqualObjects(IMPinnedPanelMenuActionIDs(@"image", @"[图片]", YES), (@[ IMPinnedMenuActionUnpin, IMPinnedMenuActionLocate ]),
                          @"复制仅文本：兜底气泡的类型词不可复制");
    IMPinnedPanelChrome none = IMPinnedPanelChromeForPermission(NO);
    XCTAssertFalse(none.showsLongPressHint);
    XCTAssertFalse(none.showsUnpinAll);
    IMPinnedPanelChrome can = IMPinnedPanelChromeForPermission(YES);
    XCTAssertTrue(can.showsLongPressHint);
    XCTAssertTrue(can.showsUnpinAll);
    IMFakePinnedHost *host = [IMFakePinnedHost new];
    host.allowPin = NO;
    IMPinnedPanelViewController *panel = [[IMPinnedPanelViewController alloc] initWithHost:host items:@[ PinnedItem(7, @"u2", 1, 1) ]];
    [panel unpinConvSeq:7];
    XCTAssertEqual(host.unpinned.count, 0u, @"无权限时取消入口即便被调到也不发 op");
    XCTAssertEqual(panel.items.count, 1u);
}

#pragma mark - msg_op targets：一键取消所有置顶的批量帧

- (void)testPinTargetsFrameExpandsAndDropsEveryTarget {
    NSDictionary *frame = @{ @"op": kIMMsgOpPin, @"conv_id": @"c1", @"pinned": @NO, @"timestamp": @123,
                             @"targets": @[ @{ @"target_conv_seq": @9, @"op_conv_seq": @101 },
                                            @{ @"target_conv_seq": @0 }, @"junk",
                                            @{ @"target_conv_seq": @3, @"op_conv_seq": @102 } ] };
    NSArray<NSDictionary *> *each = IMMsgOpPinTargetPayloads(frame);
    XCTAssertEqual(each.count, 2u, @"非正位点 / 非字典项跳过");
    XCTAssertNil(each[0][@"targets"]);
    XCTAssertEqualObjects(each[1][@"op_conv_seq"], @102);
    NSArray<IMPinnedMessage *> *items = @[ PinnedItem(9, @"u2", 1, 30), PinnedItem(5, @"u2", 1, 20), PinnedItem(3, @"u2", 1, 10) ];
    for (NSDictionary *one in each) {
        IMMsgOpPatch *patch = [IMMsgOpPatch patchFromPayload:one nowMillis:1];
        XCTAssertNotNil(patch, @"拆出来的每条都是合法的单目标 pin 帧");
        XCTAssertEqual(patch.pinnedAt, -1, @"pinned:false = 取消置顶");
        IMChatMsgOpBannerAction a = IMChatMsgOpBannerPlan([patch appliedUserInfo], items);
        XCTAssertTrue(a.dropTargetLocally, @"取消置顶命中集合 → 本地先摘");
        XCTAssertTrue(a.reload);
        items = IMChatPinnedItemsDroppingSeq(items, patch.targetConvSeq);
    }
    XCTAssertEqual(items.count, 1u);
    XCTAssertEqual(items.firstObject.convSeq, 5, @"不在 targets 里的置顶不受影响");
    NSDictionary *single = @{ @"op": kIMMsgOpPin, @"conv_id": @"c1", @"target_conv_seq": @9, @"pinned": @NO };
    XCTAssertNil(IMMsgOpPinTargetPayloads(single), @"单条帧不走批量路径");
    NSDictionary *batchDelete = @{ @"op": kIMMsgOpDelete, @"conv_id": @"c1", @"targets": @[] };
    XCTAssertNil(IMMsgOpPinTargetPayloads(batchDelete), @"批量删除帧归 IMMsgOpBatchDeleteSeqs，不在这里拆");
}

#pragma mark - 定位图标：我发的在气泡左、别人的在气泡右

- (void)testLocateIconSideRule {
    XCTAssertTrue(IMPinnedLocateIconOnLeadingSide(YES));
    XCTAssertFalse(IMPinnedLocateIconOnLeadingSide(NO));
}

/// 真 cell 上量一遍：圆钮紧挨气泡（间距 8）、底边对齐，我发的在左、别人的在右，且不出行。
- (void)testLocateButtonHugsBubbleOnCorrectSide {
    IMFakePinnedHost *host = [IMFakePinnedHost new];
    UITableView *tv = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 390, 800) style:UITableViewStylePlain];
    [IMPinnedPanelCellFactory registerCellsInTableView:tv];
    for (NSNumber *mineFlag in @[ @YES, @NO ]) {
        BOOL mine = mineFlag.boolValue;
        IMMessageModel *m = [IMMessageModel new];
        m.convSeq = 1; m.contentType = @"text"; m.from = mine ? @"me" : @"u2"; m.timestamp = 1700000000000;
        m.content = @"明天 10 点开会，会议室 A，带上上周的材料，请大家准时到场。明天 10 点开会，会议室 A，带上上周的材料。";
        UITableViewCell *cell = [IMPinnedPanelCellFactory messageCellForMessage:m mine:mine host:host tableView:tv
            indexPath:[NSIndexPath indexPathForRow:0 inSection:0] onLocate:^{} onLayoutChange:^{}];
        cell.frame = CGRectMake(0, 0, 390, 200);
        [cell layoutIfNeeded];
        UIView *bubble = [IMPinnedPanelCellFactory bubbleViewInCell:cell];
        UIButton *button = nil;
        for (UIView *v in cell.subviews) { if ([v isKindOfClass:UIButton.class]) { button = (UIButton *)v; } }
        XCTAssertNotNil(button);
        CGRect b = [bubble convertRect:bubble.bounds toView:cell];
        CGRect i = button.frame;
        XCTAssertEqualWithAccuracy(CGRectGetMaxY(i), CGRectGetMaxY(b), 0.5, @"与气泡底边对齐");
        if (mine) {
            XCTAssertEqualWithAccuracy(CGRectGetMinX(b) - CGRectGetMaxX(i), 8, 0.5, @"我发的：圆钮在气泡左侧、间距 8");
        } else {
            XCTAssertEqualWithAccuracy(CGRectGetMinX(i) - CGRectGetMaxX(b), 8, 0.5, @"别人的：圆钮在气泡右侧、间距 8");
        }
        XCTAssertGreaterThanOrEqual(CGRectGetMinX(i), 0);
        XCTAssertLessThanOrEqual(CGRectGetMaxX(i), 390 - 12 + 0.5, @"长文本气泡给圆钮让出一列，圆钮始终在行内");
        XCTAssertFalse(cell.contentView.userInteractionEnabled, @"只读：内容手势全关");
    }
}

#pragma mark - 面板：日期胶囊只在日期变化时插

- (void)testDayPillOnlyWhenDateChanges {
    NSArray *items = @[ PinnedItem(1, @"a", 100, 3), PinnedItem(2, @"me", 150, 2), PinnedItem(3, @"a", 900, 1) ];
    NSArray<IMPinnedPanelRow *> *rows = IMPinnedPanelBuildRows(items, ^IMMessageModel *(IMPinnedMessage *it) {
        return IMPinnedResolveMessage(it, nil, @"c1");
    }, @"me", ^NSString *(int64_t ms) { return [NSString stringWithFormat:@"D%lld", ms / 500]; },
       ^BOOL(int64_t x, int64_t y) { return x / 500 == y / 500; });
    XCTAssertEqual(rows.count, 5u); // D0, m1, m2, D1, m3
    XCTAssertEqualObjects(rows[0].dayHeader, @"D0");
    XCTAssertEqual(rows[1].item.convSeq, 1);
    XCTAssertTrue(rows[2].mine, @"我发的识别为 mine（靠右绿底、无头像昵称）");
    XCTAssertEqualObjects(rows[3].dayHeader, @"D1");
}

#pragma mark - 宿主契约

/// 聊天页对 IMPinnedPanelHost 只做编译期声明（方法体散在多个 category），这里兜住「每个方法都真有实现」。
- (void)testChatPageImplementsPinnedPanelHost {
    unsigned int n = 0;
    struct objc_method_description *methods = protocol_copyMethodDescriptionList(@protocol(IMPinnedPanelHost), YES, YES, &n);
    XCTAssertGreaterThan(n, 10u);
    for (unsigned int i = 0; i < n; i++) {
        XCTAssertTrue([IMChatViewController instancesRespondToSelector:methods[i].name],
                      @"IMChatViewController 缺 %@", NSStringFromSelector(methods[i].name));
    }
    free(methods);
}

@end
