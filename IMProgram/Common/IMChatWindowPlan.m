//  IMChatWindowPlan.m
//  判据都在头文件的注释里，这里只留实现。每个分支都对得上 im-web `src/windowPlan.ts` 的同名逻辑。

#import "IMChatWindowPlan.h"

int64_t IMChatFloorFromWindow(int64_t minSeqInWindow, int64_t anchor) {
    if (minSeqInWindow > 0) { return minSeqInWindow; }
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

BOOL IMChatWindowHasMoreAbove(int64_t oldestRendered, int64_t historyFloor) {
    if (oldestRendered <= 0) { return NO; }   // 窗口里全是待发消息：没有可作边界的位点
    if (oldestRendered <= 1) { return NO; }   // conv_seq 从 1 起，1 号之上确定没有
    return !IMChatAtHistoryFloor(historyFloor, oldestRendered);
}
