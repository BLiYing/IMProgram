//  IMLiquidSegmentedControl.h
//  Liquid Glass 分段控件：与首页底部 TabBar 同源观感——玻璃底轨 + 可交互玻璃药丸滑块。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 玻璃分段控件。iOS 26 走官方 `UIGlassEffect`（经 IMGlass.h 统一入口），旧系统降级为
/// 系统材质模糊底轨 + 半透明填充药丸，观感与首页底部原生 Liquid Glass TabBar 一致。
///
/// **为什么不用 UISegmentedControl**：一旦用 `setBackgroundImage:forState:` 定制底轨/选中态，
/// 控件就退回**逐段绘制**的 legacy 路径（这也是系统要提供 dividerImage 的原因）——
/// 药丸的圆头端帽在窄段里被切成方角，且底轨自带圆角会让段与段之间露缝；
/// 底轨颜色也无法与 InsetGrouped cell 对齐。这些都曾据此反复返工，故改为自持玻璃控件。
@interface IMLiquidSegmentedControl : UIControl

/// 段标题。赋值后重建内部按钮；`selectedIndex` 越界时自动收敛到 0。
@property (nonatomic, copy) NSArray<NSString *> *titles;

/// 当前选中段。程序化赋值**不**发 `UIControlEventValueChanged`（与 UISegmentedControl 一致），
/// 仅用户点击才发；越界写入按 clamp 处理。
@property (nonatomic, assign) NSInteger selectedIndex;

/// 每段标题右侧的角标文案（与 titles 一一对应；空串 / 越界 = 不显示）。**不触发**选中变化。
/// muted 与 texts 一一对应：YES=灰色（静音会话的未读）。用于会话列表的文件夹 Tab 未读数。
- (void)setBadgeTexts:(NSArray<NSString *> *)texts muted:(nullable NSArray<NSNumber *> *)muted;

/// 底轨宽度 = min(各段宽度之和, 控件宽)，**居中**；段不再均分富余宽度（Tab 少时不再被拉成半屏一个）。
/// 对齐 Android `SegTabBar`（贴合内容、居中、放不下才横向滚动）。

/// 药丸相对底轨的四周内缩，默认 4。
@property (nonatomic, assign) CGFloat pillInset;

- (void)setSelectedIndex:(NSInteger)selectedIndex animated:(BOOL)animated;

/// 控件坐标系内某点落在哪一段（含滚动偏移）；不在任何段上返回 NSNotFound。用于长按某个 Tab 弹菜单。
- (NSInteger)segmentIndexAtPoint:(CGPoint)point;

@end

NS_ASSUME_NONNULL_END
