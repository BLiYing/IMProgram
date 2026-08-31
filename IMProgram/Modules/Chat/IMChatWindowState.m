//  IMChatWindowState.m
//  纯状态容器（说明见 .h）。只在 init 里给出"空窗且贴最新"的初值。

#import "IMChatWindowState.h"

@implementation IMChatWindowState

- (instancetype)init {
    self = [super init];
    if (self) {
        _messages = [NSMutableArray array];
        _seenConvSeqs = [NSMutableSet set];
        // 初值=空窗、贴最新、上方可能还有更早的。第一次装载（loadInitialWindow）会覆盖后两项。
        _atTail = YES;
        _hasMoreAbove = YES;
    }
    return self;
}

@end
