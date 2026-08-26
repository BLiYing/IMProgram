# IMProgram 架构设计

## 技术选型
- 语言：Objective-C（ARC），必要时混编 Swift
- 通信：**自建 WebSocket 长连接**
- 依赖管理：**CocoaPods**
- 本地存储：SQLite（FMDB / WCDB）+ NSUserDefaults（轻量配置）
- 日志：**CocoaLumberjack 3.9.x**（控制台 + 5 MB 滚动文件，最多保留 7 份）
- UI：UIKit，纯代码 + AutoLayout（Masonry）
- 外观：`IMAppearance`（本地偏好/通知/模式）→ `IMTheme`（语义令牌）→ 页面；规范见 `docs/UI_COLOR.md`

## 候选三方库（CocoaPods）
| 用途 | 库 |
|------|----|
| WebSocket | `SocketRocket`（成熟稳定）或 `Starscream`(Swift) |
| 网络 HTTP | `AFNetworking` |
| 日志 | `CocoaLumberjack`（已采用） |
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

### IMMediaSendService（常驻媒体发送队列，2026-08-03 重构）
- **动因**：媒体发送（转码 → 落盘 → 上传 → poster → socket 发送 → ack 落库）此前整条链路的回调锚在
  `IMChatViewController`（weak self）——转码期退出会话 = 字节未落盘、消息未落库、彻底消失；上传完成时无页面 = 永远发不出去。
- **职责**：把整条链路托管到**常驻单例**，脱离聊天页生命周期。进度/预览字典也归服务（key=`clientMsgID`），
  页面只 `enqueue` + 订阅通知渲染；重进会话 `reattachRunningUploads` 合并服务实例（未落库的转码窗口也可见）。
- **配套**：`IMChunkedUploader`（≥8MB 分片、暂停/续传、旁挂 `upload_id` 支持杀进程续传）；`IMPendingMediaStore`
  （字节落 Application Support，失败件可见/可重试）；重 IO（写盘/poster 编码）走服务的串行 IO 队列，不占主线程。
- **未并入**：相机拍摄、粘贴图、<8MB Files 路径仍为 VC 锚定的一次性上传（小而快，风险低）。
  **语音**同为 VC 锚定（`IMChatViewController+Voice.m im_uploadAndSendVoice:`）——上传块强持有 self
  保住"松手立即退出会话，链条仍能发出"，失败字节落 `IMPendingMediaStore`（`im-pending://`，跨进程可重试）；
  进程在上传中途被杀会遗留 `content=""` 的永久 Sending 空气泡，`reattachRunningUploads` 在冷启动首次
  进会话时把它扫成 Failed（`didReclaimStaleVoiceSending` 守卫每 VC 只做一次）。完整并入 IMMediaSendService 记 P2。

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
