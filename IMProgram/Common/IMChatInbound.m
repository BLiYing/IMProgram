//  IMChatInbound.m
//  判据与坑都写在头文件注释里，这里只留实现。

#import "IMChatInbound.h"
#import "IMMessageModel.h"

/// 同毫秒内的次序键：conv_seq=0 视为 +∞。
static inline int64_t IMChatSeqKey(int64_t convSeq) { return convSeq > 0 ? convSeq : INT64_MAX; }

NSComparisonResult IMChatMessageOrder(IMMessageModel *a, IMMessageModel *b) {
    if (a.timestamp != b.timestamp) {
        return a.timestamp < b.timestamp ? NSOrderedAscending : NSOrderedDescending;
    }
    int64_t sa = IMChatSeqKey(a.convSeq);
    int64_t sb = IMChatSeqKey(b.convSeq);
    if (sa == sb) { return NSOrderedSame; }
    return sa < sb ? NSOrderedAscending : NSOrderedDescending;
}

BOOL IMChatInsertNeedsSort(IMMessageModel *last, IMMessageModel *incoming) {
    if (!last) { return NO; }
    return IMChatMessageOrder(incoming, last) == NSOrderedAscending;
}

IMChatInboundDisposition IMChatInboundDispose(BOOL convMatches,
                                              int64_t convSeq,
                                              BOOL alreadyInWindow,
                                              BOOL isFileWithSize,
                                              BOOL atTail,
                                              int64_t maxInMemoryConvSeq) {
    if (!convMatches) { return IMChatInboundDropOtherConv; }
    if (convSeq > 0 && alreadyInWindow) {
        return isFileWithSize ? IMChatInboundDedupBackfillFile : IMChatInboundDedupDrop;
    }
    if (!atTail) { return IMChatInboundDbOnlyHistoryWindow; }
    if (convSeq > 0 && convSeq <= maxInMemoryConvSeq) { return IMChatInboundDbOnlyBelowTail; }
    return IMChatInboundAppend;
}
