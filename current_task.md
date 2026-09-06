# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

> **通讯录 Tab 延迟修复 ✅ 2026-09-06**。切换到通讯录时延迟 0.5-1.5s（等待 HTTP 请求），因为
> `viewWillAppear` 每次都无条件调 `reload()`（登录 + 拉友列表）。改为**事件驱动**：
> - `reconnectReloader` 监听网络重连时刷新
> - `onFriendEvent` 监听 Socket 好友事件即时更新
> - 首次进入使用本地缓存种子（已在 init 加载），无需同步请求
> 
> 预期：Tab 切换响应 <100ms（从 500-1500ms 改善），与会话/设置切换流畅度对齐。
> 已提交 `7930087`。

> **建群两步流 ✅ 2026-09-05**（后端零改动）。原先是「选好友 →『创建』→ 弹一个 `UIAlertController`
> 输群名」；现在第一步按钮改「下一步」，第二步是 `IMGroupCreateViewController`：
> **群头像 / 群名（必填、预填「我、A、B」）/ 成员横条（可 ✕，不可删到 0）**。
> 头像随 `POST /groups` 的 `avatar_url` 一起发——**服务端一直有这一位，端上此前恒传空串**，
> 于是每个新群都得先建出来再进群管理页设图。设计稿见
> `../IMServer/docs/design/sketches/GROUP_CREATE_UX_SKETCH.html`。
>
> **顺带收敛的重复**：会话页 ＋ 菜单与通讯录群聊页**各有一份**「alert 输群名 + POST」实现（几乎逐字重复），
> 一并删掉，两处都改调 `+[IMGroupCreateViewController startInNavigationController:host:userID:onCreated:]`；
> 群管理页那个 90pt 头像头（原为该文件的私有类）提成 `Modules/Group/IMGroupAvatarHeader`，
> 加 `initial` 占位首字 + `applyAvatarImage:placeholder:caption:`，**群管理页行为逐字不变**。
>
> **三条值得记的**：
> ① **预填群名只能用公开名**：群名会发到服务端、进系统消息、显示给全群，用备注＝把私下称呼广播出去
>（同合并转发标题那次 P0）。故 `Common/IMGroupNameDefault` 只收 nickname/username/uid **三件套**，
> 不收 `IMUserCard`——免得有人顺手传"备注优先"的 `displayName`；我自己那一位取
> `IMHTTPService.currentNickname`（登录后预热的公开昵称，允许为空则跳过）。
> **成员横条上显示的名字仍认备注**（本机渲染），两者刻意分叉。
> ② **「＋ 添加」是 pop 回选好友页**（它还在栈上、勾选原样），所以 picker 的 `onDone` 必须分两支：
> 栈里已有建群页就 `updateMembers:` + `popToViewController:`，无脑 push 会**叠出第二份**建群页。
> ③ 群名按 **rune**（码点）计 30 字，与服务端 `len([]rune)` 同口径——不能用
> `ByComposedCharacterSequences`（那按字形簇算，一家四口 emoji 算 1，会放过服务端要拒的名字）。
>
> `IM_SIM="iPhone 17 Pro Max" ./scripts/test.sh` **415/415 绿**（新增 `IMGroupNameDefaultTests` 8 例，
> 与 Web `groupName.test.ts` 用例逐条对应）。
>
> **模拟器实测（用户点名要求）抓到一个 P0**：**注入式液态标题栏不监听 `navigationItem`**——
> 它只在 push/pop/present 关闭等时机由 `IMMainNavigationController syncBarForController:` 同步一次。
> 我改了 `rightBarButtonItem.enabled` 却没通知它：进页群名为空 → 栏上按钮同步成 disabled；
> 之后输入群名，`UIBarButtonItem.enabled` 已是 YES 而**栏上那颗按钮仍灰且点不动 → 建不出群**。
> 修法：`refreshCreateEnabled` 末尾调 `im_refreshNavigationBar`。**同一坑的另一面**：右上项
> 不能用 `initWithCustomView:` 塞菊花（注入栏只认 title/image，会让按钮整个消失），在途改为置灰。
> 另修：长群名把 12pt 计数挤成「25/…」→ 计数设 required 抗压缩、输入框让位。
>
> 实测跑通：两步流全程、**头像端到端**（选图→圆形裁切→上传→随建群发出→新群会话页右上与会话列表
> 都显示该图）、「＋添加」pop 回选好友页且再「下一步」回到**同一个**建群页、删成员重算预填名、
> 删到最后一位被拦、清空群名按钮置灰且头像圈回落相机。
> **未测**：那句「至少选择一位好友」toast（存活 1.9s、截图往返 ~2s 没拍到，但拦截行为已验证）、
> 头像上传超时 5s 与建群失败两支（要造网络故障）。
>
> **用户复测后再改两条（本轮按用户要求只编译、未启模拟器）**：
> ① **「＋ 添加」改成固定列**——原先它跟成员条一起横滚，人一多要先滑到头才能继续加人。
> 现用约束钉在 cell 右缘（`_strip.trailing = _addColumn.leading - space2`），成员条只占左边那段。
> ② **预填群名不再补「…」**：放不下的名字直接不要（`IMDefaultGroupName` 与 Web `groupName.ts` 同步改，
> 两端单测一起改）。理由是它是个**可改的候选名**而不是被裁短的完整名，末尾挂省略号既占掉一个可用字，
> 又会被头像圈的「取末两字」规则显示成「2…」。

> **上一批（2026-09-05，已提交 `e25ae08`）**：语音转文字撑高后把文字补进视口
>（记 `isNearBottom` → 贴底或 `ScrollPositionNone` 最小位移，`animated:NO` 免动画滚动每帧触发翻页）。只编译未跑模拟器。

> **已落地、细节转入 `current_task.archive.md`**（2026-08-30 ~ 09-03）：安全整改第 1/3/5 步
> （`IMServerEndpoint` 收口 scheme + 媒体外站 URL 白名单 / WS token 移出 query 串改 `Authorization` 头 /
> 明文密码换成可吊销的 `refresh_token`，含 `/code-review` 复查的 atomic 与 logout 两条）、
> 搜索 pill 直接开会话 + 合并转发标题口径 + 条目匿名化、回归唯一入口 `./scripts/test.sh`、
> 网络恢复秒连、`UI_COLOR` 收敛。
>
> **安全整改剩余**：第 2 步（服务端 TLS）与第 4 步（收窄 ATS `NSAllowsArbitraryLoads`）都要等真域名 +
> 云服务器到位，客户端届时不需要改代码（顺序见 `../IMServer/current_task.md`）。
>
> **无其它进行中的开发项。** 未做的都在「下一步」：真机连通性与语音 P1/相机录像手测
>（模拟器没有摄像头/麦克风，只能真机验）。

## 下一步
1. **先验真机能否连通后端**：重装 App → 弹「允许查找并连接本地网络设备」点允许 → 登录页填 Mac 当前 LAN IP，
   免密/密码登录现在都会真发请求，失败会直接显示「无法连接服务器…」；Mac 侧核对 `grep -a '"remote_ip":"192.168' ../IMServer/imserver.log | tail`。
2. **真机手测回归（重启后端后）**：按住大圆钮跟手→上滑磁吸锁定→锁定行删/停/发；来电中断→回来停在锁定暂停；发送后长按有菜单、气泡稳定；转发语音真的送达；详情页语音 tab；收藏语音播放 + 从收藏发送；scrub/倍速/转文字/接力。异常记回本文件。
3. **安全整改的真机手测（第 1/3/5 步落地后一直没验，细节见 archive）**：登录页填裸 `host:port` 与改前完全一致；
   长连接连得上（会话列表显「已连接」）；填 `https://…` 应连不上（后端未开 TLS，属预期）；
   聊天图片/头像/群头像/收藏/记录卡照常显示；链接卡片的外站预览图仍能出图；
   退出登录后那台设备从「已登录设备」列表消失（logout 已接）。
4. 遗留 P2：听筒切换（贴耳切 route）；接力连播顶部「停止」控制条；Web 转文字（Whisper 调研）；
   **语音发送接入 IMMediaSendService 常驻队列**（现为 VC 内手工链：已强持有 self 保住"退出页不丢消息"，
   但仍无上传进度/取消，上传失败即删录音无 failed 行）；Web 语音上传期无回显（对齐 useMediaSend 先回显后上传）；
   Web 收藏/气泡语音 404 失效占位（复用 MEDIA_EXPIRY）。中断 vs 手势取消的系统投递顺序仍是赌注
   （多数机型触摸先取消→行为=自动发送，通知先到→锁定暂停；根治需 recorder interrupting 窗口标志）。
5. **选好友页缺「全选」**（2026-09-05 记）：`IMFriendPickerViewController` 没有全选/取消全选，
   Web 建群第一步早就有（只作用于当前可见行 + 按上限截断 + 与已选取并集）。加的时候照抄 Web 那套口径，
   别只做「勾上全部候选」——搜索态下会勾到用户看不见的人。
6. `setupUI` 抽 `IMComposerBar`（老欠账）；「从收藏发送」入口开放（见「已知坑」）。
7. **拆 `IMProgram/Network/IMSocketManager.m`（1566 行，已在体量门禁登记欠账，上限 1600「只准降不准升」）**：
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
