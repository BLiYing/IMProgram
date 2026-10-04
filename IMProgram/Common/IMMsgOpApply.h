//  IMMsgOpApply.h
//  消息操作（msg_op：撤回 / 编辑 / 置顶 / 为所有人删除）「帧 → 终值 → 内存模型 → 横幅」这一路的纯逻辑，
//  从 IMSocketManager 的 applyMsgOpPayload: 与聊天页 onMsgOpApplied: 抽出。
//
//  服务端侧的对应实现是 `internal/gateway/hub_msgop*.go`（事件行 content 与广播帧只由 `msgOpEvent`/
//  `msgOpFrame` 构造）；协议见 IMServer/docs/PROTOCOL.md。置顶横幅的「消息被移除/撤回就重拉」三端同口径
//  （SYMMETRY 登记 PinnedBanner）。
//
//  **三端实现 2026-10-04 对读过**（im-web `sdk/imSdk.ts` 的 `applyMsgOp` + `localStore.web.ts` 的 `applyMsgOpLocal`；
//  im-android `data/MessageRepository.kt` 的 `applyMsgOp`）。要一致的是：delete=物理移除不显墓碑、recall=保留行显墓碑、
//  pin 的取消与置顶同一个 op。**已知分歧（服务端不会触发，没有对齐）**：
//   · `pinned` 字段缺失：iOS=取消 / Web=当置顶（`!== false`）/ Android=不变（`?: return`）。服务端 `Pinned` 恒下发（非 omitempty）。
//   · 编辑帧缺 `content`：iOS、Web 把正文改成空串 / Android 保留原文。服务端 `Content` 是 omitempty，空串编辑本应被拒。
//   · 撤回/编辑时刻：iOS、Web 取本地时钟 / Android 取服务端 `timestamp`。三端都只把它当「>0 即已撤回/已编辑」的标志用，不影响显示。
//   · **Android 编辑不清 `mentionSpans`**（iOS、Web 都清）：Android 靠 `Mention.validSpans` 只校验偏移处是否为 `@`，
//     Web 注释写明这一层兜底挡不住「新正文同偏移碰巧有 @ → 高亮并点进另一个人的资料页」。读码发现，未复现，已记入 TEST_DEBT。
//
//  这条路错得**很安静**：撤回/编辑/置顶的显示态错了界面照常渲染，只是
//  「取消置顶被当成置顶」「编辑后 @ 高亮错位」「撤回后横幅继续指向墓碑」。所以抽出来按错法钉。

#import <Foundation/Foundation.h>

@class IMMessageModel;
@class IMPinnedMessage;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMMsgOpKind) {
    IMMsgOpKindUnknown = 0, ///< op 不认识：忽略不崩（但回执 client_msg_id 仍要收）
    IMMsgOpKindDelete,      ///< 为所有人删除：收端物理移除，不走 patch
    IMMsgOpKindRecall,
    IMMsgOpKindEdit,
    IMMsgOpKindPin,
};

/// 一条 msg_op 帧（实时帧或 sync 的 op 事件行负载）解析后的**终值**。
@interface IMMsgOpPatch : NSObject
@property (nonatomic, assign, readonly) IMMsgOpKind kind;
@property (nonatomic, copy, readonly) NSString *convID;
@property (nonatomic, assign, readonly) int64_t targetConvSeq;
/// 我方操作成功回执的 client_msg_id（用来从在途操作集合里摘掉）。
@property (nonatomic, copy, readonly, nullable) NSString *clientMsgID;
/// 撤回操作者 uid。
@property (nonatomic, copy, readonly, nullable) NSString *by;
/// >0 才有意义；0 = 本 op 不涉及。
@property (nonatomic, assign, readonly) int64_t recalledAt;
@property (nonatomic, assign, readonly) int64_t editedAt;
@property (nonatomic, copy, readonly, nullable) NSString *editedContent;
/// **0 = 本 op 不涉及；-1 = 取消置顶（通知数据层清零）；>0 = 置顶时刻。**
@property (nonatomic, assign, readonly) int64_t pinnedAt;

/**
 解析一条 msg_op 负载。`convID` 缺失/空、`target_conv_seq` 非正 → 返回 nil（整条丢弃）。
 op 不认识 → 返回 kind=Unknown 的对象（不是 nil：clientMsgID 仍要用来收回执）。

 @param nowMillis 本地时钟，仅作缺省：撤回/编辑用它当时刻；置顶优先取服务端 `timestamp`（多端一致），缺省才用它。

 ⚠️ **置顶必须看 `pinned` 字段**：取消置顶与置顶是同一个 op。字段缺失按「取消」处理（pinnedAt=-1），
 绝不误当置顶——缺字段=取消比缺字段=置顶安全，取消置顶才不会残留已置顶态（G0 接横幅时踩过）。
 */
+ (nullable instancetype)patchFromPayload:(NSDictionary *)payload nowMillis:(int64_t)nowMillis;

/// 落库成功后广播给 UI 的 userInfo（IMSocketDidApplyMsgOpNotification）：**只带与库一致的字段终值**，
/// 收端逐字段应用、不再解读 op/pinned 协议细节。pinnedAt 的 -1（清零）在此映射为 0（=取消置顶）。
/// 只对 Recall/Edit/Pin 有意义。
- (NSDictionary *)appliedUserInfo;
@end

/// 把 `appliedUserInfo` 的终值应用到内存里的一条消息（聊天页就地更新）：
/// 撤回 → recalledAt/recalledBy；编辑 → editedAt/content，并**清掉 mentionSpans**（偏移相对原文，正文一改全错位；
/// 渲染自动回落到按昵称扫文本，与编辑前一致）；置顶 → pinnedAt（0=取消置顶）。userInfo 里没有的字段不动。
extern void IMChatApplyMsgOpToMessage(IMMessageModel *message, NSDictionary *appliedUserInfo);

/// 一条 msg_op 到达后，置顶横幅该怎么办。
typedef struct {
    /// 撤回命中横幅里的置顶项：**先本地剔除再重拉**——重拉是 best-effort（拉失败保留旧集合），
    /// 弱网下只靠它会让横幅继续挂着一条已撤回消息的预览。
    BOOL dropTargetLocally;
    /// 要重拉横幅：pin/unpin 必拉；撤回/编辑命中横幅里的置顶项也要拉（服务端置顶列表已剔除撤回、编辑改文案）。
    BOOL reload;
} IMChatMsgOpBannerAction;

extern IMChatMsgOpBannerAction IMChatMsgOpBannerPlan(NSDictionary *appliedUserInfo,
                                                     NSArray<IMPinnedMessage *> *pinnedItems);

/// 横幅置顶项里去掉 `convSeq == targetConvSeq` 的（保持原序）。
extern NSArray<IMPinnedMessage *> *IMChatPinnedItemsDroppingSeq(NSArray<IMPinnedMessage *> *items,
                                                                int64_t targetConvSeq);

NS_ASSUME_NONNULL_END
