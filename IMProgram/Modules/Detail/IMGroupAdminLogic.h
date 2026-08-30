//  IMGroupAdminLogic.h
//  群管理页「管理员 / 转让群组」的**纯逻辑**（计数口径 / 候选过滤 / 批量截断 / 错误文案）。
//  抽成无 UIKit 依赖的类方法，便于单测——见 IMProgramTests/IMGroupAdminLogicTests.m。
//  设计见 IMServer/docs/design/GROUP_ADMIN_TRANSFER_DESIGN.md §3 / §4。

#import <Foundation/Foundation.h>

@class IMGroupMember;
@class IMUserCard;

NS_ASSUME_NONNULL_BEGIN

/// 一次最多添加几位管理员。后端 SetRole **每调一次发一条系统消息**且无批量接口，
/// 选 12 个人就是群里瞬间刷 12 条系统消息。要解掉这个限制得后端上 `PUT /groups/{id}/roles`
/// （合并成一条系统消息，设计文档 §4.2 P1）。
/// ⚠️ 这**不是**管理员数量上限——后端对管理员总数无任何约束，客户端假上限只是自欺（§7.1）。
FOUNDATION_EXPORT const NSUInteger IMGroupAdminMaxBatch;

@interface IMGroupAdminLogic : NSObject

/// 群主（无则 nil）。
+ (nullable IMGroupMember *)ownerFromMembers:(nullable NSArray<IMGroupMember *> *)members;

/// 管理员列表，按 joinedAt 升序（与详情页成员表同口径；后端没存"何时被设为管理员"）。
+ (NSArray<IMGroupMember *> *)adminsFromMembers:(nullable NSArray<IMGroupMember *> *)members;

/// 群管理页「管理员」行的右值：0 → 「未设置」，>0 → 「N 人」。
+ (NSString *)adminCountTextForMembers:(nullable NSArray<IMGroupMember *> *)members;

/// 「添加管理员」的候选：排除群主 + 现有管理员 + 我自己（剩下的就是普通成员）。
+ (NSArray<IMGroupMember *> *)adminCandidatesFromMembers:(nullable NSArray<IMGroupMember *> *)members
                                                myUserID:(nullable NSString *)myUserID;

/// 「转让群组」的候选：全体成员 − 我（管理员也可以选，后端不限）。
+ (NSArray<IMGroupMember *> *)transferCandidatesFromMembers:(nullable NSArray<IMGroupMember *> *)members
                                                   myUserID:(nullable NSString *)myUserID;

/// 成员 → 选人页的行模型。nickname 填成员的**群内公开名**（群昵称 > 昵称 > @username，绝不回退内部 ID），
/// 于是 IMUserCard.displayName 天然得到「备注 > 群昵称 > 昵称 > username」——与设计 §1.3 的口径一致。
+ (NSArray<IMUserCard *> *)pickerCardsFromMembers:(nullable NSArray<IMGroupMember *> *)members;

/// 批量添加的选中集截断到 IMGroupAdminMaxBatch（选人页已拦，这里是兜底）。
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
