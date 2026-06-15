# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点
- M2「状态与可靠性」iOS 全部达成 + Telegram 绿主题细化全做完（浅绿/白气泡+绿已读双勾、壁纸、日期分组、长按菜单、列表已读双勾 `peer_read_seq`、↓N 跳转、列表常驻实时刷新、离线空洞自愈）。
- **已读改为"可见即读"(Telegram 语义，iOS+Web 一致)**：废弃"打开即全部已读"。聊天页扫 `indexPathsForVisibleRows` 取视口内最大 conv_seq，超过已上报位点则 0.3s 节流 `markRead`；进会话只读可见的、向下滚逐步推进、在上方看历史不误读下方。触发：`scrollViewDidScroll` / `viewDidAppear`(dispatch 后扫一遍) / 收新消息后。修掉了"进会话不上报已读"的回归(根因:列表常驻连接+预落库后聊天页 didChangeState/didReceiveMessage 都不再触发上报)。build+test-build 零 warning，14 测试绿。
- **下一步里程碑：M2.5 通讯录 / 加好友 / 找人**（含客户端密码登录改造）。

## 下一步
1. M2.5：通讯录页、加好友/搜索、从联系人发起会话（替换"输入 uid"占位）；登录改真账号密码（替换免密直签）。
2. 新增逻辑配套 `IMProgramTests` 用例，按 CLAUDE.md 跑 `-only-testing:IMProgramTests`。
3. （性能轨道，按需）iOS 双向分页：DB 分页查询 + 进会话只载最近一页 + 上/下滚翻页保位。单会话上万条再做。

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
