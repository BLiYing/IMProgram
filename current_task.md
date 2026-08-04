# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点
**参与四大任务（2026-08-05）**——协作 IMServer/im-web 讨论方案后实施代码：
1. **任务一**：非好友聊天权限分析 + 群成员资料页交互设计
2. **任务二**：多选消息支持合并转发的聊天记录设计
3. **任务三**：媒体与文件下载设置设计（自动下载、按网络分阈值）
4. **任务四**：文件与媒体消息下载 UI/UX（下载状态、进度、暂停）

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
