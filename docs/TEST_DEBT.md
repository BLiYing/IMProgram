# iOS 单测欠账清单

> 2026-10-03 第 0 步摸底产出。**覆盖率数字是实测**（xccov）；各条候选的「风险 / 可测性」由只读子代理**读码判断**，
> 除标「已核实」的外**都没跑过、没复现**，动手前以源码为准。行号不写进文档，用「文件 + 符号名」定位。
> 不设数量目标：用例多 ≠ 覆盖好。纯界面（弹层、布局、动画、cell 配置）一律不补，本清单已剔除。

## 1. 覆盖率基线（`IMProgramTests`，746 例，2026-10-03）

整体 **21.8%**（11105 / 51044 可执行行）。

| 模块 | 可执行行 | 未覆盖 | 覆盖率 |
|---|---:|---:|---:|
| Modules/Chat | 16509 | 15586 | 5.6% |
| Modules/Me | 5906 | 5749 | 2.7% |
| Modules/Detail | 5018 | 4832 | 3.7% |
| Network | 5735 | 3884 | 32.3% |
| Common | 6816 | 3408 | 50.0% |
| Modules/Group | 1741 | 1731 | 0.6% |
| Modules/QR | 1549 | 1549 | 0.0% |
| Modules/Contacts | 1702 | 1192 | 30.0% |
| Modules/Conversation | 1401 | 860 | 38.6% |
| Modules/RTC | 597 | 404 | 32.3% |
| Database | 2363 | 237 | 90.0% |
| Modules/Login | 197 | 197 | 0.0% |
| Models | 1036 | 166 | 84.0% |
| App | 333 | 71 | 78.7% |

**读法**：百分比低的大头是 VC 里的 UI 代码，不该追。真正的欠账是「VC 里带判断的那几十行」，下面按风险排。
Database / Models 已经好，不用再投入。

复现命令（别用 `scripts/test.sh`，它不开覆盖率）：
```bash
xcodebuild test -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=199939FB-D3EA-4449-B011-33DC16C57857' \
  -only-testing:IMProgramTests -parallel-testing-enabled NO -enableCodeCoverage YES \
  -derivedDataPath build/DerivedData -resultBundlePath <路径>.xcresult CODE_SIGNING_ALLOWED=NO
xcrun xccov view --report --json <路径>.xcresult
```

## 2. 已核实的真问题（读码 + 我自己再读了一遍）

| 问题 | 位置 | 后果 |
|---|---|---|
| **群设置开关失败不回滚** | `IMGroupManageViewController` 的 `commitSettingsSwitch:apply:revert:` | `apply` 先把乐观值写进 `self.group`，失败后 `revert` 读 `self.group.xxx` 拿到的还是新值，开关停在失败值；本地 group 也留着失败值，之后任一开关提交都会把五个字段整体上报，带上这个脏值 |
| **聊天记录 items 元素类型不校验** | `IMChatRecordViewController` 初始化只判 `items` 是数组，`cellForRow` 直接 `it[@"n"]` | 别端发来的畸形 `chat_record`（元素是数字/字符串/NSNull）会 `unrecognized selector` 崩溃。**未复现**，但代码上成立 |

以下是子代理读码提出、**我没核实**的疑点，补测时顺带确认：
- 全局搜索 `titleForConversation:` 群聊不看备注，按群备注搜不到（会话列表是备注优先）。
- 群资料页 `inviteTapped` 不判 `permInvite`（ChatDetail 判了）。
- `forwardFrom` 回落链末位是 `m.from`（内部 uid），可能随转发泄给收件人，违反「回退链止于显示名」。
- 语音类型 `voice` / `audio` 命名在 DataSource、Compose、菜单之间不一致。
- 转发三口径（`isForwardableMessage:` / `favoriteSelected` / 合并转发）过滤条件各不相同。
- 查看器「更多」菜单对发送中本地件仍显示删除，长按菜单明确隐藏。
- `IMChunkedUploader` 服务端不回 `offset` 时可能原地重传分片 0（无进展保护）；`IMMediaDownloader` 416 被当永久失败、短读不校验长度。
- `scheduleReconnect` 无 jitter；`friendsWithToken` 的 `?status=` 未转义；`IMPendingMediaStore.store*` 写入侧未清洗 `/`。

**进度**（2026-10-03）：A1 → `Common/IMChatInbound` + `IMChatInboundTests`（16 例，含与 DB `ORDER BY` 对拍）；
C2 → `IMGroupAdminLogic` 的 `valueOfField:/setValue:` + `IMGroupAdminLogicTests` 新增 2 例。两项均已变异验证变红；全量 764/764。
A2 → `Common/IMChatWindowTrim`（`IMChatTailDropCount`/`IMChatHeadDropCount`）+ `IMChatWindowTrimTests`（8 例，变异验证变红），VC 里三处裁剪循环合并为 `dropOverflowFromTail/Head` + `dropHeadRows:`；全量 772/772。
A3 → `Common/IMChatWindowRoute`（`IMChatRouteWindowResp`，9 种去向）+ `IMChatWindowRouteTests`（17 例，四轮变异均变红）；`didReceiveWindowForConv:` 改为 `switch` 分发，按读位点开窗/取最新一窗两段体拆成 `handleEntryWindowResp:`/`handleTailWindowResp`；全量 789/789。
**A3 含一处行为修正**：迟到的 anchor=0 应答（`pendingTail` 的 6s 兜底超时清掉标志之后才到）以前因 `0 == pendingAnchor(0)` 落进「向上翻页」分支、凭空多做一次向上 prepend；现在 `pendingAnchor==0` 直接忽略。其余分支为行为保持的抽取。
**A3 顺带发现、未改**：`requestServerTailWindowIfBehind` 的 6s 兜底超时无条件把 `pendingTail` 清 NO，若期间已发出第二次「要最新一窗」，第一次的超时会提前清掉第二次的标志（读码判断，未复现）。
A4 → `Common/IMMsgOpApply`（`IMMsgOpPatch` 解析与终值 / `IMChatApplyMsgOpToMessage` / `IMChatMsgOpBannerPlan` / `IMChatPinnedItemsDroppingSeq`）+ `IMMsgOpApplyTests`（21 例，四处同时变异 → 6 条变红）；`applyMsgOpPayload:` 与 `onMsgOpApplied:` 改为调用它们，行为保持（校验顺序逐步对过）；`IMSocketManager.m` 因此 1599 → 1572 行；全量 810/810。
**A4 没改行为，但抽取时看到、保持了一处现状**：编辑帧缺 `content`（或类型不对）时 `editedContent` 退成 `@""`，落库会把正文改成空串。服务端恒下发 content，实际碰不到；测试里已标「现状、非推荐行为」，要改成「缺字段则不改正文」先改那条用例。另 `pinned` 字段若是字符串，`NSString` 也响应 `boolValue`（`"yes"` 会被当成置顶），同样服务端不会发，未处理。
C2 的测试只钉「读写映射 + 写回旧值」这段纯逻辑，**VC 里失败回调那几行没有自动化覆盖**（要桩 HTTP + 起 VC）。

**2026-10-04 续做（均已变异验证变红；未提交，待审）**：
- **A9** `IMSendRejectionShowsNote/IMSendRejectionNote`（`IMChatMessageLogic`）：文本路径与媒体路径共用一份拒收码白名单。**修了一处已发生的漂移**：媒体路径漏了 `300208`（成员级禁言），被禁言期间发媒体被拒只显普通红❗、没有提示行。测试并入 `IMResendPolicyTests`（+4）。
- **A5** `Common/IMChatSendPlan`（`IMChatPlanSend`）+ `IMChatSendPlanTests`（9）：`sendTapped` 的图文合并/相册/编辑/引用分流。对读 Web/Android：合并条件三端一致；唯一分歧是「编辑态 + 输入栏攒着粘贴图」（iOS/Web 先发图再发编辑，Android 直接提交文字、图原地不动），已写进头注释，未对齐。
- **A6** `IMSocketAckTests`（11，只加测试、没动产品代码）：真实 `IMSocketManager` 上测 ack / 重复 ack / 超时重发三次后判失败(5002) / 迟到 ack 与迟到超时无效 / 拒收（码透传、缺 code 兜底 200102、文案回退链不为空）/ 取消全部未决(5005)。
- **A7** `IMSocketFrameTests`（15）：已读回执写对端（peerReadSeq）还是写我自己（readSeq）、delivered 忽略、坏帧不崩、conv_bump 标缺口记 head、消息操作被拒广播并摘在途、msg_hidden。
- **A8** `Common/IMChatReadPosition`（`IMChatFirstUnreadIndex` / `IMChatMaxSeqOfRows`）+ 测试（11）：首条未读口径与服务端一致（排除自己发的、system、msg_op）；边界上「自己 uid 未知」不再误把 `from` 为空的消息当成自己发的。
- **A10** `IMHTTPAuthTests`（13，NSURLProtocol 桩）：TTL 缓存/换账号不复用/缓存键用服务端内部 ID/同账号并发只发一个请求/失败后在途清掉/登录用 username 不用内部 ID/有续期凭据走 refresh/强制密码登录。抽出 `IMShouldDropRefreshCredential`（续期被拒是否擦凭据）单测；**不触发真实的「续期被拒」广播**——`SceneDelegate` 监听它会登出宿主。
- **B1** `IMUserProfileCacheTests`（18）：换号清空（含在途与退避）/迟到的旧账号批次丢弃/负缓存与过期/失败不写负缓存但退避/2000 条淘汰/群成员喂全局昵称不喂群昵称。
- **B2** `IMDatabaseMsgOpTests`（18）：改键不产生重复行/撤回编辑联动会话摘要（仅限最新一条，撤回抹图说）/编辑清库里的 mentionSpans/置顶三态/整体已读清 @我/设置与备注互不影响/未读总数。**修了一处真缺陷**：`deleteLocalMessageForConv:…advancingSyncedConvSeq:` 的返回值——SQLite 的 `changes()` 把「匹配到但值没变」的 UPDATE 也算命中，位点没前进时仍返回 YES，没挡住头文件注释声称要避免的自激刷新回路；改成 `... AND synced_conv_seq<?`，`IMDatabase.h` 注释同步。
- **B5（部分）**：`IMPendingMediaStoreTests`（9）并**修了写入侧不对称**：`clientMsgID` 含 `/` 或 `..` 时文件会写到暂存目录之外、返回的引用又读不回来，现与读取侧一样拒绝；`IMDeviceModelsTests`（8）；`IMRecordParseTests`（10：通话记录解析 + 收藏项转发媒体属性）。
- **C1** `IMGroupMemberActionsFor`（`IMGroupAdminLogic`，位掩码）+ `IMGroupAdminLogicTests`（+7，对 3×3 角色 × 自己 × 已禁言穷举）：成员管理权限矩阵；`IMChatDetailViewController` 的左滑/长按菜单与 `canRemoveMember:` 改读它。对读 Web：`canManageMember` 口径一致；Android 未找到同名实现，未核对。

**`IMGroupInfoViewController`（651 行）已删除**：它是死代码——全工程无任何实例化，别处引用全是注释（还管它叫「旧」）。所以清单里「成员权限矩阵两份拷贝」实际是一活（`IMChatDetailViewController`）一死，子代理报的「`GroupInfo` 缺 `permInvite` 判断」也不成立。C6 的「三份拷贝」同理只剩两份。

**2026-10-04 `/code-review` 复核后的处理**（审查对象：IMProgram 全部未提交改动，high 档，审查者没读新测试、没构建）：
- 已修：① `+Socket` 的 `maxInMemoryConvSeq` 扫描现在只在不是重复投递时才做；② `IMChatMaxSeqOfRows` 改收 `NSIndexPath`（滚动路径不再每个 tick 装箱）；③ `IMChatTailDropCount` 改收消息数组（不再为它整窗 KVC 拷一份）；④ `IMPendingMediaStore` 拒绝不安全键时补日志；⑤ 群设置开关**一次只放一个提交在途**（连拨两个开关时两次请求会各带对方的乐观值，第一次失败回滚、第二次成功会让服务端留下界面已回滚的值）；⑥ `RemoveAndBan` 位现在有真正的消费者（长按菜单第二项按它显示）；⑦ `current_task.md` 焦点段按「活快照」重写。
- **没改，有意**：`applyMsgOpForConv:` 的 BOOL 是「已提交」而不是「有改动」——sync 路径（`IMSocketManager.m` 处理 msg_op 事件行处）拿它决定要不要推进内存游标，改成「有改动」会让目标消息不在本地的事件行永远推不过去、sync 反复重拉。与已修的 `deleteLocalMessageForConv:`（调用方只用返回值决定是否广播）语义不同，不是漏改。
- **没改，有意**：迟到的 anchor=0 应答现在被忽略。审查者担心「`pendingTail` 超时后应答才到 → 窗口停在旧切片、↓ 按钮还挂着」。补救（迟到也套用尾窗）会在用户已经跳到别处时把窗口拽回去，更糟；而此时消息已落库，用户再点一次 ↓ 即可。已知取舍。
- 审查者另提：`IMChatInbound` 等头文件注释对 Web/Android 的论断是否全部读过实现——这次已逐条对读并写入 §3.1。

## 3. 按风险排序的欠账（建议补测顺序）

分三批。「型」：**P** = 现成纯函数/类方法，零重构；**S** = 需小重构（把判断抽成不碰 UIKit 的纯函数）；**I** = 要桩/注入，工作量大。

### 批 A：消息收发与同步（用户要求的第一优先）
| # | 事项 | 位置 | 型 | 风险 |
|---|---|---|---|---|
| A1 ✅ 2026-10-03（待审，未提交） | 入站处置：非本会话/去重/只落库/追加；配套**内存排序比较器**（convSeq=0 垫底） | `IMChatViewController+Socket` 的 `didReceiveMessage:`、`sortMessagesInPlace`/`needsSort` | S/P | 高。丢消息、重复、顺序错；比较器 2026-08-05 出过事故，DB 排序有测、内存排序没有 |
| A2 ✅ 2026-10-04（待审，未提交） | 窗口裁剪三处重复实现合并后测 | `+Window` 的 `dropOverflowFromTail/Head`、`trimWindowIfOverlongAtTail` | S | 高到中。静默错 |
| A3 ✅ 2026-10-04（待审，未提交） | window_resp 路由分流 | `+Window` 的 `didReceiveWindowForConv:` | S | 高。「进大群消息显示两遍」出自这里 |
| A4 ✅ 2026-10-04（待审，未提交） | msg_op 就地应用 + 撤回后横幅剔除 | `+SendService` 的 `onMsgOpApplied:`；Socket 侧 `applyMsgOpPayload`（pinned 缺失按取消） | S/P | 高。撤回/编辑/置顶状态一致性，现无任何测试 |
| A5 ✅ 2026-10-04 | 发送决策（图文合并/编辑/引用互斥） | `+Compose` 的 `sendTapped` | S | 高。丢字/重复发/编辑变新消息 |
| A6 ✅ 2026-10-04 | ACK 状态机 + 超时重发决策 | `IMSocketManager` 的 `handleAck`/`handleAckTimeout`/`handleSendRejected` | S | 高。断连时重试被空耗（约 15–20s 判失败） |
| A7 ✅ 2026-10-04 | 收据、帧分发、conv_bump | `IMSocketManager` 的 `handleReceipt`/`handleFrame` | P（复用 `IMSocketClearFloorTests` 脚手架） | 中高 |
| A8 ✅ 2026-10-04 | 首条未读下标 + 读位点推进 | `+Position` 的 `firstUnreadRow`、`markVisibleRowsRead` | P/S | 高。定位错会被「可见即读」误清未读 |
| A9 ✅ 2026-10-04 | 发送被拒错误码 → 系统提示行（**两处白名单重复**：`IMMediaSendService` ackCompletion 与 `+MediaFlow` handleSendResult） | 同左 | P | 高。易失步；可作三端共享 fixture |
| A10 ✅ 2026-10-04 | HTTP 登录态：token TTL/在途合并/续期被拒清凭据 | `IMHTTPService+Auth` 的 `obtainTokenForUserID:` | I（NSURLProtocol 桩，已有 `IMHTTPFriendsParseTests` 样板） | 高。串号/自踢 |

### 批 B：数据库与本地存储
| # | 事项 | 位置 | 型 | 风险 |
|---|---|---|---|---|
| B1 ✅ 2026-10-04 | `IMUserProfileCache`（0%）：换账号隔离、负缓存、退避、淘汰 | 整文件 | P | 高。串号类 |
| B2 ✅ 2026-10-04 | `replaceClientMsgID`、`deleteLocalMessageForConv:…advancing` 返回值、`applyMsgOp` 联动会话摘要 | `IMDatabase` | P（内存库） | 高。几乎零成本 |
| B3 | `IMChunkedUploader`（0%）错误分级/暂停代际/offset 进展 | 整文件 | S/I | 高 |
| B4 | `IMMediaDownloader` 响应分流 + `totalBytesFromResponse` | 同名 | P+I | 高。拼接错位=数据损坏 |
| B5 ✅（`IMTinyThumbDataURI` 未做）2026-10-04 | `IMPendingMediaStore`、`IMTinyThumbDataURI` | 同名 | P | 中 |

### 批 C：权限与可见性
| # | 事项 | 位置 | 型 | 风险 |
|---|---|---|---|---|
| C1 ✅ 2026-10-04（实为一活一死，见上） | **成员管理权限矩阵**（两份拷贝零测试）+ `IMCanRevokeAdmin` | `IMGroupInfoViewController showActionsForMember:`、`IMChatDetailViewController` 的 `canRemoveMember:` 与长按菜单 | S | 高 |
| C2 ✅ 2026-10-03（待审，未提交） | 修 `commitSettingsSwitch` 回滚 bug 并补「失败后恢复」（**先看红**） | `IMGroupManageViewController` | S | 高，已核实 |
| C3 | 邀请/管理入口可见性、管理页分区、管理员列表布局 | `inviteEntriesVisible`、`numberOfSections`、`IMGroupAdminListViewController` | P/S | 高 |
| C4 | 撤回/置顶/删除权限：`canDeleteForEveryone:`、`canPinMessages`（permPin 语义易写反）、输入栏禁言锁 | `+Menu`、`+PinnedBanner` | P | 中。规则唯一出处，现有测试只用 stub |
| C5 | 群事件自退判定（四处拷贝） | 四个 VC 的 `onGroupEvent:` | P | 中 |
| C6 | 超级群成员去重追加 + has_more 收敛（三份拷贝） | GroupInfo / ChatDetail+Actions / MemberSearch | P | 中 |
| C7 | 置顶比较器与 DB `ORDER BY` 对拍；全局搜索命中规则 | `animateConversation:pinnedAt:`、`IMGlobalSearchViewController` | P/S | 中 |

### 批 D：转发/账号/其它（批 A–C 之后再看）
- 转发：`forwardAttributesForMessage:stripCaption:`（P，语音缺 duration 整条被拒）、合并转发 JSON 条目拼装（协议字段与隐私：`u` 必须匿名序号、`n` 只能公开名）、`IMChatPlanForward`（相册共享新 group_id）。
- 账号安全：QR `routeInviteLinkIfOwn:` 站内链接判定（S，小）、设备列表 `applyDevices:` 分组（S）、密码校验三处重复（S）、登出清理顺序（大重构，放最后）。
- 零重构速赢：`mediaAttributesFromFavorite:`、`IMRtcCall historyRecordFromDictionary:`、`IMDeviceModels`、`IMVoicePlayer` 已播集合 FIFO 5000 与 rate 归一。
- 免打扰 PUT 必须带回 `pinnedAt`/`markedUnread`（漏带会清置顶/未读标记）。

## 3.1 跨端对读结果（2026-10-04，读了 im-web 与 im-android 的对应实现）

此前 A1–A4 里写的「iOS 独有 / 未核对」是没读就下的判断，现已读过：

| 事项 | iOS | im-web | im-android | 结论 |
|---|---|---|---|---|
| 消息显示序（A1） | `IMChatMessageOrder` | `App.tsx` 的 sort | `MessageOrder.kt` | **三端口径一致** |
| 入站去重/只落库/上屏（A1） | `IMChatInboundDispose` | `useMessageStore.ingestInbound`：同 conv_seq 去重+合并元数据，无「只落库」 | Room 为唯一数据源 | **iOS 独有**：Web 存全量+渲染切片，Android 窗口是查询 |
| 窗口裁剪（A2） | `IMChatWindowTrim` | `renderWindow.ts` 只限 DOM | 无内存窗口 | **iOS 独有** |
| window_resp 分流（A3） | `IMChatWindowRoute` | `onWindow` 只认单个 `pendingLocate`，锚点对不上就忽略 | `WindowRequester.await` 按 conv_id 认领 | **iOS 独有**（另两端结构上没有多在途标志）；Web 的「锚点对不上就忽略」与 iOS 通用路同口径 |
| msg_op 应用（A4） | `IMMsgOpPatch` | `imSdk.applyMsgOp` | `MessageRepository.applyMsgOp` | 主干一致，四处分歧见 `IMMsgOpApply.h` 注释 |
| 群设置开关回滚（C2） | 原 bug，已修 | 不做乐观更新，PUT 后重拉，**无此问题** | `GroupSettings.toggled/applied` 纯函数 + `GroupSettingsTest` + `putSettingsOrRollback` | 三端里只有 iOS 有此 bug，且 Android 早已有纯函数+测试 |

**读出的、与 iOS 无关的疑点（只记录，没改别的仓）**：
- **Android 编辑不清 `mentionSpans`**（`MessageRepository.applyMsgOp` 的 EDIT 分支只改 content/editedAt）。Web 的 `applyMsgOpLocal` 注释明确写了不清会让高亮错位、点进另一人资料页；Android 只靠 `Mention.validSpans` 校验偏移处是否为 `@`。读码判断，未复现。
- Android `GroupInfoHost` 的设置回滚是 `info = g`（回到发请求前捕获的快照）；若 PUT 在途期间 `info` 已被重拉刷新，回滚会把较新的服务端状态盖回旧快照。iOS 这次修的时候专门避开了这一点（`self.group == g` 才写回）。低风险，未复现。
- Android 注释（`MessageOrder.kt`）仍指向 iOS 的 `sortMessagesInPlace`，该比较器已搬到 `Common/IMChatInbound.m` 的 `IMChatMessageOrder`。

## 4. 长按菜单跨端共享用例（路线图第 2 步）

子代理已把 `messageActionsForMessage:mine:` 全量矩阵读出（13 项 × 条件），可作 fixture 底稿，要点：
- **进菜单闸门**：多选态 / 行越界 / `system` / 撤回墓碑 / 相册成员 → 无菜单。
- **call 类型**只出 `delete`。
- 常规项顺序：transcribe、copy、reply、forward、favorite、recall（本人 + `convSeq>0` + 120000ms 内）、pin/unpin（`canPinMessages`）、edit（本人文本）、cancelSend（本人 + `convSeq<=0` + 本地/空内容 + Sending/Failed）、multiSelect、translate、report（非本人 + `convSeq>0`）、delete（三形态：本地删 / 仅自己 / 子菜单含全体）。
- iOS 要先抽 `IMChatMenuActionIDs(message, ctx)` 到 `Common/`，输入 ctx = `{mine,isGroup,canPin,canDeleteForEveryone,hasTranscript,nowMs}`。
- 与 `docs/CLIENT_PARITY.md`「长按消息菜单跨端差异」对照后**先定产品口径**再固化 fixture，否则测试会把差异固化成「正确」。
- **前置动作**：Android `MessageActionsTest` 与 Web `menus.ts` 的实际条件我还没读，第 2 步开始时要读。

## 5. 刻意不补
IMAppearance、各 Cell 布局/动画/进度环、扫码相机、AVPlayer/手势/转场、`tableView:` 数据源、头部形变、弹层（含 `IMActionListSheet`）、`IMMainTabBarController`。

## 6. 规矩（待你确认后生效）
- 新改动凡带判断逻辑（权限/可见性/排序/去重/状态机/协议字段）必须附测试；纯界面不要求。
- 每个模块固定四步：抽纯函数 → 写测试 → 临时改坏实现确认变红 → `./scripts/test.sh` 全绿后提交。
- 覆盖率基线记在本文 §1，每批做完重跑一次、只记变化，不设数量目标。
