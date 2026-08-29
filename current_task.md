# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

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

> **登录页自证后端可达 + 本地网络授权（2026-08-28，`xcodebuild -workspace` build 绿）**：
> 真机连 `192.168.1.12:8080` 密码登录失败、免密"成功"，排查发现是**手机压根没连上 Mac**
> （`imserver.log` 里当天 04:36 后再无任何来自 `192.168.1.x` 的请求，连 `http_request_started` 都没有），
> 而不是密码问题。两处根治：
> - **免密登录改成真发一次 `POST /api/v1/login`**（`IMLoginViewController` `devLoginTapped`）：原来它零网络调用、
>   直接 `enterAppWithHost:`，后端连不上也照样进主界面，把"连不通"推迟到主界面里静默失败 → 误判成密码问题。
>   密码登录/免密登录收敛到共用的 `loginWithHost:userID:password:fallback:`（password 空串即走 dev-login 直签）。
> - **`prepareServiceWithHost:` 加 `invalidateToken`**：`loginWithUserID` 有 10 分钟 token TTL 缓存，命中就直接回调成功、
>   根本不发请求——登录页因此可能"输错密码也进得去"，也看不出后端是否真可达。换 host / 换账号 / 改密码后作废旧 token 本就正确。
> - **`Info.plist` 补 `NSLocalNetworkUsageDescription`**：iOS 14+ App 访问 192.168/10/172.16 私有网段要本地网络授权，
>   缺文案时弹窗没有理由说明、极易被顺手拒绝，此后所有到局域网 IP 的连接静默失败；**重装 App 会重置该授权**，
>   而模拟器走 127.0.0.1 不受限 → 只在真机复现。拒绝后在 设置 → 隐私与安全性 → 本地网络 重新打开。
> - **登录页请求在途转菊花**（同批追加）：三个入口（登录 / 注册并登录 / 免密登录）提成属性，新 `setBusy:activeButton:`
>   ——被点的那个用 `UIButtonConfiguration.showsActivityIndicator`（iOS 15+，不自己塞 `UIActivityIndicatorView`），
>   三个一起 `enabled=NO` 防重复提交。原来点了完全没有进行中反馈，连不上后端时像"点了没反应"。
>   注意 `configuration` 改完要整份回写按钮才生效。Web 端 `LoginView` 同批做了等价改动。
> - **未做**：没加自动化测试（改动是 VC 交互 + plist，测它要 mock `IMHTTPService` 单例；Web 侧那半有 vitest 覆盖）；
>   未做模拟器/真机实测——真机连通性已在 2026-08-28 13:49 验证通过（login/ws/conversations 全 200/101）。

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

> **补做三条（2026-08-27，build + build-for-testing 全绿）**：`/simplify` 复查提出的三条"该单独立项"里，
> 评估后现做两条半：
> - **③ 错误文案与转写文本分离**：通知 userInfo 加 `errorMessage` 字段（Done 用 `text`，Unavailable 用 `errorMessage`），
>   `IMVoiceTranscriber.postError:` 专管失败路径并加 assert 挡回归。观察者失败分支改为 toast + 收起面板——
>   原来"转文字暂未开启"下面还挂"结果可能不完全准确"尾行的自相矛盾场面消失；测试 `testFailedRoutesThroughErrorMessage`。
> - **① 转写文本 NSUserDefaults 加封顶（半步）**：每条一个永久 key、无淘汰、启动时整域解析——加 FIFO 2000 条封顶
>   （单独 `im.voice.transcript.order.v1` 数组键存插入序，超限删最旧那条 defaults 键 + 内存镜像）。**uid 不加回去**：
>   044fa41 刚修完的 key 错位坑不重挖，"跨账号泄漏"复核下来定性不成立（B 命中要求本来就能自己转，属会话共享
>   语义）；落 `IMDatabase` 是正解，属数据层改造单独立项。测试 `testTextCacheKeysPersistAndCanBePurged`。
> - **④ 陈旧 Sending 清扫 + 文档**：`reattachRunningUploads` 加"语音 Sending + convSeq≤0 + content 空"清扫
>   （守卫 `didReclaimStaleVoiceSending`，本 VC 只做一次，避免 push/pop 反复扫误伤本次录音的占位），进程中途被杀
>   遗留的永久 Sending 空气泡 → Failed + note「发送中断，请重新录制」。`ARCHITECTURE.md` 的豁免清单加语音一行——
>   否则下一个人读到"完整方案=接入 IMMediaSendService（记 P2）"注释分不清是有意边界还是遗漏。
> - **② 跳转分类下沉 `jumpToConvSeq:` 明确不做**：复核后否定复查里"Search.m 那两处是复发"——那两处过滤的是
>   搜索结果，不是同一机制。且引用跳转/媒体定位滚到墓碑本来就对（Telegram 同款）；错的只是横幅根本不该挂着这条，
>   而根因（撤回帧到达时本地先剔除）已在上一轮修完。真泛化应改成 `jumpToConvSeq:` 回结果给调用方，属更大重构，
>   等第 4 个跳转入口出现再做。

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
