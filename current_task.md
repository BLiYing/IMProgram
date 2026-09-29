# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

> **最近通话验收修复（2026-09-29，模拟器 libeyond 已验，未提交）**：① 群名全是「未命名群聊」——根因是只读
> `cachedGroups`（仅进过「通讯录 ▸ 群组」页才写入），改为 `cachedConversations` 优先、`cachedGroups` 兜底；
> 查不到的群退回「群X通话 · N人」（同 Android，设计文档 §2）。② 群行改用群会话真实头像（`im_setAvatarURL` +
> `IMMediaFullURL`，同会话列表口径），去掉统一人形图标。③ 按 UX 稿：方向箭头 13 号次要色、日期分组头自绘 12 Bold。
> 设计文档/草图已同步订正「群用群头像」。`IMCallHistoryViewController.m` 一个文件。

> **设置 ▸ 最近通话 v1 ✅ 代码 + 单测已完成，待真机验（2026-09-29，分支 `feature/call-history`，
> worktree `IMProgram-wt-call-history`，未提交前的开发态；设计：`../IMServer/docs/design/CALL_HISTORY_DESIGN.md` +
> 配套 UX 稿）**：设置「我」页 groupA 早已有的 `recentCalls` 占位行（`IMSettingsViewController.m` 的
> `openRecentCalls`）现在 push 新列表页 `IMCallHistoryViewController`（`Modules/Me/`），只读浏览自己参与过的
> 通话历史（含群通话），单聊行点了直接回拨、群聊行跳转群会话。
> - **SDK 桥接是本次最大的技术活**：im-rtc iOS SDK 的 `IMCallEngine.fetchCallHistory`（`async throws`）
>   **没有标 `@objc`**（返回体 `IMCallHistoryPage`/`IMCallHistoryRecord` 是纯 Swift struct，天生不能进 ObjC 签名），
>   `IMRtcCall.m` 原有的「调 SDK」套路（直接 `@import IMCallEngine;` 调方法）在这里走不通。新增
>   `Modules/RTC/IMRtcCallHistoryBridge.swift`（`@objc(IMRtcCallHistoryBridge)`，仿现有 `IMLiquidNavigationBar.swift`/
>   `IMTelegramAvatarMaskView.swift` 的 `@objcMembers @objc(Name) : NSObject` 套路）：`Task { try await
>   engine.fetchCallHistory(...) }`，把 struct 拍平成字典（键沿用 `IMRtcCallRecordSender.m` 已经在用的
>   snake_case：`call_id`/`media_type`/`duration_sec`…），显式 `@objc(fetchCallHistoryWithEngine:limit:cursor:completion:)`
>   钉死 selector（不依赖 Swift→ObjC 自动改名）。`IMRtcCall.h/.m` 新增两个公开方法：
>   `fetchCallHistoryWithLimit:cursor:completion:`（经桥接转 `IMCallHistoryRecord*` 数组，带 generation 防护——
>   在途请求期间若 `stop`/`startWithUserID:` 被调用过，结果一律当失败处理，不回填到已销毁的引擎状态里）、
>   `addEventObserver:`/`removeEventObserver:`（`_engine addEventObserver:` 的公开透传，供页面级消费者订阅
>   `IMCallEventNameCallEnd` 而不用碰 `_engine` 私有 ivar；沿用同一套「回调恒转主线程」约定）。
> - **纯函数层**（可测、与网络/UI 解耦）：`Common/IMCallHistoryRecord.h/.m`——`IMCallHistoryRecordIsMissed`
>   （未接判定：`caller != selfUID && durationSec==0`）、`IMCallHistoryGroupPeerCount`（群通话人数：
>   `max(members.length,1) + (caller 在 members 里?0:1)`，对齐 im-rtc Demo `peerText`）、
>   `IMCallHistoryRecordPeerUID`（1v1 对方 uid，caller 为空等脏数据兜底 nil 不崩溃）、`IMCallHistoryGroupByDate`
>   （按自然日分组，标题**复用** `IMTheme dayHeaderStringFromMillis:`——找了一圈发现聊天页日期分隔胶囊已经有
>   这个函数，不用新写）、`IMCallHistoryApplyFilter`（全部/未接过滤谓词）。行的 reason 文案**复用**
>   `IMCallRecord.h` 的 `IMCallRecordBuild`+`IMCallRecordRender`（把本记录字段拼回 `{"cid","m","r","d"}` 再走同一套
>   渲染，不重新实现判定顺序）——但**红字判定刻意不用** `IMCallRecordRender` 的 tone（那套规则对被叫侧
>   `reject` 有例外不算未接，是聊天气泡级别的细规则），列表页红字统一用 `IMCallHistoryRecordIsMissed` 的
>   简单公式（设计文档 §1/§4 原文只给了这一条，不含 reject 例外），这样「未接」筛选 tab 里的行与红字视觉
>   保证一致，不会出现"在未接列表里却不是红字"的观感矛盾——这是本次一个需要留意的判断取舍，非文档明文拍板。
> - **翻页/筛选状态机单开一个类**：`Modules/Me/IMCallHistoryPaginator.h/.m`，注入 fetcher block（与网络解耦，
>   可用假数据单测，不用起模拟器）。`generation` 计数器作废在途旧请求（`callEnd` 触发重拉首页时用得上）；
>   「未接」视图的翻页是自动连续的——过滤后新增数量不够 `minVisible` 就接着拉下一页，直到凑够或
>   `nextCursor==nil`；「全部」视图每次只拉一页。两个视图共用同一份 `allRecords`，切换只换过滤谓词不发请求。
>   `cursor`/`nextCursor` 类型是 `id`（不是 `NSString*`）——SDK 实际游标是 `Int64`（`NSNumber` 装），本类只透传
>   从不解析，写测试时才发现这个坑（最初想当然写成 NSString，读 SDK 源码才知道是数字）。
> - **身份解析全部复用现成基础设施，没有新写一套**：1v1 对方名字/头像走 `IMUserProfileCache.sharedCache
>   cardForUserID:` + `IMUserCard.displayName`（备注>昵称>@handle>"未命名用户"），命中 `IMUserProfileCacheDidResolveNotification`
>   时整页 `reloadData`；群名走 `[IMDatabase.sharedDatabase cachedGroups]` 按 `convID` 建索引（找不到落回
>   "未命名群聊"）；群聊跳转走 `IMChatViewController` 的统一群聊入口（`openInNavigationController:...groupConvID:...`），
>   **没有**直接 alloc+push（头文件明文禁止）；单聊回拨复用 `IMRtcCall placeSingleCallToPeer:video:`——与聊天
>   气泡回拨同一入口，没有新造判断。
> - **三态**：`IMCallHistoryStateView`（自绘，非满屏用 `_stateView` 就是底部 footer 条）覆盖加载中 / 空 /
>   出错（含 `IMRTCErrorInfo.domain` 判定→复用既有 `common.login_expired` 文案，不单独造一套 401 提示）；
>   已有数据在屏时翻页失败**不清空整页**，只在底部条显示「加载失败 · 重试」可点重试（UX 稿 §04-B）。
> - 新增本地化键（只加进本 worktree 两个 `.lproj`，**没有**跑 `IMServer/scripts/i18n/gen-i18n.mjs`——那个脚本
>   同时写 `../IMProgram`/`../im-web`/`../im-android` **主 checkout**，会动到其他并行 worktree 的文件，
>   有意避开；`call.history.*` 四个键需要在收口阶段补进 `IMServer/docs/i18n/strings.json` 让生成器接管）：
>   `call.history.empty`/`filter_all`/`filter_missed`/`group_subtitle`。
> - 测试：`IMProgramTests/IMCallHistoryRecordTests.m`（14 例，纯函数：未接判定/对方 uid/群人数/按日期分组/
>   全部-未接过滤）+ `IMCallHistoryPaginatorTests.m`（5 例，假 fetcher 驱动：首页到底/翻页到底后不再发请求/
>   未接自动续页/全部视图不自动续页/generation 作废在途旧请求不覆盖新首页），均对 `IMCallHistoryRecordIsMissed`
>   做过一次真实变异验红（临时改反判定，3 条测试正确地变红，改回后绿）。`./scripts/test.sh` 全量
>   **560/560 绿**（较之前 541 例新增 19 例，与新增测试数一致）。
> - **没做 / 已知限制**（v1 刻意不做，见设计文档 §0）：删除、长按菜单、未接数量角标——均未实现、未预留接口；
>   Web 端入口（`accountRows` 新增一行）不在本次范围，属 im-web worktree 的活；`docs/CLIENT_PARITY.md` 未碰
>   （按任务要求留给协调者统一收口登记三端状态）。
> - **需要真机验证**（模拟器测不出的部分，本次未做）：① 真机上实际打一通电话再回到「最近通话」页，确认
>   `callEnd` 事件触发了重拉且列表顶部出现新记录；② 真机网络切换/后台唤醒场景下的翻页体验（模拟器网络
>   稳定，测不出真实分页时延/失败率）；③ 群通话行点击跳转群会话、1v1 行点击直接回拨的**真实拨打**链路
>   （本次只走查代码复用了聊天气泡同款入口方法，没有真的拨通验证）；④ 深色模式下 `IMTheme.danger`/
>   `avatarColorForSeed:` 在真实设备上的对比度；⑤ VoiceOver：方向箭头 `↗`/`↙` 目前是纯文本 unicode 符号，
>   没有单独配无障碍 label，理论上 VoiceOver 会把箭头符号也读出来，体验待评估（不影响功能，纯打磨项）。

> 更早的已完成块（im-rtc 换票迁移、多语言 P1-P3、通话记录文案细化等）已移入
> [current_task.archive.md](current_task.archive.md)「归档于 2026-09-29」（只读归档）。

## 下一步
0. **「设置 ▸ 最近通话」真机验证**（本次新落地，清单见上「当前焦点」最后一条）：真机走一遍拨打→挂断→
   回到本页看 `callEnd` 是否自动刷新；1v1 行回拨、群聊行跳转是否真的可用；`docs/CLIENT_PARITY.md` 与
   `IMServer/docs/i18n/strings.json` 待协调者统一收口登记三端状态（本端未碰这两个跨端共用文档）。
1. **先验真机能否连通后端**：重装 App → 弹「允许查找并连接本地网络设备」点允许 → 登录页填 Mac 当前 LAN IP，
   免密/密码登录现在都会真发请求，失败会直接显示「无法连接服务器…」；Mac 侧核对 `grep -a '"remote_ip":"192.168' ../IMServer/imserver.log | tail`。
2. **真机手测回归（重启后端后）**：按住大圆钮跟手→上滑磁吸锁定→锁定行删/停/发；来电中断→回来停在锁定暂停；发送后长按有菜单、气泡稳定；转发语音真的送达；详情页语音 tab；收藏语音播放 + 从收藏发送；scrub/倍速/转文字/接力。异常记回本文件。
3. **安全整改的真机手测（第 1/3/5 步落地后一直没验，细节见 archive）**：登录页填裸 `host:port` 与改前完全一致；
   长连接连得上（会话列表显「已连接」）；填 `https://…` 应连不上（后端未开 TLS，属预期）；
   聊天图片/头像/群头像/收藏/记录卡照常显示；链接卡片的外站预览图仍能出图；
   退出登录后那台设备从「已登录设备」列表消失（logout 已接）。
4. 遗留 P2：听筒切换（贴耳切 route）；接力连播顶部「停止」控制条；Web 转文字（Whisper 调研）；
   **语音发送接入 IMMediaSendService 常驻队列**（现为 VC 内手工链：已强持有 self 保住"退出页不丢消息"，
   但仍无上传进度/取消，上传失败即删录音无 failed 行）；Web 语音上传期无回显（对齐 useMediaSend 先回显后上传）；
   Web 收藏/气泡语音 404 失效占位（复用 MEDIA_EXPIRY）。中断 vs 手势取消的系统投递顺序仍是赌注
   （多数机型触摸先取消→行为=自动发送，通知先到→锁定暂停；根治需 recorder interrupting 窗口标志）。
5. **选好友页缺「全选」**（2026-09-05 记）：`IMFriendPickerViewController` 没有全选/取消全选，
   Web 建群第一步早就有（只作用于当前可见行 + 按上限截断 + 与已选取并集）。加的时候照抄 Web 那套口径，
   别只做「勾上全部候选」——搜索态下会勾到用户看不见的人。
6. `setupUI` 抽 `IMComposerBar`（老欠账）；「从收藏发送」入口开放（见「已知坑」）。
7. **拆 `IMProgram/Network/IMSocketManager.m`（1566 行，已在体量门禁登记欠账，上限 1600「只准降不准升」）**：
   方向按 CODING_STYLE §7 三档——帧编解码 / 重连退避 / 各业务 send-recv 分组各自成协作对象或 category。
   同批还有三个 WARN 逼近 1500：`IMHTTPService.m` 1460、`IMDatabase.m` 1453、`IMChatDetailViewController.m` 1466。

## 已知坑 / 限制
- **通讯录 `reload` 不防重入（2026-09-12 复查记，老问题未修）**：切入节流只挡切入这一路；好友事件 / 增删拉黑与切入的请求
  并发时，后发先至会让 `applyFriends:` 按到达顺序覆盖成较旧名单（短暂，下次刷新自愈）。补法：`reload` 在途时只记「待重跑」，回来后再拉一次。
- **`IMProgramUITests/IMContactsPerfUITests` 对 2000 好友的账号会卡住**：XCUITest 每查一次元素都要给整棵无障碍树拍快照，
  `UITableView` 把 2000 行全暴露出来 → `cells.count` 一次 30s+ 超时重试（App 本身不卡）。重跑前须改成不查大表（只点 Tab / 看标题），
  效果改看 `contacts_index_applied` / `contacts_cache_persist` 日志与 simctl 截图。
- **撤回消息的「重新编辑」可能在重拉后消失（2026-09-03 评估后刻意不修）**：服务端本轮安全修复起，
  撤回 / 「为所有人删除」的**正文不再随 `sync_resp`/`window_resp` 下发**（原文只留服务端库内供审计）。
  而 `IMDatabase writeIncomingMessage` 的 UPDATE 里 `content=?` 是**无条件覆盖**的——`file_name`/`thumb`/
  `waveform`/媒体尺寸时长都有 `CASE WHEN LENGTH(?)>0` 保值，唯独 content 没有。于是撤回后那一段若被
  重新拉过（上翻触发 `window_resp`、或从更低游标 sync），本地正文被空串盖掉，`IMSystemCell` 的
  「重新编辑」按钮（判 `m.content.length > 0`）随之消失。**不崩、不出空输入框，纯优雅降级。**
  不修的理由：① 该按钮真实使用窗口是撤回后几秒，那时人贴着底、不会触发重拉；② 一刀切给 content 加保值
  会**同时让「为所有人删除」的正文在本地长期留存**，与该功能语义相悖，要避开就得在热路径 UPSERT 里
  区分 recalled/deleted 两种空值来源；③ 微信的重新编辑本就是「刚撤回那一刻」的能力，而**本端这个按钮
  至今没有时间限制**（一年前撤回的还能重编），服务端脱敏反而把它往正确方向推了一点。
  真要保住它，正确做法是**撤回时把原文另存为「待重编辑草稿」**（按会话存、发出或超时即清），
  而不是给 DB 加保值。服务端侧同一条记在 `IMServer/current_task.md`「已知坑」。
- **`IMMediaPlaceholderTests testFrostedLandscapeScalesLongestSideTo48` 在高负载下会偶发失败**（2026-08-30 首次观察；
  2026-08-31 起**基本被 `scripts/test.sh` 规避**）：只在**并行 clone + 同时跑 UITests** 时复现——
  该用例作为某个 clone 上的第一条执行、耗时 9.5s（正常 2.7s）后失败。`scripts/test.sh` 写死了
  `-only-testing:IMProgramTests` + `-parallel-testing-enabled NO`，两个诱因都没了，314 例稳定绿。
  **根因仍未定位**（用例本身对时序敏感），若哪天在串行模式下也复现，请抓 XCTAssert 原文再查。
- **`runAfterKeyboardHidden:` 兜底待测（2026-08-05 记）**：依赖 `resignFirstResponder` 后必然收到 `UIKeyboardDidHideNotification`——软键盘正常成立；若实测硬件/外接键盘场景引用跳转不触发，加 `dispatch_after` 超时兜底。
- 相册导出期杀 App 消息消失（PHPicker 句柄一次性，属预期，微信同）；导出失败的行点 ↻ 提示副本丢失需重选。Files 面板 <8MB 小文件、相机**拍照**、粘贴图仍为 VC 锚定一次性上传（秒级；粘贴图已带预览条攒批）；
  相机**录像**已改走 `IMMediaSendService` 常驻队列（2026-08-29）。
- iOS 无双向分页（进会话全量载入本地 DB）；presence/typing 仅聊天页标题生效。dev-login 建的账号无法再走密码登录（测密码登录用「注册并登录」或清 `imserver.db`）。
- **查看器"正在播放中"视频 404 未接失效占位（2026-08-11 记）**：`IMMediaViewerViewController` 有 `item.status` KVO 但失败一律走「无法播放该视频」兜底，未把 404/410 翻 ⊘。窄路径（气泡/媒体库通常先探到→进查看器即短路），兜底不黑屏故可接受。补法：失败分支走 `IMMediaExpiryRegistry verifyExpiredForURL:` 定性→失效覆盖层 + mid-play teardown。
- **失效标记内存态不持久（刻意，2026-08-11 记）**：`IMMediaExpiryRegistry` 用进程内 Set，冷启动首帧重探一次换自愈；仅当服务端上自动 TTL 清理使失效变常态才上持久化。
- **系统按钮文案本地化（2026-08-12 修，未编译验证）**：`Info.plist` 补 `CFBundleLocalizations=[zh-Hans,en]` 让 QLPreview「Done」/UISearchBar「Cancel」等系统文案落中文；自有 UI 硬编码中文，将来做真·多语言再建 `.lproj`。
- **原图路径 JPEG 字节戴 `.heic` 帽子（2026-08-12 记，暂不改）**：`IMMediaPicker buildImageItem` 原图分支按 `UTTypeImage` 取字节（iOS 可能把 HEIC 转 JPEG 交付）但扩展名靠 `hasItemConformingToTypeIdentifier:UTTypeHEIC` 猜 → JPEG 内容 + `.heic` 名错配。Web 靠字节嗅探已能各自正确显示故非阻塞；计划换第三方相册选择器（任务4）后此坑自消。
- 测试只跑 `-only-testing:IMProgramTests`；改后端协议后需重启后端再测。
- **体量门禁曾有覆盖盲区（2026-09-01 修）**：`scripts/check-file-size.sh` 原先只 `find IMProgram/Modules
  IMProgram/Common`，`Network`/`Database`/`Models`/`App` 整片在视野外，`IMSocketManager.m` 因此悄悄涨到
  1566 行没人拦。现扫整个 `IMProgram/`（测试 target 是它的兄弟目录，天然不在范围内）。
  **教训**：机械护栏本身也要有人核对覆盖面——"门禁全绿"只说明它扫过的那部分绿。
- **聊天页「从收藏发送」入口暂屏蔽/暂不支持（2026-08-19）**：`IMChatViewController` `attachItemTapped:` 的 `favorite` 分支仍走 `im_showComingSoon`（等效屏蔽）。设计已保留（`../IMServer/docs/FAVORITES_DESIGN.md` §5.5 标 ⏸），待收藏改造统一放开并接卡片式收藏选择器。

## 关联工程 / 常用命令
- 后端 `/Users/dev/IOSProject/IMServer`；Web `/Users/dev/IOSProject/im-web`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 测试编译 + 实跑：`xcodebuild build-for-testing ...` → 有 booted 模拟器则 `test-without-building ... -only-testing:IMProgramTests`。
- 真机日志：`xcrun devicectl device copy from --device iPhoneWork --domain-type appDataContainer --domain-identifier com.libeyond.IMProgram --source "Library/Caches/Logs/<file>.log" --destination <dst>`（list 用 `device info files`；崩溃报告 `--domain-type systemCrashLogs`）。
- 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
