> ⚠️ 历史归档（只读，勿更新）。当前活快照见同目录 current_task.md；本文件只供考古。

---

## Status（2026-08-03 迁移：统一导航 Liquid Glass 大改造 + M1~M3-5 里程碑历史，从活快照迁入）
> 以下条目原在 current_task.md「当前焦点」，均已完成/提交，为保活快照精简而迁入归档（只读，勿更新）。

- iOS 导航统一：详情页及所有 Tab/普通页面统一使用 `IMLiquidNavigationBar` 自定义 Liquid Glass 导航；详情头像统一圆形布局，HTTP 头像可点击预览；规范见 `docs/LIQUID_GLASS_NAVIGATION.md`。
- 本轮未编译：统一导航中间标题改为纯文字、单图标操作改为圆形按钮；会话列表增加导航安全区避让；聊天页恢复右上头像、群聊成员数副标题并铺至状态栏；“我”页收藏入口以上改为头像/昵称/账号信息头部，含二维码与编辑按钮。
- 最新调整（未编译）：普通页面标题与右侧按钮垂直对齐；仅聊天页保留标题玻璃背景并显示群成员副标题；聊天头像改为直接使用 UIBarButtonItem 图片以保证可见和可点击；“我”页头部按 Telegram 风格重新留白，并随滚动淡出头像/资料、在顶栏显示昵称。
- **✅ Telegram 导航头部对齐（2026-08-01，用户测试通过；按要求未编译）**：详情页与“我”页统一用 120pt 滚动进度、相同圆形接近/水滴颈部/暗色融合参数；两页初始导航磨砂为 0，随折叠渐入且底缘渐隐；修正“我”页误把额外 56pt 导航避让计入头像坐标而导致头像落在标题栏下方；聊天页恢复自定义标题栏 56pt 顶部避让，首条消息不再与标题栏重叠。实现依据为 Telegram `PeerInfoScreenImpl / PeerInfoHeaderNode`、`DynamicIslandMaskNode / DynamicIslandBlurNode`。
- Telegram 上下文菜单对齐（2026-08-01，按要求未编译）：`IMPopoverCard` 从 iPhone 底部 Action Sheet 重构为按钮旁展开的磨砂圆角菜单，包含右侧图标、分隔线、危险操作红色、轻遮罩及弹性进出场；详情页“更多”和会话列表“+”共用该组件。单聊详情不再创建“编辑”操作，且统一导航会在操作为空时同步隐藏按钮及磨砂承托。
- Telegram 原始水滴遮罩（2026-08-02，按要求未编译、待用户真机自测）：引入 `lottie-ios 4.6.0`，将 Telegram `UserAvatarMask.tgs` 无损解压为同内容 JSON 资源；新增公共 `IMTelegramAvatarMaskView`，以 `contentOffset / 120` 直接定位原始 60fps 矢量动画进度，并照搬 `DynamicIslandBlurNode` 的连续暗色模糊、径向渐变、黑色渐隐和 `0.03` 遮罩切换阈值。根据用户提供的 Telegram 录屏复核并修正首版错误几何：头像不再随旧三段轨迹缩至 18pt，而是像 Telegram 一样最小保持 55% 并随滚动线性上移；原始遮罩保持独立 171×171 固定在灵动岛下方，通过与移动头像相交产生真实拉丝/水滴吸入轮廓，不再把整份动画错误压缩进头像 bounds。详情页与“我”页共用相同参数；新增不依赖 Swift 生成头文件的 XCTest 资源校验，但遵照用户要求未编译/执行。
- 二次修正（未编译）：聊天头像强制使用原色渲染并在占位图/网络图更新后主动刷新统一导航，群资料返回后同步刷新成员数副标题；“我”页移除静态大 Header，二维码/编辑归入左右导航按钮，头像/昵称/手机号改为悬浮头部并复用详情页的圆形接近、平口水滴、模糊渐黑和吸入灵动岛滚动阶段。
- 已提交上述统一导航与资料页基线：`3b98347 feat(ui): 统一 Liquid Glass 导航与资料页交互`。其后未提交修正：导航栏新增覆盖状态栏的透明磨砂层；详情页搜索/更多移入透明 tableHeader、彻底绕开 grouped 卡片背景；详情返回不再恢复系统导航栏；设置头像改用详情页同款 92pt / `topInset + 58` 初始几何。workspace 模拟器编译通过。
- **✅ 全局 Swift/Objective-C 混编导航栏（2026-08-01，待用户模拟器验收）**：新增 Swift
  `IMLiquidNavigationBar`，由 `IMMainNavigationController` 承载所有 Tab 根页及普通 push 页面；详情页继续
  复用同一组件并保留 Objective-C 业务、头像形变、导航栈和侧滑返回。
  系统 `UINavigationBar` 在详情页隐藏，避免历史菜单和多套标题栏重叠。已设置 `SWIFT_VERSION=5.0`，
  Xcode 模拟器编译通过；按 `docs/DEPLOY.md` 成功安装并启动 iPhone 16e 模拟器，首屏截图无崩溃。
  详情页初始只显示独立返回按钮和右侧“编辑”，中间标题胶囊/副标题默认隐藏，随头像水滴吸附进度渐显；
  群聊头像不再叠加相机按钮，编辑统一从右上角进入。按用户录屏将吸附重构为“圆形接近→顶部固定形成
  水滴颈部→主体向上收缩并没入灵动岛”三段；移除完成时整条导航栏鼓胀，避免返回/编辑闪动；操作排
  去除外层卡片背景并修正 URL 图片头部重复安全区间距，Swift 导航按钮显式响应深浅色切换。第二轮
  对照 Telegram 官方 `DynamicIslandMaskNode/DynamicIslandBlurNode`：吸附遮罩增加平口颈部、暗色模糊
  与黑色渐隐；大图态导航按钮强制白色并随折叠回到动态 label 色；标题与操作排相交前淡出，操作排
  接近顶栏时整体淡出。会话列表加号崩溃根因是把 `UIBarButtonItem` 当 `UIView` 锚点，已新增专用
  barButtonItem popover 入口并修正 sender 类型。
- **iOS 导航与弹窗修正（2026-07-31，待真机验收）**：会话列表、群聊列表的加号改为与通讯录
  相同的标准 `UIBarButtonItem`，由系统负责与标题/返回键分组和 Liquid Glass 按压动画；详情页
  恢复系统导航栏与系统返回键，不再绘制自定义返回按钮。聊天右上头像改为 Glass 按钮自身承载
  圆形头像图像，避免 iOS 26 导航栏布局时只剩空圆圈或点击区域失效。`IMPopoverCard` 与
  `IMBottomSheet` 改为 UIKit `UIAlertController` action sheet，移除自绘浮层/底部面板；项目中
  现有确认弹窗本来就是系统 API，继续沿用。按用户要求本轮未编译。
- **iOS 导航与官方 Liquid Glass（2026-07-31，待真机验收）**：三个主 Tab 改用统一导航容器，
  所有非根页面 push 时自动隐藏底部 TabBar，并恢复系统边缘侧滑返回；会话/群列表加号统一为
  44 pt 真正交互的 Glass Button + 17 pt SF Symbol，恢复官方按压动画。新增 `IMGlass.h`：iOS 26
  使用官方 `UIGlassEffect` 与 Glass Button Configuration，iOS 15～25 降级系统材质。聊天页右上
  头像改为 44 pt 真 Glass 按钮 + 30 pt 严格圆形头像；普通页面统一走系统导航栏、图标式返回键和
  标准 `UIBarButtonItem`，由 iOS 26 自动形成左/中/右分离 Glass；详情页保留头像形变，但返回键
  改由系统导航栏提供，编辑操作和内容层继续使用 Glass；操作排上移并改 Glass，通用弹窗改官方效果。
  底部改用 iOS 18+ `UITab`，会话/通讯录/我融合成主组，搜索以 `UITabPlacementPinned` 成为右侧
  独立项，iOS 26 由系统呈现截图式 Liquid Glass；iOS 15～17 回退四项标准 Tab。Xcode 26.2
  iOS Simulator compile-only 已通过；未执行测试和运行时 UI 冒烟。
- **iOS 外观个性化三轮（2026-07-31，待真机验收）**：按截图进一步统一卡片层级和留白——主题颜色、显示模式、聊天外观、应用图标均为独立卡片，左右 16 pt、卡片间 24+ pt，分割线统一 `IMTheme.separator`；新增 `cardBackground`（`secondarySystemGroupedBackgroundColor`），保证浅色白卡、深色深灰卡均与 grouped 页面分层；四个分组标题显式与卡片左边缘对齐。新增四套普通 Image Set，由实际 App Icon 原图缩成 256×256，图标网格不再使用 SF Symbol 回退。重复点当前图标不再调用系统切换接口；iOS 公开 API 成功切换后的系统提示由系统强制展示，无法合规关闭。高级外观增强已登记 `../IMServer/docs/TASKS.md`。上一版 build + test-build 已通过，本轮按用户要求未编译。
- **✅ 会话菜单与交互动效修复（2026-07-31，用户真机测试通过）**：右上角加号菜单改为同一 host 单实例，阻止导航栏连续点击叠出多张卡片；置顶/取消置顶保持服务端确认后再本地按权威排序平滑移动行，随后静默同步；聊天附件面板首次创建先完成 Auto Layout，修正从左上角错误起跳。按用户要求未编译。
- **✅ 三端统一品牌图标与启动页（2026-07-31，用户测试通过）**：iOS AppIcon 接入未来感即时通讯共用图标（双气泡无限连接 + 实时脉冲），使用不含透明通道的 1024×1024 PNG，由系统负责圆角蒙版；原空白 `LaunchScreen` 已改为深海军蓝底、居中品牌图，并提供 1x/2x/3x 资源。按用户要求未编译。
- **三端日志与文档治理（2026-07-31）**：新增 `docs/LOGGING.md` 记录 iOS 的 CocoaLumberjack/HTTP/WS/DB/UI 使用规则，并引用 IMServer 的跨端共同契约；工程约定要求后续新增业务/技术 Markdown 统一放入 `docs/`，根目录入口文件除外。
- **✅ iOS 统一日志（2026-07-31）**：接入 CocoaLumberjack 3.9.x，应用自有日志全部经 `IMLog.h` 输出到 Xcode 控制台和滚动文件；按 `IM.APP/HTTP/WS/DB/UI` 分 tag。HTTP 请求/响应统一携带 `X-Request-ID`，用同一 `[req=…]` 关联并记录耗时、状态码、脱敏且最多 16 KB 的正文；multipart/binary 及 JSON 内嵌 Data URI 仅记元数据，Release 隐藏业务与非 JSON 正文。新增 `IMHTTPLogFormatterTests`；`xcodebuild build` 与 `build-for-testing` 已通过，真机已确认 Tag、请求关联及 password/token 脱敏正确。
- **仓库卫生（2026-07-31）**：根目录 `.gitignore` 已忽略 `.codegraph/` Codex 本地索引。
- **✅ 群聊详情页完整实现已提交（2026-07-13，commit e4270a8，已 push）**
  - **IMChatDetailViewController** 新增会话详情页（群聊为主，单聊备用）
  - **IMChatDetailTabs** 动态标签页（群成员 + 媒体 / 文件 / 链接）
  - **IMGroupManageViewController** 群管理入口（设置头像、编辑群名、成员管理）
  - **IMPopoverCard** 通用浮层卡片（会话菜单 + 详情页操作菜单共用）
  - **优化**：图片加载缓存、头像复用全局渲染、数据库查询接口扩展
  - **单测** IMChatDetailTabsTests 覆盖标签页逻辑（build + test-build 绿）
  - **待真机验证**（用户自装测试）
  
- **M3-5 群聊 iOS 端完成（2026-07-11，build+test-build 零 error/warning，模拟器实跑测试全绿；真机走查待用户）**，镜像 Web（`../im-web` M3-4）交互：
  - **模型/网络**：`IMGroupInfo`/`IMGroupMember`（角色 owner/admin/member 枚举 + 脏数据安全解析 + `nicknameOfMember:`）；`IMConversation` 加 `isGroup/name/avatarURL/memberCount/lastFromNickname`；`IMMessageModel.fromNickname`（`new_msg.from_nickname`，随消息落库——`IMDatabase` 加 `from_nickname` 列老库自动 ALTER）；`IMHTTPService` groups 接口族（create/list/info/update/invite/leave/remove/setRole/transfer）+ 3002xx 友好中文（**300204 不映射**，透传服务端原因如"群主需先转让"）；`IMSocketManager` `group` 帧 → `IMSocketDidReceiveGroupEventNotification`（event/convID/target）+ `sendText:toConv:`（群按 conv_id 路由、to 留空）。
  - **UI（新增 `Modules/Group/`）**：通讯录「群聊」入口 → `IMGroupListViewController`（我的群列表 + 右上 + 建群：`IMGroupMemberPickerViewController` 好友多选 → 起群名弹窗 → 建群即进群聊）；聊天页群模式（标题"群名（N人）"、右上 ⓘ → `IMGroupInfoViewController`、对方气泡内顶部主色小字**发送者昵称**（from_nickname→成员表→uid 三级回退）、typing 显示"谁"在输入、**被移出→吐司+0.9s 后退出本页**、非群成员发言被拒 300203 挂系统行）；群资料页（成员列表+群主/管理员徽章、邀请（picker 排除已在群）、退出群聊（群主被拦文案透传）、改群名（owner/admin 右上铅笔）、点成员 ActionSheet 管理：设/撤管理员·转让群主·移出，按 my_role 权限矩阵显隐，服务端二次校验）；会话列表群项（群名/群头像、预览"昵称: 内容"，群项不显示 presence/✓✓）+ `group` 帧节流刷新。
  - **测试**：`IMGroupTests` 8 例（角色映射/群资料+成员解析/脏数据/群列表/会话群项/from_nickname 解析+落库往返），模拟器实跑全绿。
  - **端对齐扫描（iOS↔Web）**：群功能逐项对齐（入口/建群/群会话昵称气泡/群资料/成员管理/group 帧/被移出处理）；仅交互载体差异——Web 点标题开群资料弹窗，iOS 右上 ⓘ 推页（等价入口）。
- M2「状态与可靠性」iOS 全部达成 + Telegram 绿主题细化全做完 + 可见即读（Telegram 语义，iOS+Web 一致）。
- **M2.5 iOS 通讯录全做完（2026-06-16）**：
  - 通讯录 Tab `IMContactsViewController`：新的朋友(pending，同意/拒绝) + 好友列表(accepted，点击发起会话)；待处理申请数显示在 Tab 角标；**好友行左滑 = 删除 / 拉黑**。
  - 找人页 `IMUserSearchViewController`（右上 + 进入）：`GET /users/search`，结果按关系显示 加好友/已申请/同意/发消息。
  - **编辑我的资料** `IMProfileEditViewController`（「我」页→编辑资料）：`GET/PUT /api/v1/users/me`，昵称/头像/手机号/标签。
  - 新增 `IMUserCard`(含 phone) + `IMHTTPService` 的 search/friends/friendAction/remove/myProfile/updateProfile；复用 `IMTheme` 绿主题、`UIButtonConfiguration`。
  - `IMUserCardTests`（找人/好友/本人资料含 phone/状态映射/脏数据）。`xcodebuild build` + `build-for-testing` 均零 error/warning。
  - **CLIENT_PARITY M2.5 三行 iOS+Web 全 ✅**。
- **真账号密码登录 + 注册 ✅（2026-06-16，iOS+Web）**：`IMHTTPService` 加 `password` 属性（全局共享登录态）+ `registerWithUsername:password:`，`loginWithUserID:` 改发 `{username,password}`；`IMSocketManager` 换 token 也带共享密码。`IMLoginViewController`：用户名+密码 + 登录(真校验，错误密码显服务端文案)/注册并登录/免密登录(开发，凭 uid)。CLIENT_PARITY M1「真账号注册/密码登录」iOS+Web 升 ✅。
- **里程碑层面 M1+M2+M2.5 客户端基本收口**。下一步可选 M3 群聊。
- **自测修复（2026-06-16）**：①好友申请/同意实时——socket 收 `friend` 帧 → `IMSocketDidReceiveFriendEventNotification` → 通讯录(init 即订阅,节流)reload,Tab 角标无需切页即亮;②找人改精确匹配(`对方完整 uid 或手机号`占位)。
- **自测修复（2026-06-17）**：①「拒绝」按钮曾被禁用点击无反应 → 按钮三态(primary/secondary 可点/disabled)修复;②**黑名单页** `IMBlockedListViewController`（「我」页→黑名单）：`?status=blocked` 列表 + 解除(unblock);③HTTP 错误码 → 友好中文(`IMFriendlyMessageForCode`,被拉黑用模糊文案"暂时无法添加对方为好友"不暴露)。
- **登录失败 UX（2026-08-01 当前策略）**：iOS 已有本地登录态时，HTTP 鉴权或网络失败均不弹模态框、不自动清登录态，继续展示本地缓存；WebSocket 用 `IMSocketDidChangeStateNotification` 驱动「会话（连接中…/未连接）」并自动重连。用户主动退出才清理登录态。Web 仍保留鉴权失败确认框，属于端交互差异。
- **拉黑模型重构 + 拒收反馈（2026-06-17，两端）**：
  - ①**拉黑≠解绑（blocked 标记模型）**：后端 `im_friend` 加与 `status` 正交的 `blocked` 标记（启动自动迁移老 `status='blocked'`→`blocked=1`，非破坏）。`Block` 只置标记、好友关系(双方 accepted)不动 → **双方好友列表始终互见**(拉黑方带标记)；`Unblock` 只清标记。`BlockedBetween`/黑名单查询改用标记。iOS：`IMUserCard.blocked` 解析 + 通讯录被拉黑好友副标题"· 已拉黑" + 左滑"解除拉黑"。Web：`FriendEntry.blocked`、`peerBlocked` 改用标记、好友列表"已拉黑"标签 + 菜单"解除拉黑"。**Web 浏览器实测全过**；iOS 真编译+test-build 过、真机待验。
  - ②**被拒收微信式反馈**：被拉黑方发消息 → 气泡左红❗ + 下方居中系统行「消息已发出，但被对方拒收了」，**不弹窗**(iOS `IMBubbleCell._failBadge/_sysNote` + `IMMessageModel.note`；Web `ChatMessage.note` + `.fail-badge/.sys-note`)。Web 实测过；**iOS 系统行真机待复验**(代码路径已逐段核对正确，疑用户上次测时走了 10s 超时而非拒收)。
  - 规则见 `../IMServer/docs/PROTOCOL.md §6.5`、`CHAT_UX.md §8`。**已知**：早期"拉黑删对端行"旧 bug 已破坏的好友对(如 a1003↔a1001)无法自动复原，需重新加好友一次。
  - ③**拉黑改微信式单向(已定+实现)**：hub 仅拦"被拉黑方→拉黑方"；**拉黑方→被拉黑方照常投递**(对方收得到)。两端聊天页不再封禁拉黑方输入(Web 改非阻断提示行、iOS 移除封禁横幅)。`TestBlockedCannotSend` 改测单向。Web 浏览器实测：拉黑方发送成功✓+提示在+输入可用。iOS 真编译过、真机待验。


# Current Task

## Status（2026-06-15 最新 ⑤：iOS 补 ↓N 跳转按钮 + 文档单一来源整顿）
- **iOS ↓N 悬浮跳转按钮**（对齐 Web，CHAT_UX §7/§9）：滚离底部出现、徽标显示下方未读/新消息数、点按回最新并清零、贴底自动隐藏；进会话停首条未读时预置计数（整屏放得下则不显示）；收消息改为"贴底才自动贴底，离底则累加 ↓N 不打断"。build/test-build 通过（零 warning），IMProgramTests 14 全绿。
- **为何漏掉 ↓N**：上轮做 Telegram 视觉细化时，只盯用户点名项，没按 CLIENT_PARITY **逐行 diff iOS↔Web**；而该表早已标 "↓N iOS ⬜"。→ 已在 `CLAUDE.md` 完成定义加"端对齐扫一遍"硬步骤防复发。
- **文档整顿**：CLIENT_PARITY 设为"功能×端"唯一状态源（ROADMAP 只记里程碑+日期、UI.md 只记视觉）；补齐 UI 细化/UX 行；标注端不对称（iOS 领先离线/落库/空洞自愈，Web 领先分页）；解释"ROADMAP M2✅ vs 表内 iOS⬜"差异（⬜ 的是独立 性能/UX 轨道、不计里程碑）。DEPLOY.md 修正 iOS 构建用 `.xcworkspace`、补自测项。
- **iOS 仍落后 Web 的真缺口**：双向分页 / 进会话最近一页（iOS 仍全量载入 DB）——属独立 `性能` 轨道，单会话上万条再排期。

## Status（2026-06-15 最新 ④：修复离线消息漏拉——③ 引入的回归）
**联调反馈**：Web(1001) 在 iOS(1002) 离线时发了 6 条，1002 登录后停在会话列表只收到了之后在线发的"7"，1–6 漏了。
- **根因（③ 的回归）**：③ 让会话列表常驻长连接并在网络层落库，但列表**没有 track/sync 会话**。于是登录后：离线的 1–6 仍在服务端离线表（只能靠 sync_req 拉）；在线发的"7"以 new_msg 直推并落库，把本地 conv_seq 位点**推过了 1–6 的空洞**；之后进聊天页从该位点同步 → 跳过 1–6。
- **修复（两层）**：
  1. **会话列表登记同步**：HTTP 拉到会话后，对每个会话以本地最大 conv_seq 为起点 `trackConversation:syncedSeq:`（每会话一次）→（重）连即 sync_req 补拉离线消息（`trackConversationsForSync`）。
  2. **空洞自愈（网络层兜底）**：`processIncomingMessage` 收到的 conv_seq 若跳过了已同步位点之后的中间段（conv_seq 连续分配，跳号=有漏），先用旧位点发 sync_req 补缺口，再推进位点。防住"实时消息抢先把位点推过空洞"的竞态。
- **验证**：build + build-for-testing 通过（零 warning）；IMProgramTests 14 全绿。
- **⚠️ 测试前提**：旧本地库里已有"空洞"（1–6 缺、位点已在其上），新逻辑只防新空洞、**不回填历史空洞** → **请先删除模拟器上的 App 重装**（清本地 im.sqlite）再测，否则旧洞仍在。
- **真机验证清单**：①1002 删 App 重装；②1002 退到登录（或杀进程）保持离线，1001 连发若干条；③1002 登录 → 停在会话列表片刻（让其 sync）→ 进会话，**离线那批应全部补齐、不漏**；④再让 1001 在线发新消息，照常实时到达。

## Status（2026-06-15 最新 ③：会话列表实时刷新 + 长连接常驻）
**联调反馈修复**：Web(1001)→iOS(1002) 连发 8 条，iOS 会话列表未读数不变，必须切 Tab 才更新。
- **根因**：socket 只在聊天页连接、离开即断开；会话列表无常驻连接，仅靠 `viewWillAppear` 的 HTTP 拉取刷新 → 停在列表收不到 new_msg。
- **修复（长连接提到 App/列表级常驻 + 通知广播）**：
  - `IMSocketManager`：收到任意消息时除 delegate 外**广播 `IMSocketDidReceiveMessageNotification`**（userInfo[`kIMConvIDKey`]）；`connectToHost` 改**幂等**（已连同 host+uid 则复用，避免列表/聊天页重复调用抖动）；**收到的消息在网络层落库**（`IMDatabase saveMessage`），不再依赖聊天页 delegate，杜绝「列表收到未入库→开聊天页漏拉」。
  - 会话列表：`viewWillAppear` 连接 socket 并订阅通知 → 收到新消息**节流 0.4s reload**（在屏才刷）；`viewWillDisappear` 退订。
  - 聊天页：离开**不再 disconnect**（连接常驻供列表持续收消息），仅交还 delegate。
- **验证**：workspace build + build-for-testing 通过（零 warning）；IMProgramTests 14 用例全绿。
- **真机验证清单**：①停在会话列表，对端连发多条 → 未读数/最后一条**实时更新**（不必切 Tab）；②停列表收到消息后开该会话 → 消息齐全（不漏）；③聊天页正常收发/已读不受影响。
- **已知限制**：presence/typing 仍在聊天页（标题）维度处理；列表不显示在线点（后续可同法用通知广播 presence）。

## Status（2026-06-15 最新 ②：Telegram UI 细化第二版 + M1 文档校正）
**本次完成（iOS UI）**：照用户选定方向「对齐截图：浅色气泡 + 绿勾」做 Telegram 绿主题细化——
- **气泡配色重做**（IMTheme 动态色，深色自动适配）：自己=浅绿底(深色暗绿)、对方=白底(深色暗灰)，文本统一主色；**已读双勾绿 ✓✓**、已送达灰单勾、时间灰小字（attributedText 分段着色），行内右下角占位逻辑保留。
- **聊天壁纸**：新增 `IMChatBackgroundView`（绿渐变 CAGradientLayer + 低透明 SF Symbol 涂鸦平铺图，深色切暗绿），设为 tableView.backgroundView。**注**：未用 Telegram 真涂鸦 .tgv 资源（仓库内为下载态矢量，非可直接复用 PNG）→ 用 CG 自绘 SF Symbol 平铺图近似。
- **消息按时间分组**：气泡 cell 顶部加居中日期胶囊（今天/昨天/M月d日/yyyy年M月d日）；逻辑入 IMTheme（`isMillis:sameDayAsMillis:`、`dayHeaderStringFromMillis:`），配单测。
- **长按消息菜单**：UIContextMenu（复制 / 删除）；删除=仅本端（IMDatabase 新增 `deleteMessage:`，从库+内存移除并刷新，不影响对端），配单测。
- **会话列表已读双勾（真已读态，本次补全）**：「我发的最后一条」时间左侧——**对端已读到该条→绿 ✓✓**，否则→**灰单勾 ✓**（已送达/未读）。判定用**后端新增字段** `peer_read_seq`：
  - 后端 `internal/conversation` Summary 加 `PeerReadSeq`（单聊取对端 `store.ReadPosition`，群聊 0），`GET /conversations` 返回；配 `TestPeerReadSeq`，`./scripts/test.sh` 全绿。
  - iOS `IMConversation` 解析 `peer_read_seq`；列表 cell 据 `latestConvSeq<=peerReadSeq` 切绿✓✓/灰✓。
- **验证**：iOS workspace `build` + `build-for-testing` 通过（**零 error/零 warning**）；iPhone 16e 模拟器 `IMProgramTests` **14 用例全绿**（含 testSameDayGrouping / testDayHeaderString / testDatabaseDeleteMessage + 扩充 testConversationParsing 含 peer_read_seq）。后端 `./scripts/test.sh` 全绿（含 conversation 包 TestPeerReadSeq）。
- **⚠️ 改了后端：用户需重启后端**（`cd IMServer && go run ./cmd/imserver`）再测，运行中的旧进程不会热更新 `/conversations` 的新字段。
- **真机验证清单（交用户手测）**：①聊天页绿壁纸+涂鸦观感；②浅色气泡+深色字、已读 ✓✓ 变绿/已送达灰单勾；③跨天聊天出现日期胶囊（今天/昨天/M月d日）；④长按气泡弹「复制/删除」，删除后该条消失且重进不再出现；⑤会话列表我发的最后一条显示绿 ✓✓；⑥深色模式切换壁纸/气泡/勾均正常。
- **真机验证清单补充**：⑦会话列表「我发的最后一条」——对端已读时显示绿 ✓✓、未读时显示灰单勾 ✓（需后端重启 + 两端互发并让对端打开会话触发已读）。
- **已知限制/TODO**：壁纸为自绘近似（非 Telegram 原涂鸦）；Web 端绿主题/壁纸/日期分组/长按菜单/列表已读双勾尚未追平。

**M1 阶段是否全部完成？（回答用户问题，已更新文档）**：**未完全**。M1 里程碑头部功能已达成（ROADMAP 记 ✅），但逐端**两项缺口**：①真账号/密码登录——后端 ✅，**iOS/Web 仍免密直签 uid**（⬜）；②多端同时在线——后端 ✅，**客户端 UI/位点同步未验证**（⬜）。其余 M1 客户端项（会话列表、iOS 本地落库、真 Web 客户端）此前文档滞后标 🚧，**本次已校正为 ✅**。已同步更新 `CLIENT_PARITY.md`（矩阵 + 诚实记录段）、`ROADMAP.md`（M1 客户端追平缺口）、`UI.md`（Telegram 细化第二版状态）。两项缺口随 M2.5 账号/登录改造补。

## Status（2026-06-15 最新）
**正在做 M2「状态与可靠性」**。后端 M2 全done（已读回执 delivered≠read、未读数/red dot、presence、typing、会话项返回 read_seq、双向分页用现有 LoadSince）。
**Web 端（im-web，React+TS）M2 已完成并浏览器实测**：已读双勾/未读红点/presence/typing、未读分割线（read_seq 精确定位）、进会话停首条未读（Telegram 式，非最新）、双向分页（上滚更早/下滚更新）、↓N 跳转、**Telegram 桌面式双栏布局（窄屏自适应单栏）**。
**聊天交互蓝图见 `../IMServer/docs/CHAT_UX.md`（多端单一事实来源）；端能力见 `../IMServer/docs/CLIENT_PARITY.md`。**
压测工具：`IMServer/cmd/loadtest`（`go run ./cmd/loadtest -from 1002 -to 1001 -n 10000`）。
**TODO（性能）**：Web 消息列表虚拟化暂回退（virtua 在双栏条件挂载/嵌套 flex 下视口测 0、渲染空且不自愈）→ 现为普通滚动列表（配反向分页常规不卡）；后续换 react-window/@tanstack/react-virtual。
**✅ M2 iOS UI 已实现（2026-06-15）**：已读双勾（已送达✓→已读✓✓，按对端 read_seq）、会话列表未读红点、聊天页标题在线点（🟢/在线）、对方正在输入提示条、未读分割线（read_seq 精确）+ 进会话停首条未读、打开即全部已读（markRead latest）。workspace build + build-for-testing 通过。
- 协议：IMProtocol 加 typing/presence 常量；IMConversation 加 readSeq。
- SocketManager：收 receipt(read)/typing/presence → 新 delegate；发 markReadConv:upToConvSeq:、sendTypingForConv:。
- 聊天页：IMBubbleCell 加分割线+已读双勾；进会话定位、typing 提示、presence 标题、typing 节流上报。
- **已知限制**：presence/typing 仅在聊天页生效（socket 当前按会话连接，不在会话列表常驻）；会话列表不显示在线点。完整需把 socket 提到 App 级常驻（后续）。
**✅ M2 真机验证通过（2026-06-15，iPhone 16e 模拟器）**：会话列表 / 进聊天 / 已读双勾(✓✓) / seq 正确显示均 OK。
**✅ Telegram 视觉对齐（第一版，2026-06-15）**：参照 Telegram iOS 重做界面（详见 `../IMServer/docs/UI.md` 的"Telegram 视觉对齐"节）——
  - 会话列表自定义 cell：圆形彩色头像(uid 末两位 + `avatarColorForSeed`) + 名称/最后一条 + 右上时间 + 右下**蓝色未读胶囊**；行高 76，分隔线缩进对齐文字。
  - 聊天气泡重做：真气泡容器(非 UILabel 空格 padding)，圆角 18 + **尾巴**(maskedCorners)，文本 17pt，**气泡内右下角**时间 + ✓/✓✓。
  - 输入栏：圆角胶囊输入框 + 圆形蓝色发送按钮(arrow.up.circle.fill)。
  - 气泡 meta(时间+✓/✓✓)改为**行内右下角**(文本末尾补 NBSP 占位预留位)，不再单独一行显散；**自己发送补本地时间戳**(之前缺 → 只剩孤零零 ✓✓)。勾为白色半透明(非绿)。
  - **待办**：聊天壁纸、按时间分组/日期分隔、长按菜单、头像渐变、群头像；会话列表未读蓝胶囊已实现(unread>0 才显示)。
**✅ 登录默认 host 修复（2026-06-15）**：模拟器恒用 `localhost:8080`（不怕 Mac DHCP 换 IP）；真机记住上次地址（NSUserDefaults）。
**下一步：M2.5 通讯录/加好友/找人。**

## Status（iOS 既有，M1-5）
客户端：登录 → **会话列表（TabBar 会话/我）** → 聊天 三段式（M1-5b）+ **本地落库 IMDatabase（M1-5c：秒显历史 + 断点续传）**。
栈：IMSocketManager（重连同步 + JWT + trackConversation:syncedSeq:）+ IMHTTPService（登录/会话列表）+ IMConversation + IMTheme(tokens) + **IMDatabase（FMDB + SQLite）**。
默认 host：模拟器 localhost:8080、真机记上次（见上"登录默认 host 修复"）。
  - **已引入 CocoaPods（仅 FMDB）**：用 `IMProgram.xcworkspace` 打开/构建（不再用 .xcodeproj）；Podfile post_install 关了脚本沙盒避免 Pods 资源拷贝被拒。workspace `build` + `build-for-testing` 通过。
  - iOS 工作流：编译 + test-build 验证；**模拟器已恢复稳定**，有 booted 模拟器时直接实跑 XCTest。
  - ✅ 2026-06-15：iPhone 16e 模拟器**实跑 XCTest 通过**（IMProtocolTests 9 用例：会话id/协议常量/消息解析/IMConversation 解析/IMDatabase 落库往返）；App install+launch，登录页渲染正常（深色模式自动适配）。UI 全流程点击走查待 computer-use 系统权限或用户手测。
  - 进聊天页隐藏底部 TabBar（hidesBottomBarWhenPushed）已修。
  - ✅ 真机端到端验证通过（host 填 Mac 局域网 IP：登录→token→连接→离线消息 sync 拉回→已读回执）。本地明文联调需临时关 Mac 防火墙/stealth（生产用 wss:// 无此问题）。
  - ✅ 首批 XCTest（IMProtocolTests，6 用例）在 iPhone 16e 模拟器**全绿**（`-only-testing:IMProgramTests` 跳过模板空 UI target）。
  - 坑记录：默认 IMProgramUITests 会因 Accessibility 超时拖垮整体测试，单测须 `-only-testing:IMProgramTests`；前期 Mach -308/启动超时是模拟器未就绪所致，先 simctl bootstatus 等就绪即可。
后端：IMServer 用 **Go**，网关 + 持久化 + 幂等 + **离线消息/增量同步** 完成，`./scripts/test.sh` 全量回归绿。

## 关联工程
- 客户端：/Users/liying/IOSProject/IMProgram
- 后端：/Users/liying/IOSProject/IMServer（协议见 IMServer/docs/PROTOCOL.md）

## Progress
- [x] 确认技术栈：Objective-C 为主，Swift 备用混编
- [x] 创建 `CODING_STYLE.md`（OC + Swift 代码规范）
- [x] 创建 `current_task.md`（本文件，任务记忆）
- [x] 创建 `CLAUDE.md`（项目说明）
- [x] 创建 `.gitignore`（修复误提交的 xcuserdata）
- [x] 选定通信方案：自建 WebSocket
- [x] 选定依赖管理：CocoaPods
- [x] 设计 IM 整体架构（写入 ARCHITECTURE.md）
- [x] 编写共用协议文档 IMServer/docs/PROTOCOL.md（v0.1）
- [x] 选定后端语言：Go
- [x] 搭建 Go WebSocket 网关骨架（protocol/gateway/cmd），集成测试通过
- [x] 后端：内嵌网页调试客户端（cmd/imserver/web/index.html，go:embed 挂 /），双开浏览器肉眼验证互发
- [x] 后端：服务端优雅接收 receipt（记录，不再回 error）
- [x] 端到端验证：两真实 WS 客户端 send→ack→new_msg→receipt 全通过（C 完成）
- [x] 移除误提交的 xcuserdata（git rm --cached）
- [x] 客户端：创建 Podfile（Masonry/FMDB/SDWebImage/YYModel/AFNetworking；WebSocket 改用系统原生）
- [x] 客户端：搭建分层目录结构（Common/Network/Models/Services）
- [x] 客户端：实现 IMSocketManager 长连接骨架（连接/心跳/退避重连/收发/ACK 超时重发），xcodebuild 通过
- [x] 客户端：登录页 IMLoginViewController + 聊天页 IMChatViewController（原生 AutoLayout，不依赖 Pod），SceneDelegate 代码设根
- [x] 客户端：IMSocketManager 接增量同步——trackConversation、重连自动 sync_req、handleSyncResp（分页+投递+回执）、按 conv_seq 去重
- [x] 客户端：首批 XCTest IMProtocolTests（6 用例，iPhone 16e 模拟器全绿）
- [后端进度见 IMServer/current_task.md] 持久化/幂等/离线同步均已完成；JWT 鉴权、errcode、HTTP 层待办
- [ ] 客户端：pod install（需联网）后用 .xcworkspace 打开
- [ ] 客户端：IMDatabase 落库（sending→sent 持久化）+ synced_conv_seq 持久化（当前记内存，重启从 0 同步）

## Decisions & Constraints
- 主语言 Objective-C；未来可混编 Swift，新模块倾向 Swift。
- 通信：自建 WebSocket。**传输层改用系统原生 NSURLSessionWebSocketTask**（iOS 13+ API）；传输封装在 IMSocketManager 内部，接口不变，未来可无痛替换。心跳 25s + 指数退避重连 + ACK 超时重发。
- **部署目标 iOS 15.0**（2026-06-15 从误设的 26.2 调低）：代码栈未用 iOS 16+ API，15 覆盖设备最广且与 Podfile/Pods（已 15.0）一致；真机（iOS 18.6.2）可正常安装运行。
- 工程用 Xcode 文件系统同步组（PBXFileSystemSynchronizedRootGroup）：往 IMProgram/ 加文件即自动入编译，无需手改 pbxproj。
- 依赖：CocoaPods（使用后改用 .xcworkspace 打开）。
- 类统一前缀 `IM`，ARC，4 空格缩进。
- 网络/IO/数据库调用必须有错误恢复分支。
- `xcuserdata` / `xcuserstate` 不再纳入版本控制。

## Next Actions
0. **【当前】M2 iOS UI**：照 `IMServer/docs/CHAT_UX.md` 蓝图，在 IMProgram 实现未读红点 / 已读双勾 / 在线点 / typing / 进会话停首条未读（read_seq 锚点）。配套 IMProgramTests，做完 M2 整体里程碑停下等用户验收。
1. 真机/模拟器联调：`cd IMServer && go run ./cmd/imserver`，App 登录页填 host=本机IP:8080 / 我的 uid / 对方 uid，两端互发；可先杀掉一端验证离线→重连 sync 补偿。
2. 后续新增客户端逻辑时，往 IMProgramTests 加用例并按 CLAUDE.md 命令补跑（`-only-testing:IMProgramTests`）。
3. 接 IMDatabase（FMDB）落库：消息 sending→sent 持久化、synced_conv_seq 持久化（替换当前内存位点）。
4. 后端（见 IMServer/current_task.md）：JWT 鉴权替换 ?uid=、errcode 包 + HTTP 登录接口。

---

## Status（2026-08-04 迁移：UI 统一/账号加固/文件与同步等已验收批次，从活快照迁入）
> 以下条目原在 current_task.md「当前焦点」，均已完成并经用户验收/提交，为保活快照精简而迁入归档（只读，勿更新）。

- **五处弹窗/菜单风格统一到自定义 `IMPopoverCard`（2026-08-03，用户验收通过）**：会话列表「＋」、详情页「更多」、MediaViewer「更多」统一走 `IMPopoverCard` 锚点磨砂菜单（MediaViewer 从底部 action sheet 改锚定「⋯」、空间不足自动上翻；删除 `IMBottomSheet.{h,m}`）；图标从右移到左，圆角用 `IMTheme.radiusBubble`。两处 cell 长按保留系统 `UIMenu`。取舍：非像素级一致换 App 内风格统一；不用系统 UIMenu 全统一是用户选择保留 Telegram 观感。
- **若干 UI 修复批次（2026-08-03，用户验收通过并已提交）**：①深色模式统一导航磨砂过亮→`backgroundGlass` 叠自适应 tint（`480c112`）；②`IMLiquidNavigationBar` init 传 `actionTitle` 不触发 didSet→按钮不渲染→`buildView` 显式落标题（`763df80`）；③建群选择页选好友后「创建」钮吞点击→`updateSelectionUI` 补 `setNeedsLayout`（`763df80`）；④日期胶囊「今天」底色改 `accent·0.64` 随主题（`d8b18d7`）。另诊断非 bug：自己发的消息在自己其它端不计未读属正确行为。
- **系统 Files 选择与返回链（2026-08-02，iOS 26 真机测试通过）**：picker 单实例、页面日志不触碰 `DOCRemote…` 私有导航项；「返回下载页」确诊为 iOS 26.3 Simulator runtime bug（remote view service `FBSceneErrorDomain Code=2` 崩溃自重启），真机无此问题。恢复 `UTTypeItem`，补回归测试。
- **iOS 单库账号上下文 generation 加固（2026-08-02，用户确认测试通过）**：`IMDatabaseAccountContext` 绑定数据库实例/owner/激活代次，异步任务原子「校验+执行」；A→B→A 迟到操作拒写；XCTest 覆盖。物理分库降级为后续增强。
- **文件分页、文件语义与大小展示（2026-08-01，用户测试通过）**：已发送文件服务端游标分页 + uid 隔离 SQLite 缓存；`file_size` 贯穿发送/转发/Socket/模型/SQLite；气泡与文件 Tab 显 KB/MB/GB。
- **会话长名与跨端文件图标（2026-08-01，用户真机测试通过）**：标题行「名称→置顶→免打扰」水平 Stack；原创折角文件卡 21 类 + 未知类型，iOS Asset Catalog 与 Web SVG 同源，含扩展名映射单测。
- **iOS 本地优先会话 + 长连接状态（2026-08-01，用户抽查通过）**：FMDB 按 `owner_uid` 隔离、`server_snapshot_seq` 防未读翻倍、离线启动先登记缓存会话；设计记录 `docs/LOCAL_FIRST_CONVERSATION_STORAGE.md`。
- **聊天 Cell 解耦 + 离线启动保持会话（2026-08-01）**：6 个消息 Cell 迁至 `Modules/Chat/Cells/`；已有本地登录态时启动直进主界面由会话页自动重连；`IMSessionStoreTests` 覆盖。


---

## Status（2026-08-04 迁移：文件消息重构/长按菜单/多选/滚动贴底/粘贴条 全链路批次，从活快照迁入）
> 以下条目原在 current_task.md「当前焦点」，**均已实测通过并提交**（当时文档标注的"待实测/待真机"
> 未及时更新——实际已由用户逐批验收：模拟器+真机+浏览器）。原文迁入，只读勿更新。


- **六项体验修（2026-08-04 晚三批，✅ iOS BUILD SUCCEEDED / web tsc+91 vitest 绿；待实测）**：
  1. **Liquid 标题栏避让**：标题盒改按较宽一侧按钮对称收缩（上限 250→220、下限 132→96、两侧留 8pt），
     多选「取消」/右上文字钮不再与标题重叠。
  2. **文本气泡宽度乱变（回归修复）**：文件行结构约束原是常开——hidden 视图仍参与布局，文本气泡被
     44pt 图标位撑最小宽、复用自文件气泡的 cell 被残留文件名撑得更宽。改 `_fileConstraints` 整组随
     文件模式 activate/deactivate + 文本模式清残留内容。
  3. **引用跳转高亮**：`jumpToConvSeq` 滚动到位后对 previewTargetView 盖强调色遮罩淡出
     （accent·0.35，0.3s 停留 + 0.9s 淡出，与 Web quoteflash 同节奏）。
  4. **Web 粘贴文件**：粘贴条对齐 iOS——图片+任意文件都进预览条 chip（文件显类型图标+名字），
     发送键统一发（图片批量成宫格、文件走分片通道）；修 `uploadAndSend` 声明序 TDZ（前移到 send 之前）。
  5. **点空白收键盘**：`handleReplyJumpTap` 入口 resignFirstResponder（微信式）。
  6. **上滑弹跳三修**：①`onMediaSizeResolved` 改带像素尺寸回调 → 写回模型+落库（一次性，之后估高
     首帧即正确）；②拖拽/惯性中不做 begin/endUpdates，记脏滚动停止后补（needsRowHeightSettle）；
     ③新增 `estimatedHeightForRowAtIndexPath` 按类型精确估高（媒体用 `displayHeightForPixelWidth:`
     与 cell 同一套缩放规则）。
  - 跟进小修（同日晚四批，✅ iOS BUILD SUCCEEDED / web tsc+91 vitest 绿）：①标题盒宽度按
    「文字按钮场景」预算（88pt/侧）一次算死——进出多选零跳变（超预算仍收缩防重叠）；
    ②web 粘贴文件 chip 背景变量笔误（--bg-elevated 不存在落 transparent）→ --surface-elevated；
    ③web 引用跳转改「到位后再闪」（视口内立即闪，否则 scrollend/降级定时后闪，对齐 iOS）。
  - caption（图+文一条消息）确认为独立里程碑，下一轮做；**方案已定案入 IMServer/docs/ROADMAP.md（M4-6 caption 追加）**：不新增 content_type/cell，image/video 加可选 caption 字段，现有媒体气泡图下长文字区。
- **多选交互修 + 粘贴图预览条（2026-08-04 晚二批，✅ 改代码未编译；待实测）**：
  1. **进/出多选列表不跳**：新增 `preserveScreenPositionOfRow:during:`（记录锚行屏幕位置 →
     编辑态切换+reload → 两轮布局对齐还原）；进入锚定长按那条、退出锚定视口首条可见消息。
  2. **「取消」键修复**：旧代码用系统 Cancel item（无标题）→ Liquid 统一标题栏回落成返回箭头、
     点击直接 pop 出聊天页。改带标题「取消」item（leftTitle 渲染文字、点击路由 exitSelection），
     enter/exit/updateSelectionUI 补 `refreshUnifiedNavigationBar`（标题「已选择 N 条」实时刷）。
     底部 转发/收藏/删除 三键原本就齐。
  3. **粘贴图预览条（Telegram 式，#2 重设计）**：粘贴不再弹蒙层确认，缩略图 chip 攒在输入栏上方
     （pasteBar，引用条之下；可多张 ≤9、逐张 ✕、横向滚动），发送键统一发出——≥2 张共享 group_id
     成宫格（sendMediaURL 补 m.groupID 本端也聚簇），有文字随后补发文本；发送键可见性计入待发图。
     删除旧 `presentPastedImagePreview` 蒙层。
  4. **引用聊天记录显裸 [chat_record] 三层修**（同批）：服务端 replySnapshot 特判 chat_record 生成
     「[聊天记录] 标题」（test.sh 全绿，**需重启后端**）；iOS/Web localizeSnippet 映射旧 token 兜底存量。
- **长按菜单/多选/合并转发六件套（2026-08-04 晚，✅ 改代码未编译；两端同步，服务端零改动；待实测）**：
  1. **长按预览只圈气泡**：补 `previewForHighlighting/Dismissing`（identifier 带 indexPath），四种 cell
     暴露 `previewTargetView`（气泡/缩略图/卡片），clear 背景 + 圆角 visiblePath——整行宽底色托盘与
     收起残影消除。
  2. **菜单矩阵收敛**：复制=仅文本+已发出图片（file/chat_record 无复制；不再复制 JSON/本地引用）；
     收藏/多选加 convSeq>0；发送中隐藏「删除」（防僵尸上传，撤走用取消发送）。Web menus.ts 同步
     （delete/multiSelect 规则 + 2 条新单测）。
  3. **多选范围**：system/撤回墓碑/待发件（convSeq≤0）无勾选圈（canEditRow / sel-check 隐藏）；
     点按待发件直接 toast「发送中/失败的消息不可选择」；转发/合并转发入口再加 convSeq>0 防御过滤。
  4. **合并转发文件行带名**：JSON items 文件项增 `fn/fs`（两端同写）；卡片摘要「[文件] 报表.xlsx」、
     iOS 详情页文件行=类型图标+原名+大小、点击 SFSafari 打开（对齐 Web）；老记录无 fn 从 URL 反推
     `<随机>__<原名>`（IMMediaFileName，Web fileNameFromContent 同逻辑）。
  5. **引用聊天记录卡片**：快照改「[聊天记录] 标题」（IMChatRecordSnippet / chatRecordSnippet 两端
     同语义），渲染端检测存量 JSON 截断快照就地救援（正则抠 "t" 标题）；引用条加 text.bubble 小图标。
  6. Web 详情页文件行补大小显示（fn/fs 优先，回退 URL 反推）。
- **文件消息布局重构 + 相册文件路径并入常驻服务（2026-08-04，✅ 改代码，按用户要求未编译；待真机实测）**：
  真机反馈「文件面板→从相册发大视频，气泡很久才出现」。根因：旧 `uploadPhotoFiles` 用
  `loadDataRepresentation` 把整个原件拷进**内存 NSData**（2GB 会 jetsam）+ 一次性 multipart 直传，
  上传全部成功后才插气泡。本轮三件套：
  1. **相册文件路径与 Files 路径同构**：选完**立刻上屏** file 气泡（`sendPhotoFileHandles`），句柄新增
     `loadFileURL:`（`loadFileRepresentation` 导出为磁盘临时文件，超时 600s 适配 2GB/iCloud）+
     `suggestedFileName`（秒上屏用）；服务新增 `enqueuePhotoFileHandles:`（asFile 作业，与媒体共用
     串行队列）：导出→落盘落库→上传（≥8MB 分片可暂停续传，<8MB 一次性）→发 file 消息，全程活在
     `IMMediaSendService`。一次性上传完成回调补 file 类型保护（服务端按字节嗅探会把视频文件变回 video）。
     删除死代码 `loadFileData:`。
  2. **文件气泡两栏布局**（IMBubbleCell）：左 44pt 图标位固定 + 右侧文件名（**≤2 行、中间截断保扩展名**）
     + 状态行 + 右下时间/✓✓，替换原「图标当 NSTextAttachment 拼富文本」（长文件名绕到图标下面、
     无行数上限；疑似 4pt 约束冲突源头）。文件行最小宽 190（仅文件模式激活）。
  3. **圆环状态机交互**（与媒体中心按钮同一套 glyph，位置在左图标位）：排队/准备中=✕（点按确认取消）→
     上传中=圆环进度+⏸ → 已暂停=↑ → 失败=↻；一次性小上传只显环无 glyph。点图标=操作
     （`onFileControlTap`→`handlePendingMediaTap:`），点气泡其余区域仅完成后打开文件（didSelectRow
     的文件切换分支已删）；长按菜单「取消发送」覆盖准备中（content 为空也可取消）。第二行文案改
     「准备中… / x MB / y MB / 发送失败」——上传与暂停均纯字节数（「已传」有歧义弃用），暂停态行首加
     ⏸ 小图标（同媒体角标做法），去掉「点击暂停」尾巴。
  4. **修真机必现崩溃**（crash 报告 IMProgram-2026-08-04-090224.ips 实锤）：Files 选 ≥8MB 视频 →
     `sendLargeFileAtURL` 先 addObject 后 `enqueueFileMessage`，而昨日五件套让分片作业入列时**同步**广播
     初始 ⏸ 进度 → `refreshVisibleCellForMessage` 对 tableView 还不知道的新行 `reloadRows` → UITableView
     行数断言 SIGABRT。修复：①先 `appendReloadAndScroll` 再入列（sendPhotoFileHandles 同步对齐）；
     ②`refreshVisibleCellForMessage` 加行数守卫（目标行 ≥ 当前行数 → 整表 reloadData 兜底）。
  5. **跳动/滚动三修**（真机反馈：文件气泡宽度不一且状态切换时跳动、发送/首进不贴底）：
     ①文件气泡**定宽**=0.75×内容区−24（原最小宽 190 会被「120.4 MB / 358.4 MB」等进度串撑宽，
     暂停/完成文案变短又缩窄 → 文件名换行数变 → 行高跳）；②`appendReloadAndScroll` 改精确贴底
     `scrollToAbsoluteBottom`（估高下 `scrollToRow…Bottom` 恒欠滚）；③`onMediaSendProgress`(file)/
     `onMediaSendDispatched` 补「wasNearBottom→重新贴底」（与 MetaChanged/Ack 对称）；④首进
     `viewDidAppear` 兜底贴底去掉 `isNearBottom` 前提（欠滚>80pt 时旧条件恰好放弃修正）。
     加诊断日志：`chat_stick_bottom_not_converged`（6 轮不收敛 WARN）、`chat_initial_position`（Debug）。
     模拟器实测 ①② 通过；「首进不贴底、二进才贴底」由日志锁定两根因并修（2026-08-04 下午）：
     a) **首进有未读**走「停首条未读」分支（设计如此），但锚定用估高且无二次校正——未读只剩末尾
        几条时停在真底部之上 350pt（日志 09:41:02 实锤）→ 新增 `anchorRowToTop:`（scrollToRow→
        layoutIfNeeded 两轮），定位后下一 runloop + viewDidAppear 各重锚一次；未读不足一屏时
        scrollToRow 自带 clamp 即等价贴底。二进未读已清 → unread_row=-1 精确贴底（日志验证 offset
        与 content−viewport 分毫不差）。
     b) **冷启动直进本页**：init 读库为空（账号上下文未就绪）、历史靠 sync 补进，而 reloadData 不触发
        viewDidLayoutSubviews → 定位整场未跑（日志：该会话零 chat_initial_position）→
        didReceiveMessage 首条落地补跑 positionInitialIfNeeded。
     另修回归：viewDidAppear 无条件贴底会把「从资料页返回」也强拉到底 → 加 `didInitialSettle`
     一次性标志（进场后只校正一次）。
  - ⚠️ 未做/限制：相册导出期杀 App 消息消失（PHPicker 句柄一次性，同视频路径，属预期）；导出失败的行
    点 ↻ 提示「本地文件已丢失」（需长按取消后重选）；Files 面板 <8MB 小文件仍为 VC 锚定一次性上传
    （秒级传完，无暂停价值）；未编译未跑单测（用户要求）。
- **水滴头部：共享驱动 + 松手临界吸附重构（2026-08-03，✅ workspace 编译通过，待真机验收）**：
  抽出共享 `IMProgram/Common/IMDropletHeaderMorph.{h,m}` 承载 Zone①（头像吸附 + name/meta 迁移进标题栏
  + 松手临界吸附），详情页与「我」页共用同一驱动 → 改一处两页同步。整页一个 tableView 分两段吸附：
  **Zone①(off 0→H=144)** 头部收拢，临界 A=头像吸附过半(H/2)、快速甩动无视位置补完，`scrollViewWillEndDragging`
  改写 targetContentOffset（仅当惯性落点也在带内才吸附，快速甩动可穿过直达列表）；**Zone②(pin→)** 详情页页签贴顶，
  贴顶线 `tabPinTop=topInset+68`（距标题栏底 12pt），detent 临界 B=运行时半个 tab 高（落点在 (pin,pin+半tab)
  回弹到 pin、tab 仍贴顶）。细节：name↔meta 间距每帧插值收窄到 18.5pt(=标题栏副标题间距)；pills 停靠标题栏下方
  **不再淡出**；页签选中色↔背景色对调(`styleSegmented:`)；`syncScrollInset` 精确到贴顶为止(2(2)a 内容不足一屏禁上滑)；
  「我」页 meta 随统一**不再单独淡出**(跟随迁移)、下拉钳制 44pt+驱动 off≥0 冻结防重叠、name 锁点 top+19 居中进标题栏。
  文档已同步重写：`docs/TELEGRAM_AVATAR_DROPLET.md`。**待真机验收手感**（临界值 0.5、甩动阈值 0.3、H=144 均可调）。
  已提交 `e23c21b`（用户真机测试通过）。跟进轮（2026-08-03，✅ 编译通过，待真机验收）：①「我」页 meta 恢复淡出（驱动加
  `metaFades` 开关，我页=YES）；②贴顶线 `topInset+68→+48`（消除标题栏下方内容外露）；③页签加大：`kTabBarH=52`/
  `kTabSegH=40`/字号 15pt/宽度下限 200；④`syncScrollInset` 重写：内容不足且未贴顶→`bounces=NO` 硬停（完全禁上滑）、
  已贴顶→补 inset 维持；⑤**#4 根因**：长列表贴顶后切短 tab，reload 变短+旧 inset 未更新→offset 被夹回顶，`setContentOffset:pin`
  也被夹——修法：切前预膨胀底部 inset 再设 pin，切 tab 全程维持贴顶。
  再跟进轮（2026-08-03b，✅ 编译通过，待真机）：修正上一轮回归 + 真根因。①「我」页大屏(17PM)内容一屏放得下→不可滚→
  raw 恒 0→name 不迁移：新增 `syncHeaderScrollRoom` 补底部 inset 保证 maxRaw≥H。②`syncScrollInset` **恢复始终补足到 pin**
  （上一轮改成条件补足导致：短内容整页不可滚、点 tab 不贴顶——已修）；短内容仅 `bounces=NO` 贴顶后硬停。③**#4 真根因**：
  行高估算开启使 reload 后 `rectForHeaderInSection`(→pinOffset)不准、`setContentOffset:pin` 落偏 → 关闭 estimatedRowHeight/
  SectionHeader/Footer + 切后下一帧再断言 pin。④贴顶线 +48（上一轮）。
- **系统 Files 选择「选中未发送」回归修复（2026-08-03，✅ workspace 编译通过，`e146c9e`；用户测试通过）+
  面板承载重构（2026-08-03b，✅ 编译通过，待真机）**：
  ①回归根因：上一版（`3cd89d4` 隔离生命周期）把系统 picker 嵌套在文件面板之上、靠面板 `viewDidAppear:`
  状态机收尾——选完文件后命中 `self.presentedViewController` 提前返回、`_documentPickerPresented` 未复位、
  回调从不触发 → 卡回文件面板、文件没发出去、再点日志刷「忽略重复的系统文件浏览器呈现请求」。先以
  delegate 回调 `[self.presentingViewController dismiss…]` 一次性收栈修好（`e146c9e`，用户验收通过）。
  ②再重构（本轮）：既然点叉叉终归回聊天页，回落面板是多余弹跳——**「从文件/从相册」入口统一先关闭面板，
  再由聊天页承载系统选择器**（恢复 `3cd89d4` 之前的结构）：面板 `initWith…onFromFiles:` 只 `dismissThen:`，
  聊天页 `presentDocumentPicker` 全屏呈现 `+systemDocumentPicker` 并作 `UIDocumentPickerDelegate`，选完/叉叉
  由系统关 picker 直接回聊天页，中间不再出现面板。picker 单实例配置仍集中在 `+systemDocumentPicker`。
  ③「返回下载页」经日志确诊为 iOS 26.3 **Simulator runtime bug**（`com.apple.DocumentManagerUICore.Service`
  远程视图服务 `FBSceneErrorDomain Code=2` 崩溃自重启、导致 Files 内部栈被重置），与呈现方式无关，真机无此问题。
- **多端历史连续同步与文件元数据补全（2026-08-02，build/test-build 通过；待跨端实测）**：iOS 将
  `synced_conv_seq` 作为 `(owner_uid,conv_id)` 隔离的独立 SQLite 状态，禁止以本地
  `MAX(conv_seq)`、单条 ACK 或实时见过的最大序号越级推进；消息/会话摘要/连续游标同事务提交，
  多页仅从本页实际连续完成位置继续。账号切换会清空内存游标/in-flight/旧账号未决发送，并用连接
  代次丢弃迟到的旧登录请求与重连任务。重复权威消息会补全当前聊天内存和 SQLite 的
  `file_name/file_size`，不再出现另一端文件长期 0 KB。Web 已同步同一机制，协议见
  `../IMServer/docs/PROTOCOL.md §6.2`；根因、不变量和自动化分层方案已记录在
  `../IMServer/docs/CONTINUOUS_SYNC_AND_MULTI_CLIENT_TESTING.md`。待用户删库后做跨端、断线、
  多页和切账号实测。本轮 `xcodebuild build` 与 `build-for-testing` 均通过。


### 迁移时点的「下一步 / 已知坑」原文（供考古比对）

## 下一步
0. **真机实测本轮文件发送交互**（优先）：文件面板→从相册选大视频应**秒上屏**（准备中…→进度）；
   图标位 ⏸/↑ 暂停续传、✕ 取消（准备中长按也可取消）、失败 ↻ 重试；文件名两行中间截断；
   小文件（<8MB）一次性上传只显环。回归：Files 路径大文件、最近文件复发。
1. **账号切换与连续同步真机/跨端实测**：代码与自动化测试已由用户确认通过；后续在真机验证
   A→B→A 快速切换、旧 Socket/HTTP 回调不污染当前账号，以及断线、多页、连续游标和文件元数据补全。

2. **用户真机测试 M4.5 会话菜单 + 群聊详情页**：
   - 会话菜单四件套（置顶/免打扰/标未读/删除）+ 指示符
   - 群聊详情页全流程（进详情 → 成员交互 → 设置头像 → 管理权限 → 退出/解散）
   - 头像闪动、标签页切换、更多菜单等 UI 细节验收
   - 反馈→迭代修复
   
3. **M4.5-3 统一资料页** 设计稿拍板后开工：
   - 聊天详情页重构为标准资料页（成员页签改为资料页的成员卡片）
   - 设置页逐项（Devices/Folders/Notifications/…按 Telegram）
   
4. 群聊 iOS 欠账（对齐 Web）：群头像上传、群内已读细化、@提醒（M5-6）。

5. 本地媒体文件离线缓存（当前 SQLite 已保存消息与媒体 URL，但远程图片/视频未下载过时离线不可查看）。

6. **账号哈希目录物理分库（后续增强，不阻塞功能迭代）**：未来需要按账号删除缓存、降低单库损坏
   影响面或强化物理隔离时，再迁移到
   `Library/Application Support/IM/accounts/<SHA-256(uid)>/im.sqlite`。届时补目录/建库失败恢复、
   A/B 同 `conv_id` 物理隔离、A→B→A 重开及非法/超长 uid 路径测试；当前不迁移、不读取、不删除旧库。

## 已知坑 / 限制
- CocoaLumberjack 只接管应用主动输出的日志；iOS/UIKit/Network.framework 自身的系统诊断仍由系统写入 Xcode 控制台。Debug 文件日志会保留脱敏后的业务正文，仅用于开发设备，分享日志前仍需复核。
- **登录已支持真账号密码**：登录页「免密登录（开发）」仍保留（凭 uid 直签，需后端 `-dev-login`）。注意 dev-login 建的账号（空密码哈希）无法再走密码登录；测密码登录请用「注册并登录」建新号或清 `imserver.db`。
- **iOS 无双向分页**：进会话一次性全量载入本地 DB；性能轨道、当前不影响使用。
- **presence/typing 仅聊天页标题**生效；会话列表不显示在线点（后续可同 notification 广播 presence）。
- 聊天壁纸为 CG 自绘 SF Symbol 近似，非 Telegram 原涂鸦。
- 测试只跑 `-only-testing:IMProgramTests`（UITests 会因 Accessibility 超时拖垮）。
- 改后端协议字段后**需重启后端**再测；当前继续使用 `Documents/im.sqlite` + `owner_uid`，账号切换由
  database context generation 防迟到串写；账号哈希目录物理分库已降级为后续增强。本轮仍按无旧数据验证。
- 已读=可见即读（已实现）：未读随滚动逐步清；进会话只清当前可见的，需滚到底才全清。↓N 徽标=视口下方未读数，随滚动递减、滚到底隐藏（按 pendingReadSeq 实时重算，非静态）。

