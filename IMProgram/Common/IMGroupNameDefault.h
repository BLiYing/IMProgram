//  IMGroupNameDefault.h
//  建群默认群名：把「我 + 已选成员」的**公开名**拼成一个候选群名（用户可改）。
//
//  纯函数单独成文件，是因为 Web 有同名同规则的 `src/groupName.ts`——两端必须逐字同规则，
//  否则同一批人在两个端上建群会得到不同的默认群名。抽出来才好用 XCTest 钉死。
//
//  ⚠️ **只能用公开名（昵称），绝不能用备注**：群名会随建群请求发到服务端、写进系统消息
//  「X 创建了群聊「…」」、出现在**全群每个人**的会话列表里。拿备注拼群名 = 把我给对方起的
//  私下称呼广播给全群。这条是 docs/UI.md 的隐私红线（合并转发卡片标题曾栽过同一个坑：
//  标题取了「备注优先」的 `IMUserCard.displayName`，把「老王」泄露给了对方）。
//  所以本文件的入参是 nickname/username/userID 三件套，**不接受** IMUserCard——
//  免得有人顺手传 `card.displayName` 进来。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 群名上限的**内置默认**（rune，30）。实际限长运行中由后台「群名最大长度」下发，
/// 业务页一律读 `IMServerConfigStore.groupNameMaxLen`（老服务端缺字段时它回落到 30）；这里只留给纯函数单测作参数。
extern const NSUInteger IMMaxGroupNameLength;

/// 群名输入框是否放行这次改动：next 不超 maxLen 放行；**比 current 短**也放行
/// （上限被调小后，已超长的旧群名要能往短里删，否则删除键都按不动）。
BOOL IMGroupNameEditAllowed(NSString *_Nullable current, NSString *_Nullable next, NSUInteger maxLen);

/// 群名输入框 EditingChanged 后是否要截断（shouldChange 在拼音组合态一律放行，超长由这里收口）：
/// 组合态（marked）不截——拼音字母还没上屏，截了就组不出词；
/// 只在**变长了**（runes(text) > previousRunes）且超上限时截——上限调小前已超长的旧群名，往短里删时不能被一刀截掉。
BOOL IMGroupNameShouldTruncate(NSUInteger previousRunes, NSString *_Nullable text, NSUInteger maxLen, BOOL marked);

/// 编辑态截断：按 rune 截到 maxLen，再退到字形簇边界（不把「👍🏽」、国旗等组合字符切成半个）。结果恒 ≤ maxLen rune。
NSString *IMGroupNameTruncateForEditing(NSString *_Nullable text, NSUInteger maxLen);

/// 群公告 / 群简介多行编辑页（IMGroupTextEditViewController）一次编辑后的收口：与群名同一套规则
/// （按码点计、组合态不截、只在变长且超限时截、截在完整字符边界）。要截则返回截后的文本，不用截返回 nil。
NSString *_Nullable IMGroupTextLimitedAfterEdit(NSUInteger previousRunes, NSString *_Nullable text, NSUInteger maxLen, BOOL marked);

/// 按 rune（Unicode 码点）数长度：与服务端 `len([]rune(name))` 同口径（非 UTF-16 长度）。
NSUInteger IMGroupNameRuneLength(NSString *_Nullable s);

/// 按 rune 截断到 n 个码点（不补省略号；不会切开代理对）。
NSString *IMGroupNameTruncateToRunes(NSString *_Nullable s, NSUInteger n);

/// 一个人的**公开名**：昵称 → @用户名 → 内部 ID 兜底。全空返回空串。
NSString *IMPublicUserName(NSString *_Nullable nickname, NSString *_Nullable username, NSString *_Nullable userID);

/// 默认群名：names 按顺序用「、」连接，**放不下的名字直接不要**（结果恒 ≤ maxLen）。
/// 调用方负责把**自己排在第一位**（建群人是群主，群名以他打头）。
/// 空名字会被跳过；全空返回 ""（调用方据此让「创建」保持置灰）。
///
/// **不补省略号**（2026-09-05 用户要求）：这是个可改的**候选**群名，不是被裁短的完整名——
/// 结尾挂个「…」既占掉一个可用字，又会被头像圈的「取末两字」规则拿去显示成「2…」。
NSString *IMDefaultGroupName(NSArray<NSString *> *names, NSUInteger maxLen);

NS_ASSUME_NONNULL_END
