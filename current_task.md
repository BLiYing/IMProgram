# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

**会话行「[有人@我]↔普通预览」来回闪烁 ✅ 根因修复（2026-08-19，clean build 绿 + `IMConversationCacheTests` 22/22 实跑绿（iPhone 17 Pro Max），UI 观感待手测）** — 读 iOS 落盘日志定位：① `fetchHiddenCatchUp` 每次 `reload` 尾部无条件重删隐藏项，`removeLocalMessageOnQueue` 又**无条件**发 `IMSocketDidRemoveMessageNotification`，列表把它当消息事件再 `reload` → 自激刷新回路（列表 ~0.47s 空转拉全量，日志实测 507 次；回路最后一环 08-18 `12af5e2` 接上才闭合，属最近改出来的）；② 本地缓存表 `im_conversation_local` **无 `mention_unread` 列**（08-11 起潜在旧账），`cachedConversations` 恒 NO，与带 `mention_unread` 的 HTTP 权威列表对同一行「[有人@我]」前缀渲染相反 → 两路在回路里对闪。修：`deleteLocalMessageForConv` 用 `db.changes` 只在真删了行/推进位点时返回 YES，`removeLocalMessageOnQueue` 据此**只在真变更时才广播**（掐断回路）；`im_conversation_local` 补 `mention_unread` 列（建表+幂等迁移+读+写），`markConversationFullyRead` 一并清零。补 `IMConversationCacheTests` 两例（mention 持久化+读到底清零、删不存在行返回 NO）。已提交 `95020a6`。

**IMChatViewController 续拆收官：主文件 1496→725 行（6 轮平移，2026-08-19，逐 commit clean build 绿，纯平移未改行为，待手测）**
- 六个内聚子系统整块平移到分文件 category（逐轮编译过→提交）：
  ① `+PinnedBanner.m`（G0 置顶/BannerStackDelegate/G2 禁言锁，11 法）② `+SendService.m`（IMMediaSendService 发件箱对账/msg_op/徽标节流，15 法）
  ③ `+Nav.m`（标题栏头像钮+资料页入口，7 法含 static 头像绘制）④ `+Group.m`（群资料/备注/群事件/发送者身份，8 法）
  ⑤ `+Presence.m`（对端在线态定时重算/watch/快照，4 法）⑥ `+Position.m`（进会话定位+可见即读节流上报，5 法）
  另：编辑/选择 tableView delegate 6 法并入既有 `+Selection.m`、举报 2 法并入 `+Menu.m`。
- 跨 TU 可见性均按 `+Private.h` 约定收口（被主实现/别的 TU 调或 @selector 接线的方法登记；纯 TU 内自用的不登记）。
  **修 Round① 埋下的 -Wprotocol**：`IMChatBannerStackDelegate` 5 方法均 @required，conformance 从类扩展移到 `(PinnedBanner)` category（对齐 DataSource/MediaFlow/Menu 约定）。共删 8 个搬空后冗余 import。
- **剩余主文件 = 不可再分骨架**：init×2 / 统一进会话入口(工厂法) / 生命周期 / **setupUI(~215 行)** / dealloc（ivar 直接访问 + 构造/视图搭建，category 不可见 ivar，故留主实现）。
  **setupUI 是下一个真正的体量点**：单方法 215 行，§7-正解是抽 `IMComposerBar` 协作对象（自持输入栏/附件面板/粘贴条视图+约束），**非再平移**——留待专门做。
- **待手测**（编译只保符号，交互需模拟器实测）：三横幅顶开表/跳转/置顶 sheet、公告卡、入群申请、禁言锁、发件箱进度回填、外观切换、右上头像进资料页、群成员资料页、在线态副标题、进会话定位到首条未读、可见即读双勾、多选勾选态、举报。

**IMChatViewController 巨类拆分 + /code-review 全修 ✅ 代码完成（2026-08-15～18，clean build 绿，待手测，纯 iOS 端）**
- 4718 行 Massive VC 按《整洁代码》拆分：真·SRP 抽独立对象/纯函数（`IMChatMessageLogic`、`IMPasteImageTextField`、`IMPendingMediaThumbnail`、`IMChatBannerStack` 三横幅栈+delegate）；其余强耦合子系统（全回耦 messages/tableView/nav/socket）按**分文件 category** 平移到多 TU：`+Selection/+Menu/+DataSource/+Media/+MediaFlow/+Mention/+Socket/+Scroll/+Compose`。私有属性/协议/跨 TU 私有方法登记在 `IMChatViewController+Private.h`。主文件 4718→约 1470 行，未改一行行为，逐 commit build 绿。
- **/code-review（high，8 finder）8 项全修**：① `sendTapped` 核心发送路径从 +Mention 挪到 +Compose；② `IMChatBannerStack` delegate 收进 init 参数（杜绝首帧 inset 回调因 delegate 未绑定被吞的顺序坑）；③ `IMReplySnippet` 移到 `IMMediaUtil`（与 `IMRecordItemPreview`/`IMLocalizeReplySnippet` 同族）；④⑤ 本地待发缩略图收口到 `IMVideoThumbnailLoader`/`IMImageLoader` 共享抽帧/降采样口径（消除 600↔720、options 分叉）；⑥ 删 3 处 `IMLooksLikeURL` 宏拷贝、直接调 `IMMediaLooksLikeURL`；⑦ `+Private.h` 分组注释改按业务概念、不再标注定义文件（防搬家失真）；⑧ 本快照就地覆盖。审查结论：**无正确性回归**（跨 TU 无重复方法定义、通知/定时器/socket delegate 拆除配平、横幅重写行为等价）。
- **待手测**：编译只保证符号，**布局/交互需模拟器实测**——键盘顶起输入栏、附件面板、长按菜单光栅化预览、多选态、↓N 跳转、@内联面板、三横幅顶开 tableView。

**相机/粘贴单图收端缺 thumb 磨砂占位 ✅（2026-08-18，clean build 绿，待手测）** — 相机/粘贴单图路径直接 `uploadData→sendMedia`，绕过 `IMMediaSendService` 的 `IMTinyThumbDataURI`，socket payload 无 `thumb`。已把生成器导出为共享函数，在 `mediaAttributesForImage:bytes:` 统一写 `attrs.thumb`（相机+粘贴同覆盖），并回填本地 `m.thumb`（修转发自拍/粘贴图丢磨砂）；`IMMediaPlaceholderTests` 补 data URI 解码 / 20px 尺寸 / 协议长度上限。**单测/手测未跑。**

## 下一步
1. **手测（优先）**：拆分后聊天页全交互回归（见上「待手测」清单）+ 相机/粘贴单图收端磨砂占位 + 转发自拍图有磨砂。
2. 无问题 → 接下一里程碑（后端排队 **语音消息 P0 → 收藏改造**，见 `../IMServer/current_task.md` 与 `docs/ROADMAP.md`）。
3. **收藏页改造设计稿已出（2026-08-19，未动代码）**：`../IMServer/docs/FAVORITES_DESIGN.md` + `FAVORITES_UX_SKETCH.html`。要点=一个 `IMFavoritesViewController` 双模（Browse/Pick）复用；分类「全部+动态」仿详情页 tab（口径复用 `IMChatDetailTabs`）；Pick=卡片式 sheet（仿 `IMFilePickerViewController`）+ 取消/多选/发送全用 `IMLiquidNavigationBar` 玻璃钮；转发复用 `IMForwardPickerViewController`+`forwardEchoContent:`；左侧图标列所有类型恒在（文本=引号色块/链接=链接色块，不留空占位）；点文本进阅读器；后端 `im_favorite` **本次要补 `file_name`/`file_size`**（DDL+老库迁移+service+HTTP+iOS 上报，不降级）。逐功能状态待落地时进 `CLIENT_PARITY.md`。

## 已知坑 / 限制
- **`runAfterKeyboardHidden:` 兜底待测（2026-08-05 记）**：依赖 `resignFirstResponder` 后必然收到 `UIKeyboardDidHideNotification`——软键盘正常成立；若实测硬件/外接键盘场景引用跳转不触发，加 `dispatch_after` 超时兜底。
- 相册导出期杀 App 消息消失（PHPicker 句柄一次性，属预期，微信同）；导出失败的行点 ↻ 提示副本丢失需重选。Files 面板 <8MB 小文件、相机拍摄、粘贴图仍为 VC 锚定一次性上传（秒级；粘贴图已带预览条攒批）。
- iOS 无双向分页（进会话全量载入本地 DB）；presence/typing 仅聊天页标题生效。dev-login 建的账号无法再走密码登录（测密码登录用「注册并登录」或清 `imserver.db`）。
- **查看器"正在播放中"视频 404 未接失效占位（2026-08-11 记）**：`IMMediaViewerViewController` 有 `item.status` KVO 但失败一律走「无法播放该视频」兜底，未把 404/410 翻 ⊘。窄路径（气泡/媒体库通常先探到→进查看器即短路），兜底不黑屏故可接受。补法：失败分支走 `IMMediaExpiryRegistry verifyExpiredForURL:` 定性→失效覆盖层 + mid-play teardown。
- **失效标记内存态不持久（刻意，2026-08-11 记）**：`IMMediaExpiryRegistry` 用进程内 Set，冷启动首帧重探一次换自愈；仅当服务端上自动 TTL 清理使失效变常态才上持久化。
- **系统按钮文案本地化（2026-08-12 修，未编译验证）**：`Info.plist` 补 `CFBundleLocalizations=[zh-Hans,en]` 让 QLPreview「Done」/UISearchBar「Cancel」等系统文案落中文；自有 UI 硬编码中文，将来做真·多语言再建 `.lproj`。
- **原图路径 JPEG 字节戴 `.heic` 帽子（2026-08-12 记，暂不改）**：`IMMediaPicker buildImageItem` 原图分支按 `UTTypeImage` 取字节（iOS 可能把 HEIC 转 JPEG 交付）但扩展名靠 `hasItemConformingToTypeIdentifier:UTTypeHEIC` 猜 → JPEG 内容 + `.heic` 名错配。Web 靠字节嗅探已能各自正确显示故非阻塞；计划换第三方相册选择器（任务4）后此坑自消。
- 测试只跑 `-only-testing:IMProgramTests`；改后端协议后需重启后端再测。
- **聊天页「从收藏发送」入口暂屏蔽/暂不支持（2026-08-19）**：`IMChatViewController` `attachItemTapped:` 的 `favorite` 分支仍走 `im_showComingSoon`（等效屏蔽），**本次不改代码**、仅记录。设计已保留（`../IMServer/docs/FAVORITES_DESIGN.md` §5.5 标 ⏸），待收藏改造统一放开并接卡片式收藏选择器。

## 关联工程 / 常用命令
- 后端 `/Users/liying/IOSProject/IMServer`；Web `/Users/liying/IOSProject/im-web`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 测试编译 + 实跑：`xcodebuild build-for-testing ...` → 有 booted 模拟器则 `test-without-building ... -only-testing:IMProgramTests`。
- 真机日志：`xcrun devicectl device copy from --device iPhoneWork --domain-type appDataContainer --domain-identifier com.libeyond.IMProgram --source "Library/Caches/Logs/<file>.log" --destination <dst>`（list 用 `device info files`；崩溃报告 `--domain-type systemCrashLogs`）。
- 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
