//  IMChatWindowState.h
//  聊天页**当前这一窗**消息的状态协作对象（见 IMServer/docs/design/MESSAGE_WINDOW_DESIGN.md §4，
//  行为在 IMChatViewController+Window.m）。
//
//  分页之前，聊天页的 `messages` 是"本会话全部消息"，进会话一次读全部。分页之后它变成
//  **一个可移动的窗口**，而窗口 = 内容（messages / seenConvSeqs）+ 边界（atTail / hasMoreAbove）
//  + 在途请求（pendingAnchor / pendingIsJump）。这七项是一个整体：谁改了内容不改边界，
//  就会出现"明明还有更早的却翻不动"或"翻到顶了还在发请求"。放在一个袋子里是为了让它们一起被想到。
//
//  同时也遵 CODING_STYLE §7：新状态归协作对象自持，不堆进 IMChatViewController+Private.h
//  共享类扩展（那里有 >72 个 @property 的硬预算，理由同 IMChatSearchState.h）。
//  纯状态容器，无行为。

#import <Foundation/Foundation.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMChatWindowState : NSObject

/// 当前窗口内的消息（**不是**本会话全部消息），按聊天页显示序升序。
@property (nonatomic, strong) NSMutableArray<IMMessageModel *> *messages;

/// 本窗内已有的 conv_seq，用于「推送 + 同步」重复投递的去重。
/// **跟着窗口重建**，不是"本页见过的全部 seq"——留着旧窗的 seq 会让那些消息再来时被当重复丢掉。
@property (nonatomic, strong) NSMutableSet<NSNumber *> *seenConvSeqs;

/// 窗口是否含本地最新一条。NO=用户正在看历史：新消息只落库不上屏、↓N 计数改由本地库出。
@property (nonatomic, assign) BOOL atTail;

/// 窗口上方是否可能还有更早的（本地库或服务端）。翻到会话真正开头时置 NO。
@property (nonatomic, assign) BOOL hasMoreAbove;

/// 已发出的 window_req 锚点（0=无在途请求）。非 0 即"正在等服务端开窗"，据此防重入。
@property (nonatomic, assign) int64_t pendingAnchor;

/// 在途请求是「跳到某条」（YES，回来要滚过去并高亮）还是「向上翻一页」（NO，回来接到顶部）。
/// 两者的 window_resp 形状完全相同，不记这一位就分不清该怎么用。
@property (nonatomic, assign) BOOL pendingIsJump;

/// 进会话「按读位点开窗」（anchor=entryReadSeq）在途的那个位点（0=无）。
///
/// 与 pendingTail **必须分开**：两者回来后的动作正相反——按读位点开窗是为了把未读分割线
/// 那一段取下来、然后**停在首条未读**；取最新一窗是为了贴底。混用一个标志就会出现
/// "本来要停在未读处，结果被甩到最底并顺手把一万条标成已读"（2026-09-03 实测）。
@property (nonatomic, assign) int64_t pendingEntryAnchor;

/// 是否有一次「要最新一窗」（anchor=0）在途：进会话发现本地不齐**且无未读**、或点 ↓ 时发出。
/// **不能复用 pendingAnchor**——anchor=0 与"无在途请求"是同一个值，混在一起会让
/// 向上翻页的防重入判据失灵（每次滚到顶都重复发请求）。
@property (nonatomic, assign) BOOL pendingTail;

@end

NS_ASSUME_NONNULL_END
