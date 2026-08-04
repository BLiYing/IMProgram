# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

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
