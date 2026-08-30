# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

> **发送失败重发（2026-08-30，**已合入 main**；`xcodebuild build` 零新增告警 +
> `xcodebuild test` **288 例全绿** + `check-file-size.sh` 通过；**模拟器端到端实测通过**）**：
> 此前**只有语音**有可点重发（`IMVoiceBubbleCell` 自造的 SF 符号红标），文本/图片/视频/文件/相册的红❗
> 全是不可点的 `UILabel`，名片/链接卡/合并转发**连红❗都没有**（发失败后既看不出、也无从重发）。
> - **判据收敛成一个纯函数** `IMResendPolicyForMessage`（`IMChatMessageLogic`，10 例单测）：
>   `None`（非本人/非失败/已有 conv_seq/**被拒收**）· `RetryUpload`（本地件重传，换新 cid 安全）·
>   `SameID`（内容已就绪 → **按原 client_msg_id 重发**）。各 cell 与聊天页都读它，不再各判各的。
> - **`SameID` 是本功能唯一的正确性红线**：服务端按 `(conv_id, client_msg_id)` 唯一索引幂等去重，
>   换新 ID 会在「上次其实已存下、只是 ack 丢了」时让对端收到两条。新增
>   `IMSocketManager.resendMessage:toUser:completion:` 按原 cid 重建负载（引用/转发溯源/@/媒体元数据
>   /caption/waveform 原样带回，走 `applyMediaAttributes:` 同一收口）。
> - **被拒收判据用 `note` 而不是 `noteCode`**：noteCode 瞬态不落库，重进会话后归 0，按码判会让
>   「重发必然再被拒」的消息重新变可点。
> - **`file://` 旧方言归入重传**：2026-08-27 前语音失败件落库的 tmp 绝对路径，若按 SameID 原样发出，
>   就是 2026-08-26 修过的那个「对端收到永远打不开的语音」的坑复发。
> - **红❗收进基类**：新 `IMFailBadgeView`（红底白「!」+ 命中区外扩，右侧只放 4pt 免吃掉气泡点击）+
>   `IMMessageCell._failBadge` / `applyFailBadgeForMessage:mine:`；6 个子类只补两条定位约束，
>   `IMBubbleCell`（不继承基类）自持一份同款。语音那份自造红标一并统一。
> - **入口只有红❗**，不进长按菜单、不弹确认（失败重发不是破坏性操作；「取消发送」才确认）。
>   相册整组共用一个红❗ → 点一次重发组里所有失败成员（`IMChatViewController+Resend.m` 统一分派）。
> - **端到端实测**（独立 `-addr :8099 -db <scratch>` 后端，不碰用户的 :8080 与主库）：发一条 ✓ →
>   杀后端发一条 → 20s 后红❗+「未发送 ✗」→ 点❗立刻转「发送中…」→ 再次失败红❗回来 →
>   重启后端等重连 → 点❗ → ✓ 已送达。核对两端库：客户端与服务端 `client_msg_id` **同一个**、
>   服务端只有**一行**，证明没有换新 ID、没有产生重复。
> - **未手测**：被拒收那条的红❗不可点、媒体/语音/相册/名片/链接卡各类型的红❗（判据有单测覆盖，
>   但 cell 布局与点击链路只在文本气泡上实机点过）。
> - **没做**：网络恢复后自动重投队列（现仍是 ack 超时 3×5s 后永久判失败，只能手点）；
>   相机**拍照**/粘贴图仍是 VC 锚定一次性直传，失败连 failed 行都不留（老欠账，与本次无关）。

> **「拍摄」入口支持录像（2026-08-29，worktree `feat/camera-video-capture`；`xcodebuild build` +
> `IMProgramTests` 全绿，**未手测**——模拟器没有摄像头，只能真机验）**：
> 加号面板「拍摄」此前只能拍照——`presentImagePickerWithSource:` 没设 `mediaTypes`，系统默认就是
> `public.image` 一种。三处改动，**不新建相机**：
> - `IMMediaPicker` 加 `+configureCameraPicker:`（照片/视频双模式 + `videoMaximumDuration`
>   + `videoQuality=High`）。**刻意不设 sourceType**：模拟器上设成 Camera 会抛异常，配置与相机是否存在无关，
>   分开才能单测。`videoQuality` 不用 `IFrame1280x720`——那是**全 I 帧**（~29Mbps）文件反而更大，
>   分辨率交给已有的 `AVAssetExportPreset1280x720`。
> - `IMPickedMediaHandle` 加**本地文件句柄** `initWithLocalVideoURL:`（工厂 `+handleForRecordedVideoAtURL:`）：
>   录制产物直接坐进已有的 `_videoTmpURL`（`ensureVideoTmpURL` 本就是"已设则直接返回"），于是
>   `buildVideoItemWithProgress` 一行不改就能跑，还**省掉一次整文件拷贝**（60s 1080p ≈130MB）。
>   `_ip == nil` 是这条路径唯一分叉，三处回落：`loadThumbnail:`（**给 nil 发
>   `loadPreviewImageWithOptions:` 会导致 completion 永不回调、缩略图永久空白**，改直接抽帧）、
>   `suggestedFileName`、`loadFileURL:`；另加 `dealloc` 兜底删未消费的录制原件（转码后 `_videoTmpURL`
>   已置 nil，不会误删）。
> - 聊天页 `didFinishPickingMediaWithInfo:` 按 UTType 分流 → `handleCapturedVideoAtURL:` →
>   **复用相册那条 `sendMediaHandles:`**（乐观气泡 → 720p H.264 转码 → 落盘落库 → 分片可续传 →
>   补传封面 → 发 video 消息），本页不另写上传编排。`openCamera` 顺手把麦克风权限提前问掉（否则系统
>   会在按下录制键那一刻才弹、打断录制）；被拒不阻断，提示放在**录完回到聊天页**时弹（相机全屏时 toast 看不见）。
> - **时长上限 60s**（`kIMCameraVideoMaxSeconds`，系统默认是 600s）。**注意与相册区分：相册选片仍不限时长**。
>   限相机是因为它多两条约束：① `exportVideoAtURL:` 的转码超时**写死 120s**，超时会回落发原编码
>   （设备开「高效」格式 → 收端 Chrome/Firefox 只能看封面播不了）；② 录制原件整份落 tmp，时长翻倍磁盘与
>   转码耗时同步翻倍。60s 转码后 ≈18MB，正好落在分片区间可暂停续传。要更长的走「照片」（相册）或「文件」（原件直传）。
> - **测试** `IMCameraCaptureTests` 7 例：picker 配置口径、时长上限 ≤120s 的护栏、空/不存在文件返回 nil、
>   AVAssetWriter 造真视频跑通 `loadData` 元数据（时长/宽高/落磁盘）、**本地句柄缩略图必回调**（防上面那个坑）、
>   未消费句柄 dealloc 删原件。
> - **没做**：相机**拍照**仍是老的 VC 锚定一次性直传（无发送中占位、失败不可重试）——与粘贴图同款欠账，
>   留给「点红色按钮重发」那批一起做；未接自绘 Telegram 式（点按拍照/长按录像）相机；录像不支持 caption 与 replyTo
>   （与相册发视频一致）。

## 下一步
1. **先验真机能否连通后端**：重装 App → 弹「允许查找并连接本地网络设备」点允许 → 登录页填 Mac 当前 LAN IP，
   免密/密码登录现在都会真发请求，失败会直接显示「无法连接服务器…」；Mac 侧核对 `grep -a '"remote_ip":"192.168' ../IMServer/imserver.log | tail`。
2. **真机手测回归（重启后端后）**：按住大圆钮跟手→上滑磁吸锁定→锁定行删/停/发；来电中断→回来停在锁定暂停；发送后长按有菜单、气泡稳定；转发语音真的送达；详情页语音 tab；收藏语音播放 + 从收藏发送；scrub/倍速/转文字/接力。异常记回本文件。
3. 遗留 P2：听筒切换（贴耳切 route）；接力连播顶部「停止」控制条；Web 转文字（Whisper 调研）；
   **语音发送接入 IMMediaSendService 常驻队列**（现为 VC 内手工链：已强持有 self 保住"退出页不丢消息"，
   但仍无上传进度/取消，上传失败即删录音无 failed 行）；Web 语音上传期无回显（对齐 useMediaSend 先回显后上传）；
   Web 收藏/气泡语音 404 失效占位（复用 MEDIA_EXPIRY）。中断 vs 手势取消的系统投递顺序仍是赌注
   （多数机型触摸先取消→行为=自动发送，通知先到→锁定暂停；根治需 recorder interrupting 窗口标志）。
4. `setupUI` 抽 `IMComposerBar`（老欠账）；「从收藏发送」入口开放（见「已知坑」）。

## 已知坑 / 限制
- **`IMMediaPlaceholderTests testFrostedLandscapeScalesLongestSideTo48` 在高负载下会偶发失败（2026-08-30 首次观察）**：
  全量 `xcodebuild test`（含 UITests，`testLaunchPerformance` 跑 109s 占满机器）时，该用例作为某个
  clone 上的**第一条**执行、耗时 9.5s（正常 2.7s）后失败；单独重跑该类、以及
  `-only-testing:IMProgramTests` 全量（289 例）都稳定绿。判定为冷启动/负载下的抖动，**未定位**。
  与后端 `internal/gateway` 那条间歇失败同类，先记着；再复现请抓 XCTAssert 原文。
- **`runAfterKeyboardHidden:` 兜底待测（2026-08-05 记）**：依赖 `resignFirstResponder` 后必然收到 `UIKeyboardDidHideNotification`——软键盘正常成立；若实测硬件/外接键盘场景引用跳转不触发，加 `dispatch_after` 超时兜底。
- 相册导出期杀 App 消息消失（PHPicker 句柄一次性，属预期，微信同）；导出失败的行点 ↻ 提示副本丢失需重选。Files 面板 <8MB 小文件、相机**拍照**、粘贴图仍为 VC 锚定一次性上传（秒级；粘贴图已带预览条攒批）；
  相机**录像**已改走 `IMMediaSendService` 常驻队列（2026-08-29）。
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
