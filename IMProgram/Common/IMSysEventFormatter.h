//  IMSysEventFormatter.h
//  P3 i18n：群系统消息 / 系统通知单聊的 sys_event+sys_args → 按 App 当前语言本地化渲染。
//  权威事件表/算法见 docs/PROTOCOL.md §6.6、internal/store/types.go 的 SysEvent*/SysEvent*Notice 常量。

#import <Foundation/Foundation.h>

@class IMSysSegment;

NS_ASSUME_NONNULL_BEGIN

/// 群系统消息（content_type=system）：`sys_event`+`sys_args` → 按 App 当前语言重渲染的分段数组
/// （与 IMSysSegment/sysSegments 同构，可直接喂给 IMSystemCell.configureWithSegments:...）。
///
/// **不在代码里拼句子结构**：不手写"{actor} removed {target}"这种词序进 ObjC——本函数用"哨兵占位符
/// + 定位切分"实现：先把人名槽位替换成语言无关的哨兵串交给 IMLocalizedFormatArgs 走真实模板格式化，
/// 再在结果串里按哨兵**出现的实际位置**切分（而不是假定调用时传入的参数顺序），天然兼容任意语言的
/// 词序差异（中/英文模板对同一批参数换位是允许的，`%1$@`/`%2$@` 已经是这个协议的体现）。
///
/// - `event` 为空，或不在权威事件表里（未来新增但本端尚不认识）→ 返回 nil，调用方**必须**回退
///   现有 `sysSegments`/`content` 整句渲染路径（不改变这条回退）。
/// - 返回的分段里，人名槽位段的 `uid` 来自 `sysSegments` 里带 uid 的段（按出现顺序），`text` 是
///   **服务端字面**（未做本地显示名替换）——真正的本地显示名解析交给调用方现有的
///   `displayNameForUID` 回调在渲染时统一做（与老 sysSegments 路径同一份逻辑，不重复实现、
///   也因此天然会跟着备注变化实时刷新，不会因为这里提前烘焙进 text 而变成快照）。
/// - `member_invite` 事件例外（§1.3）：除 actor 外其余带 uid 的段是被邀请者，本函数会**提前**用
///   `displayNameForUID` 把它们解析成本地显示名、按当前语言的分隔符拼成一句纯文本代入模板
///   （多人各自可点的 UX 在这个场景下放弃，是刻意取舍，不是遗漏）。
FOUNDATION_EXPORT NSArray<IMSysSegment *> *_Nullable
IMSegmentsForSysEvent(NSString *_Nullable event,
                      NSDictionary<NSString *, NSString *> *_Nullable sysArgs,
                      NSArray<IMSysSegment *> *_Nullable sysSegments,
                      NSString *_Nonnull (^_Nullable displayNameForUID)(NSString *uid, NSString *fallback));

/// 系统通知单聊（sender=777000/IMSystemUserID，content_type=text）：`sys_event`+`sys_args` → 本地
/// 拼装的多行文本（`\n` 连接，无 uid/点击需求，直接喂给普通文本气泡）。
/// `event` 为空，或不是 `new_device_login`/`password_changed`/`device_kicked` 三者之一 → 返回 nil，
/// 调用方**必须**回退现有 `content`（服务端预生成的中文成品）。
FOUNDATION_EXPORT NSString *_Nullable
IMTextForNoticeSysEvent(NSString *_Nullable event, NSDictionary<NSString *, NSString *> *_Nullable sysArgs);

NS_ASSUME_NONNULL_END
