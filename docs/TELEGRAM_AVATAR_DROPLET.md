# Telegram 水滴头像吸附 + 标题迁移 + 松手临界吸附（实现说明 & 可调参数）

> 复刻 Telegram「资料页头像随滚动吸进灵动岛」的水滴（droplet）动效：头像随滚动缩小、被灵动岛吸收，
> 头像下方的名字/副标题同步上移、缩放、**锁定进标题栏**；松手时按临界值**自动补完 / 回弹**。
>
> 涉及两个页面，**共用同一套驱动** `IMDropletHeaderMorph`（Zone①）——详情页改一处，「我」页自动同步：
> - 群/单聊资料页 `IMChatDetailViewController`（副标题 = "N 位成员"）
> - 「我」页 `IMSettingsViewController`（副标题 = "手机号 · @uid"）
>
> 底层素材与渲染层：
> - `IMProgram/Resources/UserAvatarMask.json`：从 Telegram 提取的原始 Lottie（`.tgs` 解包），灵动岛下方 171pt 的水滴遮罩关键帧。
> - `IMProgram/Common/IMTelegramAvatarMaskView.swift`：
>   - `IMTelegramAvatarMaskView`：把上面的 Lottie 当作「进度条」渲染（`setProgress:`，对应 Telegram `AnimationNode.setProgress`），**不自动播放**。
>   - `IMTelegramAvatarEffectsView`：对应 Telegram `DynamicIslandBlurNode`——暗色模糊 + 径向渐变 + 黑色融合层，随进度连续变化。

---

## 0. 一个 tableView、两段吸附区间（先建立心智模型）

整页是一个 `UITableView`，`off = contentOffset.y` 从 0 往上滚，分成两段各带一个「松手临界值」：

```
 off ── 0 ─────────────── H(=144) ─────────────── pin ──────────────►
        │  Zone① 头部吸附      │  自由滚动(Info/设置行)  │  Zone② 页签贴顶后列表滚
        │                     │                        │
   临界A=头像吸附过半(H/2)                         临界B=半个 tab 高(detent)
```

- **Zone①（`0→H`）头部吸附**：头像上移缩小被灵动岛吸收；name/成员迁移进标题栏；pills 上移到标题栏正下方并**保持可见**。
  两个稳定态：**态0**（展开）↔ **态H**（收拢：标题栏显示 name+成员，pills 紧贴标题栏下方）。
- **Zone②（`pin→`）页签贴顶后**：pills 滚走，`[成员][媒体][文件]` tab 撞到贴顶线（`topInset+68`）贴顶，列表在其下滚。
- 两段之间（`H→pin`）是普通自由滚动（Info / 设置分组行）。

> 「我」页没有 tab，只有 Zone①（+下拉钳制）。

---

## 1. 共享驱动 `IMDropletHeaderMorph`（Zone①）

`IMProgram/Common/IMDropletHeaderMorph.{h,m}`。两页各建一个实例，喂入各自的视图引用 + 参数，
每帧 `scrollViewDidScroll` 调 `-applyForOffset:width:`，松手时用类方法 `+snapTargetForOffset:velocity:collapseOffset:` 决策吸附。
**Zone②（页签）与 pills 停靠是详情页专有逻辑，不进驱动**。

### 1.1 静态容器 + 遮罩挂容器（而非头像）

**核心坑**：171pt 的水滴遮罩若挂在「随滚动缩小的头像」上，头像缩到 50pt 时遮罩被头像 `bounds` 裁成矩形，水滴就没了。

**解法**：建一个**静态坐标容器**（不随滚动移动/缩放），遮罩挂 `container.maskView`：
- 详情页：`IMDetailHeaderContainer`（自定义 `hitTest` 只透传给头像，避免大容器吞掉列表触摸）
- 「我」页：`dropletContainer`（普通 `UIView`，`userInteractionEnabled = NO`）

头像、黑底 `bottomCover`、effects `topCover` 在容器坐标系内各自定位；遮罩始终是固定 171pt 水滴形，不受头像尺寸影响。

### 1.2 两条独立进度值

| 变量 | 公式 | 驱动对象 | 来源 |
|------|------|----------|------|
| `q`（maskValue） | `off / 120` | 遮罩深浅、黑底 alpha、effects、导航栏磨砂 | Telegram `PeerInfoHeaderNode` 以 `contentOffset/120` 驱动灵动岛遮罩 |
| `tcf`（titleCollapseFraction） | `off / 128` | 头像缩放 + 上移量 | `PeerInfoHeaderNode.swift` L1624/L1759 |

两者**略微异步**（120 vs 128）是 Telegram 原始节奏，不要强行统一。

### 1.3 头像几何必须对齐 171pt Lottie 圆

**核心坑**：头像 rest 尺寸/圆心若和遮罩不匹配，头像会比遮罩小、缩得比遮罩快，露出的差集会把黑色 `bottomCover`
当成「一滑就整片出现的大遮罩」。**解法**：`restD = 100`（= Telegram `avatarSize`），圆心 `restCY = top + 72`；
遮罩固定 171×171、圆心 `(W/2, 133)`（屏幕 Y 47.5..218.5，灵动岛正下方）。

### 1.4 名字/副标题：慢速上移 → 锁定进标题栏（间距收窄到与标题栏一致）

- name 不 1:1 跟随头像，而是以 **`kNameSpeed`（驱动内部推导，< 1）** 上移 → 与头像逐渐拉开距离、**永远在水滴下方**。
- `kNameSpeed = (staticRestNameCenterY - kLockCenterY) / H`：让 name 恰好在 **`off = H` 时锁定**到标题栏 title 中心（`kLockCenterY = top+19`）。
- `migrate`（0=rest，1=已锁定）驱动缩放：name 26/28pt → 17pt，meta 15/17pt → 13pt，锁定瞬间刚好到位。
- **name↔meta 间距**：中心距 `centerDist` 随 `migrate` 从 rest 舒适值 **连续收窄到 18.5pt**（= 标题栏 title↔subtitle 中心距）。
  每帧显式设 name/meta 各自 frame 中心 + 纯缩放 → 间距精确可控，锁定时与标题栏逐像素一致（详情页要求 name/成员间距更紧凑就是靠这条）。
- name 标签 `bringSubviewToFront` 到导航栏之上**充当 title**（`compactContentProgress = 0` 关掉 bar 内置 title，避免双标题）。
- meta 行为由 `metaFades` 开关控制：默认 `NO`（详情页成员数：跟随 name 迁移进标题栏当副标题，全程可见）；
  「我」页置 `YES`（手机号·uid：`alpha = 1 - migrate`，迁移途中渐进淡出，锁定时完全不可见）。

### 1.5 松手临界吸附（`+snapTargetForOffset:velocity:collapseOffset:`）

纯函数，输入当前 `off`、`velocity.y`（`scrollViewWillEndDragging`，points/ms，>0=继续上滑）、`H`：

- `off` 不在 `(0, H)` 收拢带内 → 返回 `-1`（不吸附，交给系统自然减速）。
- **快速甩动**（`|velocity| > 0.3`）→ 无视位置，顺甩动方向补完（上甩→H，下甩→0）。
- 慢速松手 → 位置过半判定：`off ≥ H*0.5`（**头像吸附过半**）→ 收拢到 H；否则回弹到 0。

VC 在 `scrollViewWillEndDragging:...targetContentOffset:` 里改写 `targetContentOffset->y` 为吸附目标。

---

## 2. 可调参数速查表

### 2.1 共享驱动 `IMDropletHeaderMorph`

| 参数 | 当前值 | 含义 | 调大 / 调小 |
|------|--------|------|-------------|
| `q = off/120` | `120` | 遮罩出现速度分母 | 分母↑ → 遮罩更慢更平缓 |
| `tcf = off/128` | `128` | 头像缩放/上移速度分母 | 分母↑ → 头像收缩更慢 |
| `restD` / `restCY` | `100` / `top+72` | 头像 rest 直径 / 圆心（须对齐遮罩圆） | **不建议单独改** |
| `avatarScale` | `lerp(1, 0.55, tcf)` | 头像最终缩到 55% | 末值↓ → 头像更小 |
| `cy = restCY - off + 17*tcf` | `17` | 上移额外补偿（`apparentTitleLockOffset 7 + 10`） | — |
| 遮罩 `maskFrame` | `(W/2-85.5, 47.5, 171, 171)` | 灵动岛下方水滴带 | 改 Y → 上下移；改 171 须同步 `restD` |
| 遮罩挂载阈值 | `q > 0.03` | 低于此进度不挂遮罩 | ↑ → 更晚出现暗色 |
| **`collapseOffset` H** | `144` | 头部完全收拢所需上滑距离（= pills 停靠几何） | 见 §3.1，改动须与 pills 同步 |
| `kLockCenterY` | `top + 19` | name 锁定终点 = 标题栏 title 中心 | 两页一致 |
| `nameRestFont`/`metaRestFont` | 详情 26/15、我页 28/17 | name/meta 起始字号（→17/13pt） | 由各页设置 |
| `metaFades` | 详情 NO、我页 YES | meta 是否随迁移 `alpha=1-migrate` 淡出 | 我页手机号·uid 淡出，详情成员数常显 |
| 临界值 `H*0.5` | `0.5` | 慢速松手：头像吸附过半才补完收拢 | ↓ → 更容易吸附 |
| 快速甩动阈值 `vThresh` | `0.3` | points/ms | ↓ → 更灵敏 |
| name↔meta 锁定中心距 | `18.5` | = 标题栏 title↔subtitle 中心距 | 改会破坏「与标题栏一致」 |

### 2.2 详情页 `IMChatDetailViewController`（Zone② + pills，驱动之外）

| 参数 | 位置 | 含义 |
|------|------|------|
| `headerCollapseOffset` | 方法 | = 144，喂给驱动的 H；由 pills 几何推导（§3.1） |
| `tabPinTop` | 方法 | `topInset + 48`：tab 贴顶顶边（紧贴标题栏，上方内容被磨砂栏遮住不外露）。stickyBar/pinOffset/updateStickyTabs 统一取此值 |
| `kTabBarH` / `kTabSegH` | 常量 | 页签栏 52 / 分段控件 40（点击面积更大）；分段字号 15pt medium、宽度下限 200 |
| `tabBarHeight` | 方法 | 运行时实时页签栏高度；Zone② detent 临界 = 其一半 |
| Zone② detent | `scrollViewWillEndDragging` | 落点在 `(pin, pin + tabBarHeight/2)` → 回弹到 `pin`（tab 仍贴顶）；≥ 半 tab → 放行 |

### 2.3 「我」页 `IMSettingsViewController`（驱动之外）

| 参数 | 位置 | 含义 |
|------|------|------|
| 下拉钳制 `-44` | `scrollViewDidScroll` | 顶部橡皮筋最多下拉 44pt 即钳住（配合驱动 `off≥0` 冻结 → 头像/name 永不重叠，见 §3.4） |
| `metaFades = YES` | `buildProfileHeader` | 手机号·uid 随迁移淡出（详情页 NO） |
| `syncHeaderScrollRoom` | `viewDidLayoutSubviews` | 补底部 inset 保证 maxRaw ≥ H → 大屏一屏放得下时 name 仍能迁移进标题栏（#1） |
| `collapseOffset` | `applyProfileHeaderMorph` | = 144，与详情页一致 |

### 2.4 渲染层 `IMTelegramAvatarEffectsView`

| 参数 | 位置 | 含义 |
|------|------|------|
| `isHidden = value <= 0.03` | `setProgress:` | 低进度不显示 effects |
| `fadeView.alpha = -0.25 + value*1.55` | `setProgress:` | 黑色融合层淡入（越接近灵动岛越黑） |
| blur `fractionComplete = -0.1 + value*1.1` | `setProgress:` | 暗色模糊强度 |
| 径向渐变 `locations = [0, 0.87, 1]` / 中心 `+38` | `makeGradientImage` | 中心透明→边缘黑的过渡 / 焦点下移 |

---

## 3. 关键细节

### 3.1 `H = 144` 的由来（pills 停靠几何）

pills（搜索/更多）在内容里，rest 顶 = `topInset + 208`，随滚动上移到 view-y = `(topInset+208) - off`。
要它在态H 停到标题栏正下方（顶 ≈ `topInset + 64`）：`(topInset+208) - H = topInset+64 → H = 144`。
所以 name 锁定、头像收拢、pills 停靠**三者同时发生在 off=144**。改 H 须同步 pills 的 208 常量。

### 3.2 pills：停靠不淡出（`updatePillsVisibility`）

pills **不再 alpha 淡出**：随内容上滑停靠到标题栏下方并始终可见（态H）；继续上滑（Zone②）时它自然滚到磨砂标题栏
之后被遮挡（= 滚走）。仅在进入标题栏区后停用点击（`topInView > topInset+56` 才可交互），避免隔栏误触。

### 3.3 页签配色：选中色 ↔ 背景色对调（`styleSegmented:`）

`成员 / 媒体 / 文件` 分段控件（`self.segmented` 与吸顶镜像 `self.stickySeg` 都套）：
- `selectedSegmentTintColor = tertiarySystemFill`（选中段 ← 原**背景/轨道**色）
- `backgroundColor = systemBackground`（轨道 ← 原**选中段**色）
- 选中态文字 `label`，未选中 `secondaryLabel`。

### 3.4 「我」页下拉不重叠

驱动内部 `off = MAX(0, off)`：下拉（`raw<0`）时头像/name **冻结在 rest**，天然不会互相追上重叠。
`scrollViewDidScroll` 再把 `contentOffset.y` 钳到 `-adjustedContentInset.top - 44`，限制橡皮筋幅度。

### 3.5 贴顶后禁止越界上滑 + 点 tab/切 tab 维持贴顶（`syncScrollInset` / `switchToTab`）

**要点纠偏**：短内容不是"禁止一切滚动"，而是"能滚到贴顶、贴顶后不再越界"。所以 `syncScrollInset` **始终**
补足 inset 到「能滚到收拢 H + 贴顶 pin」——任何内容长度都能上滑贴顶、点 tab 也能贴顶（`wantMax = MAX(H, pin)`）。
再按内容长度控制橡皮筋：
- **内容够长**（`naturalMax ≥ pin`，贴顶后仍有内容）→ `bounces=YES`：可继续自然滚动，走 Zone② detent。
- **内容不足**（贴顶后是空白）→ `bounces=NO`：能滚到 pin，但**贴顶后硬停、禁止越界上滑**（2(2)a，不再"滑一点又回弹"）。

**估算必须关闭**（`estimatedRowHeight/SectionHeader/Footer = 0`）：否则 `reloadData` 后 `rectForHeaderInSection:`
（→`pinOffset`）是估算值、不准，切 tab 时 `setContentOffset:pin` 落偏 → 回到进入态。这是 **#4** 的真正根因。

`switchToTab`（#4 维持贴顶）：`reloadData → layoutIfNeeded → syncScrollInset`（始终补足 → pin 可达）→ 若之前已贴顶，
`setContentOffset:pin`；并在**下一帧再断言一次** pin 作安全网，抵消偶发的二次布局落偏。点 tab（未贴顶）则 `scrollTabsToPin`
平滑贴顶（#2(2)）。

### 3.6 「我」页自持导航栏

「我」页原本用 `IMMainTabBarController` 的**共享** `imLiquidBar`（title 是纯文本，装不下会动的 UILabel）。
为让 name 真正「进到标题栏里」，改为**自持** `IMLiquidNavigationBar`：
- `IMMainTabBarController.syncLiquidBar` 的 `ownsBar` 增加 `IMSettingsViewController` 判定 → push 后隐藏共享 bar。
- 自持 bar 需**自己**配置左（二维码）/右（编辑）按钮 + `delegate`，否则按钮消失、点击无响应。
- name/meta 直接挂 `self.view`（不是子 overlay）→ `bringSubviewToFront` 才生效、能盖过 bar。

---

## 4. 常见问题（踩过的坑）

| 现象 | 原因 | 修复 |
|------|------|------|
| 遮罩「啪」地整片出现 | 头像几何未对齐 171pt 遮罩圆 | `restD=100`、`restCY=top+72` |
| 头像缩小后水滴变矩形 | 遮罩挂在缩小的头像上被 bounds 裁切 | 遮罩挂**静态容器** `container.maskView` |
| name 与遮罩/头像重叠 | name 1:1 跟随头像 | `kNameSpeed < 1` 慢速上移 |
| 继续上滑 name 消失 | 上移量无上限 | `nameCenterY = MAX(kLockCenterY, …)` 锁死 |
| 锁定时 name/成员间距太松 | 缩放绕中心不改中心距 | 每帧插值 `centerDist → 18.5`（§1.4） |
| pills 提前淡出 | 旧逻辑按接近导航栏 alpha 淡出 | 改为停靠不淡出（§3.2） |
| 松手停在半吸附的尴尬位 | 无临界吸附 | Zone① `snapTargetForOffset`（§1.5） |
| name 停在标题栏**下方**没进去 | 标签是子 overlay 的子视图，`bringSubviewToFront` 空操作 | 标签直接挂 `self.view` |
| 「我」页二维码/编辑按钮消失 | 自持 bar 未配置按钮/delegate，共享 bar 又被隐藏 | 自持 bar 补齐 `leftImage`/`actionTitle`/`delegate` |
| 「我」页下拉头像与 name 重叠 | 下拉时头像比 name 下移快 | 驱动 `off≥0` 冻结 + 下拉钳制 44pt（§3.4） |
| 长列表贴顶后切 tab 回到进入态 | 行高估算开着，reload 后 pinOffset 不准，setContentOffset:pin 落偏 | 关闭估算 + 切后下一帧再断言 pin（§3.5 #4） |
| 短内容整页不可滚 / 点 tab 不贴顶 | inset 改成"短内容不补"→ pin 不可达 | 恢复：`syncScrollInset` **始终**补到 pin，短内容仅 `bounces=NO`（§3.5） |
| 贴顶时标题栏下方露出上一行内容 | 贴顶线距标题栏底太远（旧 12pt） | `tabPinTop` 收到 `topInset+48`，分段控件紧贴标题栏 |
| 「我」页大屏内容一屏放得下、name 不迁移 | 内容不可滚 → raw 恒为 0 | `syncHeaderScrollRoom` 补底部 inset 保证 maxRaw ≥ H |

---

## 5. 相关文件索引

| 文件 | 作用 |
|------|------|
| `IMProgram/Common/IMDropletHeaderMorph.{h,m}` | **共享 Zone① 驱动**：头像吸附 + name/meta 迁移 + 松手临界吸附 |
| `IMProgram/Resources/UserAvatarMask.json` | Telegram 原始 171pt 水滴 Lottie 关键帧 |
| `IMProgram/Common/IMTelegramAvatarMaskView.swift` | Lottie 遮罩渲染 + 灵动岛 effects（blur/gradient/fade） |
| `IMProgram/Modules/Detail/IMChatDetailViewController.m` | 详情页：静态容器、驱动接入、pills 停靠、Zone② detent、页签配色、`syncScrollInset` |
| `IMProgram/Modules/Me/IMSettingsViewController.m` | 「我」页：驱动接入 + 自持导航栏 + 下拉钳制 |
| `IMProgram/App/IMMainTabBarController.m` | `syncLiquidBar` 的 `ownsBar` 判定（详情页 + 「我」页自持 bar） |
| `IMProgram/Common/IMLiquidNavigationBar.swift` | 标题栏几何来源（title/subtitle 位置、字号 → §1.4 间距基准） |
