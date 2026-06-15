# Current Task

## Status（2026-06-15 最新）
**正在做 M2「状态与可靠性」**。后端 M2 全done（已读回执 delivered≠read、未读数/red dot、presence、typing、会话项返回 read_seq、双向分页用现有 LoadSince）。
**Web 端（im-web，React+TS）M2 已完成并浏览器实测**：已读双勾/未读红点/presence/typing、未读分割线（read_seq 精确定位）、进会话停首条未读（Telegram 式，非最新）、双向分页（上滚更早/下滚更新）、↓N 跳转、**Telegram 桌面式双栏布局（窄屏自适应单栏）**。
**聊天交互蓝图见 `../IMServer/docs/CHAT_UX.md`（多端单一事实来源）；端能力见 `../IMServer/docs/CLIENT_PARITY.md`。**
压测工具：`IMServer/cmd/loadtest`（`go run ./cmd/loadtest -from 1002 -to 1001 -n 10000`）。
**TODO（性能）**：Web 消息列表虚拟化暂回退（virtua 在双栏条件挂载/嵌套 flex 下视口测 0、渲染空且不自愈）→ 现为普通滚动列表（配反向分页常规不卡）；后续换 react-window/@tanstack/react-virtual。
**✅ M2 iOS UI 已实现（2026-06-15）**：已读双勾（已送达✓→已读✓✓，按对端 read_seq）、会话列表未读红点、聊天页标题在线点（🟢/在线）、对方正在输入提示条、未读分割线（read_seq 精确）+ 进会话停首条未读、打开即全部已读（markRead latest）。workspace build + build-for-testing 通过。
- 协议：IMProtocol 加 typing/presence 常量；IMConversation 加 readSeq。
- SocketManager：收 receipt(read)/typing/presence → 新 delegate；发 markReadConv:upToConvSeq:、sendTypingForConv:。
- 聊天页：IMBubbleCell 加分割线+已读双勾；进会话定位、typing 提示、presence 标题、typing 节流上报。
- **已知限制**：presence/typing 仅在聊天页生效（socket 当前按会话连接，不在会话列表常驻）；会话列表不显示在线点。完整需把 socket 提到 App 级常驻（后续）。
**下一步：等用户真机验收 M2；然后 M2.5 通讯录/加好友/找人。**

## Status（iOS 既有，M1-5）
客户端：登录 → **会话列表（TabBar 会话/我）** → 聊天 三段式（M1-5b）+ **本地落库 IMDatabase（M1-5c：秒显历史 + 断点续传）**。
栈：IMSocketManager（重连同步 + JWT + trackConversation:syncedSeq:）+ IMHTTPService（登录/会话列表）+ IMConversation + IMTheme(tokens) + **IMDatabase（FMDB + SQLite）**。
默认 host 改为 192.168.1.3:8080（真机联调）。
  - **已引入 CocoaPods（仅 FMDB）**：用 `IMProgram.xcworkspace` 打开/构建（不再用 .xcodeproj）；Podfile post_install 关了脚本沙盒避免 Pods 资源拷贝被拒。workspace `build` + `build-for-testing` 通过。
  - iOS 工作流：编译 + test-build 验证；**模拟器已恢复稳定**，有 booted 模拟器时直接实跑 XCTest。
  - ✅ 2026-06-15：iPhone 16e 模拟器**实跑 XCTest 通过**（IMProtocolTests 9 用例：会话id/协议常量/消息解析/IMConversation 解析/IMDatabase 落库往返）；App install+launch，登录页渲染正常（深色模式自动适配）。UI 全流程点击走查待 computer-use 系统权限或用户手测。
  - 进聊天页隐藏底部 TabBar（hidesBottomBarWhenPushed）已修。
  - ✅ 真机端到端验证通过（host 填 Mac 局域网 IP：登录→token→连接→离线消息 sync 拉回→已读回执）。本地明文联调需临时关 Mac 防火墙/stealth（生产用 wss:// 无此问题）。
  - ✅ 首批 XCTest（IMProtocolTests，6 用例）在 iPhone 16e 模拟器**全绿**（`-only-testing:IMProgramTests` 跳过模板空 UI target）。
  - 坑记录：默认 IMProgramUITests 会因 Accessibility 超时拖垮整体测试，单测须 `-only-testing:IMProgramTests`；前期 Mach -308/启动超时是模拟器未就绪所致，先 simctl bootstatus 等就绪即可。
后端：IMServer 用 **Go**，网关 + 持久化 + 幂等 + **离线消息/增量同步** 完成，`./scripts/test.sh` 全量回归绿。

## 关联工程
- 客户端：/Users/liying/IOSProject/IMProgram
- 后端：/Users/liying/IOSProject/IMServer（协议见 IMServer/docs/PROTOCOL.md）

## Progress
- [x] 确认技术栈：Objective-C 为主，Swift 备用混编
- [x] 创建 `CODING_STYLE.md`（OC + Swift 代码规范）
- [x] 创建 `current_task.md`（本文件，任务记忆）
- [x] 创建 `CLAUDE.md`（项目说明）
- [x] 创建 `.gitignore`（修复误提交的 xcuserdata）
- [x] 选定通信方案：自建 WebSocket
- [x] 选定依赖管理：CocoaPods
- [x] 设计 IM 整体架构（写入 ARCHITECTURE.md）
- [x] 编写共用协议文档 IMServer/docs/PROTOCOL.md（v0.1）
- [x] 选定后端语言：Go
- [x] 搭建 Go WebSocket 网关骨架（protocol/gateway/cmd），集成测试通过
- [x] 后端：内嵌网页调试客户端（cmd/imserver/web/index.html，go:embed 挂 /），双开浏览器肉眼验证互发
- [x] 后端：服务端优雅接收 receipt（记录，不再回 error）
- [x] 端到端验证：两真实 WS 客户端 send→ack→new_msg→receipt 全通过（C 完成）
- [x] 移除误提交的 xcuserdata（git rm --cached）
- [x] 客户端：创建 Podfile（Masonry/FMDB/SDWebImage/YYModel/AFNetworking；WebSocket 改用系统原生）
- [x] 客户端：搭建分层目录结构（Common/Network/Models/Services）
- [x] 客户端：实现 IMSocketManager 长连接骨架（连接/心跳/退避重连/收发/ACK 超时重发），xcodebuild 通过
- [x] 客户端：登录页 IMLoginViewController + 聊天页 IMChatViewController（原生 AutoLayout，不依赖 Pod），SceneDelegate 代码设根
- [x] 客户端：IMSocketManager 接增量同步——trackConversation、重连自动 sync_req、handleSyncResp（分页+投递+回执）、按 conv_seq 去重
- [x] 客户端：首批 XCTest IMProtocolTests（6 用例，iPhone 16e 模拟器全绿）
- [后端进度见 IMServer/current_task.md] 持久化/幂等/离线同步均已完成；JWT 鉴权、errcode、HTTP 层待办
- [ ] 客户端：pod install（需联网）后用 .xcworkspace 打开
- [ ] 客户端：IMDatabase 落库（sending→sent 持久化）+ synced_conv_seq 持久化（当前记内存，重启从 0 同步）

## Decisions & Constraints
- 主语言 Objective-C；未来可混编 Swift，新模块倾向 Swift。
- 通信：自建 WebSocket。**传输层改用系统原生 NSURLSessionWebSocketTask**（iOS 13+ API）；传输封装在 IMSocketManager 内部，接口不变，未来可无痛替换。心跳 25s + 指数退避重连 + ACK 超时重发。
- **部署目标 iOS 15.0**（2026-06-15 从误设的 26.2 调低）：代码栈未用 iOS 16+ API，15 覆盖设备最广且与 Podfile/Pods（已 15.0）一致；真机（iOS 18.6.2）可正常安装运行。
- 工程用 Xcode 文件系统同步组（PBXFileSystemSynchronizedRootGroup）：往 IMProgram/ 加文件即自动入编译，无需手改 pbxproj。
- 依赖：CocoaPods（使用后改用 .xcworkspace 打开）。
- 类统一前缀 `IM`，ARC，4 空格缩进。
- 网络/IO/数据库调用必须有错误恢复分支。
- `xcuserdata` / `xcuserstate` 不再纳入版本控制。

## Next Actions
0. **【当前】M2 iOS UI**：照 `IMServer/docs/CHAT_UX.md` 蓝图，在 IMProgram 实现未读红点 / 已读双勾 / 在线点 / typing / 进会话停首条未读（read_seq 锚点）。配套 IMProgramTests，做完 M2 整体里程碑停下等用户验收。
1. 真机/模拟器联调：`cd IMServer && go run ./cmd/imserver`，App 登录页填 host=本机IP:8080 / 我的 uid / 对方 uid，两端互发；可先杀掉一端验证离线→重连 sync 补偿。
2. 后续新增客户端逻辑时，往 IMProgramTests 加用例并按 CLAUDE.md 命令补跑（`-only-testing:IMProgramTests`）。
3. 接 IMDatabase（FMDB）落库：消息 sending→sent 持久化、synced_conv_seq 持久化（替换当前内存位点）。
4. 后端（见 IMServer/current_task.md）：JWT 鉴权替换 ?uid=、errcode 包 + HTTP 登录接口。
