# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

**两项 UX 优化 ✅ 代码完成 + `/code-review` 全修（2026-08-11，**未编译·用户自测**）** — 逐端矩阵见 `../IMServer/docs/CLIENT_PARITY.md`「UX」行；与 Web 同步交付。
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
- 测试只跑 `-only-testing:IMProgramTests`；改后端协议后需重启后端再测。

## 关联工程 / 常用命令
- 后端 `/Users/liying/IOSProject/IMServer`；Web `/Users/liying/IOSProject/im-web`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 测试编译 + 实跑：`xcodebuild build-for-testing ...` → 有 booted 模拟器则 `test-without-building ... -only-testing:IMProgramTests`。
- 真机日志：`xcrun devicectl device copy from --device iPhoneWork --domain-type appDataContainer --domain-identifier com.libeyond.IMProgram --source "Library/Caches/Logs/<file>.log" --destination <dst>`（list 用 `device info files`；崩溃报告 `--domain-type systemCrashLogs`）。
- 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
