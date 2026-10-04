//  IMChatInbound.h
//  聊天页「收到一条消息怎么处置」与「内存里怎么排序」的判据（从 IMChatViewController+Socket 抽出的纯函数）。
//
//  与 IMDatabase 的 `kIMMessageOrderAsc`、im-web 的渲染排序、Android 的 `MessageOrder.kt`
//  **同一份口径**（IMServer/docs/SYMMETRY.md「消息显示序」三条登记）。
//  抽成纯函数的理由：这两件事判错了**都不报错**——顺序错 = 用户以为没收到新消息，处置错 = 丢消息或重复上屏。

#import <Foundation/Foundation.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

/**
 消息显示序（**内存侧唯一比较器**）：**时间戳主排**；同一毫秒时 conv_seq=0（待发/失败）视为 +∞ 垫底，
 收到的（conv_seq>0）在前。等价 im-web 的 `convSeq || MAX_SAFE_INTEGER`。

 ⚠️ 「conv_seq=0 垫底」**只在同一毫秒内成立**。写成「conv_seq=0 一律排最后」会让被拒收的消息
 （永远 conv_seq=0）永久钉在最底部，之后收到的消息全插到它上面——用户滚到底只见旧的失败消息、
 以为新消息没收到（2026-08-05 事故，DB 与内存两处各写了一遍所以修了两次）。
 */
extern NSComparisonResult IMChatMessageOrder(IMMessageModel *a, IMMessageModel *b);

/// 把 `incoming` 直接尾插到以 `last` 结尾的有序数组后，是否还需要重排一次。
/// 判定口径与 `IMChatMessageOrder` **严格一致**（两者必须同改；单测逐对对拍）。
/// `last` 为 nil（空窗口）时不需要。
extern BOOL IMChatInsertNeedsSort(IMMessageModel *_Nullable last, IMMessageModel *incoming);

/// 一条实时/补拉到的消息，对「当前打开的聊天页」该怎么处置。
typedef NS_ENUM(NSInteger, IMChatInboundDisposition) {
    /// 不是本会话：不在此页显示（已落库）。
    IMChatInboundDropOtherConv = 0,
    /// 本窗已有这条（按 conv_seq 去重），且是带真实字节数的 file：不重复插入，但要回填元数据。
    IMChatInboundDedupBackfillFile,
    /// 本窗已有这条：直接丢弃。
    IMChatInboundDedupDrop,
    /// 窗口不在末尾（用户在看历史）：只落库不上屏，否则最新消息会接在几个月前的历史后面。
    IMChatInboundDbOnlyHistoryWindow,
    /// conv_seq 不高于窗口末尾：只落库不上屏，否则按时间序会插进窗口中间（3 万条实测的坑：
    /// 跳到比同步游标更深的历史后，后台补拉继续送 12001、12002…）。
    IMChatInboundDbOnlyBelowTail,
    /// 尾插上屏。
    IMChatInboundAppend,
};

/**
 入站处置。**判断顺序就是语义，别调**：非本会话 → 去重 → 窗口不在末尾 → 低于窗口末尾 → 上屏。

 @param convMatches    消息所属会话 == 当前页会话。
 @param convSeq        消息 conv_seq；<=0（待发/未上号）不参与去重与「低于末尾」判断，永远只看窗口是否在末尾。
 @param alreadyInWindow 本窗 seenConvSeqs 已含此 conv_seq（仅 convSeq>0 时有意义）。
 @param isFileWithSize 内容类型是 file 且 fileSize>0（去重命中时决定是否回填元数据）。
 @param atTail         窗口当前贴着会话末尾。
 @param maxInMemoryConvSeq 窗口内最大 conv_seq（无则 0）。
 */
extern IMChatInboundDisposition IMChatInboundDispose(BOOL convMatches,
                                                     int64_t convSeq,
                                                     BOOL alreadyInWindow,
                                                     BOOL isFileWithSize,
                                                     BOOL atTail,
                                                     int64_t maxInMemoryConvSeq);

NS_ASSUME_NONNULL_END
