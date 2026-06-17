# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点
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
- **登录失败 UX 修（2026-06-17，两端）**：会话列表原来"任何登录失败都弹模态框、标题无连接态"。现：NSError 带业务码 + `IMIsAuthErrorCode`;socket 加 `IMSocketDidChangeStateNotification`，会话列表标题显示「会话（连接中…/未连接）」;reload 失败分流——**鉴权失败(账号没了/密码错/token失效)→ 退回登录页**(`bounceToLoginWithReason:`)，**网络失败→不弹框**(标题已显未连接、靠自动重连)。Web 同步:`onAuthError`→退回登录、网络→保持 header 状态+重连。

## 下一步
1. （里程碑）M3 群聊 / 群成员管理；或先补「多端同时在线」客户端 UI/位点同步验证（M1 遗留 ⬜）。
2. （欠账，换真账号后更重要）本地库 `im.sqlite` 按 uid 隔离：不同账号共用一库会串号缓存。
3. （性能轨道，按需）iOS 双向分页。

## 已知坑 / 限制
- **登录已支持真账号密码**：登录页「免密登录（开发）」仍保留（凭 uid 直签，需后端 `-dev-login`）。注意 dev-login 建的账号（空密码哈希）无法再走密码登录；测密码登录请用「注册并登录」建新号或清 `imserver.db`。
- **iOS 无双向分页**：进会话一次性全量载入本地 DB；性能轨道、当前不影响使用。
- **presence/typing 仅聊天页标题**生效；会话列表不显示在线点（后续可同 notification 广播 presence）。
- 聊天壁纸为 CG 自绘 SF Symbol 近似，非 Telegram 原涂鸦。
- 测试只跑 `-only-testing:IMProgramTests`（UITests 会因 Accessibility 超时拖垮）。
- 改后端协议字段后**需重启后端**再测；涉及本地库的回归需在模拟器**删 App 重装**清 `im.sqlite`。
- **本地库 `im.sqlite` 全局单文件、不分账号、登出不清**（未修）：同一设备切号会看到上一个账号的缓存；若服务端 `imserver.db` 被清而本地没清会 conv_seq 串号 → 旧缓存显示、新消息被跳过、已读双勾错乱。**干净重测：删 App + `rm imserver.db*` 同时做**。根治待办：本地库按 uid 隔离（`im_<uid>.sqlite` 或表加 owner 列过滤）。
- 已读=可见即读（已实现）：未读随滚动逐步清；进会话只清当前可见的，需滚到底才全清。↓N 徽标=视口下方未读数，随滚动递减、滚到底隐藏（按 pendingReadSeq 实时重算，非静态）。

## 关联工程 / 常用命令
- 后端 `/Users/liying/IOSProject/IMServer`；Web `/Users/liying/IOSProject/im-web`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 测试编译 + 实跑：`xcodebuild build-for-testing ...` → 有 booted 模拟器则 `test-without-building ... -only-testing:IMProgramTests`。
- 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
