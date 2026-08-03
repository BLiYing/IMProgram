# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

- **✅ 五处弹窗/菜单风格统一到自定义 `IMPopoverCard`（2026-08-03，改代码未编译、用户验收通过，本轮提交）**：
  三处**点击**菜单——会话列表「＋」、详情页「更多」、`IMMediaViewerViewController`「更多」——统一走自定义
  `IMPopoverCard` 锚点磨砂菜单。其中 MediaViewer 从底部系统 action sheet（`IMBottomSheet`）改为**锚定右下角
  「⋯」按钮、空间不足自动上翻**；`moreActions` 契约 `IMBottomSheetItem`→`IMPopoverCardItem`（调用方
  `IMChatViewController` 同步），**删除 `IMBottomSheet.{h,m}`**（原本只封装系统 `UIAlertController` action sheet）。
  `IMPopoverCard` 图标**从右移到左**（对齐系统长按 `UIMenu` 与微信式），圆角改用设计令牌 `IMTheme.radiusBubble`
  （=14，不写魔法值）。两处 cell 长按（会话列表 / 详情成员）仍**保留系统原生 `UIMenu`**（图标本就在左）。
  取舍：自定义卡片与系统菜单在行高/展开动画/触感上非像素级一致，换取 App 内点击菜单风格统一（方案 B）。
  为何不用系统 `UIMenu` 全统一：曾试做（会自动获得真 Liquid Glass、图标左、锚定翻转全免费），但用户选择
  自定义卡片以保留 Telegram 观感；系统菜单圆角无公开 API 可读、且随 iOS 版本漂移，故走内部设计令牌。
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
