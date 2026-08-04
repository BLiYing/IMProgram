# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

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

## 关联工程 / 常用命令
- 后端 `/Users/liying/IOSProject/IMServer`；Web `/Users/liying/IOSProject/im-web`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 测试编译 + 实跑：`xcodebuild build-for-testing ...` → 有 booted 模拟器则 `test-without-building ... -only-testing:IMProgramTests`。
- 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
