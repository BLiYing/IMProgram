# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

> **2026-10-01 别的端已读后清手机通知/角标**（PUSH_M5_DESIGN §3.5，真机验证通过）：`Common/IMPushRetract` 加 `IMPushClearDeliveredNotificationsReadThrough`；`AppDelegate` 收 `clear_up_to` 推送（Info.plist 新增 `remote-notification` 后台模式）；`handleReceipt` 收本人回执时同样清。`IMSocketManager.m` 现 1596/1600。

> **2026-09-30 多选删除两档·改批量接口（2026-10-01 模拟器实测通过，已提交并推送 `74d8ecd`）**：`IMChatViewController+Selection.m` 的
> `performDeleteSelected` / `performDeleteSelectedForEveryone` → `-runBatchDelete:everyone:`，经新 category
> `Network/IMSocketManager+BatchDelete`（+ `IMHTTPService+BatchDelete`）一次请求 `POST /messages/hide|delete`，
> 成功项本地移除、失败汇总一句「N 条删除失败」；走 REST，断线也能删（不再先拦）。`msg_hidden` 批量帧读 `conv_seqs`
> （`IMMsgHiddenSeqs`）。批量删除广播帧（一帧 `targets`，2026-10-01）走 `applyBatchDeleteFrameOnQueue:`，整批移除只发一次通知（`kIMMsgOpTargetSeqsKey`），聊天页/媒体页一次删完只刷新一次。置顶横幅：`-onMessageRemoved:` 改为无条件调 `-schedulePinnedBannerReload`（+PinnedBanner.m，
> 0.3s 尾沿合并，代数存关联对象——Private.h 已 72 条到闸），批量结束再触发一次。`IMBatchDeleteTests` 3 例（先看红）；test.sh 667/667。
> **2026-10-01 模拟器已验**：单聊两档批量、收/发整批一帧、混选只一档、断服务「2 条删除失败」、删置顶消息横幅即消（服务端旁听确认每成员只收一帧）。九宫格逐格选、群主选别人的消息有第二档也已验（2026-10-01）。**已无待验项**（iOS 真机未测，仅模拟器）。

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
