#import "IMConvQuerySource.h"

NSString * const IMDegradedSearchNotice   = @"离线：仅搜索已下载的消息";
NSString * const IMDegradedCalendarNotice = @"离线：仅显示已下载的消息";
NSString * const IMNeedNetworkNotice      = @"该消息尚未下载，需要联网加载";

IMConvQuerySource IMPickConvQuerySource(BOOL complete, BOOL online) {
    // 齐全时联不联网都走本地——没有理由为一个完整的本地库去问服务端。
    if (complete) { return IMConvQuerySourceLocal; }
    return online ? IMConvQuerySourceServer : IMConvQuerySourceLocalDegraded;
}
