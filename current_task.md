# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

**聊天页导航去重 + 折叠 ✅（2026-08-14，build 绿 + test-build 绿，待手测）** — 7 处 `IMChatViewController` alloc+push 收口为统一入口 `+openInNavigationController:...`（单聊/群聊各一，走私有 `+openConvID:inNavigationController:build:seed:`）。
- **折叠（本次核心需求）**：开新会话时截掉栈里**最底部**的聊天页及其之上的所有页（资料页等），新会话接到其原位置 → 「群聊A→成员资料→发消息C」返回直达会话列表（Telegram 行为），且**同一导航栈至多一个聊天页**。纯逻辑抽为文件级 `IMChatCollapsedStack()`，配 `IMChatStackRoutingTests`（6 例，注入谓词免构造真 VC）。
- **复用刷新（修 /code-review 发现）**：命中同会话则 `popToViewController` 复用并 `prepareForReuseEntry`——重装标题/头像按钮（修死播种）、从库合并被压期间错过的消息（修陈旧空洞）、清定位标志重锚到底部。指定初始化器移入 .m 类扩展（外部无法 alloc+push，结构性防回归）；`viewWillAppear` 按 `synced` 游标跨 Tab 自愈；详情页 `originChatInStack` 改委托 `+existingChatForConvID:`（统一查找方向）。
- **已知限制**：去重/折叠只作用于单个 `UINavigationController`；各 Tab 独立栈，跨 Tab 仍可能各存一个同会话实例（数据不丢，靠 appear 合并自愈）。位点入参在复用路径刻意忽略（实例自维护已读/位点）。

**QRCODE P0 + 群组 G3 入群 ✅（2026-08-13，build 绿 + test-build 绿，待手测；iOS 全量测试用户要求暂停）** — 方案 `../IMServer/docs/QRCODE_DESIGN.md` / `GROUP_FEATURES_DESIGN.md` §4-G3、草图 `QRCODE_UX_SKETCH.html`。
- **网络/模型**：`IMHTTPService` 加 `qrMyCard/qrResetMyCard/groupQR/groupQRReset/qrResolve/joinGroup:code:hello:/joinRequests/decideJoinRequest`（新 `runDataRequest:` 保留业务码，join/resolve 靠 `error.code` 分 300210/200110）；`IMFriendlyMessageForCode` 加 200110/300207/300208；`IMGroupInfo.pendingCount`；新 `IMQRModels`（`IMQRResolved/IMQRUserCard/IMQRGroupCard/IMJoinRequest` + 纯映射 `IMQRUserActionForRelation/IMQRGroupActionForCard/…`）+ `IMQRImage`（`CIQRCodeGenerator` 出码 / `CIDetector` 解码，**一图多码** `decodeAllInImage:`）。
- **UI（Modules/QR/）**：`IMQRScannerViewController`（`AVCaptureSession` 取景 + 手电筒 + 相册识别多码候选 + 「扫码/我的二维码」页签；自行 resolve 后 `onResult` 回宿主）→ `IMQRResultRouter`（**落到已有页面**：名片→资料页 `IMChatDetailViewController`、群→加群确认弹窗含 G3 加入/需审批附言/进群/满/黑名单、失效码 200110 提示、外来码域名二确认不自动跳转）；`IMQRCardView`+`IMQRCardViewController`（出码页：进页提亮、保存相册、分享、重置二次确认）；`IMJoinRequestsViewController`（待审列表，同意/拒绝）。
- **入口/帧**：会话列表 `＋` 菜单「扫一扫」置顶 → 扫码；`IMSettingsViewController`「我的二维码」；详情页设置区「群二维码」行；`IMGroupManageViewController` 治理卡「待审入群申请(N)」；`IMSocketManager` group 帧带 `result`（`kIMGroupResultKey`）+ 会话列表 `onGroupEventForJoinResult:` 结果 toast。
- **测试**：`IMQRModelsTests`（resolve 解析 / 动作映射 / 域名 / 申请解析）。**扫码/相机需真机手测**（模拟器无摄像头）。**改了后端需重启带 QR 路由的新二进制再测。**
- **`/code-review` 修复（2026-08-13，三仓 5 项全修）**：iOS 两项——① 扫码页 `startSession/stopSession` 把 `isRunning`
  判定移进串行队列（原先在主线程判，快速切「我的二维码」↔「扫码」会让启动被自己的守卫吞掉、相机永久停住）；
  ② 扫码页「我的二维码」页签补拉 `myProfile` 显昵称+头像（原先只显 uid，对方回扫认不出是谁）。
  另三项在 IMServer（邀请入群原子上限 + 注释订正）与 im-web（重置失败无提示 / 拖非图片文件未捕获）。
- **已知限制**：① `IMQRResultRouter` 群分支用**确认弹窗兜底**（G3 独立「加群预览页」为后续替换项，附言目前是 alert 文本域）；
  ② 相册一图多码用 **ActionSheet 列候选**（草图里是"在图上画候选点"，需图片预览页，未做）；
  ③ 屏幕提亮只在出码页（`IMQRCardViewController`），扫码页内的「我的二维码」页签不提亮；
  ④ `q/l` 登录码（P1）未做——`resolve` 对它一律回 unknown，端上会当外来码显示原文。
- **建议**：完成后跑 `/code-review`（触及扫码/入群，可加 `/security-review`）。

**G2 群治理 ✅（2026-08-13，build 绿，待手测；iOS 全量测试用户要求暂停）** — 方案 `../IMServer/docs/GROUP_FEATURES_DESIGN.md` §G2、草图 §04/§07。
`IMGroupManageViewController` 加三卡（进群确认/全员禁言开关 · 三项「仅管理员」权限开关 + 新成员可见历史 · 黑名单入口，section 化重构避免行索引 bug）+ 新 `IMGroupBanListViewController`（左滑解除）+ `IMGroupInfoViewController` 成员菜单加「禁言…(10min/1h/1d/永久)/移出群聊(cooldown)/移出并不再允许加入(forever)」+ `IMChatViewController` 输入栏禁言锁（`refreshComposerMuteState`：myMuteUntil 或全员禁言且我是 member → inputField.enabled=NO + 占位「你已被管理员禁言」）。`IMGroupInfo` 扩 G2 字段 + `IMHTTPService` 加 setGroupSettings/muteGroupMember/removeGroupMember:ban:/groupBans/unban。**后端补** group.Info 下发开关组。

**G1 群资料闭环 ✅（2026-08-12，build 绿，待手测；iOS 全量测试用户要求暂停）** — 方案 `../IMServer/docs/GROUP_FEATURES_DESIGN.md` §G1、草图 §04/§08。
`IMGroupManageViewController` 三行（简介/公告/全员禁言开关，删「即将上线」占位）+ `IMChatDetailViewController` 设置区加「我在本群的昵称/群备注」行 + 群公告卡 + `IMChatViewController` **公告黄条横幅**（`IMPinnedBannerView` 加 `IMBannerStyleAnnouncement`，排在 G0 置顶蓝条之上，两条叠加算 `contentInset.top`）。`IMGroupInfo` 扩 G1 字段、`displayName`/`nicknameOfMember:` 群昵称优先。`IMHTTPService` 加 announcement/mute/me-nickname 三接口 + `updateGroup` 扩 intro。群备注本地（`NSUserDefaults im_grpremark_<uid>_<cid>`，与单聊备注 `im_remark_` 同范式；后端 remark 就绪、多端同步后续）。

**G0 置顶消息横幅 ✅（2026-08-12，build 绿 + `IMPinnedMessageTests` 8 例，待手测）** — 方案/草图见 `../IMServer/docs/GROUP_FEATURES_DESIGN.md` §G0 与 `GROUP_FEATURES_UX_SKETCH.html` §03（**实现须严格对齐草图**）。
新增 `IMPinnedBannerView`（竖条 + `📌 置顶消息 i/N · 发送者` + 单行预览 + 右侧列表键）与 `IMPinnedMessage` 模型；进会话拉 `GET /conversations/{id}/pinned` 回填，之后靠 `msg_op` 帧重拉；点条=跳转并轮转，列表键=ActionSheet 全部置顶（可取消当前条）；长按菜单加「置顶↔取消置顶」切换对（群内仅群主/管理员）。
**布局要点**：横幅浮在消息表之上、贴 `safeAreaLayoutGuide.top`，用 `tableView.contentInset.top` 顶开内容——**不能用 `additionalSafeAreaInsets`**（它会反过来推动横幅自身约束，形成循环）。
**顺带修**：`op=pin` 的 apply 写死 `pinnedAt = now`，把「取消置顶」也记成置顶；且 `IMDatabase applyMsgOpForConv:` 约定「pinnedAt 传 0 = 不改该项」导致取消永远落不了库 → 认 `payload[@"pinned"]`、约定 `pinnedAt<0` 为清零、通知补 `kIMMsgOpPinnedKey`。

**@选择器改内联下拉面板 ✅（2026-08-12，build 绿·待手测）**：原半屏 sheet 遮挡输入框、没法接着打字匹配 → 改**输入栏上方内联面板**（`IMMentionPickerViewController initInlineWithGroup:`＋`preferredInlineHeight`，child VC 底边贴 `replyBar.top`、随键盘上移、不抢键盘，过滤词由聊天输入框 `updateQuery:` 实时驱动）；`maybePresentMentionPicker` 改 add/update/remove child + `dismissMentionPanel`。

**气泡内 `@昵称` 高亮 + 点击跳资料 ✅（2026-08-12，build 绿·待手测）**：iOS 不落库 per-msg mentions，改由**当前群成员+文本**推导（`mentionMapForMessage:`→name→uid）；`@所有人`仅群主/管理员时高亮（对齐 300204、不可点）；`+[IMBubbleCell attributedContent:base:mentionColor:mentions:]` 挂 `IMMentionUIDAttributeName`，cell 与阅读器共用。**点 `@昵称` 跳资料**：气泡 UILabel 用 `NSLayoutManager` 反查 tap 落点字符属性（`mentionUIDAtPoint:`，收键盘前用稳定布局 + glyph 矩形内才算）、阅读器 UITextView 同法反查（不走已弃用 link 代理）→ `openMemberProfileForUID:`；点击先于长文展开/引用跳转。token 边界同 `IMChatTextContainsMentionToken`、长名优先。

**两项 UX 优化 ✅ 代码完成 + `/code-review` 全修（2026-08-11，build 绿·用户自测）** — 逐端矩阵见 `../IMServer/docs/CLIENT_PARITY.md`「UX」行；与 Web 同步交付。
> 审查修复（iOS 侧）：分档字数改按码点计 `IMCodePointCount`（emoji 场景与 Web 一致）；`groupedCount` 收敛为 `+[IMBubbleCell charCountLabelForText:]`（cell+阅读器共用）；长文/超长**引用**消息点击先于引用跳转判定（否则整条点击被跳转抢占、永远点不开展开/阅读器）。
1. **长文本三档显示**：`IMBubbleCell +textTierForContent:`（分档判据，阈值与 Web `longtext.ts` 一致：huge `chars≥2000|lines≥60`、long `≥300|≥10`）。cell 配置——short 全显；long 折叠前 8 行/400 字 + 「展开全文 ∨ / 收起 ∧」（宿主 `expandedTextKeys` 按 `seq-<convSeq>`/clientMsgID 记忆，点气泡切换并 `reloadRows`）；huge 摘要卡（📄 长文本·约N字 + 3 行预览 + 查看全文 ›）→ 点开新建 `IMTextReaderViewController`（全屏 `UITextView` 只读可选、字号 A±、复制全文）。tap 路由在 `handleReplyJumpTap:` → `handleLongTextTapForMessage:atIndexPath:`。**iOS 无对应单测**（判据可后补 XCTest）。
2. **视频禁复制**：`IMChatViewController` 媒体查看器 `moreActions` 加 `if (!isVideo)` 守卫（图片仍可复制；长按菜单 `messageActionsForMessage:` 的 `copyable` 本就只含 text/image，不含视频）。

**任务二（IMServer 驱动）— 详情页删文件两档 + 返回按钮全局未读徽标 ✅ 三端手测通过（2026-08-11，build 通过）**
> 完整设计/归档见 `../IMServer/current_task.archive.md`「2026-08-11 归档④」；逐端矩阵 `../IMServer/docs/CLIENT_PARITY.md`「任务二」。
- **删文件两档**：`IMProtocol`(delete/msg_hidden 常量)、`IMDatabase`(deleteLocalMessageForConv / totalUnreadExcludingConv)、`IMSocketManager`(deleteMessageForEveryone / removeLocalMessage / msg_hidden 帧 / applyMsgOp op=delete + `IMSocketDidRemoveMessageNotification`)、`IMMessageModel.deletedAt` + `processIncomingMessage` 直加载跳过、`IMHTTPService`(hide / fetchHidden)、`IMChatDetailViewController deleteFileMessage:` 两档 actionSheet（我发的/群主·管理员=为所有人删除+仅删自己；他人=删除）、`IMConversationListViewController` 登录 fetchHidden catch-up。
- **返回按钮全局未读徽标**：`IMLiquidNavigationBar.backBadge`（圆形红底/99+）+ `IMMainTabBarController im_setBackBadgeCount:` + `IMChatViewController refreshBackUnreadBadge`（=全局未读减当前会话，进页 + 收消息/已读位点通知刷新）。
- 三端交叉手测通过；`/code-review` 5 条已全修。

---

**（更早·未编译/未测试）媒体已失效·被动展示占位（2026-08-07，⚠️ 用户要求先改后测）**
> 对齐 im-web + `../IMServer/docs/MEDIA_EXPIRED_UX_SKETCH.html`。三条**被动展示**路径此前对 404 留空白（近乎透明），
> 与"加载中"分不清。统一为失效终态：⊘ + 文案、不重试、不再回源。
- **新增 `Network/IMMediaExpiryRegistry.{h,m}`**：失效登记表（进程内内存 Set）+ `verifyExpiredForURL:`（ranged-GET
  `bytes=0-0` 读状态码，404/410 才登记）+ `IMMediaExpiryDidChangeNotification`。与下载协调器路径（主动下载判失效）互补。
- **`IMMediaPlaceholder expiredOverlayWithCaption:`**：统一失效覆盖层（dim + ⊘ + 文案），四处复用。
- **四处接入**：气泡 `IMImageCell`（resolved 加载失败→复验→失效占位，保留磨砂 thumb 作 dim 底）、相册 `IMAlbumCell`
  （tile `setExpired:` 中心 ⊘）、大图查看器 `IMMediaViewerViewController`（图片失败复验；已知失效视频短路）、
  会话媒体库宫格 `IMConversationMediaViewController`（只读本地不联网，据登记表显 ⊘ + 监听通知刷新）。
  各路径先查登记表命中即失效占位、不回源（掐 404 风暴）。
- **转发/保存失效守卫（2026-08-11 补，build 绿）**：失效媒体转出去对端必 404 → 拦。`IMChatViewController`
  新增 `isMediaExpiredForForward:`（key 用 `fullMediaURL:` 同款解析）——单条转发 `presentForwardPickerForMessage:`
  头部拦（一处盖卡片/长按/详情文件列表三入口）、逐条转发 `forwardMessages:` 跳过+计数 toast、合并转发
  剔失效项+全失效则拦；`IMMediaViewerViewController saveToAlbum` 命中即拦（铁律A 天然成立：有缓存不会被登记），
  并在失效覆盖层藏掉保存钮。
- **已知未尽**：查看器**正在播放**的视频 404 需 KVO `AVPlayer.status`（当前靠气泡/媒体库先探到再短路）；失效标记
  **内存态不持久**（与协调器 `_states` 同 philosophy；原件本就落沙盒磁盘持久，重启按需重新复验一次，不会"重启变透明"）。
- **下一步**：`xcodebuild build`（synced group 会自动纳入两新文件，勿手改 pbxproj）→ 真机手测已删媒体的四处显 ⊘。

**（上一批）下载 UI/UX + 数据存储 + 门控磨砂占位（①–⑧）全部完成**——build/build-for-testing 绿、
磨砂单测 iPhone 17 Pro Max 3/3 绿；**待真机手测**。完成详情已转入 `current_task.archive.md`（2026-08-07 归档块）。

- **手测场景清单**：`docs/DOWNLOAD_TEST_SCENARIOS.md`（新增，基于下载方案 + 门控机制文档）。
- **门控/占位机制规范**（供 Web 对照）：`../IMServer/docs/MEDIA_PLACEHOLDER_MECHANISM.md`。
- **未做/遗留**均记在关联文档，不放这里：下载相关见 `../IMServer/docs/DOWNLOAD_DATA_STORAGE_PLAN.md`（§4 待办 / §5.1 / §6.5）；
  跨端遗留（任务一 P1 全局开关、iOS 通讯录在线绿点等）见 `../IMServer/docs/ROADMAP.md`。

## 下一步
1. **手测（优先）**：照 `docs/DOWNLOAD_TEST_SCENARIOS.md` 跑——门控四类（图片/视频/文件/相册宫格）+ 详情页两 Tab + 设置三层
   + 磨砂占位（气泡 / 引用缩略 / 媒体库）+ 清缓存回退。
2. 待手测暴露问题 → 修；无问题 → 接 `../IMServer/docs/ROADMAP.md` 下一里程碑（caption / 网络恢复秒连 等）。

## 已知坑 / 限制
- **`runAfterKeyboardHidden:` 兜底待测（2026-08-05 记）**：依赖 `resignFirstResponder` 后必然收到
  `UIKeyboardDidHideNotification`——软键盘正常成立；若实测发现硬件/外接键盘等场景引用跳转不触发，
  给它加个 `dispatch_after` 超时兜底。
- 相册导出期杀 App 消息消失（PHPicker 句柄一次性，属预期，微信同）；导出失败的行点 ↻ 提示副本丢失，需重选。
- Files 面板 <8MB 小文件、相机拍摄、粘贴图仍为 VC 锚定一次性上传（秒级传完；粘贴图已带预览条攒批）。
- CocoaLumberjack 只接管应用日志；Debug 文件日志保留脱敏业务正文，分享前复核。
- dev-login 建的账号无法再走密码登录；测密码登录用「注册并登录」或清 `imserver.db`。
- iOS 无双向分页（进会话全量载入本地 DB）；presence/typing 仅聊天页标题生效。
- **查看器"正在播放中"视频 404 未接失效占位（2026-08-11 记）**：`IMMediaViewerViewController` 已有 `item.status`
  KVO（`:233/:240`）但失败一律走「无法播放该视频」兜底；未把 404/410 分出来翻 ⊘ 失效态。窄路径（气泡/媒体库通常
  先探到→进查看器即短路 `:170`），兜底不黑屏故可接受。补法：失败分支改走 `IMMediaExpiryRegistry verifyExpiredForURL:`
  （`item.error` 读不出 HTTP 码，必须 ranged-GET 定性），命中→`showExpiredOverlayForVideo:YES` + mid-play teardown
  （藏 play/poster/进度条、移 playerLayer）。~20-30 行单文件。
- **失效标记内存态不持久（刻意，2026-08-11 记）**：`IMMediaExpiryRegistry` 用进程内 Set。冷启动后失效媒体首帧重探
  一次（去重+ranged-GET，无感），换来**自愈**——后台恢复文件下次启动即翻回，无陈旧标记。仅当服务端上"自动 TTL
  清理"使失效变常态，才回来上"持久化 + 标记 TTL"。
- **系统自带按钮文案本地化（2026-08-12 修）**：QLPreviewController「Done」、UISearchBar「Cancel」等**系统框架自带**文案，
  按「App 声明支持语言 ∩ 设备偏好语言」解析渲染。工程原仅声明 `en`（`project.pbxproj` `developmentRegion=en`/`knownRegions=(en,Base)`，
  Info.plist 无 `CFBundleLocalizations`），故中文设备上所有系统按钮落英文（Done/Cancel/Copy…）。已在 `IMProgram/Info.plist`
  补 `CFBundleLocalizations=[zh-Hans,en]` 声明支持简体中文，一处覆盖全部同类。**未编译验证**（设备语言设中文重装后看查看器/@面板）。
  自有 UI 文案本就硬编码中文，故未建 `zh-Hans.lproj`/改 pbxproj；将来做真·多语言再补。
- 测试只跑 `-only-testing:IMProgramTests`；改后端协议后需重启后端再测。
- **原图路径 JPEG 字节戴 `.heic` 帽子（2026-08-12 记，待第三方选择器落地后自然消除，暂不改）**：
  `IMMediaPicker.m buildImageItem` 原图分支（`:250`）以 `UTTypeImage.identifier` 取字节——**iOS 可能把 HEIC 自动转码成 JPEG 交付**，
  但扩展名却另靠 `hasItemConformingToTypeIdentifier:UTTypeHEIC`（`:254`）**猜**成 `.heic` → 上传文件是 **JPEG 内容 + `.heic` 名**的错配。
  实证：同一次发的两张（当前/自动）服务器上都叫 `photo.heic`，一张真 HEIC(`ftypheic`)、一张实为 JPEG(`FFD8FF`)。
  危害：下载文件名后缀错、凡「信扩展名」的逻辑（如 Web 按扩展名判可否网页预览）会被带偏；Web 端靠字节嗅探/`onError` 已能各自正确显示，
  故非阻塞。**根治**（若不换第三方选择器）：`copyFileForType:outExt:` 已能出真实扩展名，别再 `hasItemConforming` 猜；或直接嗅字节头
  （`FFD8`→jpg / `ftypheic`→heic / `‰PNG`→png）定后缀与 mime。**结论：iOS 计划换第三方相册选择器（任务4），届时此坑自消，现暂不改。**

## 关联工程 / 常用命令
- 后端 `/Users/liying/IOSProject/IMServer`；Web `/Users/liying/IOSProject/im-web`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 测试编译 + 实跑：`xcodebuild build-for-testing ...` → 有 booted 模拟器则 `test-without-building ... -only-testing:IMProgramTests`。
- 真机日志：`xcrun devicectl device copy from --device iPhoneWork --domain-type appDataContainer --domain-identifier com.libeyond.IMProgram --source "Library/Caches/Logs/<file>.log" --destination <dst>`（list 用 `device info files`；崩溃报告 `--domain-type systemCrashLogs`）。
- 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
