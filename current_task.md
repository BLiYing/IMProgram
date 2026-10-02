# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md`（2026-10-02 瘦身前的全量快照在其顶部）+ `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

无进行中的开发任务。最近收口（细节见 archive 顶部与 `git log`）：
2026-10-02 「我」页头部断网兜底（`IMSessionStore` 资料副本）/ 会话壳不再把 uid 当昵称（`IMConversation.knownDisplayName`），真机验证通过；
2026-10-01 通知显示发送人头像（通知扩展 target `IMNotificationService`）、别端已读清手机通知/角标（真机通过）、多选删除两档改批量接口（仅模拟器验证，iOS 真机未测）。

## 下一步

1. **真机验证欠账**：通知 P1 批一（横幅）+ 批二（定时免打扰时长菜单）只过了模拟器编译，没真机跑过，清单见 `current_task.archive.md` 里最近的归档块；「设置 ▸ 最近通话」真机走一遍拨打→挂断→回本页看 `callEnd` 是否自动刷新、1v1 回拨、群聊行跳转；批量删除两档的 iOS 真机。
2. **核对 `IMServer/docs/CLIENT_PARITY.md` 的 M5 行是否已按 iOS/安卓/Web 拆状态**（`SYMMETRY.md` 的 `alertDecision` 四端已登记）；若没拆，补上。
3. **拆体量欠账（下次碰就必须先拆）**：`Network/IMSocketManager.m` 1596/1600（只准降不准升；方向按 CODING_STYLE §7 三档：帧编解码 / 重连退避 / 各业务 send-recv 分组各成协作对象或 category，新逻辑优先开 category）；`Database/IMDatabase.m` 1500/1500，给 `im_conversation_local`/`im_message_local` 加列前先拆（参考 `IMDatabase+MuteState.m`）。
4. `IMChatViewController.m` 的 `peerDisplayName` 仍有 `fallback:peerID`（会在聊天页标题露内部 uid 的边缘路径），按 UI.md「末级不是 uid」改。
5. 小项：选好友页缺「全选」；`setupUI` 抽 `IMComposerBar`；「从收藏发送」入口开放；遗留 P2（听筒切换/接力连播停止条/Web 转文字/语音发送接入 `IMMediaSendService` 常驻队列等，细节见 archive）。

## 已知坑 / 限制

- **冷启动通知路由极端情况**：全新会话的推送点击可能落空。
- **会话列表左滑「免打扰」** 在 `done(YES)` 之前 present `IMMuteDurationMenu`、**通知横幅点击进会话** 与自身 dismiss 动画并行：真机若两个动画叠加突兀，把 present/路由挪到 `done(YES)` / dismiss 完成回调里即可（一行改动）。
- **通讯录 `reload` 不防重入**：好友事件与切入请求并发时后发先至会让 `applyFriends:` 覆盖成较旧名单（短暂，下次刷新自愈）；补法是在途时只记「待重跑」。
- **`IMProgramUITests/IMContactsPerfUITests` 对 2000 好友账号会卡住**（XCUITest 给整棵无障碍树拍快照，`cells.count` 超时重试，App 本身不卡）：重跑前改成不查大表，效果看 `contacts_index_applied` / `contacts_cache_persist` 日志与 simctl 截图。
- **撤回消息的「重新编辑」可能在重拉后消失**：服务端撤回/删除正文不再随 `sync_resp`/`window_resp` 下发，`writeIncomingMessage` 的 `content=?` 无条件覆盖，重拉后本地正文可能被空串盖掉（优雅降级，不崩溃）。
- **`IMMediaPlaceholderTests testFrostedLandscapeScalesLongestSideTo48` 高负载偶发失败**（`scripts/test.sh` 的 `-only-testing:IMProgramTests` + 关并行基本规避，根因未定位）。
- **`runAfterKeyboardHidden:` 兜底待测**：依赖 `resignFirstResponder` 后必然收到 `UIKeyboardDidHideNotification`；外接键盘场景引用跳转不触发就加 `dispatch_after` 超时兜底。
- 相册导出期杀 App 消息消失（PHPicker 句柄一次性，预期）；Files <8MB 小文件、相机拍照、粘贴图仍是 VC 锚定一次性上传；iOS 无双向分页（进会话全量载入本地 DB）；presence/typing 仅聊天页标题生效。
- dev-login 建的账号无法再走密码登录（测密码登录用「注册并登录」或清 `imserver.db`）。
- 查看器「正在播放中」视频 404 未接失效占位（窄路径可接受）；失效标记是进程内 Set、冷启动首帧重探（刻意）；原图路径 JPEG 字节戴 `.heic` 帽子（Web 靠嗅探已能显示，暂不改）；系统按钮文案靠 `CFBundleLocalizations`，自有 UI 硬编码中文。
- 测试只跑 `-only-testing:IMProgramTests`；改后端协议后需重启后端再测。体量门禁扫整个 `IMProgram/`（测试 target 是兄弟目录，不在范围）。
- 聊天页「从收藏发送」暂不支持：`attachItemTapped:` 的 `favorite` 分支仍走 `im_showComingSoon`（`../IMServer/docs/FAVORITES_DESIGN.md` §5.5 标 ⏸）。

## 关联工程 / 常用命令

- 后端 `/Users/dev/IOSProject/im-client/IMServer`；Web `/Users/dev/IOSProject/im-client/im-web`；Android `/Users/dev/IOSProject/im-client/im-android`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 装真机（iPhoneWork `00008120-000131121E50C01E`）：`xcodebuild … -destination 'id=<udid>' -derivedDataPath <dir> -allowProvisioningUpdates build` → `xcrun devicectl device install app --device <udid> <dir>/Build/Products/Debug-iphoneos/IMProgram.app`。首次连后端要允许「查找并连接本地网络设备」，登录页填 Mac 当前 LAN IP。
- 测试：唯一入口 `./scripts/test.sh`（体量门禁 + 编译 + `IMProgramTests`；`BUILD_ONLY=1` / `ONLY=<Class>` / `ONLY=<Class>/<test>`，三个坑见 `CLAUDE.md`「构建 / 测试」）。
- 真机日志：`xcrun devicectl device copy from --device iPhoneWork --domain-type appDataContainer --domain-identifier com.libeyond.IMProgram --source "Library/Caches/Logs/<file>.log" --destination <dst>`；通知扩展日志 `idevicesyslog -u <udid>` grep IMNotificationService。
- 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
