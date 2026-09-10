//  IMChatWindowPlan.h
//  取数分流里「上滚还该不该问服务端」的判据（IMServer/docs/design/OFFLINE_BACKLOG_DESIGN.md §4.7）。
//
//  与 im-web 的 `src/windowPlan.ts` **同一份口径**（IMServer/docs/SYMMETRY.md 有登记）。
//  抽成纯函数的理由与 IMConvQuerySource / IMChatEntryHasUnread 一样：**判错了不会报错**。
//  判成"本地还有"而其实没有 → 上滑什么都不发生、也永不发请求（无声卡死）；
//  判成"本地没有"而其实有 → 每次上滑空跑一次注定回空页的网络请求，界面正常、只是白花往返。
//  前一种严重得多，所以拿不准一律往"还有 / 去问"倒。
//
//  三端共同的坑，都写在各函数注释里，别只看函数名。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// **iOS 没有 `moreLocalAbove` 的对应物，这是刻意的**：im-web 要在内存数组上判「上沿之上本地
// 还有没有能直接展开的内容」，故有那个纯函数；iOS 把同一条判据下沉进了 SQL——
// `IMDatabase+Ranges` 的 `contiguousMessagesForConv:beforeConvSeq:limit:` **只取与上沿同段**的
// 更早消息，"返回空"就是"本段到头"。判据同源（都是区间清单，不是 seq 连号），落点不同。
// 别为了"两端函数一一对应"在这里补一个没有调用点的函数——上一轮 Web 侧的 `moreLocalBelow`
// 就是那样长出来的死代码（有测试、零调用点），2026-09-09 复查时删掉了。

/**
 `has_before=false` 时，该把「服务端说过的可见下界」记在哪一条上。

 **必须记位点、不能记布尔**（2026-09-09 /code-review 在 Web 侧打回）：服务端的 `has_before` 是相对
 **本窗下沿**说的，不是相对整条会话（见 IMServer `internal/gateway/window.go` 的
 `hasBefore = len(pre) > before`）。从搜索结果跳进一个旧岛、上滑到那个岛的顶部时它同样为 false
 ——记成布尔就等于宣布"整条会话到顶了"，之后回到最新那一段再上滑会被**永久静默屏蔽**，
 中间那段缺口再也补不上。

 @param minSeqInWindow 本窗里最小的正 conv_seq（含事件行与墓碑——它们同样是"服务端给过了"）；
                       0 = 整窗一条都没有。对应 im-web `floorFromWindow` 里对 seqs 取 min 那一步。
 @param anchor         本次开窗的锚点。整窗都是占号行时退回它——那同样断言了"anchor 之下没有"。
 */
extern int64_t IMChatFloorFromWindow(int64_t minSeqInWindow, int64_t anchor);

/// 两次报上来的可见下界怎么合并：**只往小里收**（同 im-web 的 `Math.min`）。
/// 往大里收会把已经证实存在的更早内容挡在外面，那是"少给用户看东西"的方向，不能容忍。
/// 任一侧为 0（未知）时取另一侧。
extern int64_t IMChatMergeHistoryFloor(int64_t currentFloor, int64_t incomingFloor);

/// 上沿是否已经踩在服务端说过的可见下界上。踩上了就别再发注定回空页的上滚请求。
/// **下界未知（0）时恒 NO**——不知道就去问，不能靠猜把用户的历史封死。
extern BOOL IMChatAtHistoryFloor(int64_t historyFloor, int64_t oldestSeq);

/**
 上滚这一路的**总闸**：窗口上方是否还可能有更早的（本地库或服务端）。

 与 im-web `App.tsx` 上滚分支里 `oldestRendered > 1 && !atHistoryFloor(cid, oldestRendered)`
 同一判据。`> 1` 只是猜——conv_seq 从 1 起，但对**入群前历史不可见的新成员**，他能看到的最早
 一条可能是 500，`> 1` 对他恒真，于是每次滚到顶都再问一次服务端、每次都得到"没有了"，
 **永远不收敛的空转**。真正权威的答案只有服务端的 `has_before`，所以要叠上下界这一条。

 @param oldestRendered 当前窗口里最早的已上号 conv_seq；<=0（窗口里全是待发消息）一律 NO。
 @param historyFloor   服务端说过的可见下界位点（0=未知）。
 */
extern BOOL IMChatWindowHasMoreAbove(int64_t oldestRendered, int64_t historyFloor);

NS_ASSUME_NONNULL_END
