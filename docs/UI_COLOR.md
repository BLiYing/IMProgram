# IMProgram UI 配色与外观规范

> 本文是 iOS 新增/修改 UI 的强制约束。代码唯一入口为 `IMTheme`，用户外观偏好唯一入口为
> `IMAppearance`。Telegram 参考截图位于 `docs/telegram/skin-waiguan/`。

## 1. 基本原则

- 使用“语义令牌”，禁止在业务页面散落 RGB/Hex 或固定黑白色。
- 优先 `IMTheme`；仅系统标准控件可直接使用 `UIColor` 的动态语义色。
- 默认显示模式为“跟随系统”，同时支持强制浅色和强制深色。
- 外观选择存储在本机，不属于账号数据；退出登录后保留。
- 新增外观项必须同时处理：持久化、实时通知、重启恢复、浅色、深色。
- 给 `CALayer` 的 `CGColor` 不会自动跟随主题，必须在外观通知或
  `traitCollectionDidChange:` 中重新赋值。

## 2. 语义颜色

| 场景 | 使用值 | 规则 |
|---|---|---|
| 品牌操作、链接、选中态 | `IMTheme.accent` | 随聊天主题变化 |
| 页面背景 | `IMTheme.pageBackground` | 导航内容、普通页面 |
| 分组页面背景 | `IMTheme.groupedBackground` | 设置、表单、分组列表 |
| 分组卡片背景 | `IMTheme.cardBackground` | 浅色白、深色深灰，始终与分组页面区分 |
| 输入栏、附件面板、一级表面 | `IMTheme.surface` | 与页面形成一层层级 |
| 浮层、嵌套卡片 | `IMTheme.surfaceElevated` | 不连续叠加超过两层 |
| 标题、正文 | `IMTheme.textPrimary` | 保证最高可读性 |
| 副标题、时间、说明 | `IMTheme.textSecondary` | 不承载关键操作 |
| 占位、禁用辅助文字 | `IMTheme.textTertiary` | 禁止用于正文 |
| 分割线 | `IMTheme.separator` | 0.5～1 pt |
| 删除、退出、失败 | `IMTheme.danger` | 不随主题色变化 |
| 未读徽标 | `IMTheme.unreadBadge` | 固定蓝色，与在线/已读绿区分 |

白色只允许用于有确定深色底的图标、头像文字和媒体遮罩；黑色只允许用于遮罩透明层。

## 3. 标题栏与导航

- 标准页面使用系统导航栏，标题采用系统标题字体和 `textPrimary`。
- 返回按钮使用系统 `chevron.backward`，颜色为 `accent`。
- 右侧普通操作使用 `accent`；危险操作进入确认流程后使用 `danger`。
- 沉浸式照片头部允许白色返回按钮，但必须提供阴影或半透明深色承托，确保浅色照片上可见。
- 禁止页面自行固定导航栏为纯白或纯黑。

## 4. 文本层级

- 页面大标题：20 pt Semibold。
- 导航标题：系统默认或 17 pt Semibold。
- 列表主标题：16～17 pt Regular/Semibold。
- 列表副标题：13～15 pt，`textSecondary`。
- 聊天正文：`IMTheme.chatFontSize`，由用户在 14～22 pt 调整。
- 时间、状态、辅助标签：11～13 pt。
- 用户调整字号后，消息高度必须通过 Auto Layout 自动重算，禁止固定正文高度。

## 5. 列表、卡片与输入

- 普通设置页使用 `UITableViewStyleInsetGrouped`；“外观”等需要实时预览的沉浸式设置中心可使用
  `UIScrollView + UIStackView`，但仍须保持分组卡片、16 pt 页面边距和统一语义令牌。
- 外观页的主题颜色、显示模式、聊天外观、应用图标必须各自处于独立卡片；卡片之间至少
  24 pt，卡片与屏幕左右保持 16 pt；分组标题左边缘必须与卡片左边缘对齐。分割线统一
  使用 `IMTheme.separator`，不得按区块换色。
- 分组页面上的卡片使用 `IMTheme.cardBackground`，不得直接使用
  `pageBackground` 或 `groupedBackground`；该动态语义色须保证浅色和深色模式下都与页面分层。
- Cell 主背景使用系统表面色；选中态使用系统选中背景或 `accent` 的低透明度。
- 卡片圆角默认 `IMTheme.radiusCard`，连续圆角使用 `kCACornerCurveContinuous`。
- 输入栏使用 `surface`，输入框使用 `pageBackground`，边框使用 `separator`。
- 空状态居中，正文使用 `textSecondary`，主操作使用 `accent`。

## 6. 聊天个性化

- 聊天主题控制强调色、自己的消息气泡和壁纸色组；对方气泡保持中性动态色。
- 内置主题：经典绿、海洋蓝、紫晶、深海。
- 壁纸风格：涂鸦、渐变、纯色。壁纸必须同时提供浅色和深色值。
- 气泡圆角读取 `IMAppearance.bubbleRadius`（6～24 pt）。
- 聊天正文读取 `IMAppearance.chatFontSize`（14～22 pt）。
- 外观变更通过 `IMAppearanceDidChangeNotification` 实时刷新已打开的聊天页。
- 应用图标只能切换预先打包的 Alternate Icons，不能在运行时生成。
- 图标选择器必须使用对应 App Icon 的真实缩略资源，不得用 SF Symbol 或占位图冒充。
- 外观首页须提供真实聊天预览和可视化缩略图；主题、壁纸、字号、圆角不得只用文字或
  `UISegmentedControl` 表达。字号与圆角调节页应在完整聊天场景中实时反馈。

## 7. 深色模式验收

- 浅色、深色、跟随系统三种模式均需检查。
- 标题、正文、按钮、输入框、分割线在两种外观中可辨识。
- 图片上的按钮必须在明暗图片上都有足够对比。
- 不允许把动态 `UIColor` 的 `CGColor` 长期缓存而不在主题变化时更新。
- 切换主题后已打开页面不得要求杀进程才能生效。

## 8. 新功能检查清单

1. 动手前读取本文以及 `CODING_STYLE.md`。
2. 优先复用已有令牌；缺少语义时先扩展 `IMTheme`，不得就地写魔法颜色。
3. 用户可调值统一进入 `IMAppearance`，不得由页面直接读写 `NSUserDefaults`。
4. 对深浅色各检查一次，对运行时切换检查一次。
5. 更新本文或说明为什么无需新增规则。
