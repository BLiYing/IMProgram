//  IMChatWindowPlan.m
//  判据都在头文件的注释里，这里只留实现。每个分支都对得上 im-web `src/windowPlan.ts` 的同名逻辑。

#import "IMChatWindowPlan.h"

int64_t IMChatFloorFromWindow(int64_t minKeptSeq, int64_t anchor) {
    if (minKeptSeq > 0) { return minKeptSeq; }
    return anchor > 0 ? anchor : 0;
}

int64_t IMChatMergeHistoryFloor(int64_t currentFloor, int64_t incomingFloor) {
    if (incomingFloor <= 0) { return MAX((int64_t)0, currentFloor); }
    if (currentFloor <= 0) { return incomingFloor; }
    return MIN(currentFloor, incomingFloor);
}

BOOL IMChatAtHistoryFloor(int64_t historyFloor, int64_t oldestSeq) {
    return historyFloor > 0 && oldestSeq > 0 && oldestSeq <= historyFloor;
}

BOOL IMChatWindowHasMoreAbove(int64_t oldestRendered) {
    if (oldestRendered <= 0) { return NO; }   // 窗口里全是待发消息：没有可作边界的位点
    return oldestRendered > 1;                // conv_seq 从 1 起，1 号之上确定没有
}

int64_t IMChatLatestPageLow(int64_t tip, NSInteger page) {
    return MAX((int64_t)1, tip - (int64_t)page + 1);
}

int64_t IMChatTailTip(int64_t liveHead, int64_t storedHead) {
    if (liveHead > 0) { return liveHead; }
    return storedHead > 0 ? storedHead : 0;
}

BOOL IMChatShouldRequestTail(int64_t tip, BOOL latestPageCovered, int64_t windowTailHi, int64_t visibleFrom) {
    if (tip <= 0) { return windowTailHi <= 0; }   // 不知道最新在哪：空窗必须问，有内容不白跑
    if (visibleFrom > 0 && tip < visibleFrom) { return NO; }   // 可见范围内一条没有（清空 / 入群前不可见）
    return !latestPageCovered;
}

BOOL IMChatBumpShouldCatchUp(BOOL following, int64_t head, int64_t tailHi) {
    if (!following || head <= 0) { return NO; }
    return head > tailHi;   // 窗口已含最新（信号晚到）就不补
}

#pragma mark - 本机清空位点

int64_t IMChatEffectiveFloor(int64_t historyFloor, int64_t clearedUpTo) {
    int64_t fromCleared = clearedUpTo > 0 ? clearedUpTo + 1 : 0;
    return MAX(MAX((int64_t)0, historyFloor), fromCleared);
}

BOOL IMChatRangesComplete(NSArray<NSArray<NSNumber *> *> *ranges, int64_t head, int64_t floor) {
    if (head <= 0) { return YES; }
    int64_t lo = MAX((int64_t)1, floor);
    if (head < lo) { return YES; }
    for (NSArray<NSNumber *> *r in ranges) {
        if (r.count >= 2 && r.firstObject.longLongValue <= lo && r.lastObject.longLongValue >= head) { return YES; }
    }
    return NO;
}

BOOL IMChatEntryStaysLocal(BOOL complete, BOOL hasLocalRows, int64_t tip, int64_t floor) {
    if (tip > 0 && floor > 0 && tip < floor) { return YES; }
    return complete && hasLocalRows;
}

int64_t IMChatLatestPageLowAboveFloor(int64_t tip, NSInteger page, int64_t floor) {
    return MAX(IMChatLatestPageLow(tip, page), floor);
}

BOOL IMChatWindowHasMoreAboveFloor(int64_t oldestRendered, int64_t floor) {
    if (oldestRendered <= 0) { return NO; }
    return oldestRendered > MAX((int64_t)1, floor);
}

BOOL IMChatEarliestJumpNeedsServer(int64_t localEarliest, int64_t floor) {
    return localEarliest > MAX((int64_t)1, floor);
}

BOOL IMChatCalendarDayIsCleared(int64_t firstConvSeq, int64_t clearedUpTo) {
    return clearedUpTo > 0 && firstConvSeq > 0 && firstConvSeq <= clearedUpTo;
}

NSArray<NSNumber *> *IMChatDropClearedSeqs(NSArray<NSNumber *> *seqs, int64_t clearedUpTo) {
    if (clearedUpTo <= 0 || seqs.count == 0) { return seqs; }
    NSMutableArray<NSNumber *> *out = [NSMutableArray arrayWithCapacity:seqs.count];
    for (NSNumber *s in seqs) { if (s.longLongValue > clearedUpTo) { [out addObject:s]; } }
    return out;
}
