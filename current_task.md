# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点
**下载 UI/UX + 数据和存储（任务三/四）✅ 阶段 0–5 全部完成（2026-08-06，build 绿，compile-only 未上模拟器，待手测）**
- **新公共件 `IMMediaDownloadCoordinator`**（Network/）：策略判定 / 门控态 / 点击路由 / 落地位置一处实现，
  **聊天页与会话详情页共用**（key=content ⇒ 同一份文件共享一个下载态与进度，转发/重复卡片天然去重）。
  聊天页原先散在 VC 里的 ~100 行编排全部迁入并删除。
- 接入四处：`IMBubbleCell`（文件五态，早前已有）/ `IMImageCell`（**新增 `downloadProgress` + 进度环**，图片与视频门控）/
  `IMAlbumCell`（**逐格门控**：↓ / 环形 / 尺寸角标 / thumb 占位，点门控格=下载而非进查看器）/ `IMChatDetailViewController`（媒体宫格 + 文件行三态）。
- **视频整段预取**：落地到 `IMOriginalVideoCache` —— 查看器早就认这份本地原件，下完点开即**本地播放**、不再流式拉远端。
- **thumb 落库**：`im_message_local` 补 `thumb` 列（迁移表 + INSERT + UPDATE 用 `LENGTH(?)>0` 防空回声覆盖 + 读回），重启后未下载卡片仍有模糊预览。
- **失败分因**：`IMDownloadProgress.expired`（404/410）→「文件已失效」**不给重试**；**无障碍** `accessibilityText` 接四处 cell。
- **修真 bug**：设置页清缓存原先只算/清 `IMDownloads`，漏 `im_original_videos` + `im_image_cache`
  →「显示 0 B 却占几百 MB」「清了还在」「图片清完仍不回退未下载态」。现三目录一起清 + `IMImageLoader clearCache`（连**内存**缓存）。
- **详情页 `autoPrefetchEnabled = NO`**：浏览历史媒体不该顺手把几十条视频拉下来。
- **日志（2026-08-06 补）**：全部走 `IMLogWithTag(IMLogTagMedia,…)`。Coordinator 记**决策**
  （`download_auto_prefetch` / `download_start reason=auto|manual` / `download_result_failed expired=` / `download_image_gate_released`）；
  Downloader 记**传输事实**（`download_request offset=` 断点起点 / `download_range_ignored_restart` 解释进度倒退 /
  `download_http_error status=` / `download_completed bytes= duration_ms=`）；Store 记 `download_settings_applied version=`
  与 `capabilities_update_received version=`（三点对账定位"另一端改了这台没变"）；清缓存记 `media_cache_cleared bytes=`。
  **不在 `stateForMessage:` 里打日志**——它每次 cellForRow 都会走，滚动即刷屏。
- **未做**：后台续传（background URLSession）；详情页文件行长按「转发/删除/在聊天中定位」；超大文件流量二次确认；保存到相册（P1）。
  取舍：聊天页对**滚到的历史视频**也会按策略预取；视频超上限后不再流式播放，需下全片（对齐草图终态 ▶）。

**Typing 提示位置对齐（2026-08-05，待用户手测）**：已移除输入栏上方的提示条；收到 typing 后聊天标题栏副标题显示「正在输入」，3 秒无新帧即恢复单聊在线态或群聊成员数。按本次要求未编译、未跑测试。

**参与四大任务（2026-08-05）**——协作 IMServer/im-web：
1. **任务一** ✅ **P0 完成**：非好友聊天拦截（微信式）+ 群成员资料页交互
   - `200103` 并入拒收落库集合（`IMChatViewController`/`IMMediaSendService`，气泡红❗+系统行）
   - `IMChatDetailViewController`：资料页非好友显「加好友」隐藏「消息/呼叫/视频」（`actionPillSpecs`/`rebuildPillsView`）；
     群成员长按菜单好友→「发送消息」、非好友→「添加好友」（`loadFriendUIDs`/`requestAddFriendUID:`）
   - ✅ 用户实测通过（2026-08-05）
   - 未做 P1（全局开关切 Telegram 式）
2. **任务二**：多选消息支持合并转发的聊天记录设计（待讨论）
3. **任务三**：媒体与文件下载设置设计（待 Telegram 截图 + 讨论）
4. **任务四**：文件与媒体消息下载 UI/UX（待 Telegram 截图 + 讨论）

详见 `../IMServer/current_task.md` 完整需求。

## 下一步
1. **接 IMServer 四大任务方案确认**（等 Telegram 截图）→ 实施代码
2. **caption（图+文一条消息）**：方案已定案（`../IMServer/docs/ROADMAP.md` M4-6 caption 追加）——
   image/video 加可选 caption 字段，媒体气泡图下长文字区；粘贴条「图+配文」合成一条。
3. **网络恢复秒连**：`NWPathMonitor` 恢复即重连+重置退避、回前台立即重试。
4. M4.5-3 统一资料页 + 设置逐项（待用户拍板）。

## 已知坑 / 限制
- **`runAfterKeyboardHidden:` 兜底待测（2026-08-05 记）**：依赖 `resignFirstResponder` 后必然收到
  `UIKeyboardDidHideNotification`——软键盘正常成立；若实测发现硬件/外接键盘等场景引用跳转不触发，
  给它加个 `dispatch_after` 超时兜底。
- 相册导出期杀 App 消息消失（PHPicker 句柄一次性，属预期，微信同）；导出失败的行点 ↻ 提示副本丢失，需重选。
- Files 面板 <8MB 小文件、相机拍摄、粘贴图仍为 VC 锚定一次性上传（秒级传完；粘贴图已带预览条攒批）。
- CocoaLumberjack 只接管应用日志；Debug 文件日志保留脱敏业务正文，分享前复核。
- dev-login 建的账号无法再走密码登录；测密码登录用「注册并登录」或清 `imserver.db`。
- iOS 无双向分页（进会话全量载入本地 DB）；presence/typing 仅聊天页标题生效。
- 测试只跑 `-only-testing:IMProgramTests`；改后端协议后需重启后端再测。

## 关联工程 / 常用命令
- 后端 `/Users/liying/IOSProject/IMServer`；Web `/Users/liying/IOSProject/im-web`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 测试编译 + 实跑：`xcodebuild build-for-testing ...` → 有 booted 模拟器则 `test-without-building ... -only-testing:IMProgramTests`。
- 真机日志：`xcrun devicectl device copy from --device iPhoneWork --domain-type appDataContainer --domain-identifier com.libeyond.IMProgram --source "Library/Caches/Logs/<file>.log" --destination <dst>`（list 用 `device info files`；崩溃报告 `--domain-type systemCrashLogs`）。
- 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
