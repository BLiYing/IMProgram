# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

> **修：聊天页点图片打开的查看器从来不能翻页（2026-09-16 用户报，未提交、未上模拟器）**：
> 翻页容器与「整会话媒体时间线」2026-08-12 就落地了（`IMMediaPagerViewController` + `conversationMediaMessages`），
> 但 `presentMediaViewerForMessage:` 取起始下标用的是 `indexOfObjectIdenticalTo:`（**指针相等**）——
> 时间线是现查库得到的**另一批对象**，故恒 `NSNotFound`，每次都走「找不到就单开一个查看器」的兜底分支。
> 媒体库那条路直接按下标开，所以一直正常，用户问的正是「媒体库的翻页不是有吗，不能共用吗」。
> 判据抽成 `Common/IMMediaTimeline.h`（`conv_seq` 优先、未确认才用 `clientMsgID`、空串不认，与 im-web `album.ts`
> 的 `msgKey` 同源，已登记 SYMMETRY），`IMMediaTimelineTests` 8 例 + 变异验红；`./scripts/test.sh` 487 例全绿。
> **同根因的第二处**（`/code-review` 抓出）：同一函数 `pageProvider` 里的 `mm == m` 也是跨批次指针比较、恒假，
> 于是「仅初始那条带气泡预载图」这个优化**从来没生效过**——每次打开都先显模糊占位再按 URL 重拉。改按下标判
> （`index == start`）。这一条没有单测，要在模拟器上看：点一张已经渲染过的图，应当**瞬时**显示、不闪占位。
> **要模拟器看**：点聊天里的图能左右翻、i/N 对得上、翻到的那张上「更多」作用在它身上。

> **第四批用户报告（iOS 部分）✅ 2026-09-15（用户自测通过，已提交）**：「消息」Tab 蓝点太大——系统 `badgeValue = @""` 尺寸不可调，
> 改 `IMMainTabBarController` 的 `setConversationsTabDotVisible:` 自绘 8pt（按标题 label 找图标、挂在图标右上角；找不到退回系统空角标）。
> ⚠️ 找图标依赖系统底栏私有层级，iOS 大版本升级后先看这颗点。

> **第三批用户报告（iOS 部分）✅ 2026-09-15（用户复测通过，已提交；`ONLY=IMTabUnreadCountTests` 5 例通过 + 变异验红）**：
> ① 页面标题与 Tab「会话」→「消息」（`IMMainTabBarController.m` 两处 + 列表页 `self.title` 两处 + UI 测试 `IMContactsPerfUITests`）；
> ② 「消息」Tab 补未读蓝点（此前只有 Android 有）：判据 `Common/IMUnreadBadge.h` 的 `IMTabUnreadCount`（免打扰不计、免打扰里 @ 计 1、
>    标未读不计，与 Web badgeCountOf / Android TabUnread 同口径）；列表页 `setConversations:` 一个咽喉算空态 + 蓝点，就地改
>    unread/muted 处手动调 `refreshListIndicators`；**离屏也要变**——viewWillDisappear 会摘掉 self 全部订阅，故另挂一组常驻
>    block token（`startTabDotObservers`，只在用户停在别的 Tab 时每秒最多补读一次本地库）；
> ③ 顺带修同一个洞：新装包首登时缓存为空先闪「还没有会话」→ `serverListed`（服务端拉成过一次才画空态）。
> **要模拟器看**：`badgeValue = @""` 在 iOS 26 UITab 上是否画成小圆点（没看过）；切到通讯录后来消息，约 1s 内点亮。

> **第二批用户报告 ✅ 2026-09-15（未提交；单测 + 变异验红 + iPhone 17 Pro Max 模拟器截图实测）**，逐条见 IMServer `docs/CLIENT_PARITY.md` 顶部：
> ① 「新的朋友」角标数字偏右：UILabel 居中不计行尾空格，`"  %@  "` 撑宽必偏——改显式 `_badgeWidth`（同会话列表）；
> ② 角标统一蓝：入口角标 `IMTheme.unreadBadge`，Tab 角标走 `UITabBarAppearance.badgeBackgroundColor`（iOS 18 起 UITab 没有 badgeColor）；
> ③ 文本 / 引用消息时间挪到气泡右下角：`IMBubbleCell` 右下角独立 `_textMeta` + 正文末尾透明占位 `IMBubbleMetaPlaceholder`
>    让位（链接卡展开时时间落卡片下方）；④ **改昵称后老消息仍显旧名**：`senderPublicNameForMessage:` 原为快照优先，
>    改「成员表 > 本窗最新快照 > 本条快照」（`Common/IMGroupSenderName.h`，4 例单测）+ 来消息昵称对不上成员表节流重拉。
> 实测：通讯录两处角标蓝且居中；「1002群」里改名后的 user3005 旧消息显示新名（本地库快照仍是旧名）；链接 / 引用消息时间在右下角。
> 模拟器没覆盖到：文件文 / 长文本折叠 / 链接卡展开这几种气泡的时间位置；会话开着时对方改名再发消息的重拉。

> **三个聊天页 bug ✅ 2026-09-15（用户报，未提交；只跑单测 + 变异验红，未上模拟器）**：
> ① **进单聊一片空白、对方发新消息才出历史**（2026-09-13 libeyond↔user1001，13 万条积压、本地 0 条）：
> `requestServerTailWindowIfBehind` 只认内存 head，改密被踢 → 重登后 `IMBacklogTracker` reset、head=0 → 直接 return。
> 改为内存 head 未知退回**落库** head、两者都未知且空窗也问（`IMChatTailTip` / `IMChatShouldRequestTail`，4 例单测）；
> 与 Web「tip 未知一律问」的差异已登记 SYMMETRY。② **文件文（文件 + caption）时间悬在气泡中段**：`IMBubbleCell`
> 的 `_fileMetaLabel` 改挂气泡，有 caption 时落到 caption 下方（约束两组互斥，行高改「贴状态行但不矮于图标位」）。
> ③ **纯链接消息没有时间**：`IMLinkCardCell` 加时间行 + configure 带 `peerReadSeq`。
> **要真机/模拟器看**：②文件名一行/两行 × 有无 caption × 上传/下载进度中 的行高；③OG 卡片异步展开前后的间距。

> **通讯录大名单（好友列表空白 + 切 Tab 卡顿 + 剩余主线程开销）✅ 2026-09-12 手测通过**（`e5cbac8` + `f57816a`）：
> 细节已移入 [current_task.archive.md](current_task.archive.md)「2026-09-11~12 通讯录大名单」。遗留的 `reload` 并发覆盖见「已知坑」。

> **会话内搜索服务端命中翻页 ✅ 2026-09-11**（与 im-web `b30bed6` 对齐）：有缺口的会话走服务端检索，
> 原先只取一页（计数写「/ 50+ 条」却翻不过去）。▲ 翻过最旧命中带 `next_cursor` 取下一页，判据在
> `Common/IMChatSearchPaging`（8 例单测），调用点 `IMChatViewController+Search.m` 的 `loadOlderSearchHitsAttempt:`。
> 模拟器实测过（20000人大群 10 万条命中翻过第一页），脚本 `IMProgramUITests/IMChatSearchPagingUITests`
> 需 `:8099` 积压副本库（IMServer `docs/ops/LOAD_TESTING.md` §10.5），默认跳过。
>
> **C4 ✅ 2026-09-11**（`c6d2015`，同步 im-web）：`requestServerTailWindowIfBehind` 改问区间清单（收掉 C3 残留①「无未读那条路
> `head <= localMax`」）、实时消息落库后登记 [seq, seq]、bump 贴底跟随才补（补法与 Web 刻意不同，见 `IMChatBumpShouldCatchUp`）。
> **只跑了单测 + 变异，未上模拟器**；实时登记区间与 onConvBump 的 following 取值没有测试覆盖。

> 更早的已完成块已移入 [current_task.archive.md](current_task.archive.md)（只读归档）。

## 下一步
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
- 后端 `/Users/liying/IOSProject/IMServer`；Web `/Users/liying/IOSProject/im-web`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 测试编译 + 实跑：`xcodebuild build-for-testing ...` → 有 booted 模拟器则 `test-without-building ... -only-testing:IMProgramTests`。
- 真机日志：`xcrun devicectl device copy from --device iPhoneWork --domain-type appDataContainer --domain-identifier com.libeyond.IMProgram --source "Library/Caches/Logs/<file>.log" --destination <dst>`（list 用 `device info files`；崩溃报告 `--domain-type systemCrashLogs`）。
- 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
