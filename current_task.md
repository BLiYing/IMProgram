# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

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

## 下一步
1. **M5 第一批真机验证**（清单见上「当前焦点」）——服务端/安卓/Web 并行实现完成后，协调者统一在真机上
   过一遍 user1002(Pixel)↔iPhone 的私聊/群聊/@我/图片四种消息、App 后台/被杀/锁屏三种状态。
2. **M5 落地后**：协调者需要补 `IMServer/docs/CLIENT_PARITY.md`（M5 行按 iOS/安卓/Web 拆状态）与
   `SYMMETRY.md`（`IMNotifySettingsMigration` 对端行、`alertDecision` 服务端第四端登记）——本次任务
   明确限定「只改 IMProgram」，这两份 IMServer 文档故意没碰。
3. **通知 P1 批一 + 批二真机验证**（清单见 `current_task.archive.md` 最新归档块）——批一横幅/批二时长菜单
   都还只过了模拟器编译，没有真机跑过。
4. **「设置 ▸ 最近通话」真机验证**（call-history v1 遗留）：真机走一遍拨打→挂断→回到本页看 `callEnd`
   是否自动刷新；1v1 行回拨、群聊行跳转是否真的可用。
5. **先验真机能否连通后端**：重装 App → 弹「允许查找并连接本地网络设备」点允许 → 登录页填 Mac 当前 LAN IP。
6. **拆 `IMProgram/Network/IMSocketManager.m`（1595 行，已在体量门禁登记欠账，上限 1600「只准降不准升」，
   本批 app_state/notify_settings_update 新逻辑已尽量收进 `+Push` category、主文件净增仅 2 行，但余量已
   压到 5 行，下次再要扩这个文件必须先拆）**：方向按 CODING_STYLE §7 三档——帧编解码 / 重连退避 / 各业务
   send-recv 分组各自成协作对象或 category。
7. **`IMDatabase.m` 已卡在体量门禁上限（1500/1500，一行不剩）**：下次再要给 `im_conversation_local`/
   `im_message_local` 加列，必须先拆（参考 `IMDatabase+MuteState.m` 的路子）。
8. 选好友页缺「全选」；`setupUI` 抽 `IMComposerBar`；「从收藏发送」入口开放；遗留 P2（听筒切换/接力连播停止条/
   Web 转文字/语音发送接入 IMMediaSendService 常驻队列等，细节见 `current_task.archive.md`）。

## 已知坑 / 限制
- **`IMSocketManager.m` 体量门禁余量已压到 5 行**（1595/1600，见「下一步」第 6 条）：任何后续改动优先
  考虑新开 category，不要再往主文件加行。
- **冷启动通知路由的极端情况**（本批新记，详见「当前焦点」没做第 1 条）：全新会话的推送点击可能落空。
- **会话列表左滑「免打扰」在 swipe action 的 `done(YES)` 之后同步 present `IMMuteDurationMenu`**：
  `UIContextualAction` 的 handler 里先调用 `presentMuteMenuForConversation:` 再 `done(YES)` 收起 swipe，
  present 与 swipe 收起动画同时发生，没有等 swipe 完全收起再弹菜单。真机如果两个动画叠加显得突兀，把
  present 挪到 `done(YES)` 之后（或加一个短延时）即可。
- **通知横幅点击进会话与自身 dismiss 动画并行发起**：`handleTouchUpInside` 里先起 dismiss 动画、同一时刻
  调 `IMConversationRouter openConversation:`——没有等横幅完全收起再转场。真机上如果转场与横幅收起动画
  叠加显得突兀，改成 dismiss 完成回调里再路由即可（一行改动）。
- **通讯录 `reload` 不防重入**：切入节流只挡切入这一路；好友事件 / 增删拉黑与切入的请求
  并发时，后发先至会让 `applyFriends:` 按到达顺序覆盖成较旧名单（短暂，下次刷新自愈）。补法：`reload` 在途时只记「待重跑」，回来后再拉一次。
- **`IMProgramUITests/IMContactsPerfUITests` 对 2000 好友的账号会卡住**：XCUITest 每查一次元素都要给整棵无障碍树拍快照，
  `UITableView` 把 2000 行全暴露出来 → `cells.count` 一次 30s+ 超时重试（App 本身不卡）。重跑前须改成不查大表（只点 Tab / 看标题），
  效果改看 `contacts_index_applied` / `contacts_cache_persist` 日志与 simctl 截图。
- **撤回消息的「重新编辑」可能在重拉后消失**：详情见 `current_task.archive.md`；
  服务端本轮安全修复起撤回/删除正文不再随 sync_resp/window_resp 下发，`IMDatabase writeIncomingMessage`
  的 `content=?` 无条件覆盖，重拉后本地正文可能被空串盖掉，「重新编辑」按钮随之消失（优雅降级，不崩溃）。
- **`IMMediaPlaceholderTests testFrostedLandscapeScalesLongestSideTo48` 在高负载下会偶发失败**（已被
  `scripts/test.sh` 的 `-only-testing:IMProgramTests` + `-parallel-testing-enabled NO` 基本规避，根因未定位）。
- **`runAfterKeyboardHidden:` 兜底待测**：依赖 `resignFirstResponder` 后必然收到
  `UIKeyboardDidHideNotification`；若实测硬件/外接键盘场景引用跳转不触发，加 `dispatch_after` 超时兜底。
- 相册导出期杀 App 消息消失（PHPicker 句柄一次性，属预期）；Files 面板 <8MB 小文件、相机拍照、粘贴图仍为
  VC 锚定一次性上传；相机录像已走 `IMMediaSendService` 常驻队列。
- iOS 无双向分页（进会话全量载入本地 DB）；presence/typing 仅聊天页标题生效。dev-login 建的账号无法再走
  密码登录（测密码登录用「注册并登录」或清 `imserver.db`）。
- **查看器"正在播放中"视频 404 未接失效占位**：窄路径（气泡/媒体库通常先探到→进查看器即
  短路）不黑屏可接受，兜底文案未区分失效。
- **失效标记内存态不持久（刻意）**：进程内 Set，冷启动首帧重探一次换自愈。
- **系统按钮文案本地化**：`Info.plist` 补 `CFBundleLocalizations` 让系统控件文案落中文；自有 UI 硬编码中文。
- **原图路径 JPEG 字节戴 `.heic` 帽子（暂不改）**：Web 靠字节嗅探已能正确显示，非阻塞。
- 测试只跑 `-only-testing:IMProgramTests`；改后端协议后需重启后端再测。
- **体量门禁覆盖面**：已扫整个 `IMProgram/`（测试 target 是兄弟目录，天然不在范围内）。
- **聊天页「从收藏发送」入口暂屏蔽/暂不支持**：`attachItemTapped:` 的 `favorite` 分支仍走
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
