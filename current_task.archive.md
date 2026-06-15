> ⚠️ 历史归档（只读，勿更新）。当前活快照见同目录 current_task.md；本文件只供考古。

---

# Current Task

## Status（2026-06-15 最新 ⑤：iOS 补 ↓N 跳转按钮 + 文档单一来源整顿）
- **iOS ↓N 悬浮跳转按钮**（对齐 Web，CHAT_UX §7/§9）：滚离底部出现、徽标显示下方未读/新消息数、点按回最新并清零、贴底自动隐藏；进会话停首条未读时预置计数（整屏放得下则不显示）；收消息改为"贴底才自动贴底，离底则累加 ↓N 不打断"。build/test-build 通过（零 warning），IMProgramTests 14 全绿。
- **为何漏掉 ↓N**：上轮做 Telegram 视觉细化时，只盯用户点名项，没按 CLIENT_PARITY **逐行 diff iOS↔Web**；而该表早已标 "↓N iOS ⬜"。→ 已在 `CLAUDE.md` 完成定义加"端对齐扫一遍"硬步骤防复发。
- **文档整顿**：CLIENT_PARITY 设为"功能×端"唯一状态源（ROADMAP 只记里程碑+日期、UI.md 只记视觉）；补齐 UI 细化/UX 行；标注端不对称（iOS 领先离线/落库/空洞自愈，Web 领先分页）；解释"ROADMAP M2✅ vs 表内 iOS⬜"差异（⬜ 的是独立 性能/UX 轨道、不计里程碑）。DEPLOY.md 修正 iOS 构建用 `.xcworkspace`、补自测项。
- **iOS 仍落后 Web 的真缺口**：双向分页 / 进会话最近一页（iOS 仍全量载入 DB）——属独立 `性能` 轨道，单会话上万条再排期。

## Status（2026-06-15 最新 ④：修复离线消息漏拉——③ 引入的回归）
**联调反馈**：Web(1001) 在 iOS(1002) 离线时发了 6 条，1002 登录后停在会话列表只收到了之后在线发的"7"，1–6 漏了。
- **根因（③ 的回归）**：③ 让会话列表常驻长连接并在网络层落库，但列表**没有 track/sync 会话**。于是登录后：离线的 1–6 仍在服务端离线表（只能靠 sync_req 拉）；在线发的"7"以 new_msg 直推并落库，把本地 conv_seq 位点**推过了 1–6 的空洞**；之后进聊天页从该位点同步 → 跳过 1–6。
- **修复（两层）**：
  1. **会话列表登记同步**：HTTP 拉到会话后，对每个会话以本地最大 conv_seq 为起点 `trackConversation:syncedSeq:`（每会话一次）→（重）连即 sync_req 补拉离线消息（`trackConversationsForSync`）。
  2. **空洞自愈（网络层兜底）**：`processIncomingMessage` 收到的 conv_seq 若跳过了已同步位点之后的中间段（conv_seq 连续分配，跳号=有漏），先用旧位点发 sync_req 补缺口，再推进位点。防住"实时消息抢先把位点推过空洞"的竞态。
- **验证**：build + build-for-testing 通过（零 warning）；IMProgramTests 14 全绿。
- **⚠️ 测试前提**：旧本地库里已有"空洞"（1–6 缺、位点已在其上），新逻辑只防新空洞、**不回填历史空洞** → **请先删除模拟器上的 App 重装**（清本地 im.sqlite）再测，否则旧洞仍在。
- **真机验证清单**：①1002 删 App 重装；②1002 退到登录（或杀进程）保持离线，1001 连发若干条；③1002 登录 → 停在会话列表片刻（让其 sync）→ 进会话，**离线那批应全部补齐、不漏**；④再让 1001 在线发新消息，照常实时到达。

## Status（2026-06-15 最新 ③：会话列表实时刷新 + 长连接常驻）
**联调反馈修复**：Web(1001)→iOS(1002) 连发 8 条，iOS 会话列表未读数不变，必须切 Tab 才更新。
- **根因**：socket 只在聊天页连接、离开即断开；会话列表无常驻连接，仅靠 `viewWillAppear` 的 HTTP 拉取刷新 → 停在列表收不到 new_msg。
- **修复（长连接提到 App/列表级常驻 + 通知广播）**：
  - `IMSocketManager`：收到任意消息时除 delegate 外**广播 `IMSocketDidReceiveMessageNotification`**（userInfo[`kIMConvIDKey`]）；`connectToHost` 改**幂等**（已连同 host+uid 则复用，避免列表/聊天页重复调用抖动）；**收到的消息在网络层落库**（`IMDatabase saveMessage`），不再依赖聊天页 delegate，杜绝「列表收到未入库→开聊天页漏拉」。
  - 会话列表：`viewWillAppear` 连接 socket 并订阅通知 → 收到新消息**节流 0.4s reload**（在屏才刷）；`viewWillDisappear` 退订。
  - 聊天页：离开**不再 disconnect**（连接常驻供列表持续收消息），仅交还 delegate。
- **验证**：workspace build + build-for-testing 通过（零 warning）；IMProgramTests 14 用例全绿。
- **真机验证清单**：①停在会话列表，对端连发多条 → 未读数/最后一条**实时更新**（不必切 Tab）；②停列表收到消息后开该会话 → 消息齐全（不漏）；③聊天页正常收发/已读不受影响。
- **已知限制**：presence/typing 仍在聊天页（标题）维度处理；列表不显示在线点（后续可同法用通知广播 presence）。

## Status（2026-06-15 最新 ②：Telegram UI 细化第二版 + M1 文档校正）
**本次完成（iOS UI）**：照用户选定方向「对齐截图：浅色气泡 + 绿勾」做 Telegram 绿主题细化——
- **气泡配色重做**（IMTheme 动态色，深色自动适配）：自己=浅绿底(深色暗绿)、对方=白底(深色暗灰)，文本统一主色；**已读双勾绿 ✓✓**、已送达灰单勾、时间灰小字（attributedText 分段着色），行内右下角占位逻辑保留。
- **聊天壁纸**：新增 `IMChatBackgroundView`（绿渐变 CAGradientLayer + 低透明 SF Symbol 涂鸦平铺图，深色切暗绿），设为 tableView.backgroundView。**注**：未用 Telegram 真涂鸦 .tgv 资源（仓库内为下载态矢量，非可直接复用 PNG）→ 用 CG 自绘 SF Symbol 平铺图近似。
- **消息按时间分组**：气泡 cell 顶部加居中日期胶囊（今天/昨天/M月d日/yyyy年M月d日）；逻辑入 IMTheme（`isMillis:sameDayAsMillis:`、`dayHeaderStringFromMillis:`），配单测。
- **长按消息菜单**：UIContextMenu（复制 / 删除）；删除=仅本端（IMDatabase 新增 `deleteMessage:`，从库+内存移除并刷新，不影响对端），配单测。
- **会话列表已读双勾（真已读态，本次补全）**：「我发的最后一条」时间左侧——**对端已读到该条→绿 ✓✓**，否则→**灰单勾 ✓**（已送达/未读）。判定用**后端新增字段** `peer_read_seq`：
  - 后端 `internal/conversation` Summary 加 `PeerReadSeq`（单聊取对端 `store.ReadPosition`，群聊 0），`GET /conversations` 返回；配 `TestPeerReadSeq`，`./scripts/test.sh` 全绿。
  - iOS `IMConversation` 解析 `peer_read_seq`；列表 cell 据 `latestConvSeq<=peerReadSeq` 切绿✓✓/灰✓。
- **验证**：iOS workspace `build` + `build-for-testing` 通过（**零 error/零 warning**）；iPhone 16e 模拟器 `IMProgramTests` **14 用例全绿**（含 testSameDayGrouping / testDayHeaderString / testDatabaseDeleteMessage + 扩充 testConversationParsing 含 peer_read_seq）。后端 `./scripts/test.sh` 全绿（含 conversation 包 TestPeerReadSeq）。
- **⚠️ 改了后端：用户需重启后端**（`cd IMServer && go run ./cmd/imserver`）再测，运行中的旧进程不会热更新 `/conversations` 的新字段。
- **真机验证清单（交用户手测）**：①聊天页绿壁纸+涂鸦观感；②浅色气泡+深色字、已读 ✓✓ 变绿/已送达灰单勾；③跨天聊天出现日期胶囊（今天/昨天/M月d日）；④长按气泡弹「复制/删除」，删除后该条消失且重进不再出现；⑤会话列表我发的最后一条显示绿 ✓✓；⑥深色模式切换壁纸/气泡/勾均正常。
- **真机验证清单补充**：⑦会话列表「我发的最后一条」——对端已读时显示绿 ✓✓、未读时显示灰单勾 ✓（需后端重启 + 两端互发并让对端打开会话触发已读）。
- **已知限制/TODO**：壁纸为自绘近似（非 Telegram 原涂鸦）；Web 端绿主题/壁纸/日期分组/长按菜单/列表已读双勾尚未追平。

**M1 阶段是否全部完成？（回答用户问题，已更新文档）**：**未完全**。M1 里程碑头部功能已达成（ROADMAP 记 ✅），但逐端**两项缺口**：①真账号/密码登录——后端 ✅，**iOS/Web 仍免密直签 uid**（⬜）；②多端同时在线——后端 ✅，**客户端 UI/位点同步未验证**（⬜）。其余 M1 客户端项（会话列表、iOS 本地落库、真 Web 客户端）此前文档滞后标 🚧，**本次已校正为 ✅**。已同步更新 `CLIENT_PARITY.md`（矩阵 + 诚实记录段）、`ROADMAP.md`（M1 客户端追平缺口）、`UI.md`（Telegram 细化第二版状态）。两项缺口随 M2.5 账号/登录改造补。

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
**✅ M2 真机验证通过（2026-06-15，iPhone 16e 模拟器）**：会话列表 / 进聊天 / 已读双勾(✓✓) / seq 正确显示均 OK。
**✅ Telegram 视觉对齐（第一版，2026-06-15）**：参照 Telegram iOS 重做界面（详见 `../IMServer/docs/UI.md` 的"Telegram 视觉对齐"节）——
  - 会话列表自定义 cell：圆形彩色头像(uid 末两位 + `avatarColorForSeed`) + 名称/最后一条 + 右上时间 + 右下**蓝色未读胶囊**；行高 76，分隔线缩进对齐文字。
  - 聊天气泡重做：真气泡容器(非 UILabel 空格 padding)，圆角 18 + **尾巴**(maskedCorners)，文本 17pt，**气泡内右下角**时间 + ✓/✓✓。
  - 输入栏：圆角胶囊输入框 + 圆形蓝色发送按钮(arrow.up.circle.fill)。
  - 气泡 meta(时间+✓/✓✓)改为**行内右下角**(文本末尾补 NBSP 占位预留位)，不再单独一行显散；**自己发送补本地时间戳**(之前缺 → 只剩孤零零 ✓✓)。勾为白色半透明(非绿)。
  - **待办**：聊天壁纸、按时间分组/日期分隔、长按菜单、头像渐变、群头像；会话列表未读蓝胶囊已实现(unread>0 才显示)。
**✅ 登录默认 host 修复（2026-06-15）**：模拟器恒用 `localhost:8080`（不怕 Mac DHCP 换 IP）；真机记住上次地址（NSUserDefaults）。
**下一步：M2.5 通讯录/加好友/找人。**

## Status（iOS 既有，M1-5）
客户端：登录 → **会话列表（TabBar 会话/我）** → 聊天 三段式（M1-5b）+ **本地落库 IMDatabase（M1-5c：秒显历史 + 断点续传）**。
栈：IMSocketManager（重连同步 + JWT + trackConversation:syncedSeq:）+ IMHTTPService（登录/会话列表）+ IMConversation + IMTheme(tokens) + **IMDatabase（FMDB + SQLite）**。
默认 host：模拟器 localhost:8080、真机记上次（见上"登录默认 host 修复"）。
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
