# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

**无进行中开发。** 下载 UI/UX + 数据存储 + 门控磨砂占位（①–⑧）全部完成——build/build-for-testing 绿、
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
- 测试只跑 `-only-testing:IMProgramTests`；改后端协议后需重启后端再测。

## 关联工程 / 常用命令
- 后端 `/Users/liying/IOSProject/IMServer`；Web `/Users/liying/IOSProject/im-web`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 测试编译 + 实跑：`xcodebuild build-for-testing ...` → 有 booted 模拟器则 `test-without-building ... -only-testing:IMProgramTests`。
- 真机日志：`xcrun devicectl device copy from --device iPhoneWork --domain-type appDataContainer --domain-identifier com.libeyond.IMProgram --source "Library/Caches/Logs/<file>.log" --destination <dst>`（list 用 `device info files`；崩溃报告 `--domain-type systemCrashLogs`）。
- 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
