# iOS UI 配色与外观规范

> **三端共同规则以 `../../IMServer/docs/UI_COLOR.md` 为准**（语义令牌总表、文本层级、
> 页面/卡片/输入口径、聊天个性化、深色验收清单、新功能检查清单）。本文只写 IMProgram
> 的入口与 **iOS 平台特有**的约束。
>
> 代码唯一入口为 `IMTheme`，用户外观偏好唯一入口为 `IMAppearance`。
> Telegram 参考截图位于 `docs/telegram/skin-waiguan/`。

## 1. 入口与 iOS 特有原则

- 优先 `IMTheme` 语义令牌；仅系统标准控件可直接使用 `UIColor` 的动态语义色。
- 用户可调值（主题色、显示模式、壁纸、字号、气泡圆角、应用图标）一律经 `IMAppearance`，
  页面不得直接读写 `NSUserDefaults`。
- **`CALayer` 的 `CGColor` 不会自动跟随主题**：必须在外观通知或 `traitCollectionDidChange:`
  里重新赋值；也不得把动态 `UIColor` 的 `CGColor` 长期缓存而不更新。这是本端最容易漏的一条。

## 2. 标题栏与导航

- 标准页面使用系统导航栏，标题采用系统标题字体和 `textPrimary`。
- 返回按钮使用系统 `chevron.backward`，颜色为 `accent`。
- 右侧普通操作使用 `accent`；危险操作进入确认流程后使用 `danger`。
- 沉浸式照片头部允许白色返回按钮，但必须提供阴影或半透明深色承托，确保浅色照片上可见。
- 禁止页面自行固定导航栏为纯白或纯黑。
- **push 出去的页面不要用 `UITableViewController`**：注入的液态标题栏会被系统下移一截
  （同一坑踩过三次）。用普通 `UIViewController` + 手放 `UITableView`。

### 2.1 Liquid Glass（iOS 26+）

- 使用 Xcode 26 / iOS 26 SDK 时，标准 `UINavigationBar`、`UITabBarController`、
  `UISegmentedControl`、`UIAlertController`、菜单与 popover 交给 UIKit 自动获得 Liquid Glass，
  不得在其外层重复叠加玻璃。
- 自绘导航控件统一通过 `IMGlass.h` 创建：按钮使用
  `glassButtonConfiguration` / `prominentGlassButtonConfiguration`，自绘浮层使用 `UIGlassEffect`。
- `IMChatDetailViewController` 的沉浸式导航栏使用 `IMLiquidNavigationBar`（Swift）作为统一组件；
  Objective-C 页面只传递标题、副标题和操作回调，不在页面内重复绘制返回/标题胶囊。Swift 组件
  通过 `@objc` 暴露边界，保持现有 Objective-C 业务逻辑不迁移。
- 应用内菜单、Popover、ActionSheet 和确认弹窗优先使用 UIKit 系统呈现（`UIAlertController`、
  `UIContextMenuInteraction` 等）；iOS 26 由系统负责 Liquid Glass 材质、分组和按压动画，
  不得再用自绘 UIView 冒充系统弹窗。确需自定义内容的页面卡片，必须明确不是系统弹窗。
- iOS 15～25 没有 Liquid Glass API，统一降级为 UIKit 系统材质和系统按钮配置；禁止仿造
  iOS 26 的折射、融合或流体动画并冒充官方效果。
- Glass 属于导航和操作层，**不用于普通内容卡片、消息气泡或整页背景**；相邻操作应分组，避免
  glass-on-glass。内容卡片继续使用 `cardBackground` / `surfaceElevated`。
- 沉浸式自绘标题栏仍须把返回、居中标题（标题 + 副标题）和右侧操作拆为独立点击区域，
  并使用动态语义前景色，不能在浅色模式固定白色图标。
- 普通页面禁止为模仿截图而自绘整条导航栏：使用系统标题、系统图标式返回键与标准
  `UIBarButtonItem`，让 UIKit 把左按钮、居中标题和右按钮按语义分离/分组。只有头像形变等
  系统导航栏无法完成的沉浸式页面，才允许使用 `IMGlass.h` 自绘三个独立区域。
- 底部主导航在 iOS 18+ 使用 `UITab`；主功能使用默认 placement，搜索入口使用
  `UITabPlacementPinned`，从而在 iOS 26 形成"主 Tab Glass 组 + 右侧独立搜索 Glass"。
  iOS 15～17 使用标准 `viewControllers` 回退，禁止手工仿造新版折射效果。

## 3. 列表与卡片（iOS 落地方式）

- 普通设置页使用 `UITableViewStyleInsetGrouped`；"外观"等需要实时预览的沉浸式设置中心可使用
  `UIScrollView + UIStackView`，但仍须保持分组卡片、16 pt 页面边距和统一语义令牌
  （间距数值见跨端主文档 §4）。
- Cell 主背景使用系统表面色；选中态使用系统选中背景或 `accent` 的低透明度。
- 卡片圆角默认 `IMTheme.radiusCard`，连续圆角使用 `kCACornerCurveContinuous`。

## 4. 聊天个性化（iOS 落地方式）

- 内置主题：经典绿、海洋蓝、紫晶、深海。壁纸风格：涂鸦、渐变、纯色。
- 气泡圆角读 `IMAppearance.bubbleRadius`（6～24 pt），聊天正文读 `IMAppearance.chatFontSize`（14～22 pt）。
- 外观变更通过 `IMAppearanceDidChangeNotification` 实时刷新已打开的聊天页。
- **应用图标**只能切换预先打包的 Alternate Icons，不能运行时生成；图标选择器必须使用对应
  App Icon 的真实缩略资源，不得用 SF Symbol 或占位图冒充。（Web 无此能力。）
