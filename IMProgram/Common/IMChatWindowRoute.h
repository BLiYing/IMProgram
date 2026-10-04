//  IMChatWindowRoute.h
//  window_resp 到达后「这帧该走哪条路」的分流判据（从 IMChatViewController+Window 抽出的纯函数）。
//
//  **iOS 独有**：Web 没有这套多个在途标志并存的结构，别为了对称去 Web 补一个。
//
//  window_resp 的形状对所有开窗用途都一样（按读位点进会话 / 取最新一窗 / 向下翻页 / 向上翻页 / 跳转 /
//  跳最早），分不清就会拿 A 的应答去干 B 的事——而且**错得很安静**：界面照常渲染，只是
//  「大群进会话最后几条各显示两遍」「翻页途中被换窗」「停在首条未读被甩到最底并顺手把一万条标成已读」。
//  这些事故都出在这条分流上（见各在途标志在 IMChatWindowState.h 的注释）。
//
//  ⚠️ **判断顺序就是语义，别调**：非本会话 → 向下翻页 → 按读位点开窗 → 取最新一窗 → 其余（锚点必须等于
//  pendingAnchor）。前三路各有自己的在途标志，必须先于通用路认领，否则会被通用路的 `anchor != pendingAnchor`
//  误吞或误用。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMChatWindowRespRoute) {
    /// 不是本会话 / 不是我们等的那一帧（含迟到的、已被超时清掉在途标志的帧）：什么都不做、不清任何标志。
    IMChatWindowRespIgnore = 0,
    /// 向下翻页那一路，但窗口已被换到更早的一段（`loadedHi <= 0 || loadedHi < anchor`）→ 这帧已过期。
    /// 只清 pendingNewerAnchor，**不能**顺手改 atTail（那说的是另一段窗口的事）。
    IMChatWindowRespNewerStale,
    /// 向下翻页：把落库的更新一段接到窗口尾部。**以应答时的窗口末尾为准，不用 anchor**（请求发出时的末尾）。
    IMChatWindowRespNewerAppend,
    /// 进会话「按读位点开窗」：换成围绕读位点的一窗并**停在首条未读**——不贴底、不强制标已读。
    IMChatWindowRespEntryRewindow,
    /// 「要最新一窗」（anchor=0）：把窗口拉到尾段并贴底。
    IMChatWindowRespTailRewindow,
    /// 跳到最早：不看 anchorFound（锚点写死 1，1 号常常不是消息），落到落库后本地实际最早一条。
    IMChatWindowRespJumpEarliest,
    /// 跳转且服务端说找到了：落库后围绕锚点开本地窗口。
    IMChatWindowRespJumpOpen,
    /// 跳转且服务端明确说这条不存在/对我不可见：提示「原消息已被删除」。
    IMChatWindowRespJumpNotFound,
    /// 向上翻页：落库后从本地库取那一段接到顶部。
    IMChatWindowRespOlder,
};

/**
 @param convMatches          应答所属会话 == 当前页会话。
 @param anchor               应答回显的锚点（0 = 「要最新一窗」那一路）。
 @param anchorFound          服务端回的 anchor_found。
 @param pendingNewerAnchor   向下翻页在途位点（0=无）。
 @param pendingEntryAnchor   按读位点开窗在途位点（0=无）。
 @param pendingTail          「要最新一窗」在途。
 @param pendingAnchor        通用在途位点（跳转 / 向上翻页共用，0=无）。
 @param pendingIsJump        通用在途是跳转（YES）还是向上翻页（NO）。
 @param pendingJumpIsEarliest 这次跳转是「跳到最早」。
 @param loadedHi             **应答到达时**窗口内最大 conv_seq（无则 0）。只在向下翻页那一路用到。
 */
extern IMChatWindowRespRoute IMChatRouteWindowResp(BOOL convMatches,
                                                   int64_t anchor,
                                                   BOOL anchorFound,
                                                   int64_t pendingNewerAnchor,
                                                   int64_t pendingEntryAnchor,
                                                   BOOL pendingTail,
                                                   int64_t pendingAnchor,
                                                   BOOL pendingIsJump,
                                                   BOOL pendingJumpIsEarliest,
                                                   int64_t loadedHi);

NS_ASSUME_NONNULL_END
