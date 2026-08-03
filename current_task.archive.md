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
