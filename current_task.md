# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

> **通知与提示音 P1 · 第一批 ✅ 代码 + 单测已完成，待真机验（2026-09-29，分支 `feature/notif-p1a`，
> 设计：`../IMServer/docs/design/NOTIFICATIONS_P1_DESIGN.md` §0–§3/§6.2(iOS 列)/§7/§8，草图
> `sketches/NOTIFICATIONS_P1_UX_SKETCH.html` 01/02 节）**：范围＝应用内横幅 + 例外「添加例外」+
> 主页「应用内预览」真开关。**定时免打扰（第二批）未动**。
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
> - **`IMNotificationTypeViewController`**：`b4d9c88`「没有免打扰会话就整组不显示」按 §8 已拍板②改回——
>   「例外」组常驻，首行固定绿色（`IMTheme.accent`，即草图 `--app-accent`，非硬编码色）圆形 + 号
>   「添加例外」行（新 cell `IMNotifAddExceptionCell`）。点了用 `immediateSingleSelect` 模式 present
>   `IMForwardPickerViewController`，`extraFilter` 用新纯函数 `Common/IMNotifExceptionPickerFilter.h`
>   的 `IMNotifExceptionPickerMatches`（该类型 + 未免打扰 + 非系统通知，独立小文件方便单测）。选中后
>   `muteNewException:` 走既有 `updateConversationSettingsWithToken:...` PUT，**原样带回
>   `pinned_at`/`marked_unread`**（与 `unmute:` 对称，同一个坑）。`unmute:` 最后一个也取消时不再删整段，
>   只删那一行（组常驻）。
> - **`IMNotificationSettingsViewController`**：「应用内预览」行从灰置占位改真开关（绑定既有
>   `IMNotificationSettings.inAppPreview`，P0 早就存了、只是没接 UI）；「应用内通知」组脚注从
>   `notif.in_app.footer` 换成 `notif.in_app.preview_footer`。
> - **本地化**：5 个新键（`notif.exceptions.add`/`pick_footer_private`/`pick_footer_group`/`pick_empty`、
>   `notif.in_app.preview_footer`）中英文均已在（工作树进来时已生成，本批一并提交）；
>   `notif.exceptions.empty_*` 两条不再被引用（未删字符串资源本身）。
> - **测试**：新增 `IMConversationPreviewTests`（13 例）/`IMInAppBannerContentTests`（6 例）/
>   `IMNotifExceptionPickerFilterTests`（6 例），均对核心分支做过一次真实变异验红（banner 判定改
>   `NO`、voice 时长公式加偏移、preview-off 分支改错文案、picker 的 `muted` 判断注掉，四处全部按预期
>   变红后改回）。`IMAlertDecisionTests` 改读 32 条向量。`./scripts/test.sh` **606/606 绿**（较 P0 收尾时
>   580 例新增 26 例）。
> - **没做 / 已知限制**：定时免打扰（时长菜单/`mute_until`/`isMutedNow`，全部留第二批）；
>   `IMServer/docs/CLIENT_PARITY.md`/`SYMMETRY.md`/`docs/i18n/strings.json`/`NOTIFICATIONS_DESIGN.md` §11
>   **均未碰**（本次任务明确限定「只改 IMProgram，不改 IMServer/im-android/im-web」，留给协调者收口三端）；
>   IMProgram 本仓没有单独的 iOS UI parity 文档（`UI_PARITY_IOS.md` 只存在于 im-android，供它对齐 iOS）。
> - **需要真机验证**（模拟器/单测测不出的部分，本次完全没做）：① 横幅滑入/滑出动效手感、阴影观感；
>   ② 4 秒自动收起的真实时长体感、按住暂停/松开恢复计时是否顺滑；③ 上滑手势收起在真实触屏上的识别率
>   （模拟器鼠标拖拽与真手指滑动手感不同）；④ 连发 5 条消息横幅原地换内容不叠加、不闪烁；⑤ 深色模式下
>   卡片背景 `IMTheme.surfaceElevated` 与阴影的可辨度；⑥ 点击横幅进会话的转场是否顺畅、横幅是否先收起
>   再转场（当前实现是先 dismiss 动画同时发起路由，两者并行，真机上可能有观感差异待评估）；⑦ 「添加例外」
>   选择页的空态/脚注文案排版、绿色圆形 + 号在浅色/深色下的对比度；⑧ VoiceOver 是否能正确读出横幅内容
>   （未加任何无障碍 label/trait，完全没有针对性适配）。

## 下一步
1. **通知 P1 批一真机验证**（清单见上「当前焦点」最后一条）。
2. **通知 P1 第二批**（定时免打扰，`../IMServer/docs/design/NOTIFICATIONS_P1_DESIGN.md` §4/§5）：三端
   `isMutedNow` 纯函数 + 共用向量 `mute_state.json`（尚未创建）、协议加 `mute_until`（后端改动）、
   三端各入口的时长菜单。**后端先行**，iOS 侧等协议落地后再接。
3. **「设置 ▸ 最近通话」真机验证**（call-history v1 遗留）：真机走一遍拨打→挂断→回到本页看 `callEnd`
   是否自动刷新；1v1 行回拨、群聊行跳转是否真的可用。
4. **先验真机能否连通后端**：重装 App → 弹「允许查找并连接本地网络设备」点允许 → 登录页填 Mac 当前 LAN IP。
5. **拆 `IMProgram/Network/IMSocketManager.m`（1593 行，已在体量门禁登记欠账，上限 1600「只准降不准升」，
   本批横幅触发代码特意放进已有的 `+Alerts.m` category 没有再往主文件里加）**：方向按 CODING_STYLE §7
   三档——帧编解码 / 重连退避 / 各业务 send-recv 分组各自成协作对象或 category。
6. 选好友页缺「全选」；`setupUI` 抽 `IMComposerBar`；「从收藏发送」入口开放；遗留 P2（听筒切换/接力连播停止条/
   Web 转文字/语音发送接入 IMMediaSendService 常驻队列等，细节见 `current_task.archive.md`）。

## 已知坑 / 限制
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
