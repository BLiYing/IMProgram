# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点
- M2「状态与可靠性」iOS 全部达成，且做完 Telegram 绿主题细化：浅绿/白气泡 + 绿已读双勾、聊天壁纸、按日期分组、长按菜单(复制/删除)、会话列表"我发的"已读双勾(`peer_read_seq`)、↓N 跳转按钮、会话列表长连接常驻实时刷新、离线消息空洞自愈。
- build + build-for-testing 通过(零 warning)；`IMProgramTests` 14 用例全绿。
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

## 关联工程 / 常用命令
- 后端 `/Users/liying/IOSProject/IMServer`；Web `/Users/liying/IOSProject/im-web`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 测试编译 + 实跑：`xcodebuild build-for-testing ...` → 有 booted 模拟器则 `test-without-building ... -only-testing:IMProgramTests`。
- 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
