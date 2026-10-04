//  IMChatReadPosition.h
//  进会话定位与「可见即读」的两个纯判断（从 IMChatViewController+Position 抽出）。
//
//  这两条错得**很安静**，而后果是**清掉用户的未读**：首条未读找错 → 进会话被锚到错误的位置 →
//  随后「可见即读」把读位点推进到视口里最大的 conv_seq，**未读被误清**（user13028 实测：十万条未读，
//  打开即清零，read_position 0 → 109820）。所以口径必须与服务端一致、且别越界。

#import <Foundation/Foundation.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

/**
 首条未读所在下标：窗口里 `conv_seq > entryReadSeq` 的第一条「对端」且**计入未读**的消息；找不到返回 -1。

 **必须与服务端未读口径一致**（M4-8）：服务端 unreadCount 排除本人发的、msg_op 事件行与 system 系统消息。
 若只按「不是我发的」找，会把分割线 / 进会话锚点定位到不计未读的系统行——表现为「以下为 N 条新消息」
 下方实际多出几行（群改名、入群留痕都会触发）。

 @param entryUnread  进会话时服务端给的真实未读数；<=0 直接返回 -1（没有未读就别猜）。
 */
extern NSInteger IMChatFirstUnreadIndex(NSArray<IMMessageModel *> *messages,
                                        NSInteger entryUnread,
                                        int64_t entryReadSeq,
                                        NSString *_Nullable myUID);

/// 视口内可见行对应消息的最大 conv_seq；无可见行 / 全是待发件（conv_seq<=0）返回 0。
/// 行号越界的直接跳过（表格刷新瞬间 indexPathsForVisibleRows 可能比数据源新）。
/// 直接收 `indexPathsForVisibleRows`：滚动路径每个 tick 都会调，不能为了传参再装箱一份数组。
extern int64_t IMChatMaxSeqOfRows(NSArray<IMMessageModel *> *messages, NSArray<NSIndexPath *> *_Nullable visibleRows);

NS_ASSUME_NONNULL_END
