# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点
- **无进行中开发**（2026-08-04 收口）：文件消息两栏布局+圆环状态机、相册文件并入常驻发送服务、
  长按菜单矩阵/预览只圈气泡、多选（锚定不跳/取消键/可选范围）、粘贴图+文预览条、滚动贴底与
  上滑弹跳修复、标题栏定宽、引用聊天记录快照三层修——**全部已实测通过并提交**（详见归档
  2026-08-04 节 + git log）。水滴头部、系统 Files 面板重构、多端连续同步等此前批次亦已实测收口。
- 已知视觉基线：文件气泡定宽=0.75×内容区；估高按类型精确；媒体尺寸首现即落库。

## 下一步
1. **caption（图+文一条消息）**：方案已定案（`../IMServer/docs/ROADMAP.md` M4-6 caption 追加）——
   image/video 加可选 caption 字段，不新增类型/cell，媒体气泡图下长文字区；粘贴条「图+配文」合成一条。
2. **网络恢复秒连**：`NWPathMonitor` 恢复即重连+重置退避、回前台立即重试（IMServer/current_task.md 已记档）。
3. M4.5-3 统一资料页 + 设置逐项（TASKS §3，待用户拍板）。
4. 群聊 iOS 欠账（对齐 Web）：群头像上传、群内已读细化、@提醒（M5-6）。
5. 本地媒体离线缓存；账号哈希目录物理分库（后续增强）。

## 已知坑 / 限制
- 相册导出期杀 App 消息消失（PHPicker 句柄一次性，属预期，微信同）；导出失败的行点 ↻ 提示副本丢失，需重选。
- Files 面板 <8MB 小文件、相机拍摄、粘贴图仍为 VC 锚定一次性上传（秒级传完；粘贴图已带预览条攒批）。
- CocoaLumberjack 只接管应用日志；Debug 文件日志保留脱敏业务正文，分享前复核。
- dev-login 建的账号无法再走密码登录；测密码登录用「注册并登录」或清 `imserver.db`。
- iOS 无双向分页（进会话全量载入本地 DB，性能轨道）；presence/typing 仅聊天页标题生效。
- 测试只跑 `-only-testing:IMProgramTests`；改后端协议后需重启后端再测。
- 已读=可见即读：↓N 徽标=视口下方未读数，滚到底清零。

## 关联工程 / 常用命令
- 后端 `/Users/liying/IOSProject/IMServer`；Web `/Users/liying/IOSProject/im-web`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 测试编译 + 实跑：`xcodebuild build-for-testing ...` → 有 booted 模拟器则 `test-without-building ... -only-testing:IMProgramTests`。
- 真机日志：`xcrun devicectl device copy from --device iPhoneWork --domain-type appDataContainer --domain-identifier com.libeyond.IMProgram --source "Library/Caches/Logs/<file>.log" --destination <dst>`（list 用 `device info files`；崩溃报告 `--domain-type systemCrashLogs`）。
- 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
