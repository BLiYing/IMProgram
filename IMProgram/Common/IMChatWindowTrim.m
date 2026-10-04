//  IMChatWindowTrim.m
//  规则与坑都写在头文件注释里，这里只留实现。

#import "IMChatWindowTrim.h"
#import "IMMessageModel.h"

NSInteger IMChatTailDropCount(NSArray<IMMessageModel *> *messages, NSInteger cap, NSInteger anchorRow) {
    NSInteger count = (NSInteger)messages.count;
    NSInteger overflow = count - cap;
    NSInteger dropped = 0;
    while (dropped < overflow) {
        // 别丢到锚点身上：丢了它，随后的保位就没有参照物、只能放弃补偿 → 又是一次跳变。
        if (anchorRow != NSNotFound && count - dropped - 1 <= anchorRow) { break; }
        if (messages[(NSUInteger)(count - dropped - 1)].convSeq <= 0) { break; }
        dropped++;
    }
    return dropped;
}

NSInteger IMChatHeadDropCount(NSInteger count, NSInteger cap, NSInteger anchorRow) {
    NSInteger overflow = count - cap;
    if (overflow <= 0) { return 0; }
    if (anchorRow != NSNotFound && anchorRow < overflow) { return 0; }
    return overflow;
}
