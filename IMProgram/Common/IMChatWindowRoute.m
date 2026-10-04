//  IMChatWindowRoute.m
//  顺序与坑写在头文件注释里，这里只留实现。

#import "IMChatWindowRoute.h"

IMChatWindowRespRoute IMChatRouteWindowResp(BOOL convMatches,
                                            int64_t anchor,
                                            BOOL anchorFound,
                                            int64_t pendingNewerAnchor,
                                            int64_t pendingEntryAnchor,
                                            BOOL pendingTail,
                                            int64_t pendingAnchor,
                                            BOOL pendingIsJump,
                                            BOOL pendingJumpIsEarliest,
                                            int64_t loadedHi) {
    if (!convMatches) { return IMChatWindowRespIgnore; }
    if (anchor != 0 && anchor == pendingNewerAnchor) {
        // 窗口被换到了更早的一段 → 这帧已过期。
        if (loadedHi <= 0 || loadedHi < anchor) { return IMChatWindowRespNewerStale; }
        return IMChatWindowRespNewerAppend;
    }
    if (anchor != 0 && anchor == pendingEntryAnchor) { return IMChatWindowRespEntryRewindow; }
    if (anchor == 0 && pendingTail) { return IMChatWindowRespTailRewindow; }
    // 通用路：必须真有一次通用开窗在途（pendingAnchor != 0）且锚点对得上。
    // pendingAnchor==0 是「没有在途」：此时 anchor=0 的帧（比如「要最新一窗」的 6s 兜底超时已清掉
    // pendingTail 之后才迟到的应答）不能因为 0==0 就落进下面的向上翻页分支。
    if (pendingAnchor == 0 || anchor != pendingAnchor) { return IMChatWindowRespIgnore; }
    if (pendingIsJump) {
        if (pendingJumpIsEarliest) { return IMChatWindowRespJumpEarliest; }
        return anchorFound ? IMChatWindowRespJumpOpen : IMChatWindowRespJumpNotFound;
    }
    return IMChatWindowRespOlder;
}
