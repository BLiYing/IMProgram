# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

- **✅ 若干 UI 修复批次（2026-08-03，改代码未编译，用户验收通过并已提交）**：
  ①深色模式下统一 `IMLiquidNavigationBar` 磨砂过亮 → 在 `backgroundGlass` 叠一层随明暗自适应的
  背景 tint（深色 `black·0.55`、浅色透明），压向页面背景色、渐变保留（`480c112`）；
  ②`IMLiquidNavigationBar` 经 init 传入的 `actionTitle` 不触发 Swift `didSet` → 按钮从未 `setTitle`，
  「我」页/详情页右上「编辑」有点击区却不渲染 → `buildView` 内显式落标题（`763df80`）；
  ③建群选择页 `IMGroupMemberPickerViewController` 承载于共享 imLiquidBar，选好友后未触发重新布局
  → 「创建」按钮停留初始 `disabled` 吞掉点击 → `updateSelectionUI` 内补 `[navigationController.view setNeedsLayout]`（`763df80`）；
  ④聊天页日期胶囊「今天」底色写死（橄榄绿/黑）不跟随主题 → 改 `[IMTheme.accent colorWithAlphaComponent:0.64]`，
  与外观页预览同源、白字一致，`configure` 里刷新以随主题切换（`d8b18d7`）。
  另诊断一则**非 bug**：web(1001) 看 1001 自己从 iOS 发的图/视频未读=0 是正确行为——自己发的消息在
  自己其它端永远不计未读（服务端 `unreadCount` 排除 `sender==本人`），非缓存问题。
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
- **✅ 系统 Files 选择与返回链（2026-08-02，iOS 26 真机测试通过；按用户要求未编译）**：
  诊断日志确认应用只创建一次 picker（唯一地址 `0x1078a8000`），随后模拟器的
  `com.apple.DocumentManagerUICore.Service` 连接中断并以 `FBSceneErrorDomain Code=2` 明确报告
  remote view controller 崩溃、系统自动重启；重复 `DOCRemote…` 页面来自这次系统服务重启，不是应用
  重复 present。日志还同时出现 iOS 26.3 runtime 缺失 AppleColorEmoji 字体、IconServices 无法解析
  `com.apple.ios-simulator`。同时发现全局页面日志曾进入 `DOCRemote…` 私有控制器并读取
  `navigationItem`；该属性可能被懒创建，存在干扰系统私有返回栈及远程视图生命周期的风险。现已将
  页面日志严格限制为 `IM*` 自有控制器，在读取 title/navigationItem 前即过滤所有系统/三方页面，并补
  回归测试。另撤回无效且可能排除 `.pages` 等包文档的 `UTTypeData` 规避，恢复 `UTTypeItem`；保留稳定
  宿主、picker 单实例保护和诊断日志。用户已确认 iOS 26 真机选择、返回“浏览”及继续选择均正常，故
  真机功能收口；iOS 26.3 Simulator 的 DocumentManager remote service 崩溃登记为 runtime 限制，若需
  继续追踪应向 Apple Feedback 附最小复现与 sysdiagnose。
- **iOS 单库账号上下文 generation 加固（2026-08-02，用户确认测试通过）**：保留
  `Documents/im.sqlite` + `owner_uid` 逻辑隔离，新增绑定数据库实例、owner 与账号激活代次的
  `IMDatabaseAccountContext`；异步任务以创建时令牌通过原子“校验 + 执行”入口访问数据库。
  Socket、会话列表 HTTP 回调、聊天发送回调及详情页本地操作已接入；A→B→A 后第一代 A 的迟到
  操作无法写入 B 或第二代 A；退出后重新登录同一 uid 也会推进代次。新增 XCTest 覆盖同账号重新
  激活失效、A→B→A 拒写、操作与切换线性化及
  跨数据库实例拒绝。账号哈希目录物理分库降级为后续增强，不阻塞当前功能迭代。
- **多端历史连续同步与文件元数据补全（2026-08-02，build/test-build 通过；待跨端实测）**：iOS 将
  `synced_conv_seq` 作为 `(owner_uid,conv_id)` 隔离的独立 SQLite 状态，禁止以本地
  `MAX(conv_seq)`、单条 ACK 或实时见过的最大序号越级推进；消息/会话摘要/连续游标同事务提交，
  多页仅从本页实际连续完成位置继续。账号切换会清空内存游标/in-flight/旧账号未决发送，并用连接
  代次丢弃迟到的旧登录请求与重连任务。重复权威消息会补全当前聊天内存和 SQLite 的
  `file_name/file_size`，不再出现另一端文件长期 0 KB。Web 已同步同一机制，协议见
  `../IMServer/docs/PROTOCOL.md §6.2`；根因、不变量和自动化分层方案已记录在
  `../IMServer/docs/CONTINUOUS_SYNC_AND_MULTI_CLIENT_TESTING.md`。待用户删库后做跨端、断线、
  多页和切账号实测。本轮 `xcodebuild build` 与 `build-for-testing` 均通过。
- **✅ 文件分页、文件语义与大小展示（2026-08-01，build/test-build 及用户测试通过）**：
  已发送文件服务端游标分页 + 按 uid 隔离 SQLite 缓存、相册原资源强制按文件发送均已由用户验收。
  新增 `file_size` 贯穿发送、转发、Socket 接收、消息模型和 SQLite；聊天气泡/详情文件 Tab 显示
  KB/MB/GB，最近文件第二行显示 `大小 · yyyy-MM-dd HH:mm`，复发继续携带原字节数。界面只
  格式化持久化的 bytes/毫秒时间戳，不重新读取或下载文件计算。`xcodebuild build` 与
  `build-for-testing` 均通过。
- **会话长名与跨端文件图标（2026-08-01，用户真机测试通过；按要求未编译）**：会话标题行改为“名称 → 置顶 → 免打扰”水平 Stack，两个图标紧跟截断后的名称、固定尺寸且统一 `textSecondary` 颜色，时间/已读状态与名称栈分离。用户已确认原创“折角文件卡”样式；同一生成源已输出 iOS Asset Catalog 和 Web SVG，覆盖 21 类主流文件 + 问号未知类型。iOS 已接入最近文件、聊天气泡/引用、详情文件 Tab 和收藏，并新增扩展名映射单测。
- **✅ iOS 本地优先会话 + 长连接状态（2026-08-01，用户已抽查部分真机场景，符合预期；按要求未编译）**：FMDB/SQLite 会话与消息按 `owner_uid` 隔离；消息和会话摘要同事务落库；新增 `server_snapshot_seq` 区分 HTTP 已统计未读与本地增量，避免首次历史同步未读翻倍，并覆盖乱序补拉、重复消息和部分已读。新单聊/群聊/多端发送副本可建立最小会话；编辑/撤回、本人/对端 read 回执及 `conv_update` 设置/删除均同步本地摘要。离线启动会先登记缓存会话，重连后补拉消息并重放本地已读位点，Connected 时自动重取权威列表。会话页先订阅 socket 状态再连接，状态变化立即同步自定义 Liquid 标题栏；WebSocket 写失败进入断线重连；会话、通讯录、黑名单、好友关系、群列表和资料页的自动 HTTP 刷新失败均静默保留当前内容，不弹“登录失败”；用户主动搜索/保存/好友操作的失败仍保留反馈。设计记录见 `docs/LOCAL_FIRST_CONVERSATION_STORAGE.md`。本轮新增测试但遵照用户要求未编译。
- **✅ 聊天 Cell 解耦 + 离线启动保持会话（2026-08-01）**：`IMChatViewController` 内 6 个消息 Cell 已全部迁至 `Modules/Chat/Cells/`，一个 Cell 一对 `.h/.m`（文本气泡、系统消息、图片/视频、相册、聊天记录、链接卡片），控制器只保留数据源与交互编排；已有本地登录态时，App 启动不再先等待 HTTP 静默登录并因服务器不可达跳登录页，而是立即进入主界面，由会话页显示“未连接”并自动重连。新增 `IMSessionStoreTests` 覆盖离线凭据可恢复。`xcodebuild build` 与 `build-for-testing` 均通过。
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

## 下一步
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

## 关联工程 / 常用命令
- 后端 `/Users/liying/IOSProject/IMServer`；Web `/Users/liying/IOSProject/im-web`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 测试编译 + 实跑：`xcodebuild build-for-testing ...` → 有 booted 模拟器则 `test-without-building ... -only-testing:IMProgramTests`。
- 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
