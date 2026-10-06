//  IMChatReadPosition.m
//  口径与坑写在头文件注释里，这里只留实现。

#import "IMChatReadPosition.h"
#import <UIKit/UIKit.h>        // NSIndexPath.row（UIKit 扩展）
#import "IMChatMessageLogic.h"   // IMContentTypeCountsAsUnread
#import "IMMessageModel.h"

NSInteger IMChatFirstUnreadIndex(NSArray<IMMessageModel *> *messages, NSInteger entryUnread,
                                 int64_t entryReadSeq, NSString *myUID) {
    if (entryUnread <= 0) { return -1; }
    for (NSInteger i = 0; i < (NSInteger)messages.count; i++) {
        IMMessageModel *m = messages[(NSUInteger)i];
        if (m.convSeq <= entryReadSeq) { continue; }
        if (myUID.length > 0 && [m.from isEqualToString:myUID]) { continue; }
        if (IMContentTypeCountsAsUnread(m.contentType)) { return i; }
    }
    return -1;
}

int64_t IMChatMaxSeqOfRows(NSArray<IMMessageModel *> *messages, NSArray<NSIndexPath *> *visibleRows) {
    int64_t maxSeq = 0;
    for (NSIndexPath *ip in visibleRows) {
        NSInteger row = ip.row;
        if (row < 0 || row >= (NSInteger)messages.count) { continue; }
        IMMessageModel *m = messages[(NSUInteger)row];
        int64_t s = m.convSeq;
        if (s > maxSeq) { maxSeq = s; }
        // 九宫格整组一行可见：其余成员是零高度占位行，是否算「可见行」取决于 UIKit，不能指望；
        // 沿同 groupID 的相邻成员取最大 seq，否则对端的相册勾（看最后一条）永远停在单勾。
        if (m.groupID.length > 0) {
            for (NSInteger j = row + 1; j < (NSInteger)messages.count; j++) {
                IMMessageModel *n = messages[(NSUInteger)j];
                if (![n.groupID isEqualToString:m.groupID]) { break; }
                if (n.convSeq > maxSeq) { maxSeq = n.convSeq; }
            }
        }
    }
    return maxSeq;
}
