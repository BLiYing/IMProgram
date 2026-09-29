# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

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
> `current_task.archive.md` 顶部归档块。

## 下一步
1. **通知 P1 批一 + 批二真机验证**（清单见上「当前焦点」两条「需要真机验证」）——批一横幅/批二时长菜单
   都还只过了模拟器编译，没有真机跑过。
2. **`feature/notif-p1b` 推上去之后**：三端收口协调者需要补 `IMServer/docs/CLIENT_PARITY.md`（通知与提示音
   行按 P1 各项拆三端状态）与 `SYMMETRY.md`（`IMMuteState`/`IMMuteDurationMenu` 对端行，本批只写了 iOS 这
   一侧的实现，Android/Web 若也已落地要在 SYMMETRY 里互相点名）——本次任务明确限定「只改 IMProgram」，
   这两份 IMServer 文档故意没碰。
3. **「设置 ▸ 最近通话」真机验证**（call-history v1 遗留）：真机走一遍拨打→挂断→回到本页看 `callEnd`
   是否自动刷新；1v1 行回拨、群聊行跳转是否真的可用。
4. **先验真机能否连通后端**：重装 App → 弹「允许查找并连接本地网络设备」点允许 → 登录页填 Mac 当前 LAN IP。
5. **拆 `IMProgram/Network/IMSocketManager.m`（1593 行，已在体量门禁登记欠账，上限 1600「只准降不准升」，
   本批 conv_update 解析 mute_until 特意就地扩展现有行、没有再往主文件里加行）**：方向按 CODING_STYLE §7
   三档——帧编解码 / 重连退避 / 各业务 send-recv 分组各自成协作对象或 category。
6. **`IMDatabase.m` 已卡在体量门禁上限（1500/1500，一行不剩）**：下次再要给 `im_conversation_local`/
   `im_message_local` 加列，必须先拆（参考本批 `IMDatabase+MuteState.m` 的路子：新老库迁移单独开
   category，主文件只留一行调用口子），不能再直接往主文件塞。
7. 选好友页缺「全选」；`setupUI` 抽 `IMComposerBar`；「从收藏发送」入口开放；遗留 P2（听筒切换/接力连播停止条/
   Web 转文字/语音发送接入 IMMediaSendService 常驻队列等，细节见 `current_task.archive.md`）。

## 已知坑 / 限制
- **会话列表左滑「免打扰」在 swipe action 的 `done(YES)` 之后同步 present `IMMuteDurationMenu`**
  （本批新记，与横幅那条同一类风险）：`UIContextualAction` 的 handler 里先调用 `presentMuteMenuForConversation:`
  再 `done(YES)` 收起 swipe，present 与 swipe 收起动画同时发生，没有等 swipe 完全收起再弹菜单。模拟器编译
  能过、没跑起来看过；真机如果两个动画叠加显得突兀，把 present 挪到 `done(YES)` 之后（或加一个短延时）即可。
- **通知横幅点击进会话与自身 dismiss 动画并行发起**（本批新记）：`handleTouchUpInside` 里先起 dismiss
  动画、同一时刻调 `IMConversationRouter openConversation:`——没有等横幅完全收起再转场。模拟器上看不出
  问题，真机上如果转场与横幅收起动画叠加显得突兀，改成 dismiss 完成回调里再路由即可（一行改动）。
- **通讯录 `reload` 不防重入（2026-09-12 复查记，老问题未修）**：切入节流只挡切入这一路；好友事件 / 增删拉黑与切入的请求
  并发时，后发先至会让 `applyFriends:` 按到达顺序覆盖成较旧名单（短暂，下次刷新自愈）。补法：`reload` 在途时只记「待重跑」，回来后再拉一次。
- **`IMProgramUITests/IMContactsPerfUITests` 对 2000 好友的账号会卡住**：XCUITest 每查一次元素都要给整棵无障碍树拍快照，
  `UITableView` 把 2000 行全暴露出来 → `cells.count` 一次 30s+ 超时重试（App 本身不卡）。重跑前须改成不查大表（只点 Tab / 看标题），
  效果改看 `contacts_index_applied` / `contacts_cache_persist` 日志与 simctl 截图。
- **撤回消息的「重新编辑」可能在重拉后消失（2026-09-03 评估后刻意不修）**：详情见 `current_task.archive.md`；
  服务端本轮安全修复起撤回/删除正文不再随 sync_resp/window_resp 下发，`IMDatabase writeIncomingMessage`
  的 `content=?` 无条件覆盖，重拉后本地正文可能被空串盖掉，「重新编辑」按钮随之消失（优雅降级，不崩溃）。
- **`IMMediaPlaceholderTests testFrostedLandscapeScalesLongestSideTo48` 在高负载下会偶发失败**（已被
  `scripts/test.sh` 的 `-only-testing:IMProgramTests` + `-parallel-testing-enabled NO` 基本规避，根因未定位）。
- **`runAfterKeyboardHidden:` 兜底待测（2026-08-05 记）**：依赖 `resignFirstResponder` 后必然收到
  `UIKeyboardDidHideNotification`；若实测硬件/外接键盘场景引用跳转不触发，加 `dispatch_after` 超时兜底。
- 相册导出期杀 App 消息消失（PHPicker 句柄一次性，属预期）；Files 面板 <8MB 小文件、相机拍照、粘贴图仍为
  VC 锚定一次性上传；相机录像已走 `IMMediaSendService` 常驻队列。
- iOS 无双向分页（进会话全量载入本地 DB）；presence/typing 仅聊天页标题生效。dev-login 建的账号无法再走
  密码登录（测密码登录用「注册并登录」或清 `imserver.db`）。
- **查看器"正在播放中"视频 404 未接失效占位（2026-08-11 记）**：窄路径（气泡/媒体库通常先探到→进查看器即
  短路）不黑屏可接受，兜底文案未区分失效。
- **失效标记内存态不持久（刻意，2026-08-11 记）**：进程内 Set，冷启动首帧重探一次换自愈。
- **系统按钮文案本地化（2026-08-12 修，未编译验证）**：`Info.plist` 补 `CFBundleLocalizations` 让系统控件
  文案落中文；自有 UI 硬编码中文。
- **原图路径 JPEG 字节戴 `.heic` 帽子（2026-08-12 记，暂不改）**：Web 靠字节嗅探已能正确显示，非阻塞。
- 测试只跑 `-only-testing:IMProgramTests`；改后端协议后需重启后端再测。
- **体量门禁覆盖面（2026-09-01 修）**：已扫整个 `IMProgram/`（测试 target 是兄弟目录，天然不在范围内）。
- **聊天页「从收藏发送」入口暂屏蔽/暂不支持（2026-08-19）**：`attachItemTapped:` 的 `favorite` 分支仍走
  `im_showComingSoon`；设计已保留（`../IMServer/docs/FAVORITES_DESIGN.md` §5.5 标 ⏸），待收藏改造统一放开。

## 关联工程 / 常用命令
- 后端 `/Users/dev/IOSProject/im-client/IMServer`；Web `/Users/dev/IOSProject/im-client/im-web`；
  Android `/Users/dev/IOSProject/im-client/im-android`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 测试：唯一入口 `./scripts/test.sh`（体量门禁 + 编译 + `IMProgramTests`，见 `CLAUDE.md`「构建 / 测试」节
  的三个坑与用法：`BUILD_ONLY=1`/`ONLY=<Class>`/`ONLY=<Class>/<test>`）。
- 真机日志：`xcrun devicectl device copy from --device iPhoneWork --domain-type appDataContainer
  --domain-identifier com.libeyond.IMProgram --source "Library/Caches/Logs/<file>.log" --destination <dst>`。
- 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
