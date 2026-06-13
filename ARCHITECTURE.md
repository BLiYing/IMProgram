# IMProgram 架构设计

## 技术选型
- 语言：Objective-C（ARC），必要时混编 Swift
- 通信：**自建 WebSocket 长连接**
- 依赖管理：**CocoaPods**
- 本地存储：SQLite（FMDB / WCDB）+ NSUserDefaults（轻量配置）
- UI：UIKit，纯代码 + AutoLayout（Masonry）

## 候选三方库（CocoaPods）
| 用途 | 库 |
|------|----|
| WebSocket | `SocketRocket`（成熟稳定）或 `Starscream`(Swift) |
| 网络 HTTP | `AFNetworking` |
| 布局 | `Masonry` |
| 数据库 | `FMDB` 或 `WCDB` |
| 图片 | `SDWebImage` |
| JSON 模型 | `YYModel` / `MJExtension` |

## 分层架构（自下而上）

```
┌─────────────────────────────────────────┐
│  Presentation 表现层                       │
│  ViewControllers + Views（仅 UI 与交互）     │
├─────────────────────────────────────────┤
│  ViewModel / Logic 逻辑层                  │
│  会话列表、聊天、联系人等业务逻辑                │
├─────────────────────────────────────────┤
│  Service 服务层                            │
│  IMSocketManager（长连接收发/重连/心跳）       │
│  IMMessageService（消息发送/接收/状态）        │
│  IMSessionService（会话管理）                │
│  IMHTTPService（登录/历史/上传，AFNetworking） │
├─────────────────────────────────────────┤
│  Data 数据层                               │
│  IMDatabase（FMDB）+ Model（YYModel）        │
└─────────────────────────────────────────┘
```

## 核心模块职责

### IMSocketManager（长连接核心）
- 建立/维护 WebSocket 连接，封装 SocketRocket
- **心跳**：定时 ping，超时判定断线
- **重连**：指数退避自动重连（含网络状态监听）
- **收发**：发送队列 + 接收分发，所有回调切回主线程
- 错误恢复：每次发送有 ACK 超时与失败回调，不吞错

### IMMessageService
- 消息发送：本地落库（status=sending）→ 经 socket 发送 → 收到 ACK 更新 status=sent
- 消息接收：解析 → 落库 → 通知 UI（去重，按 msgId）
- 失败重发、已读回执

### IMDatabase
- 表：`message`、`session`、`user`
- 所有 IO 调用包裹错误处理，失败有降级/重试

## 消息收发数据流
```
发送：UI → MessageService → 落库(sending) → SocketManager → 服务器
                                              ↓ ACK
                                         更新状态(sent) → 通知 UI

接收：服务器 → SocketManager → MessageService → 落库 → 通知 UI(回执)
```

## 目录结构（计划）
```
IMProgram/
├── App/                 # AppDelegate / SceneDelegate
├── Common/              # 常量、宏、分类、工具、日志
├── Network/             # IMSocketManager, IMHTTPService
├── Database/            # IMDatabase
├── Models/              # IMMessageModel, IMSessionModel, IMUserModel
├── Services/            # IMMessageService, IMSessionService
├── Modules/
│   ├── Login/
│   ├── Conversation/    # 会话列表
│   ├── Chat/            # 聊天页
│   └── Contacts/        # 联系人
└── Resources/           # Assets, Storyboard
```

## 消息协议（草案，JSON over WebSocket）
```json
{
  "type": "msg | ack | ping | pong | receipt",
  "msgId": "uuid",
  "from": "userId",
  "to": "userId | groupId",
  "contentType": "text | image | audio",
  "content": "...",
  "timestamp": 1700000000
}
```
> 后端协议需与服务端对齐，此处为客户端预期格式。
```
```
