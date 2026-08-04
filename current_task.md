# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点
- **引用增强（M4-2 扩展）iOS 侧已实测收口（2026-08-05，已提交）**：Model/DB 贯通 `replyToFrom`（老库自动
  ALTER；**本端回显同步带值**，review 修复）；共享 `IMLocalizeReplySnippet`/`IMReplySnippetFileName` 入
  IMMediaUtil（替换两 cell 各持 static、修问号图标 magic offset 反解，配 `IMReplySnippetTests`）；群聊
  引用条两行式；跳转失败两句提示（earliest=0 边界并入「不在本地」）。780b6f4 提交边界已补
  （6c7dd96 cell 侧入库）。**逐功能×端状态见 `../IMServer/docs/CLIENT_PARITY.md` M4-2 三行（唯一来源）**；
  交互语义 CHAT_UX §3.1。限制：URL 消息 `IMLinkCardCell` 不显发送者行。
- **URL 链接卡片三修（2026-08-04 晚，✅ iOS BUILD SUCCEEDED；待实测）**：`IMLinkCardCell` 补齐与其他
  cell 一致的能力。①**群聊左对齐**：原缺 `applyGroupAvatarURL:…gutter:`、`_leading` 写死 12 → 群聊对方
  链接卡不留 30pt 头像列，比文本气泡左突出。新增该方法（gutter=48 + 昵称/头像）并在 VC 链接分支调用。
  ②**整体高亮**：`previewTargetView` 从只返回 `_card` 改为返回 `_stack`（网址文本+OG 卡片一起高亮，
  对齐 Web；也修无 OG 卡片时圈到隐藏零尺寸 `_card` 的落空）。③**卡片被压缩滚动后才正常**：OG 预览
  异步展开改行高但无人触发重测 → 加 `onContentSizeResolved` 回调（同 IMImageCell.onMediaSizeResolved：
  cellForRow 内同步命中缓存时延到下一 runloop 防重入、滚动中延迟到停止）。
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
