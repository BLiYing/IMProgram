//  IMUnreadBadge.h
//  未读角标的显示格式（IMServer/docs/design/OFFLINE_BACKLOG_DESIGN.md §6.1 U1）。
//
//  与 im-web 的 `src/unreadBadge.ts` **同一份口径**——同一个群在两端必须显示同一个数字，
//  各写一遍格式化迟早分叉，而分叉的表现是"两台设备上数字不一样"，用户第一时间会当成丢消息。
//
//  照搬 Telegram 的三档（`compactNumericCountString`）：<1000 原样、≥1000 显示 `1.2K`、
//  ≥100 万显示 `1.2M`。**它没有上限、没有 `+`**——我们此前一律 `99+`，那顶帽子来自服务端
//  "扫 999 条再数"的成本，不是产品口径；服务端换成覆盖索引计数后上限抬到万级，这里就能报真数了。
//
//  与 Telegram 唯一的不同：我们仍有一个服务端上限，撞上了才补 `+`（如 `10K+`）。
//  那个 `+` 是**诚实**——它说的是"至少这么多"，而不是把 342 谎报成 99+。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 数值紧凑化：1234 → `1.2K`，5000 → `5K`，1200000 → `1.2M`；n ≤ 0 返回 `0`。
extern NSString *IMCompactCount(NSInteger n);

/// 未读角标文案。capped=YES 表示服务端计数撞到上限（真实值 ≥ n），补一个 `+`。
/// n ≤ 0 返回空串，调用方据此不渲染角标。
extern NSString *IMUnreadBadgeText(NSInteger n, BOOL capped);

NS_ASSUME_NONNULL_END
