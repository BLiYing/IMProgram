//  IMSearchEntryHeader.h
//  页顶「点按式」搜索入口（消息页 / 通讯录页共用）：规格与 IMLiquidNavigationBar searchMode 输入框一致——
//  44pt 玻璃胶囊（IMGlassEffectView + kIMSearchFieldCornerRadius、continuous）+ 放大镜 + 占位文字。
//  它只是入口、不承载输入：点击由 target/action 处理（通常 push 全局搜索页）。作 tableHeaderView 用（frame 布局）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 搜索入口头部视图的高度（胶囊 44 + 上下各 6）。
FOUNDATION_EXPORT const CGFloat kIMSearchEntryHeaderHeight;

/// 造一个点按式搜索入口（整条头部可点）。width = 当前表宽；之后随表宽自适应（胶囊 autoresizing）。
UIView *IMMakeSearchEntryHeader(CGFloat width, NSString *placeholder, id target, SEL action);

NS_ASSUME_NONNULL_END
