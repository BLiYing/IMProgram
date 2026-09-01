# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

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

> **收藏页 / 详情页 / 置顶 / 记录卡 五项 UI 修复（2026-08-30，两端同步；iOS `build` 绿、**已跑 `IMProgramTests` 311 例全绿**；
> Web `tsc -b` + `vitest 681` 绿。**两端已手测通过（2026-08-30，用户逐项验收）**）**
>
> 1. **置顶预览**：`IMPinnedMessage.previewText` 只认 `audio` 不认 `voice`、且没有 `chat_record` 分支
>    → 语音置顶铺一串 URL、合并转发卡片铺整段 `{"t":…,"items":[…]}` JSON。现统一收成 `[语音]` /
>    `[聊天记录] 标题`（走既有 `IMChatRecordSnippet`，与引用快照同 token 口径）。Web `pinned.ts` 同修。
> 2. **收藏页「来自X」不再露 10 位内部 ID**：根因是 `IMDatabase.cachedGroups` 恒 `members = @[]`
>    （成员只在进群详情页时联网拉），好友表又只覆盖好友 → 群里非好友发的收藏全回退 uid。
>    新增 `resolveMissingSourceNames`：按需**两级补拉**（先 `GET /groups/{id}` 拿群昵称，仍缺再
>    `GET /users/{id}` 拿名片），每个 id 只发一次、失败静默。Web 同款 effect。
> 3. **收藏页副行时间与「来自X」拆两行 + 颜色分开**（时间 tertiary / 来源 accent，对齐链接分类）：
>    长备注名/群昵称原先会把时间整个挤没。改 `IMFavoriteRowCell` / `IMFavoriteVoiceCell` /
>    `IMDetailFileCell` / `IMDetailContactCell`（名片的「由 X 分享」从副行拆成第三行，行高 64→82，
>    新增 `IMDetailContactCellHeightWithSource`）。
> 4. **详情页链接 tab 时间改「年月日 时:分」**（原「今日 HH:mm / 昨天 / M月d日」，同页四个 tab 两套语言、
>    跨年看不出年份）；Web 同修，并给 Web 文件 tab 补上原本没有的时间行。
> 5. **页签条横向可滚**：`IMLiquidSegmentedControl` 底轨 `clipsToBounds=YES` 且无滚动容器 → 段总宽超出时
>    末尾页签（详情页 6 签的「名片」/ 收藏页 7 签的「名片」）被裁掉且划不到。内嵌 `UIScrollView`，
>    塞得下时 `scrollEnabled=NO`（手势不参与竞争，行为同改前）。Web `.detail-tabs` 加 `overflow-x:auto`。
> 6. **合并转发记录详情页**：名片条目原先落通用文本分支铺 JSON 原文 → 改渲染 mini 名片卡（头像+显示名+
>    @句柄+「个人名片 ›」脚注）；语音条目原先铺裸 URL → 改用与详情页/收藏页同一个
>    `IMVoiceMiniPlayerView`。打包端补 `d`（时长）/`w`（波形）两个 key（两端同约定），老记录无这两项时
>    退化成等高条纹 + 0:00 仍可播。Web 语音同修（名片 Web 本就是卡片）。
>
> 体量门禁副产物：`IMFavoritesViewController.m` 撞 1500 行 → 抽出 `IMFavoriteRowViews.{h,m}`
> （阅读器 / 统一图标行 / 来源会话行，逐字平移、行为零变化），现 1364 行。

> **记录卡补齐 + 语音四项（2026-08-30 第三批；`IMProgramTests` 312 例全绿；**已手测通过**）**
> 1. **合并转发条目新增 `ts`/`u`/`a`**（原消息时间 / 发送者 uid / 头像相对路径，两端同 key，
>    契约表进了 [PROTOCOL.md](../IMServer/docs/PROTOCOL.md)）。记录详情页据此：右上角显**每条**消息的时间、
>    左侧显头像、**连续同一人只显一次头像与昵称**（判据抽成纯函数 `IMRecordSenderKey`，与 Web
>    `recordSenderKey` 同口径、各带单测）。**老记录一定缺这三个字段**——不显时间 / 首字母色块兜底，
>    绝不能因为缺字段就不渲染。`u` 只当查头像与判连续的键，**永不上屏**（显示名一律走 `n`）。
>    单聊里"我自己"那一方拿不到头像路径（本页没有自己的资料快照），只发 `u`（Web 有 `myInfo` 故能带 `a`；
>    `a` 可选，两端不算分叉）。
> 2. **语音「已读」= 点了就算**：新增 `im_markVoiceConsumed:` 收口——播放与**转文字**都消未播红点
>    并刷那一行（原先只有播放会消，且要等 cell 复用才刷）。判据是"点了"不是"听完"。
>    **注意**：发送方看到的 ✓✓ 仍是"进会话即读"，语音不例外——`read_seq` 是水位线，做不到单条
>    语音"听了才算"，详见 [VOICE_MESSAGE_DESIGN §7](../IMServer/docs/design/VOICE_MESSAGE_DESIGN.md)。
> 3. **单聊语音气泡终于和其它气泡左对齐**：`IMVoiceBubbleCell` 把对方气泡左缘钉死在
>    `_avatar.trailing + 8`，而 `applyGroupAvatarURL:…gutter:` **整个忽略了 gutter** ——
>    单聊没有头像列，气泡照样被推到 50pt，比同屏文本/图片气泡多缩进近 40pt。改成锚 contentView
>    + `gutter ? 48 : 12`（与 IMBubbleCell/IMImageCell/IMChatRecordCell/IMContactCardCell 同口径）；
>    顺带把头像几何 10/32 纠成 12/30（基类 cornerRadius 15 本就配 30，原来还差一点不圆）。
>
> **记录卡语音：崩溃 + 无时长（2026-08-30 用户实测报，已修并**复测通过**；`IMProgramTests` 311 例全绿）**
> - **崩溃根因不在记录卡，在语音播放通道**：Chrome 录的语音是 **MP4/Opus**（`audio/mp4` 容器塞 Opus），
>   `framesPerPacket == 0` → `AVAudioPlayer` 在 AVFAudio 内部**除零**（`EXC_ARITHMETIC`/`SIGFPE`，
>   `@try` 拦不住、整个 App 当场退出）。崩溃栈由 `~/Library/Logs/DiagnosticReports` 的 .ips 定位：
>   `AVFAudio ×4 → -[IMVoicePlayer togglePlayback:localFileURL:]`。**气泡/收藏/详情页语音 tab 同样会崩**，
>   只是这次先在记录卡撞上。修法：新增 `IMVoiceFileIsPlayable(url, &durationMs)`（AudioToolbox 读
>   `kAudioFilePropertyDataFormat`，`sampleRate<=0 / framesPerPacket==0 / channels==0` 一律拒），
>   `togglePlayback:` 与 `toggleEnsuringLocal:` 双重把关；被拒回 `NSError`「该语音格式无法播放」，
>   四个播放入口改吐 `err.localizedDescription`（原先写死「语音下载失败」，会把排查引偏）。
>   护栏 `IMVoiceFileGuardTests.m`（合成 WAV 放行并报时长 / 非音频字节被拒 / 缺文件与非 file URL 被拒）。
>   源头在 Web 侧一并修（见 im-web current_task）。
> - **无时长**：老记录打包时没有 `d` 字段。新增 `fillDurationFromLocalFileIfNeeded:`——**只探已缓存的
>   文件、绝不为显个时长去发下载**；播放触发的下载完成后再探一次并刷该行。
>   **已知限制**：坏文件（MP4/Opus）报的时长是天文数字，被 `IMVoiceFileIsPlayable` 一并挡掉 → 仍显 0:00，
>   这是对的；那条消息本身在 iOS 上就播不了。

> **/code-review 三条修复（2026-08-30，纯客户端；`build` 绿、`-only-testing:IMProgramTests` 314 例
> 仅剩那条已知偶发的 `testFrostedLandscapeScalesLongestSideTo48`，单独重跑绿。**未手测**）**
> 1. **语音上传失败的红❗点不动**（重传路径整条失效）：`im_uploadAndSendVoice` 失败时**无条件**写
>    `note`（"语音上传失败"），而 `IMResendPolicyForMessage` 把"有 note"一律当成"被服务端拒收 → 不可重发"，
>    于是 `IMFailBadgeView.tappable=NO`、红❗照显却吃不到点击。判据顺序改成
>    **「本地还留着字节（`im-pending://` / `file://`）」优先于 note** —— content 是本地引用就说明服务端
>    从没见过这条，"拒收"的解释不成立。`content` 空 + note（语音"发送中断，请重新录制"）仍判不可重发。
>    补两条护栏用例。
> 2. **会话列表预览显示早已被顶掉的旧系统消息**：`updateConversationForMessage`（实时路径）覆写了
>    `last_content` 却漏写 `last_sys_segments`，而 `IMConversation.lastPreviewTextForSelfUID:` 只要分段非空
>    就整句用它渲染、`last_content` 根本不参与 → HTTP 快照存过一次系统消息分段后，之后来的普通消息
>    在冷启动/离线首屏一律显示那条旧系统消息。INSERT/UPDATE 两处一并补上（与 2026-08-19 修过的
>    `last_caption` 同一类漏写）。
> 3. **合并转发条目里"我自己"的名字是 10 位内部 ID**：`displayNameForMessage:` 自己那一支返回
>    `self.userID`。记录详情页现在把 `n` 当头行昵称显示（2026-08-30 加 ts/u/a），于是我发的每条都顶着
>    一串随机数字。改为「我」，与 Web `useForward.ts#nameOf` 同口径。

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
