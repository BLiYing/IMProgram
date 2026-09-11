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

 ⚠️ **`minKeptSeq` 必须是「客户端真正会留下的行」的最小 seq，不能是整窗最小 seq**
 （2026-09-10 /code-review 抓到，两端同一个洞）。`window_resp` 里混着 msg_op 事件行与
 「为所有人删除」的墓碑，它们**占号但会被客户端当场丢掉**（iOS `handleWindowResp` 一个 `continue`
 一个 `removeLocalMessage…`；Web 的 `processIncoming` 同样不产出）。拿整窗最小 seq 当下界，
 就把下界记在了一条**页面永远渲染不出来的号**上，而拿去比的上沿只数真实消息 →
 `IMChatAtHistoryFloor` 恒假 → 每次滑到顶都再空问一次，**永不收敛**。
 具体：会话最早一条 seq=1 被「为所有人删除」、最早的真实消息是 seq=2 → 下界记成 1，
 上沿恒为 2，`2<=1` 永假。这正是本判据要消灭的那个空转，且比改造前更糟
 （改造前那一行是 `hasMoreAbove = hasBefore`，一次应答后就收敛）。

 @param minKeptSeq 本窗里**客户端留下的**行的最小正 conv_seq；0 = 整窗都是占号行 / 一条都没有。
 @param anchor     本次开窗的锚点。留不下任何行时退回它——那同样断言了"anchor 之下没有"，
                   且 anchor 正是请求方当时的上沿，比得上、能收敛。
 */
extern int64_t IMChatFloorFromWindow(int64_t minKeptSeq, int64_t anchor);

/// 两次报上来的可见下界怎么合并：**只往小里收**（同 im-web 的 `Math.min`）。
/// 往大里收会把已经证实存在的更早内容挡在外面，那是"少给用户看东西"的方向，不能容忍。
/// 任一侧为 0（未知）时取另一侧。
extern int64_t IMChatMergeHistoryFloor(int64_t currentFloor, int64_t incomingFloor);

/// 上沿是否已经踩在服务端说过的可见下界上。踩上了就别再发注定回空页的上滚请求。
/// **下界未知（0）时恒 NO**——不知道就去问，不能靠猜把用户的历史封死。
extern BOOL IMChatAtHistoryFloor(int64_t historyFloor, int64_t oldestSeq);

/**
 上滚的**粗闸**：窗口上方是否还可能有更早的。只回答"上沿是不是已经到 conv_seq 1"。

 ⚠️ **可见下界那道闸刻意不放在这里**（2026-09-10 /code-review 抓到）。iOS 的 `hasMoreAbove`
 是本地展开与服务端请求**共用**的一道闸，而 im-web 那边 `atHistoryFloor` 只出现在
 「本地展不出来了」之后的分支里——把下界并进总闸，就会连**本地已经存着的**更早历史也一起挡掉：
 成员退群再入群会把 `join_conv_seq` 刷成新值（服务端 `store_group.go`），下界随之抬高，
 而入群前下载过的行仍在本地库里；用户跳进那一段往上滑，本地明明有也展不出来。
 所以下界只在 `loadOlderPage` 里「本段到头、准备问服务端」那一步生效。

 @param oldestRendered 当前窗口里最早的已上号 conv_seq；<=0（窗口里全是待发消息）一律 NO。
 */
extern BOOL IMChatWindowHasMoreAbove(int64_t oldestRendered);

#pragma mark - C4：↓ 跳到底 / 超级群 conv_bump（OFFLINE_BACKLOG_DESIGN §4.8）

/**
 「取最新一页」拿回的那一段的下沿：`[tip-page+1, tip]`。

 服务端 `window_req(anchor=0, before=page)` 回的是**以 head 结尾的 page 条**
 （IMServer `internal/gateway/window.go` 的 `got[len(got)-before:]`）。按 `tip-page` 算会多要一条——
 刚取回最新一页后这一窗永远判不齐，每次点 ↓ 都白问一次（2026-09-11 im-web 的出站帧测试抓到，两端同口径）。
 */
extern int64_t IMChatLatestPageLow(int64_t tip, NSInteger page);

/**
 超级群 conv_bump 到了、会话正开着：该不该补。与 im-web `windowPlan.planBumpCatchUp` 的**不变式**一致：
 没贴底（在翻历史）就**不补**——↓N 按 head 计数，点 ↓ 再取；贴底跟随才补。

 ⚠️ **补法与 im-web 刻意不同**（SYMMETRY 已登记）：im-web 差距 ≤ 一页时只取差的那几条（`anchor=尾段上沿, after=差距`）；
 iOS 一律走 `requestServerTailWindowIfBehind`（取最新一页、整窗替换、贴底）。原因在窗口模型：iOS 内存只装一窗，
 「从尾巴接着取」落库后走 `appendNewerFromLocalAfter:`，那条路**保持首个可见行不动、不贴底**（它是给用户手动下滑用的），
 跟随中的人会看到新消息落在屏幕下方要自己滑——比现在更差。代价只是多下几十行已在本地的消息。

 @param following 窗口含本地最新**且**贴着底部。只看 atTail 不够：在尾窗里往上滑着读时取最新会整窗替换并贴底，把人拽走。
 @param head      服务端最新位点（未知为 0）。
 @param tailHi    窗口里最新一条的 conv_seq（0 = 窗口里没有已上号的消息）。
 */
extern BOOL IMChatBumpShouldCatchUp(BOOL following, int64_t head, int64_t tailHi);

NS_ASSUME_NONNULL_END
