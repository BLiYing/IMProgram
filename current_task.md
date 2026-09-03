# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

> **安全整改第 1 步：服务器地址协议收口 + 媒体外站 URL 白名单（2026-09-03；`./scripts/test.sh` 全绿 395/395；**未手测**）**
>
> 背景：`/security-review` 全仓审计报了 3 条（明文 HTTP / WS 明文且 token 在 URL / 发送方可控 URL 被零点击拉取）。
> 与后端商定的整改分 5 步（顺序见 `../IMServer/current_task.md`），**本次是第 1 步，且不引入 HTTPS**——
> 真域名与云服务器到位后再切，切换时客户端不需要改代码。
>
> 1. **新增 `IMServerEndpoint`（`Common/`）= 全 App 唯一的 scheme 权威**。此前 `http://`/`ws://` 以字面量散在
>    5 处（`IMHTTPService.urlForPath:` / `IMSocketManager` 建连 / `IMMediaUtil` / `IMChatRecordViewController`
>    的一份拷贝 / `IMRemoteLogSink`），"换 https"等于跨 5 文件改代码 + 发版。现在四路共用一处，
>    **登录页填 `https://im.example.com` 即整端切换**（http↔ws、https↔wss 成对，不会出现"网页加密了长连接还明文"）。
>    scheme 随 host 存进 `IMSessionStore`（`im_session_scheme`），冷启动在任何网络调用前恢复；
>    「上次地址」回填也带协议，否则填过的 https 下次静默退回 http。
>    **协议永不从服务端下发**（要先选协议才连得上；明文信道问"要不要 https"就是降级攻击）——理由写在头文件里。
> 2. **`IMMediaFullURL` 改为拒收外站绝对 URL**（漏洞 3 闭环）。`content`/`avatar_url` 是发送方可控且服务端原样
>    存转的字段，图片又默认自动下载 → 对方发一条消息、或只把头像设成 `http://attacker/beacon.png` 再出现在
>    你的搜索结果里，客户端就零点击发 GET，泄露 IP、粗粒度位置与精确的「已查看」时刻。现在只放行本服务器
>    （`IMServerEndpoint.isOwnHost:forAbsoluteURL:`，主机名不分大小写、**端口从严**、拒 userinfo），
>    自家的存量 `http://` 绝对地址按当前 scheme 重拼。外站图**唯一**合法场景是链接预览 OG 图，
>    显式走新函数 `IMLinkPreviewImageURL`（仅 `IMLinkCardCell` / `IMLinkPreviewView` 两处）。
> 3. 顺带：`IMChatRecordViewController.fullURLFor:` 那份逐字拷贝删掉，改调统一入口；
>    旧判据 `hasPrefix:@"http"` 收紧成 `http://`/`https://`（原来 `httpfoo:` 也算数）。
>
> 新增 `IMProgramTests/IMServerEndpointTests.m`（16 条：输入解析 / ws-wss 成对 / 自家主机判定 / 外站拦截）。
> **本步没做**：ATS 仍是全局 `NSAllowsArbitraryLoads`（第 4 步随 TLS 一起收窄）；WS token 仍在 query 串（第 3 步）；
> 明文密码仍存 `NSUserDefaults`（第 5 步）。
>
> **第 3 步同批（2026-09-03）：WS token 移出 query 串** —— `openSocketWithToken:` 改用
> `webSocketTaskWithRequest:` 并带 `Authorization: Bearer <jwt>` 头（`webSocketTaskWithURL:` 只收 URL，
> 结构上带不了自定义头）。URI 里的凭据会被沿途反向代理 / 网关 / CDN 写进访问日志。
> 后端 `gateway/client.go` 的 `handshakeToken` 两条并存（`?token=` 留给浏览器——浏览器 WebSocket API
> 设不了请求头），**故本端改动不需要后端同版本才可用**，但仍需重启后端才生效。
>
> **待真机手测**：登录页填裸 `host:port` 应与改前完全一致；长连接能连上（会话列表出现"已连接"）；填 `https://…` 应连不上（后端尚未开 TLS，属预期）；
> 聊天图片/头像/群头像/收藏/记录卡照常显示；链接卡片的外站预览图仍能出图。

> **三项：搜索 pill 直接开会话 + 合并转发标题口径 + 条目 `u` 匿名化（2026-08-31，与 Web 同步；
> `./scripts/test.sh` 全绿，`IMProgramTests` 320/320；**未手测**）**
>
> 1. **「请返回聊天页后再搜索」改成直接开会话** —— `IMChatDetailViewController+Actions.m` 的搜索 pill
>    原先要求导航栈里已有本会话的聊天页，取不到就吐司。而最常见的触发正是**从群成员头像点进来的
>    单聊资料页**——那个单聊压根没打开过，必吐司。那句话是把实现约束（栈里没有这一页）甩给用户，
>    旁边的「消息」pill 明明就能开会话。现新增 `openChatForInChatSearch`（群/单聊分派，与「消息」pill
>    同一个统一入口），取不到就开会话，转场落定后 `beginInChatSearch`。
> 2. **合并转发卡片标题收敛到微信口径** —— 原先写 `IMConversationPublicName`，群聊时**就是真实群名**，
>    发给了往往不在群里的收件人；Web 那侧则按条目发送者数量推，两端分叉。现共用纯函数
>    `IMChatRecordTitle`（`IMChatMessageLogic`）：群聊固定「群聊的聊天记录」（**不写群名**）、
>    单聊「{对方公开名}和{我的公开名}的聊天记录」，缺名逐级降级到「聊天记录」、绝不回落内部 ID。
>    **顺带补了一个此前没有的东西**：App 里没有"我叫什么"的进程内缓存（只有设置页/资料编辑页各拉一次
>    自用），而打包 JSON 是同步的等不了网络。故 `IMHTTPService` 加 `currentNickname`——登录成功后异步
>    预热一次（已有值就不重拉，避免 10min token TTL 重登时反复请求）、`invalidateToken` 一并清（换账号
>    不能顶着旧名字）。取的是 `card.nickname` **不是 `displayName`**（后者是"备注优先"，备注不能外流）。
>    **允许为空**：空则标题降级成「对方的聊天记录」。
> 3. **条目 `u` 改成卡片内匿名序号 `s1/s2`**（`IMRecordSenderKeysForUIDs`，`IMMediaUtil`）——
>    原本发的是发送者真 10 位内部 ID，随卡片到了可能不在群里的收件人手上，而 `GET /users/{id}`
>    只校验「持有合法 token」、不校验关系，随机 10 位 ID 的不可枚举是那个接口唯一的防线。
>    **读端零改动**（`IMRecordSenderKey` 本就只做相等比较，存量卡片里的真 uid 自然兼容）；
>    只把 `IMChatRecordViewController` 的头像色种从 `uid` 换成名字（匿名序号当色种没意义）。
>    契约见 `../IMServer/docs/PROTOCOL.md`「合并转发卡片（chat_record）的条目结构」。
>
> **未手测**；后端同批加了显示名字符清洗（`internal/textguard`），iOS 侧无需配合改动。


> **iOS 回归有唯一入口了：`./scripts/test.sh`（2026-08-31）** —— 与后端 `IMServer/scripts/test.sh` 对称。
> 起因：之前每次手拼 xcodebuild 命令行，反复踩三个坑（跑整 scheme 被 UITests 拖死 135s+37s、
> 并行 clone 抢 CPU 压出偶发失败、失败原因只有一句 `** TEST FAILED **`）。脚本把三条写死：
> `-only-testing:IMProgramTests` + `-parallel-testing-enabled NO` + `-resultBundlePath` 配 `xcresulttool`
> 直接打「哪条用例 + 断言原文」；另固定 `-derivedDataPath build/DerivedData`，模拟器自动挑最新 iOS 的 iPhone
> （写死名字换机就报 destination 找不到）。`BUILD_ONLY=1` 只编译、`ONLY=<类|类/用例>` 只跑一部分。
> **实测：全量 314 例绿，3 分 10 秒**（含冷编译）；那条 `IMMediaPlaceholder` 偶发失败在串行模式下没再出现。
> 用法与三条理由写进了 [CLAUDE.md](CLAUDE.md)「构建 / 测试」与「完成的定义」。

> **无其它进行中的开发项。** 网络恢复秒连（2026-08-30）与 `UI_COLOR.md` 收敛已完成，细节转入
> `current_task.archive.md`。仍**未做**的是「下一步」里那两件老账：真机手测语音 P1 与相机录像
> （模拟器没有摄像头/麦克风，只能真机验）。

## 下一步
1. **先验真机能否连通后端**：重装 App → 弹「允许查找并连接本地网络设备」点允许 → 登录页填 Mac 当前 LAN IP，
   免密/密码登录现在都会真发请求，失败会直接显示「无法连接服务器…」；Mac 侧核对 `grep -a '"remote_ip":"192.168' ../IMServer/imserver.log | tail`。
2. **真机手测回归（重启后端后）**：按住大圆钮跟手→上滑磁吸锁定→锁定行删/停/发；来电中断→回来停在锁定暂停；发送后长按有菜单、气泡稳定；转发语音真的送达；详情页语音 tab；收藏语音播放 + 从收藏发送；scrub/倍速/转文字/接力。异常记回本文件。
3. 遗留 P2：听筒切换（贴耳切 route）；接力连播顶部「停止」控制条；Web 转文字（Whisper 调研）；
   **语音发送接入 IMMediaSendService 常驻队列**（现为 VC 内手工链：已强持有 self 保住"退出页不丢消息"，
   但仍无上传进度/取消，上传失败即删录音无 failed 行）；Web 语音上传期无回显（对齐 useMediaSend 先回显后上传）；
   Web 收藏/气泡语音 404 失效占位（复用 MEDIA_EXPIRY）。中断 vs 手势取消的系统投递顺序仍是赌注
   （多数机型触摸先取消→行为=自动发送，通知先到→锁定暂停；根治需 recorder interrupting 窗口标志）。
4. `setupUI` 抽 `IMComposerBar`（老欠账）；「从收藏发送」入口开放（见「已知坑」）。
5. **拆 `IMProgram/Network/IMSocketManager.m`（1566 行，已在体量门禁登记欠账，上限 1600「只准降不准升」）**：
   方向按 CODING_STYLE §7 三档——帧编解码 / 重连退避 / 各业务 send-recv 分组各自成协作对象或 category。
   同批还有三个 WARN 逼近 1500：`IMHTTPService.m` 1460、`IMDatabase.m` 1453、`IMChatDetailViewController.m` 1466。

## 已知坑 / 限制
- **撤回消息的「重新编辑」可能在重拉后消失（2026-09-03 评估后刻意不修）**：服务端本轮安全修复起，
  撤回 / 「为所有人删除」的**正文不再随 `sync_resp`/`window_resp` 下发**（原文只留服务端库内供审计）。
  而 `IMDatabase writeIncomingMessage` 的 UPDATE 里 `content=?` 是**无条件覆盖**的——`file_name`/`thumb`/
  `waveform`/媒体尺寸时长都有 `CASE WHEN LENGTH(?)>0` 保值，唯独 content 没有。于是撤回后那一段若被
  重新拉过（上翻触发 `window_resp`、或从更低游标 sync），本地正文被空串盖掉，`IMSystemCell` 的
  「重新编辑」按钮（判 `m.content.length > 0`）随之消失。**不崩、不出空输入框，纯优雅降级。**
  不修的理由：① 该按钮真实使用窗口是撤回后几秒，那时人贴着底、不会触发重拉；② 一刀切给 content 加保值
  会**同时让「为所有人删除」的正文在本地长期留存**，与该功能语义相悖，要避开就得在热路径 UPSERT 里
  区分 recalled/deleted 两种空值来源；③ 微信的重新编辑本就是「刚撤回那一刻」的能力，而**本端这个按钮
  至今没有时间限制**（一年前撤回的还能重编），服务端脱敏反而把它往正确方向推了一点。
  真要保住它，正确做法是**撤回时把原文另存为「待重编辑草稿」**（按会话存、发出或超时即清），
  而不是给 DB 加保值。服务端侧同一条记在 `IMServer/current_task.md`「已知坑」。
- **`IMMediaPlaceholderTests testFrostedLandscapeScalesLongestSideTo48` 在高负载下会偶发失败**（2026-08-30 首次观察；
  2026-08-31 起**基本被 `scripts/test.sh` 规避**）：只在**并行 clone + 同时跑 UITests** 时复现——
  该用例作为某个 clone 上的第一条执行、耗时 9.5s（正常 2.7s）后失败。`scripts/test.sh` 写死了
  `-only-testing:IMProgramTests` + `-parallel-testing-enabled NO`，两个诱因都没了，314 例稳定绿。
  **根因仍未定位**（用例本身对时序敏感），若哪天在串行模式下也复现，请抓 XCTAssert 原文再查。
- **`runAfterKeyboardHidden:` 兜底待测（2026-08-05 记）**：依赖 `resignFirstResponder` 后必然收到 `UIKeyboardDidHideNotification`——软键盘正常成立；若实测硬件/外接键盘场景引用跳转不触发，加 `dispatch_after` 超时兜底。
- 相册导出期杀 App 消息消失（PHPicker 句柄一次性，属预期，微信同）；导出失败的行点 ↻ 提示副本丢失需重选。Files 面板 <8MB 小文件、相机**拍照**、粘贴图仍为 VC 锚定一次性上传（秒级；粘贴图已带预览条攒批）；
  相机**录像**已改走 `IMMediaSendService` 常驻队列（2026-08-29）。
- iOS 无双向分页（进会话全量载入本地 DB）；presence/typing 仅聊天页标题生效。dev-login 建的账号无法再走密码登录（测密码登录用「注册并登录」或清 `imserver.db`）。
- **查看器"正在播放中"视频 404 未接失效占位（2026-08-11 记）**：`IMMediaViewerViewController` 有 `item.status` KVO 但失败一律走「无法播放该视频」兜底，未把 404/410 翻 ⊘。窄路径（气泡/媒体库通常先探到→进查看器即短路），兜底不黑屏故可接受。补法：失败分支走 `IMMediaExpiryRegistry verifyExpiredForURL:` 定性→失效覆盖层 + mid-play teardown。
- **失效标记内存态不持久（刻意，2026-08-11 记）**：`IMMediaExpiryRegistry` 用进程内 Set，冷启动首帧重探一次换自愈；仅当服务端上自动 TTL 清理使失效变常态才上持久化。
- **系统按钮文案本地化（2026-08-12 修，未编译验证）**：`Info.plist` 补 `CFBundleLocalizations=[zh-Hans,en]` 让 QLPreview「Done」/UISearchBar「Cancel」等系统文案落中文；自有 UI 硬编码中文，将来做真·多语言再建 `.lproj`。
- **原图路径 JPEG 字节戴 `.heic` 帽子（2026-08-12 记，暂不改）**：`IMMediaPicker buildImageItem` 原图分支按 `UTTypeImage` 取字节（iOS 可能把 HEIC 转 JPEG 交付）但扩展名靠 `hasItemConformingToTypeIdentifier:UTTypeHEIC` 猜 → JPEG 内容 + `.heic` 名错配。Web 靠字节嗅探已能各自正确显示故非阻塞；计划换第三方相册选择器（任务4）后此坑自消。
- 测试只跑 `-only-testing:IMProgramTests`；改后端协议后需重启后端再测。
- **体量门禁曾有覆盖盲区（2026-09-01 修）**：`scripts/check-file-size.sh` 原先只 `find IMProgram/Modules
  IMProgram/Common`，`Network`/`Database`/`Models`/`App` 整片在视野外，`IMSocketManager.m` 因此悄悄涨到
  1566 行没人拦。现扫整个 `IMProgram/`（测试 target 是它的兄弟目录，天然不在范围内）。
  **教训**：机械护栏本身也要有人核对覆盖面——"门禁全绿"只说明它扫过的那部分绿。
- **聊天页「从收藏发送」入口暂屏蔽/暂不支持（2026-08-19）**：`IMChatViewController` `attachItemTapped:` 的 `favorite` 分支仍走 `im_showComingSoon`（等效屏蔽）。设计已保留（`../IMServer/docs/FAVORITES_DESIGN.md` §5.5 标 ⏸），待收藏改造统一放开并接卡片式收藏选择器。

## 关联工程 / 常用命令
- 后端 `/Users/liying/IOSProject/IMServer`；Web `/Users/liying/IOSProject/im-web`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 测试编译 + 实跑：`xcodebuild build-for-testing ...` → 有 booted 模拟器则 `test-without-building ... -only-testing:IMProgramTests`。
- 真机日志：`xcrun devicectl device copy from --device iPhoneWork --domain-type appDataContainer --domain-identifier com.libeyond.IMProgram --source "Library/Caches/Logs/<file>.log" --destination <dst>`（list 用 `device info files`；崩溃报告 `--domain-type systemCrashLogs`）。
- 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
