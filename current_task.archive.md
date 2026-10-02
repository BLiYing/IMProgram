> ⚠️ 历史归档（只读，勿更新）。当前活快照见同目录 current_task.md；本文件只供考古。

---

# 归档于 2026-10-02（current_task.md 瘦身前全量快照——整份原样移入；已完成/已验证条目不再回到活快照，仍有效的待办与坑已精简后留在 current_task.md）

> # Current Task — IMProgram（iOS）
>
> > **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> > 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。
>
> ## 当前焦点
>
> > **2026-10-02 「我」页头部断网兜底 + 会话壳不再把 uid 当昵称（真机验证通过）**：`IMSessionStore` 存/读本人资料副本（昵称/头像/句柄，按 uid，不存手机号，`clear` 擦除），`IMSettingsViewController` 先读缓存再 `loadMyProfile`；`IMDatabase` 由消息造壳时 `peer_nickname` 留空，`IMConversation.displayName` 末级「未命名用户」，新增 `knownDisplayName`（聊天页/通知类型页入口用它，占位文案不当昵称冻结）。**改了旧断言** `IMRemarkStoreTests`（原「无昵称→uid」违反 UI.md）。未处理：`IMChatViewController.m` 的 `peerDisplayName` 仍有 `fallback:peerID`。状态表见 CLIENT_PARITY。
>
> > **2026-10-01 通知显示发送人头像**（PUSH_M5_DESIGN §3.6/§3.7）：新增通知扩展 target `IMNotificationService`（Xcode 同步文件夹 `IMNotificationService/`，共享 `Common/IMPushSender.m`、`Common/IMPushAvatarCache.m` 靠 pbxproj 里的成员例外）；主 App 加 App Group + 通信通知 entitlement、`NSUserActivityTypes`。扩展不链接 Pods，日志用 os_log。看扩展日志：`idevicesyslog -u <udid>` grep IMNotificationService。
> > **2026-10-01 别的端已读后清手机通知/角标**（PUSH_M5_DESIGN §3.5，真机验证通过）：`Common/IMPushRetract` 加 `IMPushClearDeliveredNotificationsReadThrough`；`AppDelegate` 收 `clear_up_to` 推送（Info.plist 新增 `remote-notification` 后台模式）；`handleReceipt` 收本人回执时同样清。`IMSocketManager.m` 现 1596/1600。
>
> > **2026-09-30 多选删除两档·改批量接口（2026-10-01 模拟器实测通过，已提交并推送 `74d8ecd`）**：`IMChatViewController+Selection.m` 的
> > `performDeleteSelected` / `performDeleteSelectedForEveryone` → `-runBatchDelete:everyone:`，经新 category
> > `Network/IMSocketManager+BatchDelete`（+ `IMHTTPService+BatchDelete`）一次请求 `POST /messages/hide|delete`，
> > 成功项本地移除、失败汇总一句「N 条删除失败」；走 REST，断线也能删（不再先拦）。`msg_hidden` 批量帧读 `conv_seqs`
> > （`IMMsgHiddenSeqs`）。批量删除广播帧（一帧 `targets`，2026-10-01）走 `applyBatchDeleteFrameOnQueue:`，整批移除只发一次通知（`kIMMsgOpTargetSeqsKey`），聊天页/媒体页一次删完只刷新一次。置顶横幅：`-onMessageRemoved:` 改为无条件调 `-schedulePinnedBannerReload`（+PinnedBanner.m，
> > 0.3s 尾沿合并，代数存关联对象——Private.h 已 72 条到闸），批量结束再触发一次。`IMBatchDeleteTests` 3 例（先看红）；test.sh 667/667。
> > **2026-10-01 模拟器已验**：单聊两档批量、收/发整批一帧、混选只一档、断服务「2 条删除失败」、删置顶消息横幅即消（服务端旁听确认每成员只收一帧）。九宫格逐格选、群主选别人的消息有第二档也已验（2026-10-01）。**已无待验项**（iOS 真机未测，仅模拟器）。
>
> ## 下一步
> 1. **M5 第一批真机验证**（清单见上「当前焦点」）——服务端/安卓/Web 并行实现完成后，协调者统一在真机上
>    过一遍 user1002(Pixel)↔iPhone 的私聊/群聊/@我/图片四种消息、App 后台/被杀/锁屏三种状态。
> 2. **M5 落地后**：协调者需要补 `IMServer/docs/CLIENT_PARITY.md`（M5 行按 iOS/安卓/Web 拆状态）与
>    `SYMMETRY.md`（`IMNotifySettingsMigration` 对端行、`alertDecision` 服务端第四端登记）——本次任务
>    明确限定「只改 IMProgram」，这两份 IMServer 文档故意没碰。
> 3. **通知 P1 批一 + 批二真机验证**（清单见 `current_task.archive.md` 最新归档块）——批一横幅/批二时长菜单
>    都还只过了模拟器编译，没有真机跑过。
> 4. **「设置 ▸ 最近通话」真机验证**（call-history v1 遗留）：真机走一遍拨打→挂断→回到本页看 `callEnd`
>    是否自动刷新；1v1 行回拨、群聊行跳转是否真的可用。
> 5. **先验真机能否连通后端**：重装 App → 弹「允许查找并连接本地网络设备」点允许 → 登录页填 Mac 当前 LAN IP。
> 6. **拆 `IMProgram/Network/IMSocketManager.m`（1595 行，已在体量门禁登记欠账，上限 1600「只准降不准升」，
>    本批 app_state/notify_settings_update 新逻辑已尽量收进 `+Push` category、主文件净增仅 2 行，但余量已
>    压到 5 行，下次再要扩这个文件必须先拆）**：方向按 CODING_STYLE §7 三档——帧编解码 / 重连退避 / 各业务
>    send-recv 分组各自成协作对象或 category。
> 7. **`IMDatabase.m` 已卡在体量门禁上限（1500/1500，一行不剩）**：下次再要给 `im_conversation_local`/
>    `im_message_local` 加列，必须先拆（参考 `IMDatabase+MuteState.m` 的路子）。
> 8. 选好友页缺「全选」；`setupUI` 抽 `IMComposerBar`；「从收藏发送」入口开放；遗留 P2（听筒切换/接力连播停止条/
>    Web 转文字/语音发送接入 IMMediaSendService 常驻队列等，细节见 `current_task.archive.md`）。
>
> ## 已知坑 / 限制
> - **`IMSocketManager.m` 体量门禁余量已压到 5 行**（1595/1600，见「下一步」第 6 条）：任何后续改动优先
>   考虑新开 category，不要再往主文件加行。
> - **冷启动通知路由的极端情况**（本批新记，详见「当前焦点」没做第 1 条）：全新会话的推送点击可能落空。
> - **会话列表左滑「免打扰」在 swipe action 的 `done(YES)` 之后同步 present `IMMuteDurationMenu`**：
>   `UIContextualAction` 的 handler 里先调用 `presentMuteMenuForConversation:` 再 `done(YES)` 收起 swipe，
>   present 与 swipe 收起动画同时发生，没有等 swipe 完全收起再弹菜单。真机如果两个动画叠加显得突兀，把
>   present 挪到 `done(YES)` 之后（或加一个短延时）即可。
> - **通知横幅点击进会话与自身 dismiss 动画并行发起**：`handleTouchUpInside` 里先起 dismiss 动画、同一时刻
>   调 `IMConversationRouter openConversation:`——没有等横幅完全收起再转场。真机上如果转场与横幅收起动画
>   叠加显得突兀，改成 dismiss 完成回调里再路由即可（一行改动）。
> - **通讯录 `reload` 不防重入**：切入节流只挡切入这一路；好友事件 / 增删拉黑与切入的请求
>   并发时，后发先至会让 `applyFriends:` 按到达顺序覆盖成较旧名单（短暂，下次刷新自愈）。补法：`reload` 在途时只记「待重跑」，回来后再拉一次。
> - **`IMProgramUITests/IMContactsPerfUITests` 对 2000 好友的账号会卡住**：XCUITest 每查一次元素都要给整棵无障碍树拍快照，
>   `UITableView` 把 2000 行全暴露出来 → `cells.count` 一次 30s+ 超时重试（App 本身不卡）。重跑前须改成不查大表（只点 Tab / 看标题），
>   效果改看 `contacts_index_applied` / `contacts_cache_persist` 日志与 simctl 截图。
> - **撤回消息的「重新编辑」可能在重拉后消失**：详情见 `current_task.archive.md`；
>   服务端本轮安全修复起撤回/删除正文不再随 sync_resp/window_resp 下发，`IMDatabase writeIncomingMessage`
>   的 `content=?` 无条件覆盖，重拉后本地正文可能被空串盖掉，「重新编辑」按钮随之消失（优雅降级，不崩溃）。
> - **`IMMediaPlaceholderTests testFrostedLandscapeScalesLongestSideTo48` 在高负载下会偶发失败**（已被
>   `scripts/test.sh` 的 `-only-testing:IMProgramTests` + `-parallel-testing-enabled NO` 基本规避，根因未定位）。
> - **`runAfterKeyboardHidden:` 兜底待测**：依赖 `resignFirstResponder` 后必然收到
>   `UIKeyboardDidHideNotification`；若实测硬件/外接键盘场景引用跳转不触发，加 `dispatch_after` 超时兜底。
> - 相册导出期杀 App 消息消失（PHPicker 句柄一次性，属预期）；Files 面板 <8MB 小文件、相机拍照、粘贴图仍为
>   VC 锚定一次性上传；相机录像已走 `IMMediaSendService` 常驻队列。
> - iOS 无双向分页（进会话全量载入本地 DB）；presence/typing 仅聊天页标题生效。dev-login 建的账号无法再走
>   密码登录（测密码登录用「注册并登录」或清 `imserver.db`）。
> - **查看器"正在播放中"视频 404 未接失效占位**：窄路径（气泡/媒体库通常先探到→进查看器即
>   短路）不黑屏可接受，兜底文案未区分失效。
> - **失效标记内存态不持久（刻意）**：进程内 Set，冷启动首帧重探一次换自愈。
> - **系统按钮文案本地化**：`Info.plist` 补 `CFBundleLocalizations` 让系统控件文案落中文；自有 UI 硬编码中文。
> - **原图路径 JPEG 字节戴 `.heic` 帽子（暂不改）**：Web 靠字节嗅探已能正确显示，非阻塞。
> - 测试只跑 `-only-testing:IMProgramTests`；改后端协议后需重启后端再测。
> - **体量门禁覆盖面**：已扫整个 `IMProgram/`（测试 target 是兄弟目录，天然不在范围内）。
> - **聊天页「从收藏发送」入口暂屏蔽/暂不支持**：`attachItemTapped:` 的 `favorite` 分支仍走
>   `im_showComingSoon`；设计已保留（`../IMServer/docs/FAVORITES_DESIGN.md` §5.5 标 ⏸），待收藏改造统一放开。
>
> ## 关联工程 / 常用命令
> - 后端 `/Users/dev/IOSProject/im-client/IMServer`；Web `/Users/dev/IOSProject/im-client/im-web`；
>   Android `/Users/dev/IOSProject/im-client/im-android`。
> - 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
> - 测试：唯一入口 `./scripts/test.sh`（体量门禁 + 编译 + `IMProgramTests`，见 `CLAUDE.md`「构建 / 测试」节
>   的三个坑与用法：`BUILD_ONLY=1`/`ONLY=<Class>`/`ONLY=<Class>/<test>`）。
> - 真机日志：`xcrun devicectl device copy from --device iPhoneWork --domain-type appDataContainer
>   --domain-identifier com.libeyond.IMProgram --source "Library/Caches/Logs/<file>.log" --destination <dst>`。
> - 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
>

---

# 归档于 2026-09-30（M5 离线推送第一批落地前，把「定时免打扰」第二批的「当前焦点」详情块从活快照转入）

> **通知与提示音 P1 · 第二批「定时免打扰」✅ 代码 + 单测已完成，待真机验（2026-09-29，分支
> `feature/notif-p1b`，设计：`../IMServer/docs/design/NOTIFICATIONS_P1_DESIGN.md` §4/§5/§6.2(iOS
> 列)/§7 点2·6，协议 `../IMServer/docs/PROTOCOL.md` §6.10「mute_until」，后端已先行落地并跑在 :8080）**：
> 三端同名纯函数 `IMIsMutedNow` + 时长菜单 + 三个入口（会话列表/聊天详情页/添加例外）+ 到期本地定时刷新。
> - **`Common/IMMuteState.h/.m`**（新，与 im-android `MuteState.kt`/im-web `muteState.ts` 对端）：
>   `IMIsMutedNow(muted,muteUntil,now)` = `muted && (muteUntil==0 || now<muteUntil)`（`now==until` 视为
>   已解除）；`IMMuteUntilLabelMake` 到期文案分类器（today/tomorrow/date/forever，按 tzOffsetMinutes 纯
>   毫秒运算比日历日，不经 NSCalendar 本地时区/DST，向量可测）；`IMMuteDetailValueText`/
>   `IMMuteExceptionSubtitle` 是详情页右值/例外副标题的展示拼装（未进向量，纯 UI 层）。共用向量
>   `IMServer/docs/conformance/mute_state.json`（isMutedNow 6 例 + untilLabel 8 例）。
> - **`Common/IMMuteDurationMenu.h/.m`**（新）：ActionSheet，标题 `notif.mute.sheet_title` 代入会话名；
>   1 小时/8 小时/1 天/7 天/永久 + 取消；`showUnmuteFirst=YES` 时顶部多一条红色「取消免打扰」（聊天详情页
>   已免打扰时用，列表左滑/右键已免打扰时不弹本菜单、直接单条取消）。纯函数
>   `IMMuteUntilForDurationOption(option, nowMs)` 单独可测（不依赖真实时钟）。
> - **`Common/IMMuteExpiryScheduler.h/.m`**（新）：单例，按当前会话集合算「最近一个未到期 mute_until」
>   挂一次性 `NSTimer`，到点广播 `IMMuteExpiryDidChangeNotification`（不发请求，服务端同一时刻自然也判
>   过期）。会话列表 `refreshListIndicators`（setConversations 的唯一咽喉）与例外列表 `reloadExceptions`
>   都会顺路重排；列表页 + 例外页常驻订阅该通知与 `UIApplicationDidBecomeActiveNotification`（App 回前台
>   兜底），收到后只 `reloadData`/重算，不触网。
> - **模型/存储**：`IMConversation` 加 `muteUntil`（列表 JSON `mute_until` 解析）；`IMDatabase`
>   `im_conversation_local` 加列 `mute_until`（新库建表 + 老库 `ALTER`，迁移逻辑放新 category
>   `Database/IMDatabase+MuteState.h/.m`——`IMDatabase.m` 改动前已 1499/1500，只留一行迁移调用口子
>   `[self migrateMuteUntilColumnDB:db]`，改完恰好卡在 1500，一行不多）；`cachedConversation:isGroup:
>   muted:` 加 `muteUntil:` 出参、`applyCachedSettingsForConversation:...` 加 `muteUntil:` 入参（两个方法
>   全部调用点已同步改）。
> - **写入**：`IMHTTPService updateConversationSettingsWithToken:...` 加 `muteUntil:(nullable NSNumber*)`
>   ——传 `nil` 即省略该字段（服务端保留未到期的原到期时间），传值即照写；置顶/标未读等不碰免打扰的调用
>   一律传 `nil`，选时长/取消免打扰的调用显式传值。所有调用点（会话列表 4 处、聊天详情页、例外页 2 处）
>   已按此口径过一遍。
> - **三个入口**：① 会话列表左滑/右键「免打扰」——未免打扰弹 `IMMuteDurationMenu`（`presentMuteMenu
>   ForConversation:`），已免打扰直接单条「取消免打扰」；② 聊天详情页「免打扰」行从开关变值行（右值
>   `common.off`/`至...`/`common.permanent`，`IMDetailSettingsRowMute` 点击走 `presentMuteMenu`），脚注
>   `chat.detail.mute_footer`（新增 `titleForFooterInSection:`，Settings 分区专属）；③ 「添加例外」选择页
>   ——选完会话先弹 `IMMuteDurationMenu`（`presentMuteMenuForNewException:`）再真正 PUT，picker 的
>   `extraFilter` 改用 `IMNotifExceptionPickerMatches(isGroup, IMIsMutedNow(...), peer, wantGroup)`（签名
>   本身没变，调用方喂有效值）。
> - **读取 → `IMIsMutedNow` 全部改完**：会话列表铃铛 + 未读变灰（`IMConversationCell configureWith
>   Conversation:`）、`IMUnreadBadge.m` `IMTabUnreadCount`、`IMSocketManager+Alerts.m` 拼 `ctx.muted`
>   （复用同一个 `nowMs` 变量，避免与 `ctx.nowMs` 用两次不同的 `IMNowMillis()`）、
>   `IMNotificationTypeViewController` 例外过滤（`reloadExceptions`）与「添加例外」选择页过滤、聊天详情页
>   状态。**刻意没改**（不是遗漏，是不同的「免打扰」概念）：`IMChatViewController+PinnedBanner.m` 的
>   `refreshComposerMuteState`、`IMGroupInfoViewController.m`/`IMChatDetailViewController.m` 的群成员/全员
>   禁言（`myMuteUntil`/`group.muteUntil`）——那是管理员禁言，不是本人的通知免打扰。
> - **本地化**：任务给定的 10 个新键（`mute.8h`/`mute.7d`/`notif.mute.sheet_title{name}`/
>   `notif.mute.until_today{time}`/`_tomorrow{time}`/`_date{date}`/`notif.exceptions.muted_until{until}`/
>   `_mention{until}`/`chat.detail.mute_footer`；`notif.exceptions.pick_footer_all` web-only 未接）进来时
>   已生成，本批一并提交，未改文案本身。
> - **测试**：新增 `IMMuteStateTests`（读 `mute_state.json` 两段 14 例 + 2 补充边界）、
>   `IMMuteDurationMenuTests`（时长→`mute_until` 映射 5 例）；`IMConversationCacheTests` 补
>   `applyCachedSettingsForConversation:...muteUntil:...` 与 `cachedConversation:isGroup:muted:muteUntil:`
>   往返断言。三处核心逻辑（`IMIsMutedNow`、`IMMuteUntilLabelMake` 的 day-diff 分类、
>   `IMMuteUntilForDurationOption`）均做过一次真实变异验红（分别改错「已解除」判据、把「明天」判成
>   「后天」、把 8 小时挪成 9 小时），全部按预期变红后改回。`./scripts/test.sh` **616/616 绿**（较第一批
>   收尾时 606 例新增 10 例）。
> - **没做 / 已知限制**：`IMServer/docs/CLIENT_PARITY.md`/`SYMMETRY.md` 本批未碰（任务明确限定「只改
>   IMProgram」，留给协调者收口三端）；桌面 Dock 角标/favicon 不在 iOS 范围。
> - **需要真机验证**（模拟器/单测测不出，本次完全没做）：① 时长菜单 ActionSheet 在真机上的呈现/交互
>   手感（模拟器已过一遍编译但未跑起来看）；② 列表左滑「免打扰」弹出菜单后 swipe 动画收起与菜单呈现是否
>   顺畅（`done(YES)` 与 present 几乎同时发生，和第一批横幅记录的「dismiss 动画与路由并行」是同一类风险）；
>   ③ 聊天详情页免打扰行从开关变值行后，点击态/disclosure 箭头视觉是否符合预期；④ 到期定时器真实等到点
>   触发（1 小时起，真机长时间挂起/低电量模式下 `NSTimer` 是否被系统延后未验，App 回前台兜底逻辑理论上能
>   补上但没有真机实测过）；⑤ 深色模式、英文界面下「Until tomorrow, 18:30」等较长文案的排版。
>
> **通知与提示音 P1 · 第一批**（应用内横幅/添加例外/应用内预览开关）已合并进 main（`8796fc5`），详情见
> 上一归档块。

---

# 归档于 2026-09-29（通知第二期第二批「定时免打扰」落地前，把第一批的「当前焦点」详情块从活快照转入 —— 从此往下继续「就地覆盖、不追加」）

> **通知与提示音 P1 · 第一批 ✅ 代码 + 单测已完成，待真机验（2026-09-29，分支 `feature/notif-p1a`，
> 设计：`../IMServer/docs/design/NOTIFICATIONS_P1_DESIGN.md` §0–§3/§6.2(iOS 列)/§7/§8，草图
> `sketches/NOTIFICATIONS_P1_UX_SKETCH.html` 01/02 节）**：范围＝应用内横幅 + 例外「添加例外」+
> 主页「应用内预览」真开关。
> - **`IMAlertDecision.m`**：`banner` 从恒 `NO` 改成 `eligible && platform==mobile && settings.inApp.preview`
>   （与 sound/vibrate 同一套资格，含 appActive/通话中/免打扰@我穿透；**不看节流**、**不看提示音是不是
>   「无」**）。共用向量 `alert_decision.json` 已扩到 32 条，全过。
> - **应用内横幅新组件**（现有 `UIViewController+IMToast` 是底部一次性吐司、`IMChatBannerStack` 是聊天页内
>   的置顶横幅，都不能复用，新写）：
>   - `Common/IMInAppBannerView.h/.m`：单例式 presenter，卡片挂在 key window（不盖状态栏、盖导航栏），
>     8pt 边距、14pt 圆角、阴影；滑入 250ms 尊重 `IMAppearance.shared.animationsEnabled`；4s 自动收起，
>     手指按住暂停计时（`UIControl` 的 touch down/up 事件），上滑手势收起；点击走 `IMConversationRouter`
>     进会话后立即收起；新消息到达时**原地换内容 + 重新计时**（不叠加、不排队）。
>   - **点击「进会话」怎么绕开 Network→Modules/Chat 反向 import**：新增 `Common/IMConversationRouter.h/.m`，
>     只存一个 `opener` block；`IMChatViewController.m` 新增 `+load` 把「统一进会话入口」注册进去（Modules/Chat
>     → Common，正常方向）；`IMSocketManager+Alerts.m`/横幅视图都只 `import` `IMConversationRouter.h`，
>     不认识 `IMChatViewController`。与既有 `IMChatPresence`（`viewingConv` 的同类反转方案）同一手法。
>   - **「打开的正是横幅那个会话就收起」怎么接**：`IMChatPresence` 新增
>     `IMChatPresenceDidChangeNotification`（`noteViewingConvID:` 同步广播），横幅订阅，convID 匹配即收起——
>     不论会话是不是靠点横幅打开的（比如从别处点开）都能收。
>   - **标题/正文纯函数**：`Common/IMInAppBannerContent.h/.m` 的 `IMInAppBannerContentBuild`——标题＝
>     `conversation.displayName`（与转发选择页/例外行同一来源）；正文＝该类型「消息预览」关时固定
>     `notif.preview.hidden`，开时私聊显摘要、群聊显「发送者: 摘要」。摘要**复用**新抽出的
>     `Common/IMConversationPreview.h/.m` 的 `IMConversationMediaPreview`（image/video/file/chat_record/
>     location/contact/call/voice 判定，从 `IMConversationListViewController` 的 cell 配置里原样搬出来，
>     两处调一份，不是照抄一份）。头像仍用 `UILabel+IMAvatar`（系统通知会话 seed=系统 uid 时组件自动出
>     应用图标，本函数不用重新判定）。
>   - **触发点**：`IMSocketManager+Alerts.m` 在 `result.banner` 为真时才多做一次 `cachedConversations`
>     全表扫描找 convID 对应的完整 `IMConversation`（平时每条实时消息只查一行 muted/isGroup，不做整表扫，
>     只有真要出横幅这个稀有分支才多付这个代价）。
> - **`IMForwardPickerViewController` 加了四个可选配置属性**（不设＝转发流程原行为不变）：
>   `extraFilter`（附加过滤 block）、`titleOverride`、`footerText`、`emptyText`（非空时零结果/搜索无匹配
>   常驻空态标签，不再弹 toast）、`immediateSingleSelect`（单选态隐藏「多选」入口，点一行不弹确认框、
>   立即回调 `onDone` 并收起）。
> - **`IMNotificationTypeViewController`**：「例外」组常驻，首行固定绿色（`IMTheme.accent`）圆形 + 号
>   「添加例外」行（`IMNotifAddExceptionCell`）。点了用 `immediateSingleSelect` 模式 present
>   `IMForwardPickerViewController`，`extraFilter` 用纯函数 `Common/IMNotifExceptionPickerFilter.h` 的
>   `IMNotifExceptionPickerMatches`。选中后 `muteNewException:` 走既有 `updateConversationSettingsWithToken:...`
>   PUT，**原样带回 `pinned_at`/`marked_unread`**（与 `unmute:` 对称，同一个坑）。
> - **`IMNotificationSettingsViewController`**：「应用内预览」行从灰置占位改真开关。
> - **本地化**：5 个新键均已在。
> - **测试**：新增 `IMConversationPreviewTests`（13 例）/`IMInAppBannerContentTests`（6 例）/
>   `IMNotifExceptionPickerFilterTests`（6 例），`IMAlertDecisionTests` 改读 32 条向量。`./scripts/test.sh`
>   **606/606 绿**。
> - **没做 / 已知限制**：定时免打扰（时长菜单/`mute_until`/`isMutedNow`，留给第二批——已在
>   `feature/notif-p1b` 落地，见活快照当前焦点）；`IMServer/docs/CLIENT_PARITY.md`/`SYMMETRY.md`/
>   `docs/i18n/strings.json`/`NOTIFICATIONS_DESIGN.md` §11 本批未碰（限定只改 IMProgram）。
> - **需要真机验证**（模拟器/单测测不出，本批完全没做）：横幅滑入/滑出动效手感、4 秒自动收起体感、
>   按住暂停/松开恢复、上滑手势收起识别率、连发多条原地换内容不叠加、深色模式卡片观感、点击进会话转场
>   顺畅度、「添加例外」空态/脚注排版与绿色圆形对比度、VoiceOver（未适配）。

# 归档于 2026-09-29（第二轮清理 —— 通知与提示音 P1 第一批落地前，把上一轮清理之后又累积起来的
# 「当前焦点」历史块再次转入归档；`current_task.md` 只留 P1 批一这一条，往下继续「就地覆盖、不追加」）

> 本节是 P0 通知 / 加号面板图标立体感优化 / 六条用户报告第 5 项 / 最近通话验收修复 / 设置▸最近通话 v1
> 这五个已完成块，原样从活快照搬入，未删减。

> **设置 ▸ 通知与提示音 P0 ✅（2026-09-29，分支 `feature/notifications`，设计：
> `../IMServer/docs/design/NOTIFICATIONS_DESIGN.md`，模拟器 XCUITest 截图验证三页）**：
> `IMNotificationSettings`（`Common/`，`NSUserDefaults im.notif.*`，非法值/未知提示音 id 回落默认，
> 设备本地、退出登录不清，改动广播 `IMNotificationSettingsDidChangeNotification`）+ `IMAlertDecision`
> 纯函数（30 条共用向量 `IMServer/docs/conformance/alert_decision.json` 全过，含 desktop/browser 分支
> 只为过向量、iOS 运行时只构造 platform=mobile）+ `IMAlertPlayer`（`AudioServicesPlaySystemSound` +
> `UIImpactFeedbackGenerator(.light)`，1.5s 节流时钟自持，供 decide 读 `lastSoundAtMs`）。
> **实时消息 hook**：`IMSocketManager+Alerts.m`（新分文件 category，避免把 `IMSocketManager.m` 推过 1600
> 行体量闸——直接加进主文件会挂账超标）挂在 `processIncomingMessage:` 的 `!fromSync` 分支，历史/sync/
> window 一律不判。`viewingConv` 靠新增 `Common/IMChatPresence`（`IMChatViewController` viewDidAppear/
> viewWillDisappear 登记，独立类是为了不让 Network 层反向 import Modules/Chat）；`inCall` 读
> `IMRtcCall.shared.isStarted`。三页 UI：`IMNotificationSettingsViewController`（主页）/
> `IMNotificationTypeViewController`（私聊+群聊共用，例外列表=本机 `muted=YES` 会话，左滑取消免打扰
> 严格回传 `pinned_at`/`marked_unread`）/ `IMNotificationSoundViewController`（选中即试听）。
> `IMSettingsViewController` 入口 handler 从 `comingSoon:` 改 push；`IMTabUnreadCount` 加 `includeMuted`
> 入参（默认由设置页 `badge.includeMuted` 驱动，会话列表订阅变更通知刷新蓝点）。
> **测试**：新增 `IMAlertDecisionTests`（30 向量+2 补充）/`IMNotificationSettingsTests`（7 例）/
> `IMAlertPlayerTests`（5 例，含资源打包回归——找不到 `.caf` 会让 `lastSoundAtMs` 不推进）/
> `IMTabUnreadCountTests` 补 3 例；均对核心分支做过一次真实变异验红（`IMAlertDecision` 的
> `eligible`、`IMUnreadBadge` 的 `includeMuted` 分支）。`./scripts/test.sh` **580/580 绿**。
> **已知缺口/未做**：Web「静音→免打扰」文案统一（§9-5，属 im-web）、`CLIENT_PARITY.md`/
> `IMServer/docs/i18n/strings.json` 收口（按 call-history 先例留给协调者统一登记三端）、真机静音键/
> 振动/连发节流实测（仅模拟器截图验证 UI，未验证真实声音/触感）。

> **加号面板图标立体感优化 ✅（2026-09-29，用户反馈"图标好丑"，模拟器 XCUITest 截图验证）**：
> 圆钮原先纯色块（`systemBackgroundColor`，未走语义令牌）贴着面板背景，两层灰度太接近显得扁平。
> 征求方向后走「保留单色、加立体感」（未引入每项一个颜色——项目 `UI_COLOR.md` 是严格的语义化
> 单色令牌体系，全 app 没有这个先例）：圆钮背景改 `IMTheme.surfaceElevated`，补轻阴影
> （`shadowOpacity 0.12/radius 4/offset (0,1)`），同 `IMVoicePressOverlay` 的 `_lockPill` 那套
> 手法。Android `AttachPanel.kt` 同批改（`c.surfaceElevated` + `shadow(1.dp)`，图标 26→28dp、
> 色调 `textSecondary`→`textPrimary` 补对比度）。两端 `./scripts/test.sh` 全绿。**验证**：
> XCUITest/adb 截图核对，肉眼确认方块与面板背景可辨、有明显阴影，已删除脚本。

> **六条用户报告第 5 项：加号面板去掉音视频占位 ✅（2026-09-29，模拟器 XCUITest 截图验证）**：
> `attachItems` 的 "av" 一直是打不通的占位——点了只弹「还没做」，而呼叫/视频早已在聊天详情页
> （`showsMessagePill`/`IMChatDetailViewController`）真正接通，面板这颗反而误导用户以为是
> 另一条独立的路。删掉数组条目、`chat.attach.av`/`chat.attach.audio_video_unimplemented`
> 两条不再被引用的本地化字符串；`attachItemTapped:` 末尾兜底从 `im_showComingSoon` 改成
> `NSAssert`（五个已知 id 现在全部真实接通，走到兜底说明加了新项忘记接实现）。**顺手修了
> `buildAttachPanel` 一个此前没暴露过的布局坑**：末行不足 3 个时 `UIStackViewDistributionFillEqually`
> 会把实际项数均分，「文件」这类本该卡在右下角/固定列的项会被拉到不对的位置——补透明 `UIView`
> 占位保持列对齐（Android `AttachPanel.kt` 本就有这层处理，这次对齐过去）。Android 同批删除。
> `./scripts/test.sh` 561/561 绿。**验证**：写了一次性 XCUITest 截图核对面板剩 5 项、布局对齐，
> 通过后已删除脚本（不是常规回归）。

> **最近通话验收修复（2026-09-29，模拟器 libeyond 已验，已提交 `537c2b4`）**：① 群名全是「未命名群聊」——根因是只读
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

---

# 归档于 2026-09-29（当前焦点历史journal清理 + 「设置▸最近通话」落地前的全部旧状态 —— 从活快照转入，被最近通话页顶下）

> 本节是 2026-09-29 之前 `current_task.md`「当前焦点」积累的全部历史状态块，一次性转入归档
> （此前多轮会话一直在「当前焦点」下追加 `> **...**` 段落，违反了 `CLAUDE.md`/全局 memory 规则的
> 「活快照就地覆盖、不追加」——本次顺手纠正，往下不再重犯）。内容原样保留，仅搬家，未删减。

> **im-rtc 换票：从调试密钥迁移到 IMServer 真实换票接口 ✅（2026-09-28，本端已完成，Android 待迁移；
> Web 端同日已完成，见 `../im-web/current_task.md`）**：`IMRtcCall.m` 的 `signToken`（同步、本地用
> `IMDebugToken` 签票）改成 `signTokenWithCompletion:`（异步，调 IMServer 新接口 `POST /api/v1/rtc/token`）：
> - `token` 参数取 `IMHTTPService.sharedService.currentToken`（当前 IM 会话，与项目里其它业务接口取 token
>   同一入口）；未登录 IM 或换票失败只记日志、回调 nil——调用方按"通话入口不可用"静默降级，不打扰主流程。
> - 新增 `IMHTTPService+RTC.h/.m`（分类文件，仿 `+Auth.m`/`+ConvQueries.m` 已有拆分模式）：
>   `rtcTokenWithToken:completion:`，复用既有 `authedRequestForPath:method:token:body:`/`runDataRequest:`。
> - `startWithUserID:` 与 `TokenWillExpire` 分支都改成异步流程后，各自加了 `generation` 判定
>   （换票是网络请求，回来时可能已经 `stop` 过——切账号/登出，同 `handleEvent:generation:` 已有的
>   防护思路，防止对一个已销毁的 `_engine` 发消息）。
> - `IMRtcConfig` 精简为只剩 `wsURL`（去掉 `appID`/`keyID`/`debugSecret`），`.example.plist`/`.local.plist`
>   同步精简；`IMDebugToken` 调用点整段删除（死代码 `_config` ivar 一并清掉）。
> - 新增测试 `IMRtcConfigTests.m`（9 例，纯逻辑，之前这块完全没测试覆盖，顺手补上）、
>   `IMHTTPRtcTokenParseTests.m`（2 例，`NSURLProtocol` 拦截，仿 `IMHTTPFriendsParseTests.m` 的
>   app-hosted 套路，覆盖成功换票 + `600001` 业务码透传两条路径），均变异验红过。
> - 新增文案键 `rtc.error.token_fetch_failed`（`../IMServer/docs/i18n/strings.json`，已重新生成
>   `Resources/Localization/*.lproj/Localizable.strings`）。
> - `./scripts/test.sh` 全量 **541/541 绿**（较之前 530 例多出的 11 例正是新增的两个测试文件）。
> - 三端对称登记 `../IMServer/docs/SYMMETRY.md`：Android `rtc/RtcConfig.kt` 仍在用调试密钥，尚未迁移——
>   迁移前对照本端 `signTokenWithCompletion:` 与 im-web `signToken` 的实现。
> - **未做**：真机/模拟器实测一次完整登录 → 通话流程（本次只验证了单测 + 编译；Web 端已经浏览器
>   端到端实测过同一个后端接口，链路本身已验证可行，iOS 侧走查代码逻辑与 Web 端同构）。
>   需要真机验证清单见下方「真机验证清单」小节。
>
> **真机验证清单**（本次改动需要肉眼确认的点，未做）：
> ① 单聊详情页点「呼叫」，能正常拨通（观察 `IMLog` 里 `rtc_start`/`rtc_login_failed`，
>    确认走的是 `rtcTokenWithToken:` 而非本地签名——搜日志不该再出现 `IMDebugToken` 相关字样）；
> ② IMServer 未配置 `-rtc-server-url` 等三项时，点「呼叫」应静默不可用（`unavailableReason` 文案），
>    不应崩溃或弹出网络错误；③ 退出登录再重新登录，确认没有残留两条 RTC 连接（服务端会踢掉旧的）。

> **贴底收消息时「↓N」箭头闪一下的真实 bug 修复（2026-09-28，用户真机报——Android 发语音过来，
> 已贴底的 iOS 聊天页会闪一下↓N 箭头+未读角标才落定；Web 端无此问题）**：`appendReloadAndScroll`
> （自己发消息）早就为这个坑打了 0.5s 抑制窗口（`selfSendScrollGuardUntil`，防 `reloadData` 让
> `contentSize` 骤增到滚动收敛之间那段 `isNearBottom` 短暂 false 时 `updateJumpButton` 弹出箭头），
> 但 `IMChatViewController+Socket.m` 的 `didReceiveMessage:`（对端消息、贴底时用 `scrollToBottomAnimated:`
> 而非精确贴底、动画耗时更长更易被看见）漏了同一个抑制——两条路径同一个坑，只有一条打了补丁。
> 属性改名 `selfSendScrollGuardUntil`→`scrollToBottomGuardUntil`（语义已不止"自己发消息"），
> `didReceiveMessage:` 里 `wasNearBottom` 分支贴底滚动前也设一次同样的 0.5s 窗口。
> `./scripts/test.sh` 全量 **530/530 绿**。**未做**：真机/模拟器上实测"Android 发语音、iOS 贴底态接收"
> 这条跨端路径肉眼确认箭头不再闪——本轮只连上了模拟器（idb 未配好，没法自动化点击登录+进对应会话），
> 走查代码 + 编译 + 现有单测全绿，逻辑与自己发消息那条已验证过的修法完全同构，但没有肉眼二次确认。

> **im-rtc 2.1.0 通话 Kit 多语言接线到「设置 ▸ 语言」（三端，2026-09-27，已提交待真机验）**：
> SDK 2.1.0 的 `IMCallKitConfig.locale` 默认恒中文、不跟任何东西，此前升级后一直是"能用但没打开"。
> `Modules/RTC/IMRtcCall.m` 加了 `IMLocaleFromLanguage()`（把 `IMLocalization.shared.language` 已解析结果
> 映射到 SDK 的 `IMLocale`，**不用** SDK 自带的 `IMLocale.system()`，避免两套"跟系统"判据打架），
> `startWithUserID:` 建 `kitConfig` 时设置 `.locale`；新增监听 `IMLanguageDidChangeNotification`，
> 通话中途切语言直接改 `_kit.config.locale`（SDK 确认 `config` 是 `start()` 传入的同一实例，不用重建 Kit），
> `stop` 里对称移除观察者。`IMLocalization` 本身不用动，它已是权威实现。`BUILD_ONLY=1 ./scripts/test.sh` 编译过；
> **未做**：真机切一次语言后实际发起/接听通话看 Kit 文案是否跟着变。三端对称改动见 `../IMServer/docs/SYMMETRY.md`
> 新增的 `IMRtcCall.m`/`RtcCall.kt`/`RtcHost.tsx` 那三行；Android 同批顺手补了「设置 ▸ 语言」入口本身
> （此前只是占位符），细节见 im-android 的 `current_task.md`。

> **通话记录：被叫侧 `cancel` 文案「未接来电」→「对方已取消」（三端 + 设计文档，2026-09-27，与用户讨论后拍板）**：
> `cancel`（主叫主动撤回）跟真正错过（`no_answer`/`busy`/`offline`）不是一回事，只改这一种 reason 的措辞，其余三种
> 与推送文案不变；`tone`（红/计未读/推送）完全不变，纯文案改动。本端改动：`Common/IMCallRecord.m` 的
> `table` 里 `cancel` 行被叫键从 `call.record.missed` 改成新键 `call.record.cancelled_by_peer`
> （`../IMServer/docs/i18n/strings.json` 新增，已 `node scripts/i18n/gen-i18n.mjs` 重新生成
> `Resources/Localization/*.lproj/Localizable.strings`）；`missed` 判定
> （`*missed = !viewerIsSender && ![k isEqualToString:@"reject"]`）本就结构化、不依赖文案字符串，未受影响
> （这点 Android 那边不同，见其 `current_task.md` 记的一个真实隐患）。三端共用向量
> `../IMServer/docs/conformance/call_record.json` 改的那条用例，`IMCallRecordTests.m` 按相对路径直接读
> 该文件（不像 Android/Web 需要拷贝副本），无需额外同步。`./scripts/test.sh` 全量 **530/530 绿**。
> **未做**：真机上实际走一遍"A 呼叫 B、A 取消"看气泡文案。

> **多语言 P1+P2+P3 ✅ 已完成（2026-09-22，中文 + 英文；已 commit 37f1d2f 推送、未真机）**：P1 基础设施（`Common/IMLocalization` + `Modules/Me/IMLanguageViewController` 设置 ▸ 语言）+ **P2 全部业务模块迁完**：Contacts/Conversation/Group/Login/Me（15 文件）/QR/Network/Detail（16 文件）/Chat（含 `Cells/`，46 文件）+ `IMPresence.subtitleText`。**P3 客户端消费**（未提交，另一次会话完成）：新增 `Common/IMSysEventFormatter.{h,m}`（`IMSegmentsForSysEvent`/`IMTextForNoticeSysEvent`，消费服务端 `sys_event`/`sys_args` 渲染群系统消息与系统通知，占位符分词 + 哨兵定位切分，兼容 iOS `%N$@` 位置格式与任意语言词序）+ `IMMediaUtil.m` 的 `IMRenderReplySnapshot`（消费 `reply_snapshot_kind`/`_args`）；接入点 `IMBubbleCell.m`/`IMLinkCardCell.m`/`IMChatViewController+DataSource.m`；`IMMessageModel`/`IMConversation`/`IMDatabase` 三处补齐新字段解析/落库/会话列表预览。**顺手修了两个真实 bug**：`IMLocalizeReplySnippet` 硬编码中文（不跟随 App 语言）、`IMMediaGlyphForSnippet` 图标判定比较的是本地化后文本（英文模式下会失效）。`./scripts/test.sh` 全量 **527/527 绿**。文案表现有 **1386 键**（跨三端共用，见 `../IMServer/docs/i18n/strings.json`）。
> ⚠️ 已知缺口（详见 `../IMServer/docs/design/I18N_DESIGN.md` §6.1）：`IMChatRecordSnippet`/`IMCallRecordNeutralPreview`/`IMContactCardPreview` 仍硬编码中文（服务面更广，未纳入本批）；系统通知单聊的会话列表预览未接结构化渲染（聊天页内气泡已修）。
> **P2 范围内刻意 DEFERRED（不是漏改）**：消息内容预览占位符（`[图片]`/`[视频]`/`[聊天记录]`等，`IMChatMessageLogic.m`/`IMBubbleCell.m` 等，会烧进 `content` JSON 发给对端）、@全员 mention token（`+Mention.m`，与解析逻辑强绑定）、合并转发/群聊兜底标题——均待 P3 服务端结构化后处理。
> ⚠️ Detail 批次发现「月日+时分」这类 `NSDateFormatter` 硬编码中文格式（如 `@"M月d日 HH:mm"`）**尚未纳入 `time.*` 体系**（现有 `time.*` 只有 today/yesterday/month_day/full_date），全仓至少 6 处（`IMGroupTextViewController.m`/`IMChatViewController+Search.m`/`IMChatRecordViewController.m`/`IMTheme.m`/`IMMediaUtil.m`/`IMDeviceModels.m`）都是这个模式，DEFERRED，需要专门扩展 `time.*` 键位后统一处理，不要零散改一两处。
> ⚠️ 单测由 `IMProgramTests/IMTestBootstrap.m` 固定简体中文（模拟器系统语言常是 en）；**它会把偏好写进模拟器里 App 的 defaults**，手测发现界面是中文别奇怪。`IMMainTabBarController` 里找「消息」tab 标题 label 是**按文字匹配**的（`IMFindTabTitleLabel`），已改成取本地化后的词——再动底栏标题要一起改。
> ⚠️ P2 迁移子代理**曾因周额度限流失败两次**（batch I3/W3，2026-09-21）——失败前的代码改动与文案片段合并均已正常完成，只是收尾报告被打断；每次继续迁移前先核实 git diff 与片段合并状态，别假设失败=没做完，也别假设失败=都做完，务必重新跑一遍 `test.sh`/`check-i18n.mjs` 确认。
>
> 更早的 im-rtc 首次接入（调试密钥联调阶段）记录已移入 [current_task.archive.md](current_task.archive.md)
> 「归档于 2026-09-28」；SPM 依赖来源、入口位置（单聊/群资料页）、Info.plist 配置等静态信息仍在那里、仍然准确。

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

---

# 归档于 2026-09-28（im-rtc 音视频首次接入·调试密钥联调阶段的状态 —— 从活快照转入，被换票接口迁移顶下）

> **接入 im-rtc 音视频（2026-09-19，代码已写、模拟器编译通过，未上真机、未提交）**：本地 SPM 依赖 `../im-rtc/im-rtc-ios`
> （`IMCallEngine` / `IMCallKit` / `IMCallEngineWebRTC`），调试密钥本机签票，SDKAppID 10000002 / kid `dbg-1`。
> 代码在 `Modules/RTC/`：`IMRtcCall`（起停、票、引擎事件）、`IMRtcProfileResolver`（读 IM 已有数据：备注 > 群昵称 > 昵称，
> 头像走 `IMImageLoader`；不为通话另建缓存）、`IMRtcConfig`。配置在 `IMRtcConfig.local.plist`（gitignored，模板见 `.example.plist`，
> `wsUrl` 填本机局域网 IP）。入口：单聊资料页「呼叫 / 视频」、群资料页新增「群通话」（先选人，最多 8 人）；主界面出现时起服务，登出 / 被踢时停。
> `Info.plist` 补了通话用途文案与 `UIBackgroundModes=audio`。**待真机验**：单聊 / 群通话、名字头像、退出登录后重登不出现两条连接。
> 限制：超级群只能选已翻出来的成员；来电的群成员表只有打开过该群资料页才有，否则退回全局名片。
>
> 此状态已被 2026-09-28 的换票接口迁移取代（本端不再用调试密钥本机签票，改调 IMServer
> `POST /api/v1/rtc/token`），见活快照当前焦点。SPM 依赖来源、入口位置、Info.plist 配置这些仍然准确。

---

## 归档于 2026-09-27b（im-rtc 音视频 SDK 2.0.0→2.1.0 三端版本升级 —— 从活快照转入，被通话记录 cancel 文案细化顶下）

> 从活快照转入（活快照只留当前焦点，见 current_task.md）。

> **im-rtc 音视频 SDK 2.0.0 → 2.1.0（三端同步，2026-09-27）**：`IMProgram.xcodeproj/project.pbxproj`
> 里 `XCRemoteSwiftPackageReference "im-rtc-ios"` 的 `exactVersion` 改为 `2.1.0`；
> `Package.resolved`（`IMProgram.xcworkspace/xcshareddata/swiftpm/`）同步改 `version`/`revision`
> （`revision` 取自 `git ls-remote --tags` 对 2.1.0 tag 的解引用提交），并跑
> `xcodebuild -resolvePackageDependencies` 确认 Xcode 真能 checkout 到 2.1.0（非纸面编辑）。同批联动改了
> Android（`im-android`，`libs.versions.toml` 的 `imrtc`）与 Web（`im-web`，`im-rtc-call-engine`/
> `im-rtc-call-uikit-react` npm 依赖）。`./scripts/test.sh` 全量 **530/530 绿**。
> 未做真机验证通话功能本身（SDK 内部行为改动未知，只验证了版本号解析与编译）。

## 归档于 2026-09-27（日历请求跨度 730 天超限 + 搜索命中崩溃 —— 从活快照转入，被 im-rtc 2.1.0 版本升级顶下）

> 从活快照转入（活快照只留当前焦点，见 current_task.md）。

> **修：日历请求跨度 730 天超服务端上限 + 搜索命中崩溃 ✅ 2026-09-25（已提交 `63a074f`/`2bc2f6e`，
> IMServer 侧 `bf97410`）**：Android 端做圆点标记功能时比对发现"Android 圆点比 iOS 多"，查出根因在
> iOS 这侧——`IMChatViewController+Search.m` 的 `searchCalTapped` 写死请求近两年（730 天），但服务端
> `conversation.MaxCalendarSpan` 只放行约 400 天，请求恒被拒（`errcode.ParamInvalid "time range too
> wide"`），`error||days.count==0` 分支把这次必然失败静默吞掉、退化成"仅本地打点"——iOS 的圆点从未真正
> 包含过服务端补的历史。改成 `kIMChatCalendarQuerySpanMs = 390 天`，与 Android
> `ChatCalendar.QUERY_SPAN_MS` 同一个数值、同一份理由（留 10 天余量）。
>
> 之前这台机器 `xcodebuild` 一度卡在 Resolve Package Graph（本机授权问题，非代码问题），解决后新增
> `IMProgramUITests/IMChatCalendarUITests`（驱动 iPhone 17 Pro Max 模拟器进搜索态→点日历→核对圆点→
> 点「最早」「今天」）真机跑通，**顺手撞见一个真实崩溃**：搜索有命中时 `updateSearchNavState` 拼计数文案
> 用 `IMLocalizedFormat(@"chat.search.hit_position", (long)idx, (long)n, ...)`，但两份
> `Localizable.strings` 把这个键写成 `%1$@/%2$@%3$@`（期望对象），`NSString initWithFormat:` 按格式串
> 类型读栈上的 vararg，把小整数当指针解引用直接 `EXC_BAD_ACCESS`——任何账号只要搜到东西就必崩，是个
> 相当严重的既有回归（多语言 P2 迁移遗留，见下一条）。改成 `%1$ld/%2$ld%3$@`，同步修
> `IMServer/docs/i18n/strings.json` 里这个键的 `args` 声明（`string`→`int`，`node scripts/i18n/
> gen-i18n.mjs --check` 确认三端生成物与文案表一致、无漂移）。日历钮补了 `chat.search.calendar`
> accessibilityIdentifier（同 prev/next/count 已有模式），否则 UI 测试定位不到。
>
> `./scripts/test.sh` 全量 **530/530 绿**；`IMChatCalendarUITests` 在模拟器上验证：圆点位置正确、
> 「最早」落到会话真正开头、「今天」正确退化到最新消息，全程不再崩溃（截图核对过）。

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

---

## 2026-09-03 从 current_task.md 退役（内容原样搬运，未改写）

> **收藏页 / 详情页 / 置顶 / 记录卡 五项 UI 修复（2026-08-30，两端同步；iOS `build` 绿、**已跑 `IMProgramTests` 311 例全绿**；
> Web `tsc -b` + `vitest 681` 绿。**两端已手测通过（2026-08-30，用户逐项验收）**）**
>
> 1. **置顶预览**：`IMPinnedMessage.previewText` 只认 `audio` 不认 `voice`、且没有 `chat_record` 分支
>    → 语音置顶铺一串 URL、合并转发卡片铺整段 `{"t":…,"items":[…]}` JSON。现统一收成 `[语音]` /
>    `[聊天记录] 标题`（走既有 `IMChatRecordSnippet`，与引用快照同 token 口径）。Web `pinned.ts` 同修。
> 2. **收藏页「来自X」不再露 10 位内部 ID**：根因是 `IMDatabase.cachedGroups` 恒 `members = @[]`
>    （成员只在进群详情页时联网拉），好友表又只覆盖好友 → 群里非好友发的收藏全回退 uid。
>    新增 `resolveMissingSourceNames`：按需**两级补拉**（先 `GET /groups/{id}` 拿群昵称，仍缺再
>    `GET /users/{id}` 拿名片），每个 id 只发一次、失败静默。Web 同款 effect。
> 3. **收藏页副行时间与「来自X」拆两行 + 颜色分开**（时间 tertiary / 来源 accent，对齐链接分类）：
>    长备注名/群昵称原先会把时间整个挤没。改 `IMFavoriteRowCell` / `IMFavoriteVoiceCell` /
>    `IMDetailFileCell` / `IMDetailContactCell`（名片的「由 X 分享」从副行拆成第三行，行高 64→82，
>    新增 `IMDetailContactCellHeightWithSource`）。
> 4. **详情页链接 tab 时间改「年月日 时:分」**（原「今日 HH:mm / 昨天 / M月d日」，同页四个 tab 两套语言、
>    跨年看不出年份）；Web 同修，并给 Web 文件 tab 补上原本没有的时间行。
> 5. **页签条横向可滚**：`IMLiquidSegmentedControl` 底轨 `clipsToBounds=YES` 且无滚动容器 → 段总宽超出时
>    末尾页签（详情页 6 签的「名片」/ 收藏页 7 签的「名片」）被裁掉且划不到。内嵌 `UIScrollView`，
>    塞得下时 `scrollEnabled=NO`（手势不参与竞争，行为同改前）。Web `.detail-tabs` 加 `overflow-x:auto`。
> 6. **合并转发记录详情页**：名片条目原先落通用文本分支铺 JSON 原文 → 改渲染 mini 名片卡（头像+显示名+
>    @句柄+「个人名片 ›」脚注）；语音条目原先铺裸 URL → 改用与详情页/收藏页同一个
>    `IMVoiceMiniPlayerView`。打包端补 `d`（时长）/`w`（波形）两个 key（两端同约定），老记录无这两项时
>    退化成等高条纹 + 0:00 仍可播。Web 语音同修（名片 Web 本就是卡片）。
>
> 体量门禁副产物：`IMFavoritesViewController.m` 撞 1500 行 → 抽出 `IMFavoriteRowViews.{h,m}`
> （阅读器 / 统一图标行 / 来源会话行，逐字平移、行为零变化），现 1364 行。

> **记录卡补齐 + 语音四项（2026-08-30 第三批；`IMProgramTests` 312 例全绿；**已手测通过**）**
> 1. **合并转发条目新增 `ts`/`u`/`a`**（原消息时间 / 发送者 uid / 头像相对路径，两端同 key，
>    契约表进了 [PROTOCOL.md](../IMServer/docs/PROTOCOL.md)）。记录详情页据此：右上角显**每条**消息的时间、
>    左侧显头像、**连续同一人只显一次头像与昵称**（判据抽成纯函数 `IMRecordSenderKey`，与 Web
>    `recordSenderKey` 同口径、各带单测）。**老记录一定缺这三个字段**——不显时间 / 首字母色块兜底，
>    绝不能因为缺字段就不渲染。`u` 只当查头像与判连续的键，**永不上屏**（显示名一律走 `n`）。
>    单聊里"我自己"那一方拿不到头像路径（本页没有自己的资料快照），只发 `u`（Web 有 `myInfo` 故能带 `a`；
>    `a` 可选，两端不算分叉）。
> 2. **语音「已读」= 点了就算**：新增 `im_markVoiceConsumed:` 收口——播放与**转文字**都消未播红点
>    并刷那一行（原先只有播放会消，且要等 cell 复用才刷）。判据是"点了"不是"听完"。
>    **注意**：发送方看到的 ✓✓ 仍是"进会话即读"，语音不例外——`read_seq` 是水位线，做不到单条
>    语音"听了才算"，详见 [VOICE_MESSAGE_DESIGN §7](../IMServer/docs/design/VOICE_MESSAGE_DESIGN.md)。
> 3. **单聊语音气泡终于和其它气泡左对齐**：`IMVoiceBubbleCell` 把对方气泡左缘钉死在
>    `_avatar.trailing + 8`，而 `applyGroupAvatarURL:…gutter:` **整个忽略了 gutter** ——
>    单聊没有头像列，气泡照样被推到 50pt，比同屏文本/图片气泡多缩进近 40pt。改成锚 contentView
>    + `gutter ? 48 : 12`（与 IMBubbleCell/IMImageCell/IMChatRecordCell/IMContactCardCell 同口径）；
>    顺带把头像几何 10/32 纠成 12/30（基类 cornerRadius 15 本就配 30，原来还差一点不圆）。
>
> **记录卡语音：崩溃 + 无时长（2026-08-30 用户实测报，已修并**复测通过**；`IMProgramTests` 311 例全绿）**
> - **崩溃根因不在记录卡，在语音播放通道**：Chrome 录的语音是 **MP4/Opus**（`audio/mp4` 容器塞 Opus），
>   `framesPerPacket == 0` → `AVAudioPlayer` 在 AVFAudio 内部**除零**（`EXC_ARITHMETIC`/`SIGFPE`，
>   `@try` 拦不住、整个 App 当场退出）。崩溃栈由 `~/Library/Logs/DiagnosticReports` 的 .ips 定位：
>   `AVFAudio ×4 → -[IMVoicePlayer togglePlayback:localFileURL:]`。**气泡/收藏/详情页语音 tab 同样会崩**，
>   只是这次先在记录卡撞上。修法：新增 `IMVoiceFileIsPlayable(url, &durationMs)`（AudioToolbox 读
>   `kAudioFilePropertyDataFormat`，`sampleRate<=0 / framesPerPacket==0 / channels==0` 一律拒），
>   `togglePlayback:` 与 `toggleEnsuringLocal:` 双重把关；被拒回 `NSError`「该语音格式无法播放」，
>   四个播放入口改吐 `err.localizedDescription`（原先写死「语音下载失败」，会把排查引偏）。
>   护栏 `IMVoiceFileGuardTests.m`（合成 WAV 放行并报时长 / 非音频字节被拒 / 缺文件与非 file URL 被拒）。
>   源头在 Web 侧一并修（见 im-web current_task）。
> - **无时长**：老记录打包时没有 `d` 字段。新增 `fillDurationFromLocalFileIfNeeded:`——**只探已缓存的
>   文件、绝不为显个时长去发下载**；播放触发的下载完成后再探一次并刷该行。
>   **已知限制**：坏文件（MP4/Opus）报的时长是天文数字，被 `IMVoiceFileIsPlayable` 一并挡掉 → 仍显 0:00，
>   这是对的；那条消息本身在 iOS 上就播不了。

> **/code-review 三条修复（2026-08-30，纯客户端；`build` 绿、`-only-testing:IMProgramTests` 314 例
> 仅剩那条已知偶发的 `testFrostedLandscapeScalesLongestSideTo48`，单独重跑绿。**未手测**）**
> 1. **语音上传失败的红❗点不动**（重传路径整条失效）：`im_uploadAndSendVoice` 失败时**无条件**写
>    `note`（"语音上传失败"），而 `IMResendPolicyForMessage` 把"有 note"一律当成"被服务端拒收 → 不可重发"，
>    于是 `IMFailBadgeView.tappable=NO`、红❗照显却吃不到点击。判据顺序改成
>    **「本地还留着字节（`im-pending://` / `file://`）」优先于 note** —— content 是本地引用就说明服务端
>    从没见过这条，"拒收"的解释不成立。`content` 空 + note（语音"发送中断，请重新录制"）仍判不可重发。
>    补两条护栏用例。
> 2. **会话列表预览显示早已被顶掉的旧系统消息**：`updateConversationForMessage`（实时路径）覆写了
>    `last_content` 却漏写 `last_sys_segments`，而 `IMConversation.lastPreviewTextForSelfUID:` 只要分段非空
>    就整句用它渲染、`last_content` 根本不参与 → HTTP 快照存过一次系统消息分段后，之后来的普通消息
>    在冷启动/离线首屏一律显示那条旧系统消息。INSERT/UPDATE 两处一并补上（与 2026-08-19 修过的
>    `last_caption` 同一类漏写）。
> 3. **合并转发条目里"我自己"的名字是 10 位内部 ID**：`displayNameForMessage:` 自己那一支返回
>    `self.userID`。记录详情页现在把 `n` 当头行昵称显示（2026-08-30 加 ts/u/a），于是我发的每条都顶着
>    一串随机数字。改为「我」，与 Web `useForward.ts#nameOf` 同口径。


---

# 归档于 2026-09-05（安全整改 1/3/5 步 · 搜索 pill 与合并转发标题口径 · 回归入口 test.sh）

> 从活快照转入（活快照只留当前焦点，见 current_task.md）。

> **安全整改第 1 步：服务器地址协议收口 + 媒体外站 URL 白名单（2026-09-03；`./scripts/test.sh` 全绿 395/395；**未手测**）**
>
> 背景：`/security-review` 全仓审计报了 3 条（明文 HTTP / WS 明文且 token 在 URL / 发送方可控 URL 被零点击拉取）。
> 与后端商定的整改分 5 步（顺序见 `../IMServer/current_task.md`），**本次是第 1 步，且不引入 HTTPS**——
> 真域名与云服务器到位后再切，切换时客户端不需要改代码。
>
> 1. **新增 `IMServerEndpoint`（`Common/`）= 全 App 唯一的 scheme 权威**。此前 `http://`/`ws://` 以字面量散在
>    5 处（`IMHTTPService.urlForPath:` / `IMSocketManager` 建连 / `IMMediaUtil` / `IMChatRecordViewController`
>    的一份拷贝 / `IMRemoteLogSink`），"换 https"等于跨 5 文件改代码 + 发版。现在四路共用一处，
>    **登录页填 `https://im.example.com` 即整端切换**（http↔ws、https↔wss 成对，不会出现"网页加密了长连接还明文"）。
>    scheme 随 host 存进 `IMSessionStore`（`im_session_scheme`），冷启动在任何网络调用前恢复；
>    「上次地址」回填也带协议，否则填过的 https 下次静默退回 http。
>    **协议永不从服务端下发**（要先选协议才连得上；明文信道问"要不要 https"就是降级攻击）——理由写在头文件里。
> 2. **`IMMediaFullURL` 改为拒收外站绝对 URL**（漏洞 3 闭环）。`content`/`avatar_url` 是发送方可控且服务端原样
>    存转的字段，图片又默认自动下载 → 对方发一条消息、或只把头像设成 `http://attacker/beacon.png` 再出现在
>    你的搜索结果里，客户端就零点击发 GET，泄露 IP、粗粒度位置与精确的「已查看」时刻。现在只放行本服务器
>    （`IMServerEndpoint.isOwnHost:forAbsoluteURL:`，主机名不分大小写、**端口从严**、拒 userinfo），
>    自家的存量 `http://` 绝对地址按当前 scheme 重拼。外站图**唯一**合法场景是链接预览 OG 图，
>    显式走新函数 `IMLinkPreviewImageURL`（仅 `IMLinkCardCell` / `IMLinkPreviewView` 两处）。
> 3. 顺带：`IMChatRecordViewController.fullURLFor:` 那份逐字拷贝删掉，改调统一入口；
>    旧判据 `hasPrefix:@"http"` 收紧成 `http://`/`https://`（原来 `httpfoo:` 也算数）。
>
> 新增 `IMProgramTests/IMServerEndpointTests.m`（16 条：输入解析 / ws-wss 成对 / 自家主机判定 / 外站拦截）。
> **本步没做**：ATS 仍是全局 `NSAllowsArbitraryLoads`（第 4 步随 TLS 一起收窄）；WS token 仍在 query 串（第 3 步）；
> 明文密码仍存 `NSUserDefaults`（第 5 步）。
>
> **第 3 步同批（2026-09-03）：WS token 移出 query 串** —— `openSocketWithToken:` 改用
> `webSocketTaskWithRequest:` 并带 `Authorization: Bearer <jwt>` 头（`webSocketTaskWithURL:` 只收 URL，
> 结构上带不了自定义头）。URI 里的凭据会被沿途反向代理 / 网关 / CDN 写进访问日志。
> 后端 `gateway/client.go` 的 `handshakeToken` 两条并存（`?token=` 留给浏览器——浏览器 WebSocket API
> 设不了请求头），**故本端改动不需要后端同版本才可用**，但仍需重启后端才生效。
>
> **`/code-review` 复查后的两条修复（2026-09-03，紧接第 5 步）**：
> ① **跨线程属性改 `atomic`** —— `IMServerEndpoint.scheme` 与 `IMHTTPService` 的
> `host`/`username`/`password`/`refreshToken`。这些值在 **IMSocketManager 的私有串行队列**上被读
> （建 ws URL、socket 换 token），`IMMediaFullURL` 还会在媒体下载/图片加载回调里读 scheme，
> 而写它们的是主线程（登录页、SceneDelegate、登录响应落盘）。`nonatomic` 的并发读写没有任何同步，
> 读方可能拿到正在被替换、已 release 的 `NSString` → 随机 EXC_BAD_ACCESS。
> 本仓对这类属性的既有口径本来就是 atomic（`currentToken`/`tokenUserID`/`lastLoginUserID`）。
> **`scheme` 两个存取器都手写加锁**（`@synchronized` + `@synthesize`）——它有自定义校验 setter，
> 只写 `atomic` 关键字会让编译器仅合成 getter，写路径反而绕过原子性，比 nonatomic 更骗人。
> `host`/`username` 属于**既有问题**（非本轮引入），顺手收口，免得四个跨线程字符串两个 atomic 两个不是。
> ② **退出登录调 `POST /api/v1/logout`** —— 只清本地不够：那枚绑定会话的 refresh_token 在 180 天内
> 还能换新 token，且这台设备会一直留在别处看到的「已登录设备」里。**best-effort、不等回调**：
> 请求在同步构造时已把 token 写进请求头，所以立刻清本地不影响它；网络不好也绝不把用户困在
> "退不出去"的状态里，失败只记日志。被踢下线那条路径（`handleSessionRevoked`）不调——会话已被吊销。

> **第 5 步同批（2026-09-03）：不再存账号明文密码，改存可吊销的续期凭据** ——
> 原先 `IMSessionStore` 存的是**账号明文密码**，`SceneDelegate` 每次冷启动把它恢复进
> `IMHTTPService` 重放去换 token。真正的问题不是"明文"，是**密码不可吊销**：App 里那套
> 「设备管理 / 注销这台设备」对"保持登录"这条路径**完全失效**（注销掉的只是会话，拿密码立刻重登），
> 自己做的安全功能形同虚设。
> 现在存后端签发的 `refresh_token`（绑定本设备会话 sid），`loginWithUserID:` 优先走
> `POST /api/v1/token/refresh`；`loginWithUsername:`（登录页）强制走密码登录——
> 否则本地若还留着上一个账号的有效凭据，**密码填错也会"登录成功"**。
> 凭据由 `IMHTTPService` 在收到登录响应时自行落盘（触发登录的入口不止登录页，交给调用方各自保存必然漏）；
> 拿到它就把明文密码从内存与磁盘一起清掉。续期被服务端明确拒绝（`IMIsAuthErrorCode`）时擦掉凭据并复用
> `IMSocketDidRevokeSessionNotification` 把用户送回登录页——不擦的话每次进页面都拿同一枚废凭据重试，
> 界面永远停在"未连接"且**没有出路**（密码已不落盘，退不回密码登录）。
> **一次性迁移**：老安装升上来没有 refresh，退回用 `IMSessionStore.legacyPassword` 做最后一次密码登录，
> 成功后立即 `clearLegacyPassword`（垫片可删除的条件写在头文件里）。
> **登出/换账号三处都清内存里的凭据**：`invalidateToken` 刻意不动它（那只管 10min access token 缓存），
> 所以退出登录、被踢下线、以及登录页每次提交各自显式清一次。
> 顺带修 I7：`IMSessionStore.h` 那句"password 从 Keychain 删除"是假的（实现只清 `NSUserDefaults`）。
> **体量门禁副产物**：`IMHTTPService.m` 撞 1503 > 1500 → 抽出 `IMHTTPService+Auth.m`（登录/token 生命周期，
> 与上传/好友/会话无共享状态），类扩展下沉到 `IMHTTPService+Private.h`；**公开入口留在主实现**——
> 声明在公开头上的方法放 category 会同时触发 `-Wincomplete-implementation` 与
> "category is implementing a method which will also be implemented by its primary class"。现 1364 行。
>
> **待真机手测**：登录页填裸 `host:port` 应与改前完全一致；长连接能连上（会话列表出现"已连接"）；填 `https://…` 应连不上（后端尚未开 TLS，属预期）；
> 聊天图片/头像/群头像/收藏/记录卡照常显示；链接卡片的外站预览图仍能出图。

> **三项：搜索 pill 直接开会话 + 合并转发标题口径 + 条目 `u` 匿名化（2026-08-31，与 Web 同步；
> `./scripts/test.sh` 全绿，`IMProgramTests` 320/320；**未手测**）**
>
> 1. **「请返回聊天页后再搜索」改成直接开会话** —— `IMChatDetailViewController+Actions.m` 的搜索 pill
>    原先要求导航栈里已有本会话的聊天页，取不到就吐司。而最常见的触发正是**从群成员头像点进来的
>    单聊资料页**——那个单聊压根没打开过，必吐司。那句话是把实现约束（栈里没有这一页）甩给用户，
>    旁边的「消息」pill 明明就能开会话。现新增 `openChatForInChatSearch`（群/单聊分派，与「消息」pill
>    同一个统一入口），取不到就开会话，转场落定后 `beginInChatSearch`。
> 2. **合并转发卡片标题收敛到微信口径** —— 原先写 `IMConversationPublicName`，群聊时**就是真实群名**，
>    发给了往往不在群里的收件人；Web 那侧则按条目发送者数量推，两端分叉。现共用纯函数
>    `IMChatRecordTitle`（`IMChatMessageLogic`）：群聊固定「群聊的聊天记录」（**不写群名**）、
>    单聊「{对方公开名}和{我的公开名}的聊天记录」，缺名逐级降级到「聊天记录」、绝不回落内部 ID。
>    **顺带补了一个此前没有的东西**：App 里没有"我叫什么"的进程内缓存（只有设置页/资料编辑页各拉一次
>    自用），而打包 JSON 是同步的等不了网络。故 `IMHTTPService` 加 `currentNickname`——登录成功后异步
>    预热一次（已有值就不重拉，避免 10min token TTL 重登时反复请求）、`invalidateToken` 一并清（换账号
>    不能顶着旧名字）。取的是 `card.nickname` **不是 `displayName`**（后者是"备注优先"，备注不能外流）。
>    **允许为空**：空则标题降级成「对方的聊天记录」。
> 3. **条目 `u` 改成卡片内匿名序号 `s1/s2`**（`IMRecordSenderKeysForUIDs`，`IMMediaUtil`）——
>    原本发的是发送者真 10 位内部 ID，随卡片到了可能不在群里的收件人手上，而 `GET /users/{id}`
>    只校验「持有合法 token」、不校验关系，随机 10 位 ID 的不可枚举是那个接口唯一的防线。
>    **读端零改动**（`IMRecordSenderKey` 本就只做相等比较，存量卡片里的真 uid 自然兼容）；
>    只把 `IMChatRecordViewController` 的头像色种从 `uid` 换成名字（匿名序号当色种没意义）。
>    契约见 `../IMServer/docs/PROTOCOL.md`「合并转发卡片（chat_record）的条目结构」。
>
> **未手测**；后端同批加了显示名字符清洗（`internal/textguard`），iOS 侧无需配合改动。


> **iOS 回归有唯一入口了：`./scripts/test.sh`（2026-08-31）** —— 与后端 `IMServer/scripts/test.sh` 对称。
> 起因：之前每次手拼 xcodebuild 命令行，反复踩三个坑（跑整 scheme 被 UITests 拖死 135s+37s、
> 并行 clone 抢 CPU 压出偶发失败、失败原因只有一句 `** TEST FAILED **`）。脚本把三条写死：
> `-only-testing:IMProgramTests` + `-parallel-testing-enabled NO` + `-resultBundlePath` 配 `xcresulttool`
> 直接打「哪条用例 + 断言原文」；另固定 `-derivedDataPath build/DerivedData`，模拟器自动挑最新 iOS 的 iPhone
> （写死名字换机就报 destination 找不到）。`BUILD_ONLY=1` 只编译、`ONLY=<类|类/用例>` 只跑一部分。
> **实测：全量 314 例绿，3 分 10 秒**（含冷编译）；那条 `IMMediaPlaceholder` 偶发失败在串行模式下没再出现。
> 用法与三条理由写进了 [CLAUDE.md](CLAUDE.md)「构建 / 测试」与「完成的定义」。

> **无其它进行中的开发项。** 网络恢复秒连（2026-08-30）与 `UI_COLOR.md` 收敛已完成，细节转入
> `current_task.archive.md`。仍**未做**的是「下一步」里那两件老账：真机手测语音 P1 与相机录像
> （模拟器没有摄像头/麦克风，只能真机验）。

---

# 归档：2026-09-08 收口时从 current_task.md 裁下的「当前焦点」历史块
（共 1 块，原样搬运，未做删改）

> **建群两步流 ✅ 2026-09-05**（后端零改动）。原先是「选好友 →『创建』→ 弹一个 `UIAlertController`
> 输群名」；现在第一步按钮改「下一步」，第二步是 `IMGroupCreateViewController`：
> **群头像 / 群名（必填、预填「我、A、B」）/ 成员横条（可 ✕，不可删到 0）**。
> 头像随 `POST /groups` 的 `avatar_url` 一起发——**服务端一直有这一位，端上此前恒传空串**，
> 于是每个新群都得先建出来再进群管理页设图。设计稿见
> `../IMServer/docs/design/sketches/GROUP_CREATE_UX_SKETCH.html`。
>
> **顺带收敛的重复**：会话页 ＋ 菜单与通讯录群聊页**各有一份**「alert 输群名 + POST」实现（几乎逐字重复），
> 一并删掉，两处都改调 `+[IMGroupCreateViewController startInNavigationController:host:userID:onCreated:]`；
> 群管理页那个 90pt 头像头（原为该文件的私有类）提成 `Modules/Group/IMGroupAvatarHeader`，
> 加 `initial` 占位首字 + `applyAvatarImage:placeholder:caption:`，**群管理页行为逐字不变**。
>
> **三条值得记的**：
> ① **预填群名只能用公开名**：群名会发到服务端、进系统消息、显示给全群，用备注＝把私下称呼广播出去
>（同合并转发标题那次 P0）。故 `Common/IMGroupNameDefault` 只收 nickname/username/uid **三件套**，
> 不收 `IMUserCard`——免得有人顺手传"备注优先"的 `displayName`；我自己那一位取
> `IMHTTPService.currentNickname`（登录后预热的公开昵称，允许为空则跳过）。
> **成员横条上显示的名字仍认备注**（本机渲染），两者刻意分叉。
> ② **「＋ 添加」是 pop 回选好友页**（它还在栈上、勾选原样），所以 picker 的 `onDone` 必须分两支：
> 栈里已有建群页就 `updateMembers:` + `popToViewController:`，无脑 push 会**叠出第二份**建群页。
> ③ 群名按 **rune**（码点）计 30 字，与服务端 `len([]rune)` 同口径——不能用
> `ByComposedCharacterSequences`（那按字形簇算，一家四口 emoji 算 1，会放过服务端要拒的名字）。
>
> `IM_SIM="iPhone 17 Pro Max" ./scripts/test.sh` **415/415 绿**（新增 `IMGroupNameDefaultTests` 8 例，
> 与 Web `groupName.test.ts` 用例逐条对应）。
>
> **模拟器实测（用户点名要求）抓到一个 P0**：**注入式液态标题栏不监听 `navigationItem`**——
> 它只在 push/pop/present 关闭等时机由 `IMMainNavigationController syncBarForController:` 同步一次。
> 我改了 `rightBarButtonItem.enabled` 却没通知它：进页群名为空 → 栏上按钮同步成 disabled；
> 之后输入群名，`UIBarButtonItem.enabled` 已是 YES 而**栏上那颗按钮仍灰且点不动 → 建不出群**。
> 修法：`refreshCreateEnabled` 末尾调 `im_refreshNavigationBar`。**同一坑的另一面**：右上项
> 不能用 `initWithCustomView:` 塞菊花（注入栏只认 title/image，会让按钮整个消失），在途改为置灰。
> 另修：长群名把 12pt 计数挤成「25/…」→ 计数设 required 抗压缩、输入框让位。
>
> 实测跑通：两步流全程、**头像端到端**（选图→圆形裁切→上传→随建群发出→新群会话页右上与会话列表
> 都显示该图）、「＋添加」pop 回选好友页且再「下一步」回到**同一个**建群页、删成员重算预填名、
> 删到最后一位被拦、清空群名按钮置灰且头像圈回落相机。
> **未测**：那句「至少选择一位好友」toast（存活 1.9s、截图往返 ~2s 没拍到，但拦截行为已验证）、
> 头像上传超时 5s 与建群失败两支（要造网络故障）。
>
> **用户复测后再改两条（本轮按用户要求只编译、未启模拟器）**：
> ① **「＋ 添加」改成固定列**——原先它跟成员条一起横滚，人一多要先滑到头才能继续加人。
> 现用约束钉在 cell 右缘（`_strip.trailing = _addColumn.leading - space2`），成员条只占左边那段。
> ② **预填群名不再补「…」**：放不下的名字直接不要（`IMDefaultGroupName` 与 Web `groupName.ts` 同步改，
> 两端单测一起改）。理由是它是个**可改的候选名**而不是被裁短的完整名，末尾挂省略号既占掉一个可用字，
> 又会被头像圈的「取末两字」规则显示成「2…」。

> **上一批（2026-09-05，已提交 `e25ae08`）**：语音转文字撑高后把文字补进视口
>（记 `isNearBottom` → 贴底或 `ScrollPositionNone` 最小位移，`animated:NO` 免动画滚动每帧触发翻页）。只编译未跑模拟器。

> **已落地、细节转入 `current_task.archive.md`**（2026-08-30 ~ 09-03）：安全整改第 1/3/5 步
> （`IMServerEndpoint` 收口 scheme + 媒体外站 URL 白名单 / WS token 移出 query 串改 `Authorization` 头 /
> 明文密码换成可吊销的 `refresh_token`，含 `/code-review` 复查的 atomic 与 logout 两条）、
> 搜索 pill 直接开会话 + 合并转发标题口径 + 条目匿名化、回归唯一入口 `./scripts/test.sh`、
> 网络恢复秒连、`UI_COLOR` 收敛。
>
> **安全整改剩余**：第 2 步（服务端 TLS）与第 4 步（收窄 ATS `NSAllowsArbitraryLoads`）都要等真域名 +
> 云服务器到位，客户端届时不需要改代码（顺序见 `../IMServer/current_task.md`）。
>
> **无其它进行中的开发项。** 未做的都在「下一步」：真机连通性与语音 P1/相机录像手测
>（模拟器没有摄像头/麦克风，只能真机验）。

## 2026-09-06 通讯录 Tab 延迟修复（2026-09-11 自 current_task.md「当前焦点」移入）

> **通讯录 Tab 延迟修复 ✅ 2026-09-06**。切换到通讯录时延迟 0.5-1.5s（等待 HTTP 请求），因为
> `viewWillAppear` 每次都无条件调 `reload()`（登录 + 拉友列表）。改为**事件驱动**：
> - `reconnectReloader` 监听网络重连时刷新
> - `onFriendEvent` 监听 Socket 好友事件即时更新
> - 首次进入使用本地缓存种子（已在 init 加载），无需同步请求
> 
> 预期：Tab 切换响应 <100ms（从 500-1500ms 改善），与会话/设置切换流畅度对齐。
> 已提交 `7930087`。

## 2026-09-11 读屏（VoiceOver）两处缺口（2026-09-11 自 current_task.md「当前焦点」移入）

> **顺带发现的两处读屏（VoiceOver）缺口 ✅ 2026-09-11 已修**：① 注入的液态标题栏丢了页面挂在右上 item 上的
> accessibilityLabel（聊天页头像按钮念不出「X的聊天详情」）→ `IMLiquidNavigationBar.actionAccessibilityLabel`，
> 由 `IMMainTabBarController.m` 的 `applyBarItemsForController:` 透传；② 详情页操作排 label 是动作键（念英文 "search"）
> → label 改放标题，动作键放 identifier `detail.pill.<键>`（`+Private.h` 的 `IMDetailPillIdentifier`），`pillTapped:` 改认 identifier。
> 单测 `IMAccessibilityLabelTests`（2 例，双向变异过）；上面那条 UI 测试已改成按标签/标识找这两处、不再按位置兜底，模拟器重跑通过。
> 左上角自定义纯图标钮（如 xmark）仍一律念「返回」——目前没有页面给左 item 设标签，未做透传。

## 2026-09-11~12 通讯录大名单（2026-09-12 自 current_task.md「当前焦点」移入）

> **通讯录好友列表空白 + 切 Tab 卡顿 ✅ 2026-09-11**（`e5cbac8`；真机手测通过 2026-09-12；`scripts/test.sh` 462/462，
> 新增 8 例中 7 例变异红过——`testAsyncBuildNilCards` 是边界例、未单独变异；独立复查无阻塞项）：`7930087`（09-06）为治卡顿删了
> `viewWillAppear` 里的 `reload`，但好友缓存只有通讯录页自己写、socket 早在会话页就连上（重连刷新不触发）→
> 整页空白、左滑删除/拉黑静默失效（`token` 从未赋值）、「新的朋友」徽标不亮。**上面 2026-09-06 那段的诊断（「同步 HTTP 请求」）是错的。**
> **卡顿真因不是请求**（异步 + 10 分钟 token 缓存），是 user1001/1002 各约 2000 好友、回来后**主线程**重建拼音索引
> （Mac 实测旧实现 300–440ms，其中每人拼音转了两遍）。修法：`IMContactSectionIndex buildWithCards:completion:`
> 后台串行队列算 + 拼音 `NSCache` + 去掉重复转换（首次约 290ms 在后台，之后约 12ms；真机首次 608ms，同样在后台）；
> 切入刷新恢复并加 30s 节流（判据 `IMContactsShouldRefreshOnAppear`，好友事件/重连/本页增删不走节流）；种子与备注变更也改后台建，旧代号结果丢弃。
>
> **剩余三项主线程开销 ✅ 2026-09-12**（`f57816a`；单测 466/466，独立复查两条已修；手测通过 2026-09-12）：好友快照「名单没变就不写」
> （`IMCachedFriendsFingerprint`，不含顺序——服务端同 updated_at 时顺序不稳定），变了才到后台串行队列写、**写成功才记指纹**
> （`replaceCachedFriends:` 改回报成败，写失败下次刷新重试）；`friendsWithToken:` 建卡 + 灌 `IMRemarkStore`/`IMFriendStateStore`
> 挪到后台串行队列（completion 仍在主线程、回调时两份缓存已就绪）；选好友页分组改后台建 + 代号丢弃过期结果。
> 复查两条：① 指纹原先先于写成就记，写失败后再不重试；② `IMHTTPFriendsParseTests` 原先改全局 host，改成按专用 Bearer token 拦截。
>
> **UI 自测脚本 `IMProgramUITests/IMContactsPerfUITests.m`**（2026-09-12 提交，默认跳过）：对 2000 好友账号跑到 `cells.count`
> 会因 XCUITest 无障碍快照 30s+ 超时卡住，未跑通；遗留项记在 current_task.md「已知坑」。

---

# 归档于 2026-10-01（从活快照「当前焦点」移入较早批次：均已完成/已提交，待办仍以「下一步」「已知坑」为准）

> **2026-09-30 撤回 / 删除后收回通知（iOS 侧）**：设计 `../IMServer/docs/design/PUSH_M5_DESIGN.md` §3.4。
> App 没在跑时由服务端用同一个 `apns-collapse-id` 把原通知替换成「对方撤回了一条消息」，本端无代码；
> App 活着时 `IMSocketManager applyMsgOpPayload:`（实时帧与 sync 补到的事件行都走它）调
> `Common/IMPushRetract`，按通知 userInfo 的 `conv_id`+`conv_seq` 把通知中心里那条（含替换后的撤回提示）移除。
> 纯判据 `IMPushUserInfoMatchesMessage` + `IMPushRetractTests`。`IMSocketManager.m` 现 1597 行（上限 1600）。
> 「点通知定位到具体消息」评估后不做：进会话本来停在首条未读，跳过去会把前面的未读标成已读。

> **2026-09-30 修：应用内提示音 / 振动 / 横幅全部不出（已 commit+push）**。根因：`IMSocketManager+Alerts.m` 给通知判定喂的
> `inCall` 读的是 `IMRtcCall.isStarted`（= 通话引擎已建好，登录后只要通话服务配置齐全就恒 YES），不是"正在通话"，
> 于是 `IMAlertDecide` 永远判「通话中→静默」。没配通话服务的环境里 `isStarted` 恒 NO，所以一直没暴露。
> 改为新增 `IMRtcCall.isInCall`（读 Kit `controller.objcPhase`：来电/拨出/接通中/通话中算，空闲与结束页不算，
> 对齐 im-android `RtcCall.inCall`），纯判据 `IMRtcCallPhaseCountsAsInCall` + `IMRtcCallInCallTests`。
> 顺带给判定加了一行 debug 日志 `alert_decision …`（只有布尔与会话号）。真机已验：`sound=1 vibrate=1 banner=1 in_call=0`。
> 同时报的「未读角标出现后立刻消失」不是代码问题：同一账号在**模拟器**上一直停在那个会话页里，来一条它就读一条，
> 已读同步把真机的未读清掉了（日志 dev=CBE171A0，CoreSimulator 路径）。

> **M5 离线推送 · 第一批 ✅ 代码 + 单测已完成，待真机验（2026-09-30，未开分支——直接在 IMProgram 工作树，
> 设计 `../IMServer/docs/design/PUSH_M5_DESIGN.md`（§8 全部按推荐），协议 `../IMServer/docs/PROTOCOL.md`
> §6.12 app_state / §6.13 notify_settings_update / §6.14 APNs payload / §11 push/token·notify-settings，
> 服务端与安卓/Web 由其他并行 agent 同步实现，本仓只改 iOS）**：
> - **推送令牌注册**：`Network/IMPushTokenManager.h/.m`（新）——`start` 订阅 socket 连接态，每次
>   (重)连成功即 `registerIfEligible`（已登录 + 系统通知已授权 + 本机「接收离线推送」开 → 调
>   `registerForRemoteNotifications`，幂等廉价，符合"每次启动/登录都上报"的要求）；
>   `didRegisterForRemoteNotificationsWithDeviceToken:` 转 hex、读 `embedded.mobileprovision` 判环境
>   （development→sandbox，缺失/production/解析失败→production）、取 `IMLocalization.shared.language`
>   当 locale，`PUT /api/v1/push/token`。纯函数 `IMPushTokenHexFromData`/`IMPushEnvironmentFromMobileProvisionData`
>   可单测（后者用构造的「类 CMS」样例数据，不依赖真机签名包）。
> - **`Common/IMPushSettings.h/.m`**（新）：「接收离线推送（本设备）」开关，`NSUserDefaults` 本地偏好，
>   默认开；与账号级 `IMNotificationSettings` 是两类不同的东西（这个只管"这台设备要不要注册令牌"）。
> - **app_state 上行帧**：`Network/IMSocketManager+Push.h/.m`（新 category，主实现 `IMSocketManager.m`
>   已在体量门禁登记欠账、1600 行封顶只准降不准升，新逻辑一律不进主文件——本批净增 2 行：
>   握手成功处补一次 `sendForegroundAppStateIfActive` 调用、`handleFrame` 未识别分支改派发到本
>   category 的 `handleAdditionalFrameType:payload:`）。`SceneDelegate` 的 `sceneDidEnterBackground`/
>   `sceneWillEnterForeground` 各调一次 `noteAppDidEnterBackground`/`noteAppDidBecomeActive`。
> - **notify_settings_update 下行帧**：同一 category 里 `handleAdditionalFrameType:` 识别并广播
>   `IMSocketDidReceiveNotifySettingsUpdateNotification`（带 version），`IMAccountNotifySettingsSync` 订阅。
> - **通知点击进会话（含冷启动）**：`AppDelegate` 早设 `UNUserNotificationCenter.delegate`，实现
>   `willPresentNotification`（前台收到时不弹系统横幅——应用内横幅已覆盖）与
>   `didReceiveNotificationResponse`（纯函数 `IMPushConvIDFromUserInfo` 取 `conv_id` → 记入
>   `Common/IMPendingNotificationRoute.h/.m`（新）。`IMMainTabBarController.viewDidAppear:` 建好即
>   `tryRouteWithHost:userID:`——本地库暂时查不到该会话（冷启动会话列表还没同步下来）时线性退避重试
>   最多 6 次（约 10.5s 窗口）后放弃，避免无限占着）。
> - **App 图标角标**：`IMUnreadBadge.h/.m` 新增 `IMApplyAppIconBadge(n)`（iOS 16+ 走
>   `UNUserNotificationCenter.setBadgeCount:`，15 走 `applicationIconBadgeNumber`），挂在
>   `IMConversationListViewController.refreshListIndicators`（本页数据变更/回前台的唯一咽喉）——与
>   Tab 未读蓝点同一口径同一入参 `IMNotificationSettings.shared.badgeIncludeMuted`。
> - **设置页「锁屏与后台通知」做实**（`Modules/Me/IMNotificationSettingsViewController.m`，移除
>   `im_showComingSoon` 占位）：「通知权限」行异步查 `UNUserNotificationCenter` 三态（已开启/未开启/
>   未设置），`viewWillAppear`/`UIApplicationDidBecomeActiveNotification` 都刷新；点击按状态分支
>   （未决定→请求系统授权；已拒绝→弹 `permission_denied_hint`+`open_settings` 引导；已开启→直接跳
>   `UIApplicationOpenSettingsURLString`）。「接收离线推送」真开关，脚注换 `notif.system.footer_apns`。
>   登录后第一次进主页（`IMMainTabBarController.viewDidAppear:` 首次）直接请求系统通知授权
>   （`IMPushTokenManager.requestAuthorizationOnFirstMainScreen`）。
> - **账号级通知设置迁移/同步**（私聊/群聊 `{enabled,preview,sound}` + `badge.include_muted` 从每设备
>   本地迁到账号级）：纯逻辑 `Common/IMNotifySettingsMigration.h/.m`（`IMNotifySettingsSyncDecideAction`
>   判定 Push/ApplyServer——`dirty` 优先于 `serverExists`；`IMNotifySettingsShouldRefetchForVersion`；
>   JSON↔值对象互转，容错回默认、提示音复用 `IMNotificationSoundIDNormalize`）+ 编排
>   `Network/IMAccountNotifySettingsSync.h/.m`（写法照抄 `IMDownloadSettingsStore`：socket 连上/收到
>   `notify_settings_update` 都 `refresh`；`exists=false`→PUT 本地现值迁移，`exists=true`→覆盖本地
>   `IMNotificationSettings` 私聊/群聊/角标三项；本地任一改动广播 `IMNotificationSettingsDidChangeNotification`
>   →立即 PUT，失败置 `im.notify.sync.dirty`，下次 `refresh` 优先重推而不是被服务端旧值覆盖）。
>   **应用内三项（声音/振动/横幅）与桌面音量仍是每设备本地，不受影响**。安卓/Web 实现同一套迁移语义，
>   互相对齐见 `IMNotifySettingsMigration.h` 头注释（本批未碰 `SYMMETRY.md`，留给协调者登记）。
> - **新增 HTTP 端点**：`Network/IMHTTPService+Push.h/.m`（新 category）——
>   `PUT/DELETE /api/v1/push/token`、`GET/PUT /api/v1/notify-settings`。
> - **`IMProtocol.h/.m`** 加 `kIMTypeAppState`("app_state")、`kIMTypeNotifySettingsUpdate`("notify_settings_update")。
> - **新日志 Tag**：`IMLogTagPush`/`IMLogPush`（`IM.PUSH`，事件名 `push_*`/`notify_settings_*`），已按
>   `docs/LOGGING.md` 规则登记该文档（新领域、长期存在）。
> - **测试**（新增 `IMProgramTests/IMPushTokenManagerTests.m`/`IMPendingNotificationRouteTests.m`/
>   `IMNotifySettingsMigrationTests.m`，共约 20 例纯函数用例）：hex 转换、mobileprovision 环境解析（含
>   development/production/缺字段/空数据/无 plist 标记/标记间内容损坏六种边界）、通知 userInfo→conv_id
>   解析、同步动作判定（dirty 优先级）、版本比较、设置 JSON 往返。均做过一次真实变异验红后改回
>   （改错 hex 大小写、development/production 映射对调、conv_id 类型校验去掉、忽略 dirty 优先级、
>   sound 字段名拼错）。`./scripts/test.sh` 输出见下方「测试结果」，跑绿后填入本节。
> - **没做 / 已知限制**：
>   1. **冷启动路由查不到会话的极端情况**：若推送对应的会话是「本机从未见过」的全新会话（如新联系人
>      第一条消息、App 恰好在这条消息落库前就被杀），`IMPendingNotificationRoute` 重试 10.5s 后放弃，
>      用户点通知会进主页而不是直接进会话——之后手动点会话列表能看到。真机验证清单第 5 条。
>   2. **`GET /api/v1/notify-settings` 首次迁移与「本地 dirty 值」的极端并发**未做更细的时序保护：
>      若迁移 PUT 与用户几乎同时在设置页改了值，理论上有一次写入被覆盖的窗口（概率极低，未做锁）。
>   3. **推送权限被拒后的「已拒绝」态没有引导去开『消息预览』等替代方案**，只按设计给了系统设置跳转。
>   4. `IMServer/docs/CLIENT_PARITY.md`/`SYMMETRY.md` 本批未碰（任务明确限定「只改 IMProgram」）。
> - **需要真机验证**（模拟器/单测测不出）：
>   1. 登录后首次进主页系统授权弹窗的时机与文案；
>   2. App 切后台/回前台时抓包确认 `app_state` 帧确实发出（模拟器无法真实触发 App Store 级挂起）；
>   3. 真实收到 APNs 推送：后台/被上划杀掉/锁屏三态下点击通知能否冷启动直接进对应会话；
>   4. App 图标角标与 Tab 未读蓝点是否始终一致（含免打扰/@我穿透场景）；
>   5. 冷启动点通知但本地会话未同步完成时的重试体验（见上「没做」第 1 条）；
>   6. 设置页「通知权限」三态在系统设置里切换后回到本页是否及时刷新；
>   7. 关闭「接收离线推送」后确认服务端令牌被删、且此后不再收到推送。
