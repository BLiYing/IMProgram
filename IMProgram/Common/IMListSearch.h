//  IMListSearch.h
//  列表页「搜一下」的两件共用小事：**统一外观的搜索框** + **统一口径的子串匹配**。
//
//  为什么单开一个文件：转发选择、选好友（建群/邀请）、@提及面板三处都要"顶部一个框、
//  按显示名/uid 收窄列表"。各写各的会漂移成三套——占位文案不一、有的匹配 uid 有的不匹配、
//  有的忘了 trim。这里收成一处，新页面接两行即可。
//
//  **匹配口径**：大小写不敏感子串，命中任一字段即算命中；查询词两端空白先裁掉；空查询恒命中
//  （调用方据此可以不写分支）。拼音首字母匹配需额外索引，本期不做——中文直接键入汉字即可命中。
//
//  **隐私提醒**：好友备注可以作为匹配字段传进来（搜索是纯本地的），但备注**不能**因此进入
//  任何会发出去的内容，见 docs/UI.md「备注 · 隐私红线」。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 建一个各页统一外观的搜索框（minimal 风格，适合直接挂 tableHeaderView）。
FOUNDATION_EXPORT UISearchBar *IMListSearchBarMake(CGFloat width, NSString *placeholder,
                                                   id<UISearchBarDelegate> _Nullable delegate);

/// 搜索框的**表头容器**：把 bar 托在一个定高（56）容器里居中，作 tableHeaderView 用。
///
/// 为什么不直接把 UISearchBar 当 tableHeaderView：它的 frame 宽度在 `viewDidLoad` 那一刻就被写死成
/// `view.bounds.size.width`，而 UIKit **不保证**替你把 tableHeaderView 的宽度跟到表格的真实宽度上
/// （安全区、右侧 A–Z 索引尺、旋转、iPad 分屏都会让两者对不上）。宽度对不上时 header 仍从 x=0 左对齐，
/// 于是整个搜索框看起来左右都偏了（用户 2026-08-30 报的选好友页）。容器用约束托 bar，宽度由
/// `IMListSearchHeaderSyncWidth` 在每次布局时对齐表格。
FOUNDATION_EXPORT UIView *IMListSearchHeaderMake(UISearchBar *bar);

/// 在 `viewDidLayoutSubviews` 里调用：把 header 宽度对齐表格并让表格重新采纳（宽度没变则什么都不做，
/// 故不会自激循环）。改完 frame **必须重新赋值 tableHeaderView**，否则表格不会按新尺寸重排。
FOUNDATION_EXPORT void IMListSearchHeaderSyncWidth(UIView *_Nullable header, UITableView *_Nullable table);

/// 规整查询词（裁两端空白）。返回空串表示"没有在搜"，调用方可据此直接用全量列表、免遍历。
FOUNDATION_EXPORT NSString *IMListSearchNormalizedQuery(NSString *_Nullable raw);

/// fields 里任一字段包含 query（大小写不敏感）即命中。query 为空/全空白恒返回 YES。
/// fields 允许含 nil/空串（跳过），调用方不必自己判空。
FOUNDATION_EXPORT BOOL IMListSearchMatches(NSString *_Nullable query,
                                           NSArray<NSString *> *_Nullable fields);

NS_ASSUME_NONNULL_END
