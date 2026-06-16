# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点
- M2「状态与可靠性」iOS 全部达成 + Telegram 绿主题细化全做完 + 可见即读（Telegram 语义，iOS+Web 一致）。
- **M2.5-5 iOS 通讯录 🚧（2026-06-16）**：底部新增「通讯录」Tab。
  - `IMContactsViewController`：新的朋友(pending，同意/拒绝) + 好友列表(accepted，点击发起会话)；待处理申请数显示在 Tab 角标。
  - 右上 + 进 `IMUserSearchViewController`（找人）：搜索框→`GET /users/search`，结果按"我与对端关系"显示 加好友/已申请/同意/发消息。
  - 新增 `IMUserCard` 模型 + `IMHTTPService` 的 search/friends/friendAction/removeFriend；复用 `IMTheme` 绿主题、`UIButtonConfiguration`（免 contentEdgeInsets 弃用告警）。
  - `IMUserCardTests` 解析单测（找人/好友/状态映射/脏数据）。`xcodebuild build` + `build-for-testing` 均零 error/warning。
  - **与 Web 对齐**：找人 ✅、好友关系 🚧（拉黑/删除好友 UI 未做）；两端均无"编辑我的资料"页。
- **下一步：M2.5-6 收尾**——拉黑/删除好友 UI（两端）+ 编辑我的资料页 + 客户端真账号密码登录（替换免密直签）。

## 下一步
1. 拉黑/删除好友 UI（iOS：好友行左滑删除/长按拉黑；Web：好友行 hover 操作）→ 两端好友关系行升 ✅。
2. "编辑我的资料"页（昵称/头像/标签 `PUT /users/me`）→ 用户资料行客户端升 ✅。
3. 登录改真账号密码（替换免密直签）。
4. （性能轨道，按需）iOS 双向分页。

## 已知坑 / 限制
- **真账号/密码登录未做**：iOS 仍开发期免密直签 uid（后端已具备）。
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
