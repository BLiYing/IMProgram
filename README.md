# IMProgram

IM 即时通讯 **iOS 客户端**（Objective-C）。与 Web 端功能对齐，后端为同级目录的 `IMServer`（Go）。

## 技术栈
- 语言：**Objective-C（ARC）**，必要时混编 Swift
- UI：UIKit，纯代码 + 原生 AutoLayout（当前不依赖 Pod；Masonry 等列在 Podfile 备用）
- 长连接：系统原生 `NSURLSessionWebSocketTask`（部署目标 iOS 15+，无需 SocketRocket）
- 本地存储：**FMDB + SQLite**（IMDatabase，M1-5c 落地）
- 依赖管理：CocoaPods（已引入 FMDB；**用 `IMProgram.xcworkspace` 打开**）

## 目录结构
```
IMProgram/
├── App/ (AppDelegate / SceneDelegate)   应用入口（代码设根控制器）
├── Common/      IMLog 日志宏等
├── Network/     IMProtocol（协议常量/会话id）、IMSocketManager（连接/登录/收发/心跳/重连/同步）
├── Models/      IMMessageModel（消息模型 + 状态机）
├── Modules/
│   ├── Login/   IMLoginViewController
│   └── Chat/    IMChatViewController（气泡/输入/发送态）
IMProgramTests/  IMProtocolTests（XCTest）
```
分层与设计见 [ARCHITECTURE.md](ARCHITECTURE.md)，代码规范见 [CODING_STYLE.md](CODING_STYLE.md)。
`IMSocketManager` 是 iOS 的"协议 SDK"雏形（对应 Web 的 `@im/sdk`），后续沉淀为 `IMKit`。

## 运行
1. 先起后端：`cd ../IMServer && go run ./cmd/imserver`（详见 [IMServer/docs/DEPLOY.md](../IMServer/docs/DEPLOY.md)）。
2. 首次：`cd IMProgram && pod install`；之后 Xcode 打开 **`IMProgram.xcworkspace`**（不是 .xcodeproj），选模拟器点 ▶。
3. 登录页 host：模拟器填 `localhost:8080`；真机填 Mac 局域网 IP（如 `192.168.1.3:8080`，需同一 Wi-Fi，注意 Mac 防火墙，见 DEPLOY.md §2.D）。

## 测试
只跑单测 target（跳过模板自带空 UI 测试，避免 Accessibility 超时）：
```bash
xcodebuild test -project IMProgram.xcodeproj -scheme IMProgram \
  -destination 'platform=iOS Simulator,id=<booted-udid>' -only-testing:IMProgramTests CODE_SIGNING_ALLOWED=NO
```

## 现状（进度详见 current_task.md / ../IMServer/docs/ROADMAP.md）
- ✅ JWT 登录换 token、1:1 收发、ACK、心跳、退避重连、重连增量同步、按 conv_seq 去重；真机端到端验证通过。
- ⬜ 会话列表页、本地落库（IMDatabase）、已读/未读、群聊等：按 ROADMAP 各阶段与 Web 端同步推进。

## 关联文档
- 协议：[../IMServer/docs/PROTOCOL.md](../IMServer/docs/PROTOCOL.md)
- 路线图 / 端一致性 / UI 蓝图：[ROADMAP](../IMServer/docs/ROADMAP.md) · [CLIENT_PARITY](../IMServer/docs/CLIENT_PARITY.md) · [UI](../IMServer/docs/UI.md)
