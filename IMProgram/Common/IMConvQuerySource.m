#import "IMConvQuerySource.h"


IMConvQuerySource IMPickConvQuerySource(BOOL complete, BOOL online) {
    // 齐全时联不联网都走本地——没有理由为一个完整的本地库去问服务端。
    if (complete) { return IMConvQuerySourceLocal; }
    return online ? IMConvQuerySourceServer : IMConvQuerySourceLocalDegraded;
}
