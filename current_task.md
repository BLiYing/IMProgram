# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点
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
- **登录失败 UX 修（2026-06-17，两端）**：会话列表原来"任何登录失败都弹模态框、标题无连接态"。现：NSError 带业务码 + `IMIsAuthErrorCode`;socket 加 `IMSocketDidChangeStateNotification`，会话列表标题显示「会话（连接中…/未连接）」;reload 失败分流——**鉴权失败(账号没了/密码错/token失效)→ 弹框「重新登录/取消」**(取消则留看本地缓存、不强制踢走、只提示一次:authPromptActive/authDismissed)，**网络失败→不弹框**(标题已显未连接、靠自动重连)。Web 同步:`onAuthError`→`window.confirm`(确定登录/取消留看缓存)、网络→保持 header 状态+重连。两端浏览器/编译验证通过。
- **拉黑模型重构 + 拒收反馈（2026-06-17，两端）**：
  - ①**拉黑≠解绑（blocked 标记模型）**：后端 `im_friend` 加与 `status` 正交的 `blocked` 标记（启动自动迁移老 `status='blocked'`→`blocked=1`，非破坏）。`Block` 只置标记、好友关系(双方 accepted)不动 → **双方好友列表始终互见**(拉黑方带标记)；`Unblock` 只清标记。`BlockedBetween`/黑名单查询改用标记。iOS：`IMUserCard.blocked` 解析 + 通讯录被拉黑好友副标题"· 已拉黑" + 左滑"解除拉黑"。Web：`FriendEntry.blocked`、`peerBlocked` 改用标记、好友列表"已拉黑"标签 + 菜单"解除拉黑"。**Web 浏览器实测全过**；iOS 真编译+test-build 过、真机待验。
  - ②**被拒收微信式反馈**：被拉黑方发消息 → 气泡左红❗ + 下方居中系统行「消息已发出，但被对方拒收了」，**不弹窗**(iOS `IMBubbleCell._failBadge/_sysNote` + `IMMessageModel.note`；Web `ChatMessage.note` + `.fail-badge/.sys-note`)。Web 实测过；**iOS 系统行真机待复验**(代码路径已逐段核对正确，疑用户上次测时走了 10s 超时而非拒收)。
  - 规则见 `../IMServer/docs/PROTOCOL.md §6.5`、`CHAT_UX.md §8`。**已知**：早期"拉黑删对端行"旧 bug 已破坏的好友对(如 a1003↔a1001)无法自动复原，需重新加好友一次。
  - ③**拉黑改微信式单向(已定+实现)**：hub 仅拦"被拉黑方→拉黑方"；**拉黑方→被拉黑方照常投递**(对方收得到)。两端聊天页不再封禁拉黑方输入(Web 改非阻断提示行、iOS 移除封禁横幅)。`TestBlockedCannotSend` 改测单向。Web 浏览器实测：拉黑方发送成功✓+提示在+输入可用。iOS 真编译过、真机待验。

## 下一步
1. **真机走查 M3-5 群聊**（清单见最近一次 checkpoint：建群/群消息昵称/群资料管理/被移出）；主线随后端 M3-6 Admin 群治理（iOS 无任务）。
2. 群聊 iOS 待补（对齐 Web 的同款欠账）：群头像上传（现首字母圈）、群内已读细化（自己消息恒单 ✓）、@提醒（M4 期）。
3. （欠账，换真账号后更重要）本地库 `im.sqlite` 按 uid 隔离：不同账号共用一库会串号缓存。
4. （性能轨道，按需）iOS 双向分页。

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
