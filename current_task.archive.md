> ⚠️ 历史归档（只读，勿更新）。当前活快照见同目录 current_task.md；本文件只供考古。


---

## 归档于 2026-08-30（群系统消息可读性 · 转发排除系统通知 · 单聊资料页收口 · 失败重发 · 相机录像）

> 从活快照转入（活快照只留当前焦点，见 current_task.md）。


> **群系统消息可读性两条（2026-08-30 用户反馈；`xcodebuild build-for-testing` 绿、零新增告警；
> **按用户要求不启模拟器**，故 `IMSysSegmentTests` 新增 2 例尚未执行）**：
> - **名字段不再用 `IMTheme.accent`**：胶囊底 `datePillBg` 是主题绿（0x5C8A4C@55%），名字再染同为绿的
>   accent，两者色相几乎重合、看不出哪几个字是名字。改新 token **`IMTheme.datePillNameText`
>   （浅琥珀 `0xFFD98A`）+ semibold**——绿胶囊与黑胶囊上都够跳，故深浅两色同值。
>   （先试过白+加粗，与胶囊正文同色只剩粗细之差，用户不要白色。）
> - **我自己那段显示「我」**：口径收敛到 `IMSysSegment.localNameForUID:selfUID:groupNickname:fallback:`
>   （我 > 备注 > 群昵称 > 服务端字面），**聊天页系统行（`+DataSource.m`）与会话列表预览
>   （`IMConversation.lastPreviewTextForSelfUID:`）共用同一个方法**——不共用就会一处「我」、一处自己的昵称。
>   `lastPreviewText` 保留为 `…ForSelfUID:nil`（老口径，不替换）；列表 cell 的
>   `configureWithConversation:mine:host:` 加 `selfUID:` 参数（模型不知道当前账号，由调用方传）。

> **转发选择页不再列「系统通知」会话（2026-08-30；**按用户要求本次未编译、未跑模拟器**）**：
> 与 Web 同批做，后端零改动。
> - `IMForwardPickerViewController` 的 `loadConversations` 拿到会话后先剔除系统通知单聊
>   （`!c.isGroup && IMIsSystemUserID(c.peer)`），再喂 `_convs`；空态判定挪到过滤之后
>   （否则"只剩系统通知"会显成一页空列表而不是「暂无可转发的会话」）。
> - 理由：系统通知是只读会话，服务端直接拒 `send_msg to=system`
>   （`../IMServer/docs/design/SYSTEM_NOTICE_SESSION_DESIGN.md` §2.2），列出来点了必报错。
> - 判定一律走 `IMAccountIdentity.h` 的 `IMIsSystemUserID()`，不写 `@"777000"` 字面量。

> **单聊资料页收口 · 6 条用户反馈（2026-08-30；`xcodebuild build-for-testing` 绿、零新增告警；
> **本次按用户要求只编译不跑模拟器**，故新增单测（`IMFriendStateStoreTests` 7 例 + `IMListSearchTests` +2 例）
> **尚未执行**）**：与 Web 同批做，逐功能状态见 `../IMServer/docs/CLIENT_PARITY.md`「资料 · 单聊资料页收口」行。
> - **进页先闪一遍好友界面再变「加好友」** —— 根因是 `initSingleWithHost:` 里无条件 `_peerIsFriend = YES`
>   （乐观默认），等 `GET /friends` 回来才校正，于是点**非好友**的名片进来会先显示「消息/呼叫/视频 +
>   备注·设置·页签三张卡」再整页翻脸。新增 **`IMFriendStateStore`**（`Common/`，uid → 是不是好友的进程内快照，
>   **三态**：是 / 不是 / **不知道**）：喂入口只有两处且都是全集——`IMHTTPService.friendsWithToken:`
>   （每次拉好友顺路刷新，故加/删好友后自然是新的）与 `IMDatabase.cachedFriends`（本地 `im_friend_local`
>   全量快照，冷启动种子）。资料页 `init` 先问它（`initialPeerIsFriendGuess:`，在 +Peer.m），
>   不知道才回落乐观 YES。**"不知道"必须是独立一态**：塌成"不是"会在冷启动把好友显示成陌生人，
>   塌成"不知道"会在删好友后照旧显示好友界面——两个方向都有单测钉住。
> - **非好友只显「加好友」一个 pill**（`actionPillSpecs` 早退，连「更多」都不显）；系统通知会话不受影响。
> - **「更多」补「删除好友」**（`confirmRemoveFriend`，+Actions.m）：二次确认 → `DELETE /friends/{id}` →
>   `loadPeerBlockState` 重拉关系。**删完不退页**，本页随即切成非好友视图。破坏性最重故置末位。
> - **「用户名」行长按复制**裸句柄（不带 @）+ 轻触感 + 吐司。备注名行与用户名行**分开复用池**
>   （`dRemark`/`dUsername`）——共用一个池会让长按手势跟着 cell 串到备注行上。
> - **`IMFriendPickerViewController` 搜索框左右偏位**：直接把 `UISearchBar` 当 `tableHeaderView` 时，
>   它的宽度停在 `viewDidLoad` 那一刻的 `view.bounds`，UIKit 不保证替你跟到表格真实宽度（本页右侧还有
>   A–Z 索引尺）。新增 `IMListSearchHeaderMake` / `IMListSearchHeaderSyncWidth`（`Common/IMListSearch`）：
>   容器用约束托 bar（水平贴满 + 垂直居中），宽度在 `viewDidLayoutSubviews` 对齐表格；宽度一致即早退，
>   不自激。**转发选择页同因同修**（同一套外观，不改一处就会漂移）。
> - **体量门禁**：`IMChatDetailViewController.m` 贴着 1500 行红线，故 `infoCell:row:` 连同新增的
>   长按复制一并搬去 `+Peer.m`（1494 → 1473）。

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


## 归档于 2026-08-30（登录页自证后端可达 · `/simplify` 代码质量清理 · 补做三条）

> 从活快照转入（活快照只留当前焦点，见 current_task.md）。

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
---

## 归档于 2026-08-22（会话行闪烁根因修复 · IMChatViewController 续拆收官 · 巨类拆分+code-review · 相机/粘贴单图磨砂占位 · 收藏页 B 方案——全部手测通过）

> 从活快照转入。以下均已完成、手测通过（逐 commit 见 git log，逐功能×端状态见 `../IMServer/docs/CLIENT_PARITY.md`）。

**会话行「[有人@我]↔普通预览」来回闪烁 ✅ 根因修复（2026-08-19，clean build 绿 + `IMConversationCacheTests` 22/22 实跑绿（iPhone 17 Pro Max），已提交 `95020a6`）** — 读 iOS 落盘日志定位：① `fetchHiddenCatchUp` 每次 `reload` 尾部无条件重删隐藏项，`removeLocalMessageOnQueue` 又**无条件**发 `IMSocketDidRemoveMessageNotification`，列表把它当消息事件再 `reload` → 自激刷新回路（列表 ~0.47s 空转拉全量，日志实测 507 次；回路最后一环 08-18 `12af5e2` 接上才闭合）；② 本地缓存表 `im_conversation_local` **无 `mention_unread` 列**（08-11 起潜在旧账），`cachedConversations` 恒 NO，与带 `mention_unread` 的 HTTP 权威列表对同一行「[有人@我]」前缀渲染相反 → 两路在回路里对闪。修：`deleteLocalMessageForConv` 用 `db.changes` 只在真删了行/推进位点时返回 YES，`removeLocalMessageOnQueue` 据此**只在真变更时才广播**（掐断回路）；`im_conversation_local` 补 `mention_unread` 列（建表+幂等迁移+读+写），`markConversationFullyRead` 一并清零。补 `IMConversationCacheTests` 两例。

**IMChatViewController 续拆收官：主文件 1496→725 行（6 轮平移，2026-08-19，逐 commit clean build 绿，纯平移未改行为，手测通过）**
- 六个内聚子系统整块平移到分文件 category（逐轮编译过→提交）：
  ① `+PinnedBanner.m`（G0 置顶/BannerStackDelegate/G2 禁言锁，11 法）② `+SendService.m`（IMMediaSendService 发件箱对账/msg_op/徽标节流，15 法）
  ③ `+Nav.m`（标题栏头像钮+资料页入口，7 法含 static 头像绘制）④ `+Group.m`（群资料/备注/群事件/发送者身份，8 法）
  ⑤ `+Presence.m`（对端在线态定时重算/watch/快照，4 法）⑥ `+Position.m`（进会话定位+可见即读节流上报，5 法）
  另：编辑/选择 tableView delegate 6 法并入既有 `+Selection.m`、举报 2 法并入 `+Menu.m`。
- 跨 TU 可见性均按 `+Private.h` 约定收口。**修 Round① 埋下的 -Wprotocol**：`IMChatBannerStackDelegate` 5 方法均 @required，conformance 从类扩展移到 `(PinnedBanner)` category。共删 8 个搬空后冗余 import。
- **剩余主文件 = 不可再分骨架**：init×2 / 统一进会话入口(工厂法) / 生命周期 / **setupUI(~215 行)** / dealloc。**setupUI 是下一个真正的体量点**：单方法 215 行，§7-正解是抽 `IMComposerBar` 协作对象，非再平移，留待专门做。

**IMChatViewController 巨类拆分 + /code-review 全修 ✅（2026-08-15～18，clean build 绿，手测通过，纯 iOS 端）**
- 4718 行 Massive VC 按《整洁代码》拆分：真·SRP 抽独立对象/纯函数（`IMChatMessageLogic`、`IMPasteImageTextField`、`IMPendingMediaThumbnail`、`IMChatBannerStack` 三横幅栈+delegate）；其余强耦合子系统按**分文件 category** 平移到多 TU：`+Selection/+Menu/+DataSource/+Media/+MediaFlow/+Mention/+Socket/+Scroll/+Compose`。主文件 4718→约 1470 行，未改一行行为，逐 commit build 绿。
- **/code-review（high，8 finder）8 项全修**：① `sendTapped` 核心发送路径从 +Mention 挪到 +Compose；② `IMChatBannerStack` delegate 收进 init 参数；③ `IMReplySnippet` 移到 `IMMediaUtil`；④⑤ 本地待发缩略图收口到 `IMVideoThumbnailLoader`/`IMImageLoader` 共享抽帧/降采样口径；⑥ 删 3 处 `IMLooksLikeURL` 宏拷贝；⑦ `+Private.h` 分组注释改按业务概念；⑧ 本快照就地覆盖。审查结论：无正确性回归。

**相机/粘贴单图收端缺 thumb 磨砂占位 ✅（2026-08-18，clean build 绿，手测通过）** — 相机/粘贴单图路径直接 `uploadData→sendMedia`，绕过 `IMMediaSendService` 的 `IMTinyThumbDataURI`，socket payload 无 `thumb`。已把生成器导出为共享函数，在 `mediaAttributesForImage:bytes:` 统一写 `attrs.thumb`（相机+粘贴同覆盖），并回填本地 `m.thumb`（修转发自拍/粘贴图丢磨砂）；`IMMediaPlaceholderTests` 补 data URI 解码 / 20px 尺寸 / 协议长度上限。

**收藏页 B 方案已实现 ✅（2026-08-19，clean build 绿 + `IMFavoritesCategoriesTests` 7 例，手测通过）**：设计 `../IMServer/docs/FAVORITES_DESIGN.md` **§14** + `FAVORITES_B_UX_SKETCH.html`。`IMFavoritesViewController.m` 整体重写为 B：**去「全部」逐签**（媒体/文件/链接/语音/文本/聊天记录，默认媒体）；**媒体=复用详情页 `IMDetailMediaContainerCell` 宫格逐格门控、文件=复用 `IMDetailFileCell` 三态行**（修"未下载文件与详情页不一致"）；右上 ⋯ 玻璃钮→`IMPopoverCard`「以消息/聊天模式查看」（`NSUserDefaults` 持久化，副标题显模式）；**聊天模式=按 `source_conv_id` 分组来源列表（自己发→「我的」）→ 点进按来源过滤子页**；搜索 token 恒=当前签。清缓存联动维持现状。
- （v1 记录，已被 B 覆盖）原实现 Browse 全量：分类分段（`IMFavoritesCategories` 纯逻辑+单测）；范围搜索（内嵌 `UISearchBar` + `UISearchToken`）；统一左图标列；长按菜单（转发/复制/删除）+ 左滑删除；点媒体→查看器、链接/文件→下载 QuickLook、文本→只读阅读器、聊天记录→`IMChatRecordViewController`；转发复用 `IMForwardPickerViewController`；空/错/载入态 + 下拉刷新。Q1/Q2 + 3 项打磨：文件点击对齐聊天页（`IMMediaDownloadCoordinator`+`QLPreviewController`）、聊天记录卡片化、邀请链接走 `IMQRResultRouter`、搜索框圆角 `IMApplyUnifiedSearchFieldStyle`、列表贴近分段。
- **未做**：Pick/「从收藏发送」（聊天入口仍屏蔽，见「已知坑」）；文件"下载环"UI（收藏用副行文案显进度）；副行来源显示名（P1）；媒体保存复用查看器（未进菜单）。
- 后端（`../IMServer`）+ Web（`../im-web`）同批已实现并各自跑绿。

## 归档于 2026-08-07（下载 UI/UX + 数据存储 + 门控磨砂占位 全部收口）

> 从活快照转入归档。以下均已完成（build/build-for-testing 绿 + 磨砂单测 iPhone 17 Pro Max 3/3 绿），**待真机手测**。
> 完整实现原文见 `git log` 与 `../IMServer/docs/DOWNLOAD_DATA_STORAGE_PLAN.md §6.6–6.9`；机制规范 `../IMServer/docs/MEDIA_PLACEHOLDER_MECHANISM.md`；
> 手测场景 `docs/DOWNLOAD_TEST_SCENARIOS.md`；未做/遗留见计划文档 §4 待办/§5.1/§6.5。

- **下载 UI/UX 任务三/四（阶段 0–5，2026-08-06）**：`IMMediaDownloadCoordinator`（策略判定/门控/路由/落地，聊天页+详情页共用，key=content 去重）；
  四处接入（`IMBubbleCell` 文件五态 / `IMImageCell` 图片视频门控+进度环 / `IMAlbumCell` 逐格 / `IMChatDetailViewController` 媒体宫格+文件行三态）；
  视频整段预取落 `IMOriginalVideoCache`；`im_message_local` 加 `thumb` 列；失败分因（404/410 不给重试）；清缓存三目录一起清 + `IMImageLoader clearCache`。
- **多轮 code-review 收口（2026-08-06~07）**：点下载卡死/列表跳变根因（改就地更新，`onProgress` 绝不 reload）；三设置页标题栏改 UIViewController+内嵌 InsetGrouped；
  详情页文件列表去右侧配件、改长按菜单（转发/定位/删除，删除占位）；取消下载错显「已下载」根因（走 notifyChanged）；定位滚动挂 transitionCoordinator。
- **门控磨砂占位（2026-08-07，本批最终收口）**：**根因**——门控视频「必现不显示小模糊 JPEG」是 `IMImageCell` 门控分支 `isVideo && poster` 优先取封面、
  使内嵌 thumb 成死代码（web 每视频都生成 poster 故必现，非并发）。**修**：门控占位一律 thumb 优先（方案 A·纯净，零额外流量，无 thumb 才灰底）。
  新公共件 `IMMediaPlaceholder`：`frostedForThumb`（thumb dataURI→高斯磨砂，代理 48px/σ=4，后台渲染+缓存，本地 base64 解码）与
  `previewForURL`（**集中**「真帧仅已下载>thumb 磨砂>nil」）。**两档刻意分开**：聊天气泡/详情宫格=协调器策略门控（下载控件，档 A，直调 frostedForThumb）；
  引用缩略（输入框条+气泡引用块）+ 会话媒体库宫格=被动预览（只读本地绝不联网，档 B，走 previewForURL），`IMMediaItem` 加 thumb。引用条 `replyingTo` 防串图。
  三点日志 `media_gated_render`/`media_gated_thumb_dropped`/`incoming_media`；新增 `IMMediaPlaceholderTests`。
  code-review 7 条：F1 解码走 base64、F2 引用条防串图、F5 单测、F7 媒体库纳入门控 已修；F3/F4 skipped、F6 self-correcting。
- **Typing 提示位置（2026-08-05）**：移到聊天标题栏副标题「正在输入」，3s 无帧恢复；待手测。

---

## 归档于 2026-08-05（引用消息增强收口，转入四大任务协作）

**当时焦点**：
- **无进行中开发（2026-08-05 收口）**：近期批次均已**实测通过、提交并推送 origin/main**——① 群聊气泡对方
  头像 → 成员资料页（`openMemberProfileForUID:` 复用单聊 `IMChatDetailViewController`，微信式）+ 引用跳转
  键盘时序修复（先反查源消息、后收键盘、`jumpToConvSeq` 经 `runAfterKeyboardHidden:` 延到 inset 落定）；
  ② 引用增强 M4-2（`replyToFrom` 群聊发送者两行式 / 文件名快照 `[file] 名`+类型图标 / 跳转失败两句提示，
  含 /code-review 10 条修复）。更早批次——文件消息两栏+圆环状态机、相册文件入常驻服务、长按菜单·多选·
  合并转发、统一 Liquid Glass 导航等——亦均已实测收口。
- **URL 链接卡片三修（2026-08-04 晚）**：`IMLinkCardCell` 群聊左对齐 gutter=48 / 整体高亮 / 高度重测。
- **已知视觉基线**：文件气泡定宽=0.75×内容区；估高按类型精确；媒体尺寸首现即落库。

**当时下一步**：
1. caption（图+文一条消息）
2. 网络恢复秒连
3. M4.5-3 统一资料页 + 设置逐项
4. 群聊 iOS 欠账（对齐 Web）

---

## Status（2026-08-05：引用增强 M4-2 + 头像进资料页 + 键盘时序，从活快照迁入）
> 均已实测通过、提交并推送 origin/main；逐功能×端状态见 `../IMServer/docs/CLIENT_PARITY.md` M4-2 三行（唯一来源）。
- **群聊气泡对方头像 → 成员资料页**（`3a757b0`，用户实测通过）：`IMBubbleCell` 加 `onAvatarTap`（`_avatar`
  开 userInteractionEnabled + tap 手势 → `handleAvatarTap` 回调）；VC `openMemberProfileForUID:` 复用单聊
  `IMChatDetailViewController initSingle…` + `showsMessagePill`，仅群聊对方气泡挂载（单聊/自己不挂）。落实
  「点成员先进资料页」跨端约定（微信式）。
- **引用跳转键盘时序修复**（`3a757b0`）：`handleMessageTap` 原「先 `resignFirstResponder` 再
  `indexPathForRowAtPoint`」使坐标反查落在键盘收起动画中间态、取错源消息（表现为跳到别条/高亮错行）。改为
  先反查取 m、后收键盘；键盘弹起时 `jumpToConvSeq` 经新增 `runAfterKeyboardHidden:`（一次性听
  `UIKeyboardDidHideNotification`）推迟到 inset 落定后执行。**待测兜底**：硬件/外接键盘不发 DidHide 时加
  `dispatch_after` 超时（见活快照「已知坑」）。
- **引用增强 M4-2 iOS 消费**（`f582d8f`）：Model/DB 贯通 `replyToFrom`（老库自动 ALTER、本端回显同步带值）；
  共享 `IMLocalizeReplySnippet`/`IMReplySnippetFileName` 入 IMMediaUtil（替两 cell 各持 static、修问号图标
  magic offset 反解，配 `IMReplySnippetTests`）；引用条两行式群聊发送者；文件名快照 `[file] 名` + 类型图标；
  跳转失败两句提示（earliest=0 边界并入「不在本地」）。/code-review 八角度 10 条全修复，含 780b6f4 提交边界
  治愈（`6c7dd96` 补 IMLinkCardCell cell 侧入库）。

## Status（2026-08-03 迁移：统一导航 Liquid Glass 大改造 + M1~M3-5 里程碑历史，从活快照迁入）
> 以下条目原在 current_task.md「当前焦点」，均已完成/提交，为保活快照精简而迁入归档（只读，勿更新）。

- iOS 导航统一：详情页及所有 Tab/普通页面统一使用 `IMLiquidNavigationBar` 自定义 Liquid Glass 导航；详情头像统一圆形布局，HTTP 头像可点击预览；规范见 `docs/LIQUID_GLASS_NAVIGATION.md`。
- 本轮未编译：统一导航中间标题改为纯文字、单图标操作改为圆形按钮；会话列表增加导航安全区避让；聊天页恢复右上头像、群聊成员数副标题并铺至状态栏；“我”页收藏入口以上改为头像/昵称/账号信息头部，含二维码与编辑按钮。
- 最新调整（未编译）：普通页面标题与右侧按钮垂直对齐；仅聊天页保留标题玻璃背景并显示群成员副标题；聊天头像改为直接使用 UIBarButtonItem 图片以保证可见和可点击；“我”页头部按 Telegram 风格重新留白，并随滚动淡出头像/资料、在顶栏显示昵称。
- **✅ Telegram 导航头部对齐（2026-08-01，用户测试通过；按要求未编译）**：详情页与“我”页统一用 120pt 滚动进度、相同圆形接近/水滴颈部/暗色融合参数；两页初始导航磨砂为 0，随折叠渐入且底缘渐隐；修正“我”页误把额外 56pt 导航避让计入头像坐标而导致头像落在标题栏下方；聊天页恢复自定义标题栏 56pt 顶部避让，首条消息不再与标题栏重叠。实现依据为 Telegram `PeerInfoScreenImpl / PeerInfoHeaderNode`、`DynamicIslandMaskNode / DynamicIslandBlurNode`。
- Telegram 上下文菜单对齐（2026-08-01，按要求未编译）：`IMPopoverCard` 从 iPhone 底部 Action Sheet 重构为按钮旁展开的磨砂圆角菜单，包含右侧图标、分隔线、危险操作红色、轻遮罩及弹性进出场；详情页“更多”和会话列表“+”共用该组件。单聊详情不再创建“编辑”操作，且统一导航会在操作为空时同步隐藏按钮及磨砂承托。
- Telegram 原始水滴遮罩（2026-08-02，按要求未编译、待用户真机自测）：引入 `lottie-ios 4.6.0`，将 Telegram `UserAvatarMask.tgs` 无损解压为同内容 JSON 资源；新增公共 `IMTelegramAvatarMaskView`，以 `contentOffset / 120` 直接定位原始 60fps 矢量动画进度，并照搬 `DynamicIslandBlurNode` 的连续暗色模糊、径向渐变、黑色渐隐和 `0.03` 遮罩切换阈值。根据用户提供的 Telegram 录屏复核并修正首版错误几何：头像不再随旧三段轨迹缩至 18pt，而是像 Telegram 一样最小保持 55% 并随滚动线性上移；原始遮罩保持独立 171×171 固定在灵动岛下方，通过与移动头像相交产生真实拉丝/水滴吸入轮廓，不再把整份动画错误压缩进头像 bounds。详情页与“我”页共用相同参数；新增不依赖 Swift 生成头文件的 XCTest 资源校验，但遵照用户要求未编译/执行。
- 二次修正（未编译）：聊天头像强制使用原色渲染并在占位图/网络图更新后主动刷新统一导航，群资料返回后同步刷新成员数副标题；“我”页移除静态大 Header，二维码/编辑归入左右导航按钮，头像/昵称/手机号改为悬浮头部并复用详情页的圆形接近、平口水滴、模糊渐黑和吸入灵动岛滚动阶段。
- 已提交上述统一导航与资料页基线：`3b98347 feat(ui): 统一 Liquid Glass 导航与资料页交互`。其后未提交修正：导航栏新增覆盖状态栏的透明磨砂层；详情页搜索/更多移入透明 tableHeader、彻底绕开 grouped 卡片背景；详情返回不再恢复系统导航栏；设置头像改用详情页同款 92pt / `topInset + 58` 初始几何。workspace 模拟器编译通过。
- **✅ 全局 Swift/Objective-C 混编导航栏（2026-08-01，待用户模拟器验收）**：新增 Swift
  `IMLiquidNavigationBar`，由 `IMMainNavigationController` 承载所有 Tab 根页及普通 push 页面；详情页继续
  复用同一组件并保留 Objective-C 业务、头像形变、导航栈和侧滑返回。
  系统 `UINavigationBar` 在详情页隐藏，避免历史菜单和多套标题栏重叠。已设置 `SWIFT_VERSION=5.0`，
  Xcode 模拟器编译通过；按 `docs/DEPLOY.md` 成功安装并启动 iPhone 16e 模拟器，首屏截图无崩溃。
  详情页初始只显示独立返回按钮和右侧“编辑”，中间标题胶囊/副标题默认隐藏，随头像水滴吸附进度渐显；
  群聊头像不再叠加相机按钮，编辑统一从右上角进入。按用户录屏将吸附重构为“圆形接近→顶部固定形成
  水滴颈部→主体向上收缩并没入灵动岛”三段；移除完成时整条导航栏鼓胀，避免返回/编辑闪动；操作排
  去除外层卡片背景并修正 URL 图片头部重复安全区间距，Swift 导航按钮显式响应深浅色切换。第二轮
  对照 Telegram 官方 `DynamicIslandMaskNode/DynamicIslandBlurNode`：吸附遮罩增加平口颈部、暗色模糊
  与黑色渐隐；大图态导航按钮强制白色并随折叠回到动态 label 色；标题与操作排相交前淡出，操作排
  接近顶栏时整体淡出。会话列表加号崩溃根因是把 `UIBarButtonItem` 当 `UIView` 锚点，已新增专用
  barButtonItem popover 入口并修正 sender 类型。
- **iOS 导航与弹窗修正（2026-07-31，待真机验收）**：会话列表、群聊列表的加号改为与通讯录
  相同的标准 `UIBarButtonItem`，由系统负责与标题/返回键分组和 Liquid Glass 按压动画；详情页
  恢复系统导航栏与系统返回键，不再绘制自定义返回按钮。聊天右上头像改为 Glass 按钮自身承载
  圆形头像图像，避免 iOS 26 导航栏布局时只剩空圆圈或点击区域失效。`IMPopoverCard` 与
  `IMBottomSheet` 改为 UIKit `UIAlertController` action sheet，移除自绘浮层/底部面板；项目中
  现有确认弹窗本来就是系统 API，继续沿用。按用户要求本轮未编译。
- **iOS 导航与官方 Liquid Glass（2026-07-31，待真机验收）**：三个主 Tab 改用统一导航容器，
  所有非根页面 push 时自动隐藏底部 TabBar，并恢复系统边缘侧滑返回；会话/群列表加号统一为
  44 pt 真正交互的 Glass Button + 17 pt SF Symbol，恢复官方按压动画。新增 `IMGlass.h`：iOS 26
  使用官方 `UIGlassEffect` 与 Glass Button Configuration，iOS 15～25 降级系统材质。聊天页右上
  头像改为 44 pt 真 Glass 按钮 + 30 pt 严格圆形头像；普通页面统一走系统导航栏、图标式返回键和
  标准 `UIBarButtonItem`，由 iOS 26 自动形成左/中/右分离 Glass；详情页保留头像形变，但返回键
  改由系统导航栏提供，编辑操作和内容层继续使用 Glass；操作排上移并改 Glass，通用弹窗改官方效果。
  底部改用 iOS 18+ `UITab`，会话/通讯录/我融合成主组，搜索以 `UITabPlacementPinned` 成为右侧
  独立项，iOS 26 由系统呈现截图式 Liquid Glass；iOS 15～17 回退四项标准 Tab。Xcode 26.2
  iOS Simulator compile-only 已通过；未执行测试和运行时 UI 冒烟。
- **iOS 外观个性化三轮（2026-07-31，待真机验收）**：按截图进一步统一卡片层级和留白——主题颜色、显示模式、聊天外观、应用图标均为独立卡片，左右 16 pt、卡片间 24+ pt，分割线统一 `IMTheme.separator`；新增 `cardBackground`（`secondarySystemGroupedBackgroundColor`），保证浅色白卡、深色深灰卡均与 grouped 页面分层；四个分组标题显式与卡片左边缘对齐。新增四套普通 Image Set，由实际 App Icon 原图缩成 256×256，图标网格不再使用 SF Symbol 回退。重复点当前图标不再调用系统切换接口；iOS 公开 API 成功切换后的系统提示由系统强制展示，无法合规关闭。高级外观增强已登记 `../IMServer/docs/TASKS.md`。上一版 build + test-build 已通过，本轮按用户要求未编译。
- **✅ 会话菜单与交互动效修复（2026-07-31，用户真机测试通过）**：右上角加号菜单改为同一 host 单实例，阻止导航栏连续点击叠出多张卡片；置顶/取消置顶保持服务端确认后再本地按权威排序平滑移动行，随后静默同步；聊天附件面板首次创建先完成 Auto Layout，修正从左上角错误起跳。按用户要求未编译。
- **✅ 三端统一品牌图标与启动页（2026-07-31，用户测试通过）**：iOS AppIcon 接入未来感即时通讯共用图标（双气泡无限连接 + 实时脉冲），使用不含透明通道的 1024×1024 PNG，由系统负责圆角蒙版；原空白 `LaunchScreen` 已改为深海军蓝底、居中品牌图，并提供 1x/2x/3x 资源。按用户要求未编译。
- **三端日志与文档治理（2026-07-31）**：新增 `docs/LOGGING.md` 记录 iOS 的 CocoaLumberjack/HTTP/WS/DB/UI 使用规则，并引用 IMServer 的跨端共同契约；工程约定要求后续新增业务/技术 Markdown 统一放入 `docs/`，根目录入口文件除外。
- **✅ iOS 统一日志（2026-07-31）**：接入 CocoaLumberjack 3.9.x，应用自有日志全部经 `IMLog.h` 输出到 Xcode 控制台和滚动文件；按 `IM.APP/HTTP/WS/DB/UI` 分 tag。HTTP 请求/响应统一携带 `X-Request-ID`，用同一 `[req=…]` 关联并记录耗时、状态码、脱敏且最多 16 KB 的正文；multipart/binary 及 JSON 内嵌 Data URI 仅记元数据，Release 隐藏业务与非 JSON 正文。新增 `IMHTTPLogFormatterTests`；`xcodebuild build` 与 `build-for-testing` 已通过，真机已确认 Tag、请求关联及 password/token 脱敏正确。
- **仓库卫生（2026-07-31）**：根目录 `.gitignore` 已忽略 `.codegraph/` Codex 本地索引。
- **✅ 群聊详情页完整实现已提交（2026-07-13，commit e4270a8，已 push）**
  - **IMChatDetailViewController** 新增会话详情页（群聊为主，单聊备用）
  - **IMChatDetailTabs** 动态标签页（群成员 + 媒体 / 文件 / 链接）
  - **IMGroupManageViewController** 群管理入口（设置头像、编辑群名、成员管理）
  - **IMPopoverCard** 通用浮层卡片（会话菜单 + 详情页操作菜单共用）
  - **优化**：图片加载缓存、头像复用全局渲染、数据库查询接口扩展
  - **单测** IMChatDetailTabsTests 覆盖标签页逻辑（build + test-build 绿）
  - **待真机验证**（用户自装测试）
  
- **M3-5 群聊 iOS 端完成（2026-07-11，build+test-build 零 error/warning，模拟器实跑测试全绿；真机走查待用户）**，镜像 Web（`../im-web` M3-4）交互：
  - **模型/网络**：`IMGroupInfo`/`IMGroupMember`（角色 owner/admin/member 枚举 + 脏数据安全解析 + `nicknameOfMember:`）；`IMConversation` 加 `isGroup/name/avatarURL/memberCount/lastFromNickname`；`IMMessageModel.fromNickname`（`new_msg.from_nickname`，随消息落库——`IMDatabase` 加 `from_nickname` 列老库自动 ALTER）；`IMHTTPService` groups 接口族（create/list/info/update/invite/leave/remove/setRole/transfer）+ 3002xx 友好中文（**300204 不映射**，透传服务端原因如"群主需先转让"）；`IMSocketManager` `group` 帧 → `IMSocketDidReceiveGroupEventNotification`（event/convID/target）+ `sendText:toConv:`（群按 conv_id 路由、to 留空）。
  - **UI（新增 `Modules/Group/`）**：通讯录「群聊」入口 → `IMGroupListViewController`（我的群列表 + 右上 + 建群：`IMGroupMemberPickerViewController` 好友多选 → 起群名弹窗 → 建群即进群聊）；聊天页群模式（标题"群名（N人）"、右上 ⓘ → `IMGroupInfoViewController`、对方气泡内顶部主色小字**发送者昵称**（from_nickname→成员表→uid 三级回退）、typing 显示"谁"在输入、**被移出→吐司+0.9s 后退出本页**、非群成员发言被拒 300203 挂系统行）；群资料页（成员列表+群主/管理员徽章、邀请（picker 排除已在群）、退出群聊（群主被拦文案透传）、改群名（owner/admin 右上铅笔）、点成员 ActionSheet 管理：设/撤管理员·转让群主·移出，按 my_role 权限矩阵显隐，服务端二次校验）；会话列表群项（群名/群头像、预览"昵称: 内容"，群项不显示 presence/✓✓）+ `group` 帧节流刷新。
  - **测试**：`IMGroupTests` 8 例（角色映射/群资料+成员解析/脏数据/群列表/会话群项/from_nickname 解析+落库往返），模拟器实跑全绿。
  - **端对齐扫描（iOS↔Web）**：群功能逐项对齐（入口/建群/群会话昵称气泡/群资料/成员管理/group 帧/被移出处理）；仅交互载体差异——Web 点标题开群资料弹窗，iOS 右上 ⓘ 推页（等价入口）。
- M2「状态与可靠性」iOS 全部达成 + Telegram 绿主题细化全做完 + 可见即读（Telegram 语义，iOS+Web 一致）。
- **M2.5 iOS 通讯录全做完（2026-06-16）**：
  - 通讯录 Tab `IMContactsViewController`：新的朋友(pending，同意/拒绝) + 好友列表(accepted，点击发起会话)；待处理申请数显示在 Tab 角标；**好友行左滑 = 删除 / 拉黑**。
  - 找人页 `IMUserSearchViewController`（右上 + 进入）：`GET /users/search`，结果按关系显示 加好友/已申请/同意/发消息。
  - **编辑我的资料** `IMProfileEditViewController`（「我」页→编辑资料）：`GET/PUT /api/v1/users/me`，昵称/头像/手机号/标签。
  - 新增 `IMUserCard`(含 phone) + `IMHTTPService` 的 search/friends/friendAction/remove/myProfile/updateProfile；复用 `IMTheme` 绿主题、`UIButtonConfiguration`。
  - `IMUserCardTests`（找人/好友/本人资料含 phone/状态映射/脏数据）。`xcodebuild build` + `build-for-testing` 均零 error/warning。
  - **CLIENT_PARITY M2.5 三行 iOS+Web 全 ✅**。
- **真账号密码登录 + 注册 ✅（2026-06-16，iOS+Web）**：`IMHTTPService` 加 `password` 属性（全局共享登录态）+ `registerWithUsername:password:`，`loginWithUserID:` 改发 `{username,password}`；`IMSocketManager` 换 token 也带共享密码。`IMLoginViewController`：用户名+密码 + 登录(真校验，错误密码显服务端文案)/注册并登录/免密登录(开发，凭 uid)。CLIENT_PARITY M1「真账号注册/密码登录」iOS+Web 升 ✅。
- **里程碑层面 M1+M2+M2.5 客户端基本收口**。下一步可选 M3 群聊。
- **自测修复（2026-06-16）**：①好友申请/同意实时——socket 收 `friend` 帧 → `IMSocketDidReceiveFriendEventNotification` → 通讯录(init 即订阅,节流)reload,Tab 角标无需切页即亮;②找人改精确匹配(`对方完整 uid 或手机号`占位)。
- **自测修复（2026-06-17）**：①「拒绝」按钮曾被禁用点击无反应 → 按钮三态(primary/secondary 可点/disabled)修复;②**黑名单页** `IMBlockedListViewController`（「我」页→黑名单）：`?status=blocked` 列表 + 解除(unblock);③HTTP 错误码 → 友好中文(`IMFriendlyMessageForCode`,被拉黑用模糊文案"暂时无法添加对方为好友"不暴露)。
- **登录失败 UX（2026-08-01 当前策略）**：iOS 已有本地登录态时，HTTP 鉴权或网络失败均不弹模态框、不自动清登录态，继续展示本地缓存；WebSocket 用 `IMSocketDidChangeStateNotification` 驱动「会话（连接中…/未连接）」并自动重连。用户主动退出才清理登录态。Web 仍保留鉴权失败确认框，属于端交互差异。
- **拉黑模型重构 + 拒收反馈（2026-06-17，两端）**：
  - ①**拉黑≠解绑（blocked 标记模型）**：后端 `im_friend` 加与 `status` 正交的 `blocked` 标记（启动自动迁移老 `status='blocked'`→`blocked=1`，非破坏）。`Block` 只置标记、好友关系(双方 accepted)不动 → **双方好友列表始终互见**(拉黑方带标记)；`Unblock` 只清标记。`BlockedBetween`/黑名单查询改用标记。iOS：`IMUserCard.blocked` 解析 + 通讯录被拉黑好友副标题"· 已拉黑" + 左滑"解除拉黑"。Web：`FriendEntry.blocked`、`peerBlocked` 改用标记、好友列表"已拉黑"标签 + 菜单"解除拉黑"。**Web 浏览器实测全过**；iOS 真编译+test-build 过、真机待验。
  - ②**被拒收微信式反馈**：被拉黑方发消息 → 气泡左红❗ + 下方居中系统行「消息已发出，但被对方拒收了」，**不弹窗**(iOS `IMBubbleCell._failBadge/_sysNote` + `IMMessageModel.note`；Web `ChatMessage.note` + `.fail-badge/.sys-note`)。Web 实测过；**iOS 系统行真机待复验**(代码路径已逐段核对正确，疑用户上次测时走了 10s 超时而非拒收)。
  - 规则见 `../IMServer/docs/PROTOCOL.md §6.5`、`CHAT_UX.md §8`。**已知**：早期"拉黑删对端行"旧 bug 已破坏的好友对(如 a1003↔a1001)无法自动复原，需重新加好友一次。
  - ③**拉黑改微信式单向(已定+实现)**：hub 仅拦"被拉黑方→拉黑方"；**拉黑方→被拉黑方照常投递**(对方收得到)。两端聊天页不再封禁拉黑方输入(Web 改非阻断提示行、iOS 移除封禁横幅)。`TestBlockedCannotSend` 改测单向。Web 浏览器实测：拉黑方发送成功✓+提示在+输入可用。iOS 真编译过、真机待验。


# Current Task

## Status（2026-06-15 最新 ⑤：iOS 补 ↓N 跳转按钮 + 文档单一来源整顿）
- **iOS ↓N 悬浮跳转按钮**（对齐 Web，CHAT_UX §7/§9）：滚离底部出现、徽标显示下方未读/新消息数、点按回最新并清零、贴底自动隐藏；进会话停首条未读时预置计数（整屏放得下则不显示）；收消息改为"贴底才自动贴底，离底则累加 ↓N 不打断"。build/test-build 通过（零 warning），IMProgramTests 14 全绿。
- **为何漏掉 ↓N**：上轮做 Telegram 视觉细化时，只盯用户点名项，没按 CLIENT_PARITY **逐行 diff iOS↔Web**；而该表早已标 "↓N iOS ⬜"。→ 已在 `CLAUDE.md` 完成定义加"端对齐扫一遍"硬步骤防复发。
- **文档整顿**：CLIENT_PARITY 设为"功能×端"唯一状态源（ROADMAP 只记里程碑+日期、UI.md 只记视觉）；补齐 UI 细化/UX 行；标注端不对称（iOS 领先离线/落库/空洞自愈，Web 领先分页）；解释"ROADMAP M2✅ vs 表内 iOS⬜"差异（⬜ 的是独立 性能/UX 轨道、不计里程碑）。DEPLOY.md 修正 iOS 构建用 `.xcworkspace`、补自测项。
- **iOS 仍落后 Web 的真缺口**：双向分页 / 进会话最近一页（iOS 仍全量载入 DB）——属独立 `性能` 轨道，单会话上万条再排期。

## Status（2026-06-15 最新 ④：修复离线消息漏拉——③ 引入的回归）
**联调反馈**：Web(1001) 在 iOS(1002) 离线时发了 6 条，1002 登录后停在会话列表只收到了之后在线发的"7"，1–6 漏了。
- **根因（③ 的回归）**：③ 让会话列表常驻长连接并在网络层落库，但列表**没有 track/sync 会话**。于是登录后：离线的 1–6 仍在服务端离线表（只能靠 sync_req 拉）；在线发的"7"以 new_msg 直推并落库，把本地 conv_seq 位点**推过了 1–6 的空洞**；之后进聊天页从该位点同步 → 跳过 1–6。
- **修复（两层）**：
  1. **会话列表登记同步**：HTTP 拉到会话后，对每个会话以本地最大 conv_seq 为起点 `trackConversation:syncedSeq:`（每会话一次）→（重）连即 sync_req 补拉离线消息（`trackConversationsForSync`）。
  2. **空洞自愈（网络层兜底）**：`processIncomingMessage` 收到的 conv_seq 若跳过了已同步位点之后的中间段（conv_seq 连续分配，跳号=有漏），先用旧位点发 sync_req 补缺口，再推进位点。防住"实时消息抢先把位点推过空洞"的竞态。
- **验证**：build + build-for-testing 通过（零 warning）；IMProgramTests 14 全绿。
- **⚠️ 测试前提**：旧本地库里已有"空洞"（1–6 缺、位点已在其上），新逻辑只防新空洞、**不回填历史空洞** → **请先删除模拟器上的 App 重装**（清本地 im.sqlite）再测，否则旧洞仍在。
- **真机验证清单**：①1002 删 App 重装；②1002 退到登录（或杀进程）保持离线，1001 连发若干条；③1002 登录 → 停在会话列表片刻（让其 sync）→ 进会话，**离线那批应全部补齐、不漏**；④再让 1001 在线发新消息，照常实时到达。

## Status（2026-06-15 最新 ③：会话列表实时刷新 + 长连接常驻）
**联调反馈修复**：Web(1001)→iOS(1002) 连发 8 条，iOS 会话列表未读数不变，必须切 Tab 才更新。
- **根因**：socket 只在聊天页连接、离开即断开；会话列表无常驻连接，仅靠 `viewWillAppear` 的 HTTP 拉取刷新 → 停在列表收不到 new_msg。
- **修复（长连接提到 App/列表级常驻 + 通知广播）**：
  - `IMSocketManager`：收到任意消息时除 delegate 外**广播 `IMSocketDidReceiveMessageNotification`**（userInfo[`kIMConvIDKey`]）；`connectToHost` 改**幂等**（已连同 host+uid 则复用，避免列表/聊天页重复调用抖动）；**收到的消息在网络层落库**（`IMDatabase saveMessage`），不再依赖聊天页 delegate，杜绝「列表收到未入库→开聊天页漏拉」。
  - 会话列表：`viewWillAppear` 连接 socket 并订阅通知 → 收到新消息**节流 0.4s reload**（在屏才刷）；`viewWillDisappear` 退订。
  - 聊天页：离开**不再 disconnect**（连接常驻供列表持续收消息），仅交还 delegate。
- **验证**：workspace build + build-for-testing 通过（零 warning）；IMProgramTests 14 用例全绿。
- **真机验证清单**：①停在会话列表，对端连发多条 → 未读数/最后一条**实时更新**（不必切 Tab）；②停列表收到消息后开该会话 → 消息齐全（不漏）；③聊天页正常收发/已读不受影响。
- **已知限制**：presence/typing 仍在聊天页（标题）维度处理；列表不显示在线点（后续可同法用通知广播 presence）。

## Status（2026-06-15 最新 ②：Telegram UI 细化第二版 + M1 文档校正）
**本次完成（iOS UI）**：照用户选定方向「对齐截图：浅色气泡 + 绿勾」做 Telegram 绿主题细化——
- **气泡配色重做**（IMTheme 动态色，深色自动适配）：自己=浅绿底(深色暗绿)、对方=白底(深色暗灰)，文本统一主色；**已读双勾绿 ✓✓**、已送达灰单勾、时间灰小字（attributedText 分段着色），行内右下角占位逻辑保留。
- **聊天壁纸**：新增 `IMChatBackgroundView`（绿渐变 CAGradientLayer + 低透明 SF Symbol 涂鸦平铺图，深色切暗绿），设为 tableView.backgroundView。**注**：未用 Telegram 真涂鸦 .tgv 资源（仓库内为下载态矢量，非可直接复用 PNG）→ 用 CG 自绘 SF Symbol 平铺图近似。
- **消息按时间分组**：气泡 cell 顶部加居中日期胶囊（今天/昨天/M月d日/yyyy年M月d日）；逻辑入 IMTheme（`isMillis:sameDayAsMillis:`、`dayHeaderStringFromMillis:`），配单测。
- **长按消息菜单**：UIContextMenu（复制 / 删除）；删除=仅本端（IMDatabase 新增 `deleteMessage:`，从库+内存移除并刷新，不影响对端），配单测。
- **会话列表已读双勾（真已读态，本次补全）**：「我发的最后一条」时间左侧——**对端已读到该条→绿 ✓✓**，否则→**灰单勾 ✓**（已送达/未读）。判定用**后端新增字段** `peer_read_seq`：
  - 后端 `internal/conversation` Summary 加 `PeerReadSeq`（单聊取对端 `store.ReadPosition`，群聊 0），`GET /conversations` 返回；配 `TestPeerReadSeq`，`./scripts/test.sh` 全绿。
  - iOS `IMConversation` 解析 `peer_read_seq`；列表 cell 据 `latestConvSeq<=peerReadSeq` 切绿✓✓/灰✓。
- **验证**：iOS workspace `build` + `build-for-testing` 通过（**零 error/零 warning**）；iPhone 16e 模拟器 `IMProgramTests` **14 用例全绿**（含 testSameDayGrouping / testDayHeaderString / testDatabaseDeleteMessage + 扩充 testConversationParsing 含 peer_read_seq）。后端 `./scripts/test.sh` 全绿（含 conversation 包 TestPeerReadSeq）。
- **⚠️ 改了后端：用户需重启后端**（`cd IMServer && go run ./cmd/imserver`）再测，运行中的旧进程不会热更新 `/conversations` 的新字段。
- **真机验证清单（交用户手测）**：①聊天页绿壁纸+涂鸦观感；②浅色气泡+深色字、已读 ✓✓ 变绿/已送达灰单勾；③跨天聊天出现日期胶囊（今天/昨天/M月d日）；④长按气泡弹「复制/删除」，删除后该条消失且重进不再出现；⑤会话列表我发的最后一条显示绿 ✓✓；⑥深色模式切换壁纸/气泡/勾均正常。
- **真机验证清单补充**：⑦会话列表「我发的最后一条」——对端已读时显示绿 ✓✓、未读时显示灰单勾 ✓（需后端重启 + 两端互发并让对端打开会话触发已读）。
- **已知限制/TODO**：壁纸为自绘近似（非 Telegram 原涂鸦）；Web 端绿主题/壁纸/日期分组/长按菜单/列表已读双勾尚未追平。

**M1 阶段是否全部完成？（回答用户问题，已更新文档）**：**未完全**。M1 里程碑头部功能已达成（ROADMAP 记 ✅），但逐端**两项缺口**：①真账号/密码登录——后端 ✅，**iOS/Web 仍免密直签 uid**（⬜）；②多端同时在线——后端 ✅，**客户端 UI/位点同步未验证**（⬜）。其余 M1 客户端项（会话列表、iOS 本地落库、真 Web 客户端）此前文档滞后标 🚧，**本次已校正为 ✅**。已同步更新 `CLIENT_PARITY.md`（矩阵 + 诚实记录段）、`ROADMAP.md`（M1 客户端追平缺口）、`UI.md`（Telegram 细化第二版状态）。两项缺口随 M2.5 账号/登录改造补。

## Status（2026-06-15 最新）
**正在做 M2「状态与可靠性」**。后端 M2 全done（已读回执 delivered≠read、未读数/red dot、presence、typing、会话项返回 read_seq、双向分页用现有 LoadSince）。
**Web 端（im-web，React+TS）M2 已完成并浏览器实测**：已读双勾/未读红点/presence/typing、未读分割线（read_seq 精确定位）、进会话停首条未读（Telegram 式，非最新）、双向分页（上滚更早/下滚更新）、↓N 跳转、**Telegram 桌面式双栏布局（窄屏自适应单栏）**。
**聊天交互蓝图见 `../IMServer/docs/CHAT_UX.md`（多端单一事实来源）；端能力见 `../IMServer/docs/CLIENT_PARITY.md`。**
压测工具：`IMServer/cmd/loadtest`（`go run ./cmd/loadtest -from 1002 -to 1001 -n 10000`）。
**TODO（性能）**：Web 消息列表虚拟化暂回退（virtua 在双栏条件挂载/嵌套 flex 下视口测 0、渲染空且不自愈）→ 现为普通滚动列表（配反向分页常规不卡）；后续换 react-window/@tanstack/react-virtual。
**✅ M2 iOS UI 已实现（2026-06-15）**：已读双勾（已送达✓→已读✓✓，按对端 read_seq）、会话列表未读红点、聊天页标题在线点（🟢/在线）、对方正在输入提示条、未读分割线（read_seq 精确）+ 进会话停首条未读、打开即全部已读（markRead latest）。workspace build + build-for-testing 通过。
- 协议：IMProtocol 加 typing/presence 常量；IMConversation 加 readSeq。
- SocketManager：收 receipt(read)/typing/presence → 新 delegate；发 markReadConv:upToConvSeq:、sendTypingForConv:。
- 聊天页：IMBubbleCell 加分割线+已读双勾；进会话定位、typing 提示、presence 标题、typing 节流上报。
- **已知限制**：presence/typing 仅在聊天页生效（socket 当前按会话连接，不在会话列表常驻）；会话列表不显示在线点。完整需把 socket 提到 App 级常驻（后续）。
**✅ M2 真机验证通过（2026-06-15，iPhone 16e 模拟器）**：会话列表 / 进聊天 / 已读双勾(✓✓) / seq 正确显示均 OK。
**✅ Telegram 视觉对齐（第一版，2026-06-15）**：参照 Telegram iOS 重做界面（详见 `../IMServer/docs/UI.md` 的"Telegram 视觉对齐"节）——
  - 会话列表自定义 cell：圆形彩色头像(uid 末两位 + `avatarColorForSeed`) + 名称/最后一条 + 右上时间 + 右下**蓝色未读胶囊**；行高 76，分隔线缩进对齐文字。
  - 聊天气泡重做：真气泡容器(非 UILabel 空格 padding)，圆角 18 + **尾巴**(maskedCorners)，文本 17pt，**气泡内右下角**时间 + ✓/✓✓。
  - 输入栏：圆角胶囊输入框 + 圆形蓝色发送按钮(arrow.up.circle.fill)。
  - 气泡 meta(时间+✓/✓✓)改为**行内右下角**(文本末尾补 NBSP 占位预留位)，不再单独一行显散；**自己发送补本地时间戳**(之前缺 → 只剩孤零零 ✓✓)。勾为白色半透明(非绿)。
  - **待办**：聊天壁纸、按时间分组/日期分隔、长按菜单、头像渐变、群头像；会话列表未读蓝胶囊已实现(unread>0 才显示)。
**✅ 登录默认 host 修复（2026-06-15）**：模拟器恒用 `localhost:8080`（不怕 Mac DHCP 换 IP）；真机记住上次地址（NSUserDefaults）。
**下一步：M2.5 通讯录/加好友/找人。**

## Status（iOS 既有，M1-5）
客户端：登录 → **会话列表（TabBar 会话/我）** → 聊天 三段式（M1-5b）+ **本地落库 IMDatabase（M1-5c：秒显历史 + 断点续传）**。
栈：IMSocketManager（重连同步 + JWT + trackConversation:syncedSeq:）+ IMHTTPService（登录/会话列表）+ IMConversation + IMTheme(tokens) + **IMDatabase（FMDB + SQLite）**。
默认 host：模拟器 localhost:8080、真机记上次（见上"登录默认 host 修复"）。
  - **已引入 CocoaPods（仅 FMDB）**：用 `IMProgram.xcworkspace` 打开/构建（不再用 .xcodeproj）；Podfile post_install 关了脚本沙盒避免 Pods 资源拷贝被拒。workspace `build` + `build-for-testing` 通过。
  - iOS 工作流：编译 + test-build 验证；**模拟器已恢复稳定**，有 booted 模拟器时直接实跑 XCTest。
  - ✅ 2026-06-15：iPhone 16e 模拟器**实跑 XCTest 通过**（IMProtocolTests 9 用例：会话id/协议常量/消息解析/IMConversation 解析/IMDatabase 落库往返）；App install+launch，登录页渲染正常（深色模式自动适配）。UI 全流程点击走查待 computer-use 系统权限或用户手测。
  - 进聊天页隐藏底部 TabBar（hidesBottomBarWhenPushed）已修。
  - ✅ 真机端到端验证通过（host 填 Mac 局域网 IP：登录→token→连接→离线消息 sync 拉回→已读回执）。本地明文联调需临时关 Mac 防火墙/stealth（生产用 wss:// 无此问题）。
  - ✅ 首批 XCTest（IMProtocolTests，6 用例）在 iPhone 16e 模拟器**全绿**（`-only-testing:IMProgramTests` 跳过模板空 UI target）。
  - 坑记录：默认 IMProgramUITests 会因 Accessibility 超时拖垮整体测试，单测须 `-only-testing:IMProgramTests`；前期 Mach -308/启动超时是模拟器未就绪所致，先 simctl bootstatus 等就绪即可。
后端：IMServer 用 **Go**，网关 + 持久化 + 幂等 + **离线消息/增量同步** 完成，`./scripts/test.sh` 全量回归绿。

## 关联工程
- 客户端：/Users/liying/IOSProject/IMProgram
- 后端：/Users/liying/IOSProject/IMServer（协议见 IMServer/docs/PROTOCOL.md）

## Progress
- [x] 确认技术栈：Objective-C 为主，Swift 备用混编
- [x] 创建 `CODING_STYLE.md`（OC + Swift 代码规范）
- [x] 创建 `current_task.md`（本文件，任务记忆）
- [x] 创建 `CLAUDE.md`（项目说明）
- [x] 创建 `.gitignore`（修复误提交的 xcuserdata）
- [x] 选定通信方案：自建 WebSocket
- [x] 选定依赖管理：CocoaPods
- [x] 设计 IM 整体架构（写入 ARCHITECTURE.md）
- [x] 编写共用协议文档 IMServer/docs/PROTOCOL.md（v0.1）
- [x] 选定后端语言：Go
- [x] 搭建 Go WebSocket 网关骨架（protocol/gateway/cmd），集成测试通过
- [x] 后端：内嵌网页调试客户端（cmd/imserver/web/index.html，go:embed 挂 /），双开浏览器肉眼验证互发
- [x] 后端：服务端优雅接收 receipt（记录，不再回 error）
- [x] 端到端验证：两真实 WS 客户端 send→ack→new_msg→receipt 全通过（C 完成）
- [x] 移除误提交的 xcuserdata（git rm --cached）
- [x] 客户端：创建 Podfile（Masonry/FMDB/SDWebImage/YYModel/AFNetworking；WebSocket 改用系统原生）
- [x] 客户端：搭建分层目录结构（Common/Network/Models/Services）
- [x] 客户端：实现 IMSocketManager 长连接骨架（连接/心跳/退避重连/收发/ACK 超时重发），xcodebuild 通过
- [x] 客户端：登录页 IMLoginViewController + 聊天页 IMChatViewController（原生 AutoLayout，不依赖 Pod），SceneDelegate 代码设根
- [x] 客户端：IMSocketManager 接增量同步——trackConversation、重连自动 sync_req、handleSyncResp（分页+投递+回执）、按 conv_seq 去重
- [x] 客户端：首批 XCTest IMProtocolTests（6 用例，iPhone 16e 模拟器全绿）
- [后端进度见 IMServer/current_task.md] 持久化/幂等/离线同步均已完成；JWT 鉴权、errcode、HTTP 层待办
- [ ] 客户端：pod install（需联网）后用 .xcworkspace 打开
- [ ] 客户端：IMDatabase 落库（sending→sent 持久化）+ synced_conv_seq 持久化（当前记内存，重启从 0 同步）

## Decisions & Constraints
- 主语言 Objective-C；未来可混编 Swift，新模块倾向 Swift。
- 通信：自建 WebSocket。**传输层改用系统原生 NSURLSessionWebSocketTask**（iOS 13+ API）；传输封装在 IMSocketManager 内部，接口不变，未来可无痛替换。心跳 25s + 指数退避重连 + ACK 超时重发。
- **部署目标 iOS 15.0**（2026-06-15 从误设的 26.2 调低）：代码栈未用 iOS 16+ API，15 覆盖设备最广且与 Podfile/Pods（已 15.0）一致；真机（iOS 18.6.2）可正常安装运行。
- 工程用 Xcode 文件系统同步组（PBXFileSystemSynchronizedRootGroup）：往 IMProgram/ 加文件即自动入编译，无需手改 pbxproj。
- 依赖：CocoaPods（使用后改用 .xcworkspace 打开）。
- 类统一前缀 `IM`，ARC，4 空格缩进。
- 网络/IO/数据库调用必须有错误恢复分支。
- `xcuserdata` / `xcuserstate` 不再纳入版本控制。

## Next Actions
0. **【当前】M2 iOS UI**：照 `IMServer/docs/CHAT_UX.md` 蓝图，在 IMProgram 实现未读红点 / 已读双勾 / 在线点 / typing / 进会话停首条未读（read_seq 锚点）。配套 IMProgramTests，做完 M2 整体里程碑停下等用户验收。
1. 真机/模拟器联调：`cd IMServer && go run ./cmd/imserver`，App 登录页填 host=本机IP:8080 / 我的 uid / 对方 uid，两端互发；可先杀掉一端验证离线→重连 sync 补偿。
2. 后续新增客户端逻辑时，往 IMProgramTests 加用例并按 CLAUDE.md 命令补跑（`-only-testing:IMProgramTests`）。
3. 接 IMDatabase（FMDB）落库：消息 sending→sent 持久化、synced_conv_seq 持久化（替换当前内存位点）。
4. 后端（见 IMServer/current_task.md）：JWT 鉴权替换 ?uid=、errcode 包 + HTTP 登录接口。

---

## Status（2026-08-04 迁移：UI 统一/账号加固/文件与同步等已验收批次，从活快照迁入）
> 以下条目原在 current_task.md「当前焦点」，均已完成并经用户验收/提交，为保活快照精简而迁入归档（只读，勿更新）。

- **五处弹窗/菜单风格统一到自定义 `IMPopoverCard`（2026-08-03，用户验收通过）**：会话列表「＋」、详情页「更多」、MediaViewer「更多」统一走 `IMPopoverCard` 锚点磨砂菜单（MediaViewer 从底部 action sheet 改锚定「⋯」、空间不足自动上翻；删除 `IMBottomSheet.{h,m}`）；图标从右移到左，圆角用 `IMTheme.radiusBubble`。两处 cell 长按保留系统 `UIMenu`。取舍：非像素级一致换 App 内风格统一；不用系统 UIMenu 全统一是用户选择保留 Telegram 观感。
- **若干 UI 修复批次（2026-08-03，用户验收通过并已提交）**：①深色模式统一导航磨砂过亮→`backgroundGlass` 叠自适应 tint（`480c112`）；②`IMLiquidNavigationBar` init 传 `actionTitle` 不触发 didSet→按钮不渲染→`buildView` 显式落标题（`763df80`）；③建群选择页选好友后「创建」钮吞点击→`updateSelectionUI` 补 `setNeedsLayout`（`763df80`）；④日期胶囊「今天」底色改 `accent·0.64` 随主题（`d8b18d7`）。另诊断非 bug：自己发的消息在自己其它端不计未读属正确行为。
- **系统 Files 选择与返回链（2026-08-02，iOS 26 真机测试通过）**：picker 单实例、页面日志不触碰 `DOCRemote…` 私有导航项；「返回下载页」确诊为 iOS 26.3 Simulator runtime bug（remote view service `FBSceneErrorDomain Code=2` 崩溃自重启），真机无此问题。恢复 `UTTypeItem`，补回归测试。
- **iOS 单库账号上下文 generation 加固（2026-08-02，用户确认测试通过）**：`IMDatabaseAccountContext` 绑定数据库实例/owner/激活代次，异步任务原子「校验+执行」；A→B→A 迟到操作拒写；XCTest 覆盖。物理分库降级为后续增强。
- **文件分页、文件语义与大小展示（2026-08-01，用户测试通过）**：已发送文件服务端游标分页 + uid 隔离 SQLite 缓存；`file_size` 贯穿发送/转发/Socket/模型/SQLite；气泡与文件 Tab 显 KB/MB/GB。
- **会话长名与跨端文件图标（2026-08-01，用户真机测试通过）**：标题行「名称→置顶→免打扰」水平 Stack；原创折角文件卡 21 类 + 未知类型，iOS Asset Catalog 与 Web SVG 同源，含扩展名映射单测。
- **iOS 本地优先会话 + 长连接状态（2026-08-01，用户抽查通过）**：FMDB 按 `owner_uid` 隔离、`server_snapshot_seq` 防未读翻倍、离线启动先登记缓存会话；设计记录 `docs/LOCAL_FIRST_CONVERSATION_STORAGE.md`。
- **聊天 Cell 解耦 + 离线启动保持会话（2026-08-01）**：6 个消息 Cell 迁至 `Modules/Chat/Cells/`；已有本地登录态时启动直进主界面由会话页自动重连；`IMSessionStoreTests` 覆盖。


---

## Status（2026-08-04 迁移：文件消息重构/长按菜单/多选/滚动贴底/粘贴条 全链路批次，从活快照迁入）
> 以下条目原在 current_task.md「当前焦点」，**均已实测通过并提交**（当时文档标注的"待实测/待真机"
> 未及时更新——实际已由用户逐批验收：模拟器+真机+浏览器）。原文迁入，只读勿更新。


- **六项体验修（2026-08-04 晚三批，✅ iOS BUILD SUCCEEDED / web tsc+91 vitest 绿；待实测）**：
  1. **Liquid 标题栏避让**：标题盒改按较宽一侧按钮对称收缩（上限 250→220、下限 132→96、两侧留 8pt），
     多选「取消」/右上文字钮不再与标题重叠。
  2. **文本气泡宽度乱变（回归修复）**：文件行结构约束原是常开——hidden 视图仍参与布局，文本气泡被
     44pt 图标位撑最小宽、复用自文件气泡的 cell 被残留文件名撑得更宽。改 `_fileConstraints` 整组随
     文件模式 activate/deactivate + 文本模式清残留内容。
  3. **引用跳转高亮**：`jumpToConvSeq` 滚动到位后对 previewTargetView 盖强调色遮罩淡出
     （accent·0.35，0.3s 停留 + 0.9s 淡出，与 Web quoteflash 同节奏）。
  4. **Web 粘贴文件**：粘贴条对齐 iOS——图片+任意文件都进预览条 chip（文件显类型图标+名字），
     发送键统一发（图片批量成宫格、文件走分片通道）；修 `uploadAndSend` 声明序 TDZ（前移到 send 之前）。
  5. **点空白收键盘**：`handleReplyJumpTap` 入口 resignFirstResponder（微信式）。
  6. **上滑弹跳三修**：①`onMediaSizeResolved` 改带像素尺寸回调 → 写回模型+落库（一次性，之后估高
     首帧即正确）；②拖拽/惯性中不做 begin/endUpdates，记脏滚动停止后补（needsRowHeightSettle）；
     ③新增 `estimatedHeightForRowAtIndexPath` 按类型精确估高（媒体用 `displayHeightForPixelWidth:`
     与 cell 同一套缩放规则）。
  - 跟进小修（同日晚四批，✅ iOS BUILD SUCCEEDED / web tsc+91 vitest 绿）：①标题盒宽度按
    「文字按钮场景」预算（88pt/侧）一次算死——进出多选零跳变（超预算仍收缩防重叠）；
    ②web 粘贴文件 chip 背景变量笔误（--bg-elevated 不存在落 transparent）→ --surface-elevated；
    ③web 引用跳转改「到位后再闪」（视口内立即闪，否则 scrollend/降级定时后闪，对齐 iOS）。
  - caption（图+文一条消息）确认为独立里程碑，下一轮做；**方案已定案入 IMServer/docs/ROADMAP.md（M4-6 caption 追加）**：不新增 content_type/cell，image/video 加可选 caption 字段，现有媒体气泡图下长文字区。
- **多选交互修 + 粘贴图预览条（2026-08-04 晚二批，✅ 改代码未编译；待实测）**：
  1. **进/出多选列表不跳**：新增 `preserveScreenPositionOfRow:during:`（记录锚行屏幕位置 →
     编辑态切换+reload → 两轮布局对齐还原）；进入锚定长按那条、退出锚定视口首条可见消息。
  2. **「取消」键修复**：旧代码用系统 Cancel item（无标题）→ Liquid 统一标题栏回落成返回箭头、
     点击直接 pop 出聊天页。改带标题「取消」item（leftTitle 渲染文字、点击路由 exitSelection），
     enter/exit/updateSelectionUI 补 `refreshUnifiedNavigationBar`（标题「已选择 N 条」实时刷）。
     底部 转发/收藏/删除 三键原本就齐。
  3. **粘贴图预览条（Telegram 式，#2 重设计）**：粘贴不再弹蒙层确认，缩略图 chip 攒在输入栏上方
     （pasteBar，引用条之下；可多张 ≤9、逐张 ✕、横向滚动），发送键统一发出——≥2 张共享 group_id
     成宫格（sendMediaURL 补 m.groupID 本端也聚簇），有文字随后补发文本；发送键可见性计入待发图。
     删除旧 `presentPastedImagePreview` 蒙层。
  4. **引用聊天记录显裸 [chat_record] 三层修**（同批）：服务端 replySnapshot 特判 chat_record 生成
     「[聊天记录] 标题」（test.sh 全绿，**需重启后端**）；iOS/Web localizeSnippet 映射旧 token 兜底存量。
- **长按菜单/多选/合并转发六件套（2026-08-04 晚，✅ 改代码未编译；两端同步，服务端零改动；待实测）**：
  1. **长按预览只圈气泡**：补 `previewForHighlighting/Dismissing`（identifier 带 indexPath），四种 cell
     暴露 `previewTargetView`（气泡/缩略图/卡片），clear 背景 + 圆角 visiblePath——整行宽底色托盘与
     收起残影消除。
  2. **菜单矩阵收敛**：复制=仅文本+已发出图片（file/chat_record 无复制；不再复制 JSON/本地引用）；
     收藏/多选加 convSeq>0；发送中隐藏「删除」（防僵尸上传，撤走用取消发送）。Web menus.ts 同步
     （delete/multiSelect 规则 + 2 条新单测）。
  3. **多选范围**：system/撤回墓碑/待发件（convSeq≤0）无勾选圈（canEditRow / sel-check 隐藏）；
     点按待发件直接 toast「发送中/失败的消息不可选择」；转发/合并转发入口再加 convSeq>0 防御过滤。
  4. **合并转发文件行带名**：JSON items 文件项增 `fn/fs`（两端同写）；卡片摘要「[文件] 报表.xlsx」、
     iOS 详情页文件行=类型图标+原名+大小、点击 SFSafari 打开（对齐 Web）；老记录无 fn 从 URL 反推
     `<随机>__<原名>`（IMMediaFileName，Web fileNameFromContent 同逻辑）。
  5. **引用聊天记录卡片**：快照改「[聊天记录] 标题」（IMChatRecordSnippet / chatRecordSnippet 两端
     同语义），渲染端检测存量 JSON 截断快照就地救援（正则抠 "t" 标题）；引用条加 text.bubble 小图标。
  6. Web 详情页文件行补大小显示（fn/fs 优先，回退 URL 反推）。
- **文件消息布局重构 + 相册文件路径并入常驻服务（2026-08-04，✅ 改代码，按用户要求未编译；待真机实测）**：
  真机反馈「文件面板→从相册发大视频，气泡很久才出现」。根因：旧 `uploadPhotoFiles` 用
  `loadDataRepresentation` 把整个原件拷进**内存 NSData**（2GB 会 jetsam）+ 一次性 multipart 直传，
  上传全部成功后才插气泡。本轮三件套：
  1. **相册文件路径与 Files 路径同构**：选完**立刻上屏** file 气泡（`sendPhotoFileHandles`），句柄新增
     `loadFileURL:`（`loadFileRepresentation` 导出为磁盘临时文件，超时 600s 适配 2GB/iCloud）+
     `suggestedFileName`（秒上屏用）；服务新增 `enqueuePhotoFileHandles:`（asFile 作业，与媒体共用
     串行队列）：导出→落盘落库→上传（≥8MB 分片可暂停续传，<8MB 一次性）→发 file 消息，全程活在
     `IMMediaSendService`。一次性上传完成回调补 file 类型保护（服务端按字节嗅探会把视频文件变回 video）。
     删除死代码 `loadFileData:`。
  2. **文件气泡两栏布局**（IMBubbleCell）：左 44pt 图标位固定 + 右侧文件名（**≤2 行、中间截断保扩展名**）
     + 状态行 + 右下时间/✓✓，替换原「图标当 NSTextAttachment 拼富文本」（长文件名绕到图标下面、
     无行数上限；疑似 4pt 约束冲突源头）。文件行最小宽 190（仅文件模式激活）。
  3. **圆环状态机交互**（与媒体中心按钮同一套 glyph，位置在左图标位）：排队/准备中=✕（点按确认取消）→
     上传中=圆环进度+⏸ → 已暂停=↑ → 失败=↻；一次性小上传只显环无 glyph。点图标=操作
     （`onFileControlTap`→`handlePendingMediaTap:`），点气泡其余区域仅完成后打开文件（didSelectRow
     的文件切换分支已删）；长按菜单「取消发送」覆盖准备中（content 为空也可取消）。第二行文案改
     「准备中… / x MB / y MB / 发送失败」——上传与暂停均纯字节数（「已传」有歧义弃用），暂停态行首加
     ⏸ 小图标（同媒体角标做法），去掉「点击暂停」尾巴。
  4. **修真机必现崩溃**（crash 报告 IMProgram-2026-08-04-090224.ips 实锤）：Files 选 ≥8MB 视频 →
     `sendLargeFileAtURL` 先 addObject 后 `enqueueFileMessage`，而昨日五件套让分片作业入列时**同步**广播
     初始 ⏸ 进度 → `refreshVisibleCellForMessage` 对 tableView 还不知道的新行 `reloadRows` → UITableView
     行数断言 SIGABRT。修复：①先 `appendReloadAndScroll` 再入列（sendPhotoFileHandles 同步对齐）；
     ②`refreshVisibleCellForMessage` 加行数守卫（目标行 ≥ 当前行数 → 整表 reloadData 兜底）。
  5. **跳动/滚动三修**（真机反馈：文件气泡宽度不一且状态切换时跳动、发送/首进不贴底）：
     ①文件气泡**定宽**=0.75×内容区−24（原最小宽 190 会被「120.4 MB / 358.4 MB」等进度串撑宽，
     暂停/完成文案变短又缩窄 → 文件名换行数变 → 行高跳）；②`appendReloadAndScroll` 改精确贴底
     `scrollToAbsoluteBottom`（估高下 `scrollToRow…Bottom` 恒欠滚）；③`onMediaSendProgress`(file)/
     `onMediaSendDispatched` 补「wasNearBottom→重新贴底」（与 MetaChanged/Ack 对称）；④首进
     `viewDidAppear` 兜底贴底去掉 `isNearBottom` 前提（欠滚>80pt 时旧条件恰好放弃修正）。
     加诊断日志：`chat_stick_bottom_not_converged`（6 轮不收敛 WARN）、`chat_initial_position`（Debug）。
     模拟器实测 ①② 通过；「首进不贴底、二进才贴底」由日志锁定两根因并修（2026-08-04 下午）：
     a) **首进有未读**走「停首条未读」分支（设计如此），但锚定用估高且无二次校正——未读只剩末尾
        几条时停在真底部之上 350pt（日志 09:41:02 实锤）→ 新增 `anchorRowToTop:`（scrollToRow→
        layoutIfNeeded 两轮），定位后下一 runloop + viewDidAppear 各重锚一次；未读不足一屏时
        scrollToRow 自带 clamp 即等价贴底。二进未读已清 → unread_row=-1 精确贴底（日志验证 offset
        与 content−viewport 分毫不差）。
     b) **冷启动直进本页**：init 读库为空（账号上下文未就绪）、历史靠 sync 补进，而 reloadData 不触发
        viewDidLayoutSubviews → 定位整场未跑（日志：该会话零 chat_initial_position）→
        didReceiveMessage 首条落地补跑 positionInitialIfNeeded。
     另修回归：viewDidAppear 无条件贴底会把「从资料页返回」也强拉到底 → 加 `didInitialSettle`
     一次性标志（进场后只校正一次）。
  - ⚠️ 未做/限制：相册导出期杀 App 消息消失（PHPicker 句柄一次性，同视频路径，属预期）；导出失败的行
    点 ↻ 提示「本地文件已丢失」（需长按取消后重选）；Files 面板 <8MB 小文件仍为 VC 锚定一次性上传
    （秒级传完，无暂停价值）；未编译未跑单测（用户要求）。
- **水滴头部：共享驱动 + 松手临界吸附重构（2026-08-03，✅ workspace 编译通过，待真机验收）**：
  抽出共享 `IMProgram/Common/IMDropletHeaderMorph.{h,m}` 承载 Zone①（头像吸附 + name/meta 迁移进标题栏
  + 松手临界吸附），详情页与「我」页共用同一驱动 → 改一处两页同步。整页一个 tableView 分两段吸附：
  **Zone①(off 0→H=144)** 头部收拢，临界 A=头像吸附过半(H/2)、快速甩动无视位置补完，`scrollViewWillEndDragging`
  改写 targetContentOffset（仅当惯性落点也在带内才吸附，快速甩动可穿过直达列表）；**Zone②(pin→)** 详情页页签贴顶，
  贴顶线 `tabPinTop=topInset+68`（距标题栏底 12pt），detent 临界 B=运行时半个 tab 高（落点在 (pin,pin+半tab)
  回弹到 pin、tab 仍贴顶）。细节：name↔meta 间距每帧插值收窄到 18.5pt(=标题栏副标题间距)；pills 停靠标题栏下方
  **不再淡出**；页签选中色↔背景色对调(`styleSegmented:`)；`syncScrollInset` 精确到贴顶为止(2(2)a 内容不足一屏禁上滑)；
  「我」页 meta 随统一**不再单独淡出**(跟随迁移)、下拉钳制 44pt+驱动 off≥0 冻结防重叠、name 锁点 top+19 居中进标题栏。
  文档已同步重写：`docs/TELEGRAM_AVATAR_DROPLET.md`。**待真机验收手感**（临界值 0.5、甩动阈值 0.3、H=144 均可调）。
  已提交 `e23c21b`（用户真机测试通过）。跟进轮（2026-08-03，✅ 编译通过，待真机验收）：①「我」页 meta 恢复淡出（驱动加
  `metaFades` 开关，我页=YES）；②贴顶线 `topInset+68→+48`（消除标题栏下方内容外露）；③页签加大：`kTabBarH=52`/
  `kTabSegH=40`/字号 15pt/宽度下限 200；④`syncScrollInset` 重写：内容不足且未贴顶→`bounces=NO` 硬停（完全禁上滑）、
  已贴顶→补 inset 维持；⑤**#4 根因**：长列表贴顶后切短 tab，reload 变短+旧 inset 未更新→offset 被夹回顶，`setContentOffset:pin`
  也被夹——修法：切前预膨胀底部 inset 再设 pin，切 tab 全程维持贴顶。
  再跟进轮（2026-08-03b，✅ 编译通过，待真机）：修正上一轮回归 + 真根因。①「我」页大屏(17PM)内容一屏放得下→不可滚→
  raw 恒 0→name 不迁移：新增 `syncHeaderScrollRoom` 补底部 inset 保证 maxRaw≥H。②`syncScrollInset` **恢复始终补足到 pin**
  （上一轮改成条件补足导致：短内容整页不可滚、点 tab 不贴顶——已修）；短内容仅 `bounces=NO` 贴顶后硬停。③**#4 真根因**：
  行高估算开启使 reload 后 `rectForHeaderInSection`(→pinOffset)不准、`setContentOffset:pin` 落偏 → 关闭 estimatedRowHeight/
  SectionHeader/Footer + 切后下一帧再断言 pin。④贴顶线 +48（上一轮）。
- **系统 Files 选择「选中未发送」回归修复（2026-08-03，✅ workspace 编译通过，`e146c9e`；用户测试通过）+
  面板承载重构（2026-08-03b，✅ 编译通过，待真机）**：
  ①回归根因：上一版（`3cd89d4` 隔离生命周期）把系统 picker 嵌套在文件面板之上、靠面板 `viewDidAppear:`
  状态机收尾——选完文件后命中 `self.presentedViewController` 提前返回、`_documentPickerPresented` 未复位、
  回调从不触发 → 卡回文件面板、文件没发出去、再点日志刷「忽略重复的系统文件浏览器呈现请求」。先以
  delegate 回调 `[self.presentingViewController dismiss…]` 一次性收栈修好（`e146c9e`，用户验收通过）。
  ②再重构（本轮）：既然点叉叉终归回聊天页，回落面板是多余弹跳——**「从文件/从相册」入口统一先关闭面板，
  再由聊天页承载系统选择器**（恢复 `3cd89d4` 之前的结构）：面板 `initWith…onFromFiles:` 只 `dismissThen:`，
  聊天页 `presentDocumentPicker` 全屏呈现 `+systemDocumentPicker` 并作 `UIDocumentPickerDelegate`，选完/叉叉
  由系统关 picker 直接回聊天页，中间不再出现面板。picker 单实例配置仍集中在 `+systemDocumentPicker`。
  ③「返回下载页」经日志确诊为 iOS 26.3 **Simulator runtime bug**（`com.apple.DocumentManagerUICore.Service`
  远程视图服务 `FBSceneErrorDomain Code=2` 崩溃自重启、导致 Files 内部栈被重置），与呈现方式无关，真机无此问题。
- **多端历史连续同步与文件元数据补全（2026-08-02，build/test-build 通过；待跨端实测）**：iOS 将
  `synced_conv_seq` 作为 `(owner_uid,conv_id)` 隔离的独立 SQLite 状态，禁止以本地
  `MAX(conv_seq)`、单条 ACK 或实时见过的最大序号越级推进；消息/会话摘要/连续游标同事务提交，
  多页仅从本页实际连续完成位置继续。账号切换会清空内存游标/in-flight/旧账号未决发送，并用连接
  代次丢弃迟到的旧登录请求与重连任务。重复权威消息会补全当前聊天内存和 SQLite 的
  `file_name/file_size`，不再出现另一端文件长期 0 KB。Web 已同步同一机制，协议见
  `../IMServer/docs/PROTOCOL.md §6.2`；根因、不变量和自动化分层方案已记录在
  `../IMServer/docs/CONTINUOUS_SYNC_AND_MULTI_CLIENT_TESTING.md`。待用户删库后做跨端、断线、
  多页和切账号实测。本轮 `xcodebuild build` 与 `build-for-testing` 均通过。


### 迁移时点的「下一步 / 已知坑」原文（供考古比对）

## 下一步
0. **真机实测本轮文件发送交互**（优先）：文件面板→从相册选大视频应**秒上屏**（准备中…→进度）；
   图标位 ⏸/↑ 暂停续传、✕ 取消（准备中长按也可取消）、失败 ↻ 重试；文件名两行中间截断；
   小文件（<8MB）一次性上传只显环。回归：Files 路径大文件、最近文件复发。
1. **账号切换与连续同步真机/跨端实测**：代码与自动化测试已由用户确认通过；后续在真机验证
   A→B→A 快速切换、旧 Socket/HTTP 回调不污染当前账号，以及断线、多页、连续游标和文件元数据补全。

2. **用户真机测试 M4.5 会话菜单 + 群聊详情页**：
   - 会话菜单四件套（置顶/免打扰/标未读/删除）+ 指示符
   - 群聊详情页全流程（进详情 → 成员交互 → 设置头像 → 管理权限 → 退出/解散）
   - 头像闪动、标签页切换、更多菜单等 UI 细节验收
   - 反馈→迭代修复
   
3. **M4.5-3 统一资料页** 设计稿拍板后开工：
   - 聊天详情页重构为标准资料页（成员页签改为资料页的成员卡片）
   - 设置页逐项（Devices/Folders/Notifications/…按 Telegram）
   
4. 群聊 iOS 欠账（对齐 Web）：群头像上传、群内已读细化、@提醒（M5-6）。

5. 本地媒体文件离线缓存（当前 SQLite 已保存消息与媒体 URL，但远程图片/视频未下载过时离线不可查看）。

6. **账号哈希目录物理分库（后续增强，不阻塞功能迭代）**：未来需要按账号删除缓存、降低单库损坏
   影响面或强化物理隔离时，再迁移到
   `Library/Application Support/IM/accounts/<SHA-256(uid)>/im.sqlite`。届时补目录/建库失败恢复、
   A/B 同 `conv_id` 物理隔离、A→B→A 重开及非法/超长 uid 路径测试；当前不迁移、不读取、不删除旧库。

## 已知坑 / 限制
- CocoaLumberjack 只接管应用主动输出的日志；iOS/UIKit/Network.framework 自身的系统诊断仍由系统写入 Xcode 控制台。Debug 文件日志会保留脱敏后的业务正文，仅用于开发设备，分享日志前仍需复核。
- **登录已支持真账号密码**：登录页「免密登录（开发）」仍保留（凭 uid 直签，需后端 `-dev-login`）。注意 dev-login 建的账号（空密码哈希）无法再走密码登录；测密码登录请用「注册并登录」建新号或清 `imserver.db`。
- **iOS 无双向分页**：进会话一次性全量载入本地 DB；性能轨道、当前不影响使用。
- **presence/typing 仅聊天页标题**生效；会话列表不显示在线点（后续可同 notification 广播 presence）。
- 聊天壁纸为 CG 自绘 SF Symbol 近似，非 Telegram 原涂鸦。
- 测试只跑 `-only-testing:IMProgramTests`（UITests 会因 Accessibility 超时拖垮）。
- 改后端协议字段后**需重启后端**再测；当前继续使用 `Documents/im.sqlite` + `owner_uid`，账号切换由
  database context generation 防迟到串写；账号哈希目录物理分库已降级为后续增强。本轮仍按无旧数据验证。
- 已读=可见即读（已实现）：未读随滚动逐步清；进会话只清当前可见的，需滚到底才全清。↓N 徽标=视口下方未读数，随滚动递减、滚到底隐藏（按 pendingReadSeq 实时重算，非静态）。


## 2026-08-18 归档（从 current_task.md 下沉——巨类拆分及更早已完成块，保留全文供追溯）

## 当前焦点

**相机拍照收端缺少 `thumb` 磨砂占位 ✅（2026-08-18，clean build 绿，待手测）** — 根因是相机/粘贴单图路径直接 `uploadData → sendMedia`，只填写 `media_w/media_h/file_size`，绕过 `IMMediaSendService` 内部的 `IMTinyThumbDataURI`，故 socket payload 不含 `thumb`；服务端透传与收端解析/磨砂渲染均正常。现将生成器导出为共享函数，在 `mediaAttributesForImage:bytes:` 统一写入 `attrs.thumb`，相机和粘贴路径同时覆盖；`IMMediaPlaceholderTests` 补 data URI 可解码、20px 尺寸和协议长度上限测试。
- **两处修正（2026-08-18 编译/追链发现）**：① 导出声明 `IMTinyThumbDataURI` 误用裸 `nullable`（Obj-C 方法/属性专用上下文关键字），C 函数须用 `NSString * _Nullable`——否则 `unknown type name 'nullable'` 直接编译失败。② `sendMediaURL:...mediaAttributes:` 构造本地 `IMMessageModel` 时漏回填 `m.thumb`，导致**转发自己刚拍/粘贴的图**时 `forwardAttributesForMessage` 读到空 thumb、收端仍只有空磨砂；已补 `m.thumb = mediaAttributes.thumb`（表已有 thumb 列，可落库→重进会话再转发亦生效）。**build 绿；单测/手测未跑。**

**IMChatViewController 巨类拆分 ✅ 代码完成（2026-08-15，clean build 绿，待手测，纯 iOS 端）** — 应《整洁代码》拆 4718 行的 Massive VC。
- **真·SRP 抽取（独立对象/纯函数，零～低运行时风险）**：`IMChatMessageLogic`（@提及 token/未读口径/引用占位，测试从前置声明改引头）、`IMPasteImageTextField`、`IMPendingMediaThumbnail`、`IMChatBannerStack`（G0/G1/G3 三横幅栈视图+布局+收起持久化，点击导航经 `IMChatBannerStackDelegate` 回本页）。
- **分文件 category（同一个类、方法平移到多 TU，零运行时风险；剩余子系统全回耦 messages/tableView/nav/socket，强抽独立对象只会把耦合塞进宽 delegate 还添风险）**：`+Selection`（多选/转发）、`+Menu`（长按菜单+iOS26 光栅化预览）、`+DataSource`（cellForRow+相册聚簇+连续分组+行高）、`+Media`（附件面板/选择器/上传/查看器/粘贴）、`+MediaFlow`（转发/长文本/下载编排）、`+Mention`、`+Socket`、`+Scroll`（↓N/键盘）、`+Compose`（引用/收藏/编辑）。私有属性/协议/跨 TU 私有方法登记在 **`IMChatViewController+Private.h`**。
- **收口**：主文件 **4718→1482 行**（仅留 init/lifecycle、导航去重折叠入口、setupUI、发送接收核心、群资料、banner delegate 装配、presence、辅助）；`_downloads` 懒加载 getter 与 `dealloc` 因直接访问 ivar 留主实现。`kIMFlashOverlayTag`/`kIMAttachPanelHeight` 由 static const 改为跨 TU 共享常量。**未改一行行为**，10 次提交每次 build 绿。
- **待手测**：编译只能保证符号，**布局/交互（键盘顶起输入栏、附件面板、长按菜单预览、多选、↓N、@面板）需模拟器实测**——纯编译过不代表布局对。

**气泡样式统一 + iOS26 长按预览修复 ✅ 代码完成（2026-08-15，待编译/手测，纯 iOS 端）** — 见 `../IMServer/current_task.md` 同条。
- **长按菜单迁移**：从 UITableView 行级 contextMenu API（iOS26 不再回调其自定义预览 delegate → 预览退化整行矩形）迁到挂在气泡 `previewTargetView` 上的 `UIContextMenuInteraction`（`attachMessageContextMenuToCell:` 由 `willDisplayCell` 统一幂等挂，取代 cellForRow 四处散点）。配置走共享 `messageContextMenuConfigurationForIndexPath:`，预览 delegate 新旧两代都实现（iOS15 旧签名 + 16/26 `...ForItemWithIdentifier:`）。
- **iOS26 预览只剩文字/空气泡**：`targetedPreviewForInteraction:` 把气泡**从父视图按 frame 开窗光栅化**成独立 UIImage（`CGContextTranslateCTM` + `drawViewHierarchyInRect:`）——绕过 iOS26 lift 剥离源视图背景，且开窗能带上链接卡 `_stack`、图片角标等**兄弟视图**（只画 target 子树会漏成空气泡/裸封面）。highlight 缓存快照、dismissal 复用、`willEnd` 清（防菜单期间 reload 换绑截错内容）。截图前按 `kIMFlashOverlayTag` 隐藏跳转高亮遮罩。
- **配色/尾角统一**：链接卡接收端 `surface` 灰→`bubbleThem` 白；聊天记录卡收发都灰→按 mine 上 `bubbleMe`/`bubbleThem`；两者加尾角（媒体类不加）。方向样式（底色+圆角+尾角）收口为 `+[IMTheme applyBubbleDirectionStyle:mine:]`，IMBubbleCell/IMLinkCardCell/IMChatRecordCell 三处共用（原三份手抄）。flash 高亮层补 `maskedCorners` 跟随尾角。
- **/code-review 自审**：8 finder × 验证，10 项发现——4 正确性（空气泡预览/收起截错/flash 烘进预览/flash 尾角）+ 5 清理（方向样式复制、attach 散点、identifier 死参、init 死赋值、共享函数）+ 1 规范（本快照）已随本次全修；2 项（宫格多选态、iOS≤18 重影）验证驳回。
- **已知限制**：相册宫格每格长按预览仍系统默认形状（IMAlbumCell 自带交互无自定义预览，非本次范围）；长按须落在气泡上，行内空白/昵称/头像处不再出菜单（对齐 Telegram）。

**聊天页导航去重 + 折叠 ✅（2026-08-14，build 绿 + test-build 绿，待手测）** — 7 处 `IMChatViewController` alloc+push 收口为统一入口 `+openInNavigationController:...`（单聊/群聊各一，走私有 `+openConvID:inNavigationController:build:seed:`）。
- **折叠（本次核心需求）**：开新会话时截掉栈里**最底部**的聊天页及其之上的所有页（资料页等），新会话接到其原位置 → 「群聊A→成员资料→发消息C」返回直达会话列表（Telegram 行为），且**同一导航栈至多一个聊天页**。纯逻辑抽为文件级 `IMChatCollapsedStack()`，配 `IMChatStackRoutingTests`（7 例，注入谓词免构造真 VC；含钉住「聊天页为根→原地替换」语义的用例）。
- **复用刷新（修 /code-review 发现）**：命中同会话则 `popToViewController` 复用并 `prepareForReuseEntry`——重装标题/头像按钮（修死播种）、从库合并被压期间错过的消息（修陈旧空洞）、清定位标志重锚到底部。指定初始化器移入 .m 类扩展（外部无法 alloc+push，结构性防回归）；`viewWillAppear` 按 `synced` 游标跨 Tab 自愈；详情页 `originChatInStack` 改委托 `+existingChatForConvID:`（统一查找方向）。
- **二轮 /code-review 复核修复（同日）**：① 复用 seed 群名改 fill-if-empty + `prepareForReuseEntry` 群聊补 `reloadGroupInfo`（快照旧群名不再覆盖服务端新名；单聊保持覆盖——页内无服务端刷新，caller 快照恒 ≥ 页内值）；② 命中即栈顶时只 seed、不清定位标志不 pop（防下次重布局把上翻用户拉回底部）；③ 复用重锚前清 `entryUnread`（防锚回早已读的旧「首条未读」）；④ 被压期间消息合并移到 viewWillAppear 按 synced 守卫（去掉复用路径双重读库），合并后补 `markVisibleRowsRead` 刷 ↓N；⑤ cut==0（聊天页为根）复核为刻意语义，配测试钉住。
- **已知限制**：去重/折叠只作用于单个 `UINavigationController`；各 Tab 独立栈，跨 Tab 仍可能各存一个同会话实例（数据不丢，靠 appear 合并自愈）。位点入参在复用路径刻意忽略（实例自维护已读/位点）。`maxInMemoryConvSeq` 每次 appear O(n) 扫描（数千条量级微秒级，不值得加增量状态）。

**QRCODE P0 + 群组 G3 入群 ✅（2026-08-13，build 绿 + test-build 绿，待手测；iOS 全量测试用户要求暂停）** — 方案 `../IMServer/docs/QRCODE_DESIGN.md` / `GROUP_FEATURES_DESIGN.md` §4-G3、草图 `QRCODE_UX_SKETCH.html`。
- **网络/模型**：`IMHTTPService` 加 `qrMyCard/qrResetMyCard/groupQR/groupQRReset/qrResolve/joinGroup:code:hello:/joinRequests/decideJoinRequest`（新 `runDataRequest:` 保留业务码，join/resolve 靠 `error.code` 分 300210/200110）；`IMFriendlyMessageForCode` 加 200110/300207/300208；`IMGroupInfo.pendingCount`；新 `IMQRModels`（`IMQRResolved/IMQRUserCard/IMQRGroupCard/IMJoinRequest` + 纯映射 `IMQRUserActionForRelation/IMQRGroupActionForCard/…`）+ `IMQRImage`（`CIQRCodeGenerator` 出码 / `CIDetector` 解码，**一图多码** `decodeAllInImage:`）。
- **UI（Modules/QR/）**：`IMQRScannerViewController`（`AVCaptureSession` 取景 + 手电筒 + 相册识别多码候选 + 「扫码/我的二维码」页签；自行 resolve 后 `onResult` 回宿主）→ `IMQRResultRouter`（**落到已有页面**：名片→资料页 `IMChatDetailViewController`、群→加群确认弹窗含 G3 加入/需审批附言/进群/满/黑名单、失效码 200110 提示、外来码域名二确认不自动跳转）；`IMQRCardView`+`IMQRCardViewController`（出码页：进页提亮、保存相册、分享、重置二次确认）；`IMJoinRequestsViewController`（待审列表，同意/拒绝）。
- **入口/帧**：会话列表 `＋` 菜单「扫一扫」置顶 → 扫码；`IMSettingsViewController`「我的二维码」；详情页设置区「群二维码」行；`IMGroupManageViewController` 治理卡「待审入群申请(N)」；`IMSocketManager` group 帧带 `result`（`kIMGroupResultKey`）+ 会话列表 `onGroupEventForJoinResult:` 结果 toast。
- **测试**：`IMQRModelsTests`（resolve 解析 / 动作映射 / 域名 / 申请解析）。**扫码/相机需真机手测**（模拟器无摄像头）。**改了后端需重启带 QR 路由的新二进制再测。**
- **`/code-review` 修复（2026-08-13，三仓 5 项全修）**：iOS 两项——① 扫码页 `startSession/stopSession` 把 `isRunning`
  判定移进串行队列（原先在主线程判，快速切「我的二维码」↔「扫码」会让启动被自己的守卫吞掉、相机永久停住）；
  ② 扫码页「我的二维码」页签补拉 `myProfile` 显昵称+头像（原先只显 uid，对方回扫认不出是谁）。
  另三项在 IMServer（邀请入群原子上限 + 注释订正）与 im-web（重置失败无提示 / 拖非图片文件未捕获）。
- **已知限制**：① `IMQRResultRouter` 群分支用**确认弹窗兜底**（G3 独立「加群预览页」为后续替换项，附言目前是 alert 文本域）；
  ② 相册一图多码用 **ActionSheet 列候选**（草图里是"在图上画候选点"，需图片预览页，未做）；
  ③ 屏幕提亮只在出码页（`IMQRCardViewController`），扫码页内的「我的二维码」页签不提亮；
  ④ `q/l` 登录码（P1）未做——`resolve` 对它一律回 unknown，端上会当外来码显示原文。
- **建议**：完成后跑 `/code-review`（触及扫码/入群，可加 `/security-review`）。

**G2 群治理 ✅（2026-08-13，build 绿，待手测；iOS 全量测试用户要求暂停）** — 方案 `../IMServer/docs/GROUP_FEATURES_DESIGN.md` §G2、草图 §04/§07。
`IMGroupManageViewController` 加三卡（进群确认/全员禁言开关 · 三项「仅管理员」权限开关 + 新成员可见历史 · 黑名单入口，section 化重构避免行索引 bug）+ 新 `IMGroupBanListViewController`（左滑解除）+ `IMGroupInfoViewController` 成员菜单加「禁言…(10min/1h/1d/永久)/移出群聊(cooldown)/移出并不再允许加入(forever)」+ `IMChatViewController` 输入栏禁言锁（`refreshComposerMuteState`：myMuteUntil 或全员禁言且我是 member → inputField.enabled=NO + 占位「你已被管理员禁言」）。`IMGroupInfo` 扩 G2 字段 + `IMHTTPService` 加 setGroupSettings/muteGroupMember/removeGroupMember:ban:/groupBans/unban。**后端补** group.Info 下发开关组。

**G1 群资料闭环 ✅（2026-08-12，build 绿，待手测；iOS 全量测试用户要求暂停）** — 方案 `../IMServer/docs/GROUP_FEATURES_DESIGN.md` §G1、草图 §04/§08。
`IMGroupManageViewController` 三行（简介/公告/全员禁言开关，删「即将上线」占位）+ `IMChatDetailViewController` 设置区加「我在本群的昵称/群备注」行 + 群公告卡 + `IMChatViewController` **公告黄条横幅**（`IMPinnedBannerView` 加 `IMBannerStyleAnnouncement`，排在 G0 置顶蓝条之上，两条叠加算 `contentInset.top`）。`IMGroupInfo` 扩 G1 字段、`displayName`/`nicknameOfMember:` 群昵称优先。`IMHTTPService` 加 announcement/mute/me-nickname 三接口 + `updateGroup` 扩 intro。群备注本地（`NSUserDefaults im_grpremark_<uid>_<cid>`，与单聊备注 `im_remark_` 同范式；后端 remark 就绪、多端同步后续）。

**G0 置顶消息横幅 ✅（2026-08-12，build 绿 + `IMPinnedMessageTests` 8 例，待手测）** — 方案/草图见 `../IMServer/docs/GROUP_FEATURES_DESIGN.md` §G0 与 `GROUP_FEATURES_UX_SKETCH.html` §03（**实现须严格对齐草图**）。
新增 `IMPinnedBannerView`（竖条 + `📌 置顶消息 i/N · 发送者` + 单行预览 + 右侧列表键）与 `IMPinnedMessage` 模型；进会话拉 `GET /conversations/{id}/pinned` 回填，之后靠 `msg_op` 帧重拉；点条=跳转并轮转，列表键=ActionSheet 全部置顶（可取消当前条）；长按菜单加「置顶↔取消置顶」切换对（群内仅群主/管理员）。
**布局要点**：横幅浮在消息表之上、贴 `safeAreaLayoutGuide.top`，用 `tableView.contentInset.top` 顶开内容——**不能用 `additionalSafeAreaInsets`**（它会反过来推动横幅自身约束，形成循环）。
**顺带修**：`op=pin` 的 apply 写死 `pinnedAt = now`，把「取消置顶」也记成置顶；且 `IMDatabase applyMsgOpForConv:` 约定「pinnedAt 传 0 = 不改该项」导致取消永远落不了库 → 认 `payload[@"pinned"]`、约定 `pinnedAt<0` 为清零、通知补 `kIMMsgOpPinnedKey`。

**@选择器改内联下拉面板 ✅（2026-08-12，build 绿·待手测）**：原半屏 sheet 遮挡输入框、没法接着打字匹配 → 改**输入栏上方内联面板**（`IMMentionPickerViewController initInlineWithGroup:`＋`preferredInlineHeight`，child VC 底边贴 `replyBar.top`、随键盘上移、不抢键盘，过滤词由聊天输入框 `updateQuery:` 实时驱动）；`maybePresentMentionPicker` 改 add/update/remove child + `dismissMentionPanel`。

**气泡内 `@昵称` 高亮 + 点击跳资料 ✅（2026-08-12，build 绿·待手测）**：iOS 不落库 per-msg mentions，改由**当前群成员+文本**推导（`mentionMapForMessage:`→name→uid）；`@所有人`仅群主/管理员时高亮（对齐 300204、不可点）；`+[IMBubbleCell attributedContent:base:mentionColor:mentions:]` 挂 `IMMentionUIDAttributeName`，cell 与阅读器共用。**点 `@昵称` 跳资料**：气泡 UILabel 用 `NSLayoutManager` 反查 tap 落点字符属性（`mentionUIDAtPoint:`，收键盘前用稳定布局 + glyph 矩形内才算）、阅读器 UITextView 同法反查（不走已弃用 link 代理）→ `openMemberProfileForUID:`；点击先于长文展开/引用跳转。token 边界同 `IMChatTextContainsMentionToken`、长名优先。

**两项 UX 优化 ✅ 代码完成 + `/code-review` 全修（2026-08-11，build 绿·用户自测）** — 逐端矩阵见 `../IMServer/docs/CLIENT_PARITY.md`「UX」行；与 Web 同步交付。
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

---

## 归档：语音 P1 全量 + P0 自查修复（自 current_task.md 迁出，2026-08-28）

> **语音 P1 全量 + P0 自查修复（2026-08-26，build 绿、待真机手测）**：用户实测报 8 问全部定位修复——
> ① 发送链重做：落库 + ack 回写 convSeq/status（曾 completion:nil → 长按菜单空「无反应」+ 气泡忽隐忽现「错乱」）；
> ② 转发语音修通（曾 attrs=nil 不带 duration 被服务端拒但 UI 报已转发）；三处 attrs 构造放行 voice 带 duration+waveform；
> ③ 大圆钮跟手 + 呼吸环 + 磁吸小锁 `IMVoicePressOverlay`（70pt 高亮/34pt 即锁，此前只有不可见 80pt 阈值＝设计稿缺件）；
> ④ HUD/锁定条不透明主题底（曾 clear 透底重叠 + 硬编码粉色）；⑤ 己方波形 bubbleMeText 配色（曾绿 on 绿看不见进度）；
> ⑥ 中断转锁定暂停（§5.4）+ 删除 >10s 确认 + 暂停时长不再算进 duration；⑦ 详情页语音 tab（曾匹配 audio 恒空）点行播放；
> ⑧ 收藏语音 `IMFavoriteVoiceCell` 迷你波形播放器（曾 SFSafari 打开裸音频）；从收藏发送带 duration+waveform（后端收藏快照加 waveform 列）。
> 拍板：语音支持转发（Telegram 式）；收藏=内嵌迷你播放器。
