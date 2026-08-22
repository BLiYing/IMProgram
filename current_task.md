# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

> **无待手测活跃项**：会话行闪烁根因修复 / IMChatViewController 续拆收官（1496→725 行）/ 巨类拆分+code-review / 相机·粘贴单图磨砂占位 / 收藏页 B 方案 均已手测通过，细节转入 `current_task.archive.md`（归档于 2026-08-22）。
>
> **下一里程碑 = 语音消息 P0**（设计定稿于 `../IMServer/docs/VOICE_MESSAGE_DESIGN.md` v2，后端未动代码）。iOS 侧承载：录制 UI 单行收纳（B+B 拍板，Telegram 式按住/锁定/播放三态）+ 波形气泡 + 收方长按端上转文字。等后端 `send_msg` 协议/`waveform` 列落定后开工。
> **顺带欠账**：`setupUI(~215 行)` 抽 `IMComposerBar` 协作对象（体量正解，非再平移，专门做）。

## 下一步
1. **接下一里程碑：语音消息 P0**（后端排队最前，见 `../IMServer/current_task.md` 与 `docs/ROADMAP.md`）——等后端协议/DB 列落定后做 iOS 录制 UI + 波形气泡。
2. 语音落地后，收藏页 `content_type` 分类把 `voice` 一起做进去（B 方案已留位）。
3. 欠账：`setupUI` 抽 `IMComposerBar`；「从收藏发送」入口随收藏改造统一放开（见「已知坑」）。

## 已知坑 / 限制
- **`runAfterKeyboardHidden:` 兜底待测（2026-08-05 记）**：依赖 `resignFirstResponder` 后必然收到 `UIKeyboardDidHideNotification`——软键盘正常成立；若实测硬件/外接键盘场景引用跳转不触发，加 `dispatch_after` 超时兜底。
- 相册导出期杀 App 消息消失（PHPicker 句柄一次性，属预期，微信同）；导出失败的行点 ↻ 提示副本丢失需重选。Files 面板 <8MB 小文件、相机拍摄、粘贴图仍为 VC 锚定一次性上传（秒级；粘贴图已带预览条攒批）。
- iOS 无双向分页（进会话全量载入本地 DB）；presence/typing 仅聊天页标题生效。dev-login 建的账号无法再走密码登录（测密码登录用「注册并登录」或清 `imserver.db`）。
- **查看器"正在播放中"视频 404 未接失效占位（2026-08-11 记）**：`IMMediaViewerViewController` 有 `item.status` KVO 但失败一律走「无法播放该视频」兜底，未把 404/410 翻 ⊘。窄路径（气泡/媒体库通常先探到→进查看器即短路），兜底不黑屏故可接受。补法：失败分支走 `IMMediaExpiryRegistry verifyExpiredForURL:` 定性→失效覆盖层 + mid-play teardown。
- **失效标记内存态不持久（刻意，2026-08-11 记）**：`IMMediaExpiryRegistry` 用进程内 Set，冷启动首帧重探一次换自愈；仅当服务端上自动 TTL 清理使失效变常态才上持久化。
- **系统按钮文案本地化（2026-08-12 修，未编译验证）**：`Info.plist` 补 `CFBundleLocalizations=[zh-Hans,en]` 让 QLPreview「Done」/UISearchBar「Cancel」等系统文案落中文；自有 UI 硬编码中文，将来做真·多语言再建 `.lproj`。
- **原图路径 JPEG 字节戴 `.heic` 帽子（2026-08-12 记，暂不改）**：`IMMediaPicker buildImageItem` 原图分支按 `UTTypeImage` 取字节（iOS 可能把 HEIC 转 JPEG 交付）但扩展名靠 `hasItemConformingToTypeIdentifier:UTTypeHEIC` 猜 → JPEG 内容 + `.heic` 名错配。Web 靠字节嗅探已能各自正确显示故非阻塞；计划换第三方相册选择器（任务4）后此坑自消。
- 测试只跑 `-only-testing:IMProgramTests`；改后端协议后需重启后端再测。
- **聊天页「从收藏发送」入口暂屏蔽/暂不支持（2026-08-19）**：`IMChatViewController` `attachItemTapped:` 的 `favorite` 分支仍走 `im_showComingSoon`（等效屏蔽）。设计已保留（`../IMServer/docs/FAVORITES_DESIGN.md` §5.5 标 ⏸），待收藏改造统一放开并接卡片式收藏选择器。

## 关联工程 / 常用命令
- 后端 `/Users/liying/IOSProject/IMServer`；Web `/Users/liying/IOSProject/im-web`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 测试编译 + 实跑：`xcodebuild build-for-testing ...` → 有 booted 模拟器则 `test-without-building ... -only-testing:IMProgramTests`。
- 真机日志：`xcrun devicectl device copy from --device iPhoneWork --domain-type appDataContainer --domain-identifier com.libeyond.IMProgram --source "Library/Caches/Logs/<file>.log" --destination <dst>`（list 用 `device info files`；崩溃报告 `--domain-type systemCrashLogs`）。
- 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
