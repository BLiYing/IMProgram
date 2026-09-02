#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 连上时「顺手补齐」与「留成缺口」的分水岭（条）。三端同值，见 IMServer/docs/CHAT_UX.md §2。
extern const int64_t IMSyncMaxGap;

/// 离线积压的连接级状态（IMServer/docs/design/OFFLINE_BACKLOG_DESIGN.md §4.4/§4.5/§4.8）。
///
/// 管四件事，都是「跟着这条连接活、断了就该清」的东西：
///   ① 哪些会话是超级群（决定 `max_gap`：超级群恒 0，正文只在打开会话时按需取）；
///   ② 各会话服务端最新位点 `head` 的快照（↓N 计数与"本地齐不齐"的上界）；
///   ③ 哪些会话本地有缺口（收到过 `too_long`）；
///   ④ 待上报的 `delivered` 回执（按会话取最大位点，合批成一帧）。
///
/// **为什么抽成独立对象**：这些状态原本散在 IMSocketManager 的 ivar 里，而那个文件已经触到
/// 体量红线（CODING_STYLE §7）。更要紧的是它们是一组**纯簿记逻辑**——合批取最大值、
/// 缺口标记的置位与消位、max_gap 的取值——正是最该被单测钉住、也最容易在 socket 回调里
/// 被写错的部分（写错的表现不是崩溃，是"少收了消息但没人发现"）。
///
/// **线程约定**：本类**不自带锁**，由调用方保证串行——IMSocketManager 全部在其内部串行队列上调用。
/// 加锁反而会掩盖"在错误的队列上碰状态"这类真正的 bug。
@interface IMBacklogTracker : NSObject

/// 标记/取消某会话为超级群。两个方向都要生效：群可能被降级、或某次列表标记有误，
/// 只置不清会让一次错误标记永久粘住（超级群标记决定 max_gap，粘错 = 永不自动补拉）。
- (void)setSuper:(BOOL)isSuper forConv:(NSString *)convID;

/// 该会话本次 sync 允许补拉的最大积压深度：超级群 0（永不自动补），其余 IMSyncMaxGap。
- (int64_t)maxGapForConv:(NSString *)convID;

/// 记录服务端最新位点（单调，只前进）。乱序到达的旧快照不得把它拉回去，
/// 否则"本地齐不齐"的判定会来回抖。
- (void)noteHead:(int64_t)head forConv:(NSString *)convID;
- (int64_t)headForConv:(NSString *)convID;

/// 缺口标记：收到 `too_long`（或 bump 显示本地落后）时置位；追平后消位。
/// 缺口只会收窄不会扩大，所以消位条件必须是"确实追平了"，不能只看单页拉成功。
- (void)markGapForConv:(NSString *)convID;
- (void)clearGapForConv:(NSString *)convID;
- (BOOL)hasGapForConv:(NSString *)convID;

/// 排队一个 delivered 回执（同会话只留最大位点）。返回 YES 表示**本次需要安排一次 flush**
/// （调用方据此只排一个定时器，而不是每条消息各排一个）。
- (BOOL)queueReceiptForConv:(NSString *)convID upTo:(int64_t)convSeq;

/// 取出并清空待上报回执，逐会话回调一次（conv_id → 最大位点）。
- (void)drainReceipts:(void (^)(NSString *convID, int64_t upTo))emit;

/// 清空全部状态（切账号 / 断开）。**必须清**：同一个 conv_id 在两个账号下可见范围不同，
/// 缺口标记与 head 快照串了就是错的。
- (void)reset;

@end

NS_ASSUME_NONNULL_END
