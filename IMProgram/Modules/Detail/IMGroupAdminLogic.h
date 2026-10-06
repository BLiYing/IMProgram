//  IMGroupAdminLogic.h
//  群管理页「管理员 / 转让群组」的**纯逻辑**（计数口径 / 候选过滤 / 批量截断 / 错误文案）。
//  抽成无 UIKit 依赖的类方法，便于单测——见 IMProgramTests/IMGroupAdminLogicTests.m。
//  设计见 IMServer/docs/design/GROUP_ADMIN_TRANSFER_DESIGN.md §3 / §4。

#import <Foundation/Foundation.h>
#import "IMGroupInfo.h"

@class IMGroupMember;
@class IMUserCard;

NS_ASSUME_NONNULL_BEGIN

/// 一次最多添加几位管理员。后端 SetRole **每调一次发一条系统消息**且无批量接口，
/// 选 12 个人就是群里瞬间刷 12 条系统消息。要解掉这个限制得后端上 `PUT /groups/{id}/roles`
/// （合并成一条系统消息，设计文档 §4.2 P1）。
/// ⚠️ 这**不是**管理员数量上限——后端对管理员总数无任何约束，客户端假上限只是自欺（§7.1）。
FOUNDATION_EXPORT const NSUInteger IMGroupAdminMaxBatch;

/// 对某个成员**我能做的管理动作**（位掩码）。
typedef NS_OPTIONS(NSUInteger, IMGroupMemberAction) {
    IMGroupMemberActionNone         = 0,
    IMGroupMemberActionMakeAdmin    = 1 << 0, ///< 设为管理员（仅群主、对普通成员）
    IMGroupMemberActionRevokeAdmin  = 1 << 1, ///< 撤销管理员（仅群主、对管理员）
    IMGroupMemberActionTransfer     = 1 << 2, ///< 转让群主（仅群主）
    IMGroupMemberActionMute         = 1 << 3, ///< 禁言（对方当前未被禁言）
    IMGroupMemberActionUnmute       = 1 << 4, ///< 解除禁言（对方当前已被禁言）
    IMGroupMemberActionRemove       = 1 << 5, ///< 移出群聊（冷却档）
    IMGroupMemberActionRemoveAndBan = 1 << 6, ///< 移出并不再允许加入（永久）
};

/**
 成员管理**权限矩阵**——唯一出处（群资料页点成员的动作表、会话详情页成员行的左滑 / 长按菜单共用）。

 · 对自己：什么都没有。
 · 群主：对任何非自己的人——升/撤管理员依目标角色（member→可设管理员，admin→可撤销）、可转让群主、
   可禁言/解禁/移出。
 · 管理员：**只能管普通成员**（禁言/解禁/移出）；对管理员、群主无任何动作。
 · 普通成员：无任何动作。
 禁言 / 解禁二选一，由 `targetMuted` 决定；**禁言、移出的权限都是「严格高于对方」**（G2）。

 **跨端对读（2026-10-04）**：im-web `App.tsx` 的 `canManageMember`（非自己 且 群主，或 管理员对普通成员）与这里的「移出 / 禁言」
 口径逐条一致。im-android 我没找到同名的权限矩阵实现，**未核对**。
 这两份拷贝曾各写一遍且零测试；服务端才是最终裁判（越权会被拒），但客户端多给一个入口 = 用户点了才被拒。
 */
FOUNDATION_EXPORT IMGroupMemberAction IMGroupMemberActionsFor(IMGroupRole myRole, IMGroupRole targetRole,
                                                              BOOL isSelf, BOOL targetMuted);

/// 群管理页「开关组」的五个字段（`PUT /groups/{id}/settings` 整体上报的那五个）。
typedef NS_ENUM(NSInteger, IMGroupSettingField) {
    IMGroupSettingFieldJoinApproval = 0,
    IMGroupSettingFieldPermInvite,
    IMGroupSettingFieldPermEditInfo,
    IMGroupSettingFieldPermPin,
    IMGroupSettingFieldHistoryVisible,
};

@interface IMGroupAdminLogic : NSObject

/// 读 / 写本地群资料里的某个开关字段。
///
/// 存在的理由：开关提交是**乐观更新 + 整体上报五个字段**。失败回滚必须拿「改之前」的值——
/// 旧写法让 revert 去读 `self.group.xxx`，而 apply 早已把它改成新值，于是开关回不去，
/// 本地 group 还留着失败值，之后**任何**开关再提交都会把这个脏值一并上报。
+ (BOOL)valueOfField:(IMGroupSettingField)field inGroup:(IMGroupInfo *)group;
+ (void)setValue:(BOOL)value forField:(IMGroupSettingField)field inGroup:(IMGroupInfo *)group;

/// 群主（无则 nil）。
+ (nullable IMGroupMember *)ownerFromMembers:(nullable NSArray<IMGroupMember *> *)members;

/// 管理员列表，按 joinedAt 升序（与详情页成员表同口径；后端没存"何时被设为管理员"）。
+ (NSArray<IMGroupMember *> *)adminsFromMembers:(nullable NSArray<IMGroupMember *> *)members;

/// 群管理页「管理员」行的右值：0 → 「未设置」，>0 → 「N 人」。
+ (NSString *)adminCountTextForMembers:(nullable NSArray<IMGroupMember *> *)members;

/// 「添加管理员」的候选：排除群主 + 现有管理员 + 我自己（剩下的就是普通成员）。
+ (NSArray<IMGroupMember *> *)adminCandidatesFromMembers:(nullable NSArray<IMGroupMember *> *)members
                                                myUserID:(nullable NSString *)myUserID;

/// 「添加管理员」在**远端候选模式**（超级群）下的排除集：群主 + 现有管理员 + 我。
///
/// 与 adminCandidatesFromMembers: 是同一套口径的两种用法：普通群端上有全量成员，直接**筛出**候选；
/// 超级群端上只有治理集（群主+管理员），候选来自服务端搜索，只能**排除**。
/// 排除集正好只需要治理集 + 我——而那恰恰是超级群资料里有的（2026-09-01 服务端补下发）。
+ (NSSet<NSString *> *)adminExclusionsFromMembers:(nullable NSArray<IMGroupMember *> *)members
                                         myUserID:(nullable NSString *)myUserID;

/// 「转让群组」的候选：全体成员 − 我（管理员也可以选，后端不限）。
+ (NSArray<IMGroupMember *> *)transferCandidatesFromMembers:(nullable NSArray<IMGroupMember *> *)members
                                                   myUserID:(nullable NSString *)myUserID;

/// 成员 → 选人页的行模型。nickname 填成员的**群内公开名**（群昵称 > 昵称 > @username，绝不回退内部 ID），
/// 于是 IMUserCard.displayName 天然得到「备注 > 群昵称 > 昵称 > username」——与设计 §1.3 的口径一致。
+ (NSArray<IMUserCard *> *)pickerCardsFromMembers:(nullable NSArray<IMGroupMember *> *)members;

/// 批量添加的选中集截断到 IMGroupAdminMaxBatch（选人页已拦，这里是兜底）。
/// 还能再设几位管理员：总管理员数 ≤ IMGroupAdminMaxBatch（5，含现有），余量 = max(0, 5 − 现有管理员数)。
+ (NSUInteger)remainingAdminSlotsFromMembers:(nullable NSArray<IMGroupMember *> *)members;
+ (NSArray<NSString *> *)clampBatchSelection:(nullable NSArray<NSString *> *)selectedIDs;

/// 业务错误 → 中文 toast（设计 §4.4）。
/// **不 parse 服务端英文串**：100001 一个码在 SetRole/Transfer 里复用了三种语义，靠文案分支太脆，
/// 统一给「操作失败，请刷新后重试」；真正值得单独说的「TA 已不在群里」在发请求前用候选表本地判定。
+ (NSString *)toastForError:(nullable NSError *)error;

/// 批量结果 toast：全成功→「已添加 N 位管理员」；部分失败→「N 位已添加，M 位失败：…」；全失败→首条错误。
+ (NSString *)batchToastWithSucceeded:(NSUInteger)succeeded
                               failed:(NSUInteger)failed
                           firstError:(nullable NSString *)firstError;

@end

NS_ASSUME_NONNULL_END
