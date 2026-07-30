# iOS 日志规范

> 三端共同规则以 `../../IMServer/docs/LOGGING.md` 为准。本文只描述 IMProgram 的入口和操作方式。

## 统一入口

- App 启动由 `AppDelegate` 调用 `IMLogConfigure()`。
- 业务代码只使用 `IMLog.h`：
  - `IMLog` / `IMLogWithTag`
  - `IMLogHTTP`
  - `IMLogSocket`
  - `IMLogDatabase`
  - `IMLogUI`
  - 对应的 Debug/Warn/Error 宏
- 禁止业务代码直接调用 `NSLog` 或 `DDLog*`。

新增模块优先复用已有 Tag。只有职责明确且会长期存在的新领域才能新增 Tag，并同步更新本文、
`CODING_STYLE.md` 和测试。

## HTTP

- API 必须经过 `IMHTTPService` 的公共请求通道，不在业务层直接创建 `NSURLSessionDataTask`。
- 公共通道自动生成/透传 `X-Request-ID`，REQUEST/RESPONSE/ERROR 使用同一 `[req=…]`。
- 自动记录 method、path、status、duration、bytes 和安全正文。
- password/token/Authorization/cookie/phone/secret 始终脱敏。
- multipart、二进制、Data URI 只记录元数据；正文最多 16 KB。
- Debug 可记录脱敏后的业务正文；Release 隐藏业务正文及非 JSON 正文。

## WebSocket、数据库与 UI

- WebSocket 生命周期、重连、ACK 和协议异常使用 `IMLogSocket`；不打印 JWT 或完整聊天正文。
- 数据库失败使用 `IMLogDatabase`，包含操作和错误，不包含消息正文。
- 页面生命周期和交互诊断使用 `IMLogUI`；高频滚动/布局事件默认不记录。

## 输出与保留

CocoaLumberjack 同时输出到 Xcode 控制台和滚动文件：

- 单文件最大 5 MB
- 每 24 小时滚动
- 最多保留 7 份

日志文件路径会在启动 `CocoaLumberjack ready` 日志中打印。分享文件前仍需人工复核敏感信息。

## 新增日志检查

1. 是否使用了正确模块宏和级别。
2. 是否能用 `request_id`、`client_msg_id` 或 `conv_id` 与服务端对账。
3. 是否避免密码、token、手机号、消息正文和二进制泄漏。
4. 新增 HTTP 字段是否需要扩展 `IMHTTPLogFormatter` 的脱敏集合。
5. 是否为脱敏、Data URI、超长或 Release 边界补充 `IMHTTPLogFormatterTests`。

提交前可检查：

```bash
rg 'NSLog\s*\(|DDLog(Verbose|Debug|Info|Warn|Error)\s*\(' IMProgram IMProgramTests
```

除 `IMLog.h` 内部封装外，不应出现直接日志调用。
