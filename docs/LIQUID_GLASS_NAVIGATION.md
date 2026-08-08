# IMProgram Liquid Glass 导航栏规范

## 目标

IMProgram 使用 `IMLiquidNavigationBar` 作为统一的自定义导航栏。它隐藏 UIKit 默认 `UINavigationBar`，由 `IMMainNavigationController` 在每个 Tab 的导航栈顶部承载；详情页等需要沉浸式头部的页面也复用同一组件。这样返回按钮、标题、右侧操作和按压反馈保持一致，并避免系统返回按钮长按历史菜单。

组件在 iOS 26 使用可交互的 `UIGlassEffect`，旧系统使用 `UIBlurEffect` 兼容材质。按钮最小触控区域为 44pt，点击反馈由组件统一提供。

## 页面接入约定

1. 新页面必须通过 `IMMainNavigationController` push，禁止重新显示系统导航栏或另建一套顶部导航栏。
2. 页面标题设置 `viewController.title`；右侧入口设置 `navigationItem.rightBarButtonItem`。组件会把标题、图片、启用状态和点击事件映射到独立的 Glass 按钮。
3. 需要“取消/关闭”等左侧操作时设置 `navigationItem.leftBarButtonItem`；没有左侧项且不在根页面时自动显示统一返回按钮。根 Tab 页面默认不显示返回按钮。
4. 详情页的头像、标题和编辑操作可使用自己的布局，但必须使用 `IMLiquidNavigationBar`，不要直接创建 `UINavigationBar`。
5. 搜索、更多、加号等并列入口应使用彼此独立的 Glass 控件，不要再包一层共享圆角背景；每个控件保持至少 44pt 触控尺寸。
6. 模态页面若有独立导航容器，也应在其容器中安装同一组件，避免出现系统导航栏和自定义栏混用。

## 新页面检查清单

- [ ] 未调用 `setNavigationBarHidden:NO`，未创建 `UINavigationBar`。
- [ ] 标题和操作通过 `title` / `navigationItem` 暴露。
- [ ] 返回、关闭、编辑等按钮均由 `IMLiquidNavigationBar` 呈现。
- [ ] 浅色、深色和 iOS 26 Glass 状态下文字对比度可读。
- [ ] 交互控件触控区域不小于 44×44pt。

## 维护入口

统一实现位于 `IMProgram/Common/IMLiquidNavigationBar.swift`；导航栈接入位于 `IMProgram/App/IMMainTabBarController.m`。后续新增页面前先阅读本文档，优先扩展这两个入口而不是复制页面级导航代码。

## 待排期增强（Backlog，按排期节点实现）

### 中间标题改原生玻璃按钮（获系统"涌起放大"按压）
- **现状（已实现）**：聊天页中间标题可点——`IMLiquidNavigationBar` 在标题区盖了透明点击层 `titleButton`（仅 `showsTitleGlass=YES` 即聊天页可点，其他页穿透不拦截）；按下时 `setTitlePressed:` 把标题玻璃 + 主/副标题缩放到 `0.96` 做**缩放式**按压反馈；点击经可选 delegate `liquidNavigationBarDidTapTitle:` 回调，容器转发到当前页 `rightBarButtonItem` 的 action（＝与点右上角头像同逻辑，打开 `IMChatDetailViewController`）。
- **未尽**：标题本体是「磨砂视图 + 两个 label」而非原生玻璃按钮，拿不到 iOS 26 那种玻璃**涌起放大**动效，故用缩放近似。
- **增强方案（改动较大，待排期）**：把中间标题重构为**原生玻璃按钮**（`UIButton` + `UIButton.Configuration.glass()`，与返回/操作按钮同源），使其获得系统按压放大/聚合动画。难点：标题是主标题 + 副标题两行的自定义竖排布局（见 `layoutSubviews` 的 `titleY`/副标题槽位），需在玻璃按钮内承载双行内容且不破坏「有无副标题」二选一的竖向布局与宽度冻结逻辑。评估工作量后单独排期。
