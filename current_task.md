# Current Task

## Status
客户端：登录 → **会话列表（TabBar 会话/我）** → 聊天 三段式（M1-5b）。IMSocketManager（重连增量同步 + JWT 登录）+ IMHTTPService（登录/会话列表）+ IMConversation + IMTheme(design tokens)。`build` + `build-for-testing` 均通过、零 error/warning。
  - iOS 工作流已改：编译 + test-build 验证，**不强制启动模拟器**（环境不稳）；XCTest 由真机/Xcode 手测。
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
- 通信：自建 WebSocket。**传输层改用系统原生 NSURLSessionWebSocketTask**（部署目标 iOS 26.2，SocketRocket 是 pre-iOS13 老库，无意义）；传输封装在 IMSocketManager 内部，接口不变，未来可无痛替换。心跳 25s + 指数退避重连 + ACK 超时重发。
- 工程用 Xcode 文件系统同步组（PBXFileSystemSynchronizedRootGroup）：往 IMProgram/ 加文件即自动入编译，无需手改 pbxproj。
- 依赖：CocoaPods（使用后改用 .xcworkspace 打开）。
- 类统一前缀 `IM`，ARC，4 空格缩进。
- 网络/IO/数据库调用必须有错误恢复分支。
- `xcuserdata` / `xcuserstate` 不再纳入版本控制。

## Next Actions
1. 真机/模拟器联调：`cd IMServer && go run ./cmd/imserver`，App 登录页填 host=本机IP:8080 / 我的 uid / 对方 uid，两端互发；可先杀掉一端验证离线→重连 sync 补偿。
2. 后续新增客户端逻辑时，往 IMProgramTests 加用例并按 CLAUDE.md 命令补跑（`-only-testing:IMProgramTests`）。
3. 接 IMDatabase（FMDB）落库：消息 sending→sent 持久化、synced_conv_seq 持久化（替换当前内存位点）。
4. 后端（见 IMServer/current_task.md）：JWT 鉴权替换 ?uid=、errcode 包 + HTTP 登录接口。
