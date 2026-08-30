# iOS 长连接重连机制

> **跨端共同口径以 `../../IMServer/docs/RECONNECT.md` 为准**（三态、退避参数表、唤醒判据、
> 鉴权失败与网络失败的分野、不变量清单、手测口径）。本文只写 IMProgram 的落点与 **iOS 特有**的坑。

## 1. 落点

| 关注点 | 位置 |
|---|---|
| 连接与重连主体 | `IMProgram/Network/IMSocketManager.m`——`openSocket` / `handleDisconnect:authRejected:` / `scheduleReconnect` |
| 退避常量 | 同文件顶部 `kIMReconnectBase=1.0` / `kIMReconnectCap=30.0`；心跳 `kIMPingInterval=25.0` |
| 唤醒判据（纯函数） | `IMSocketManager.h` 的 `IMSocketWakeActionFor(state, manualClose)` → `None`/`Reconnect`/`Probe` |
| 唤醒入口 | `-[IMSocketManager reconnectNowWithReason:]`（幂等，随便多调） |
| 信号①网络恢复 | `Network/IMNetworkMonitor.m` 广播 `IMNetworkDidBecomeReachableNotification`，**由 `IMSocketManager` 自己订阅**（`init` 里注册） |
| 信号②回到前台 | `SceneDelegate.m` 的 `sceneWillEnterForeground:` 调 `reconnectNowWithReason:@"foreground"` |
| 单测 | `IMProgramTests/IMSocketWakeActionTests.m`（4 例，钉三条"不该做"） |

所有连接操作都在 `IMSocketManager` 的串行队列 `_queue` 上执行；`reconnectNowWithReason:`
自己 `dispatch_async` 进队列，调用方在任意线程调都安全。

## 2. `IMNetworkMonitor` 为什么只报一种跃迁

这个监视器（`nw_path_monitor`）本来就在跑，原先只服务「自动下载用 Wi-Fi 档还是蜂窝档」的判断，
**从不通知任何人**。现在只在**不可达 → 可达**那一刻广播一次：

- **Wi-Fi ↔ 蜂窝互切不广播**：那条路径本就没断，重连只会白掉一次线。真断了系统会先给一帧
  `unsatisfied`，届时自然走本分支。
- **首帧不广播**：`_currentType` 初值乐观地取 Wi-Fi（避免冷启动误伤自动下载），因此启动时的第一帧
  `satisfied` 不构成跃迁，冷启动不会多打一次重连。
- handler 已在主队列，通知同步发出。

## 3. iOS 特有的坑

- **后台挂起**：App 进后台后系统会挂起 socket，多数情况下回到前台时连接其实已经死了、但本端
  状态还停在 `Connected`。所以回前台走的是 **probe**（发一次 ping）而不是重连——ping 写失败
  会走既有断线路径，那时失败次数已归零，1s 即重试。别改成"回前台一律重连"，那会把每次切前台
  都变成一次真断线。
- **鉴权被拒的判定时机**：`isAuthRejectedTask:` 读的是**握手的 HTTP 响应码 401**，而
  `didCompleteWithError:` 才是拿到该响应最可靠的时机。注意服务端强制踢当前活连接是 **WS close**
  （握手早已 101，`authRejected=NO`，不会误判）；401 只出现在随后"拿被吊销 token 重新握手"的那次重连上。
- **401 之后必须停重连**：`_manualClose = YES` + 发 `IMSocketDidRevokeSessionNotification`，
  由 `SceneDelegate` 清登录态回登录页。否则 `loginWithUserID` 的 **10 分钟 token 缓存** + 稳定
  `device_id` 会让"被踢下线"退化成 ≤10min 的伪自愈（2026-08-13 修）。
- **连接代次 `_connectionGeneration`**：`openSocket` 每次 `++`。在途的退避定时器、登录 HTTP 回调、
  WS 回调都捕获了自己那一代，到点发现代次不符即自行作废——所以 `reconnectNowWithReason:`
  **不需要**手动取消旧定时器，直接 `openSocket` 即可。
- **`watch` 重发在页面层**：Web 由 SDK 自己记住订阅集在 `onopen` 重发，iOS 是
  `IMChatViewController+Socket.m` 的 `didChangeState:` 收到 `Connected` 后重发
  （`updatePeerWatch:`）。都满足 PROTOCOL §5.5，但改的时候别按错层找。
- **页面级的"连上就刷一次"** 另有共用件 `Network/IMReconnectReloader.h`：宿主 VC 持有它、
  在 `viewWillAppear/Disappear` 更新 `visible`，连接恢复且页面可见时取一次权威数据。
  它与本文的重连是两层——重连负责"连回来"，它负责"连回来之后把这一页的数据刷新"。

## 4. 排查

日志 Tag 为 `IM.SOCKET`（`IMLogSocket`）。关键行：

| 现象 | 搜什么 |
|---|---|
| 排到第几档、等多久 | `reconnect in %.1fs (attempt N)` |
| 唤醒信号有没有到、做了什么 | `wake(network_reachable)` / `wake(foreground)` |
| 网络跃迁有没有被识别 | `网络恢复可达 type=` |
| 是不是被踢了 | `disconnected: … [鉴权被拒 401 → 跳登录页]` |

手测口径（断够 40 秒再恢复，否则看不出差别）与反例（退出登录后不得自动连回）见跨端主文档 §7。
