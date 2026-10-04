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
        int64_t s = messages[(NSUInteger)row].convSeq;
        if (s > maxSeq) { maxSeq = s; }
    }
    return maxSeq;
}
