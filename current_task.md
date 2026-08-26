# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

> **`/simplify` iOS 代码质量清理（2026-08-27，build + build-for-testing 全绿）**：四路复查（复用/简化/效率/层次）
> 对准 `HEAD~2..` 那批（转文字改服务端 + 当日自审修复 + 置顶横幅），去重后落地：
> - **错误码映射单一来源**：删 `IMVoiceTranscriber.messageForErrorCode:`（第二张 code→中文表），
>   5001xx + 100002（全站限流码）并入 `IMFriendlyMessageForCode`；`runDataRequest` 本就把映射结果
>   塞进 `localizedDescription`，转写只需直接用。副作用：**其它所有接口撞 100002 也终于是中文**。
> - **转写观察者改常驻**：原来"每点一次转文字装一个一次性 observer、收到终态才自摘"，块里**强持有 self**，
>   而服务端识别的常态终点是 pending（等 WS 帧）——切后台/掉线/任务被丢就永远不摘，整个聊天页跟着不释放。
>   改为每 VC 一个（弱 self），连点也不再叠加。顺带：块式观察者 `removeObserver:self` **摘不掉**，
>   token 统一收进 `im_teardownVoiceObservers`，宿主 dealloc 调（接力观察者的同款旧漏一并堵上）。
> - **重复请求去重**：`statusByID` 原本只写不读（唯一读者是测试）；改为 `transcribeConvID:` 里
>   「已 Recognizing 就早退」——连点 3 次不再 = 3 个 POST + 3 轮整表行高重算。逃生门是「取消转文字」。
> - **失败语音件改走 `IMPendingMediaStore`**：原来把 tmp 的 `file://` 绝对路径写进 `content`，造出第二种
>   "本地待发"方言——全仓按 `+isLocalRef:` 拦"别当媒体地址用"的护栏只认 `im-pending://`，且 tmp 被系统
>   回收后重试只能提示"录音已丢失"。现与图片/视频同一套（Application Support，杀进程也能重试）。
> - **展示规则收敛**：新 `visibleTextForMessageID:content:`（折叠优先于缓存），cell 复用与长按菜单标题
>   两处不再各拼一遍；新 `expandMessageID:`，缓存命中不必再跑整套 transcribe（含一次假 `token:@""`）。
>   `transcribeConvID:` 去掉 token 位参，内部取 `currentToken`。
> - **淡入淡出抽 `UIView+IMFade`**：HUD 与锁定条的 `wantsVisible` 过期回调自查是逐字两份，收成一处。
> - **横幅根因**：撤回命中置顶横幅时**先本地剔除再重拉**——`reloadPinnedBanner` 是 best-effort，
>   弱网下只靠它收敛，横幅会一直挂着已撤回消息的文案（a9dd9a6 的提示退回成兜底）。
> - 另修：合并失败/成功两分支复制的清理提到分支外、`layoutTranscriptText:` 两个 `if (shows)` 合一、
>   死 import `IMMediaDownloader.h`、三处 SFSpeech 注释残骸（含 `+Menu.m` 那句错误隐私承诺）、
>   `voice_transcript` 通知 userInfo 用回 `kIMConvIDKey`。
> - **明确没做**（复查提出但判定该单独立项）：① 转写文本落 `NSUserDefaults` 无上限/无淘汰/无登出清理，
>   且 key 不带 uid（多账号设备上 A 转出的文本 B 能看到）——正解是落 `IMDatabase`，属数据层改造；
>   ② 「跳不到」的分类本该收敛进 `jumpToConvSeq:`（撤回判定现只在置顶一条链上，Search 另有两处手写
>   `recalledAt` 过滤），下沉会改到 7 个调用点的行为；③ 错误文案与转写文本共用 `text` 字段，UI 无法分辨
>   （错误被塞进转写面板、下面还挂"结果可能不完全准确"）；④ 语音发送并入 `IMMediaSendService`（已在下一步 P2）。
> - **待真机手测**：转文字（首次/缓存命中/取消后重进）、上传失败 → 重试、录音浮层连按两次。

> **语音 P1 全量 + P0 自查修复（2026-08-26，build 绿、待真机手测）**：用户实测报 8 问全部定位修复——
> ① 发送链重做：落库 + ack 回写 convSeq/status（曾 completion:nil → 长按菜单空「无反应」+ 气泡忽隐忽现「错乱」）；
> ② 转发语音修通（曾 attrs=nil 不带 duration 被服务端拒但 UI 报已转发）；三处 attrs 构造放行 voice 带 duration+waveform；
> ③ 大圆钮跟手 + 呼吸环 + 磁吸小锁 `IMVoicePressOverlay`（70pt 高亮/34pt 即锁，此前只有不可见 80pt 阈值＝设计稿缺件）；
> ④ HUD/锁定条不透明主题底（曾 clear 透底重叠 + 硬编码粉色）；⑤ 己方波形 bubbleMeText 配色（曾绿 on 绿看不见进度）；
> ⑥ 中断转锁定暂停（§5.4）+ 删除 >10s 确认 + 暂停时长不再算进 duration；⑦ 详情页语音 tab（曾匹配 audio 恒空）点行播放；
> ⑧ 收藏语音 `IMFavoriteVoiceCell` 迷你波形播放器（曾 SFSafari 打开裸音频）；从收藏发送带 duration+waveform（后端收藏快照加 waveform 列）。
> 拍板：语音支持转发（Telegram 式）；收藏=内嵌迷你播放器。

## 下一步
1. **真机手测回归（重启后端后）**：按住大圆钮跟手→上滑磁吸锁定→锁定行删/停/发；来电中断→回来停在锁定暂停；发送后长按有菜单、气泡稳定；转发语音真的送达；详情页语音 tab；收藏语音播放 + 从收藏发送；scrub/倍速/转文字/接力。异常记回本文件。
2. 遗留 P2：听筒切换（贴耳切 route）；接力连播顶部「停止」控制条；Web 转文字（Whisper 调研）；
   **语音发送接入 IMMediaSendService 常驻队列**（现为 VC 内手工链：已强持有 self 保住"退出页不丢消息"，
   但仍无上传进度/取消，上传失败即删录音无 failed 行）；Web 语音上传期无回显（对齐 useMediaSend 先回显后上传）；
   Web 收藏/气泡语音 404 失效占位（复用 MEDIA_EXPIRY）。中断 vs 手势取消的系统投递顺序仍是赌注
   （多数机型触摸先取消→行为=自动发送，通知先到→锁定暂停；根治需 recorder interrupting 窗口标志）。
3. `setupUI` 抽 `IMComposerBar`（老欠账）；「从收藏发送」入口开放（见「已知坑」）。

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
