# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md` + `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

> **收藏页 / 详情页 / 置顶 / 记录卡 五项 UI 修复（2026-08-30，两端同步；iOS `build` 绿、**按约定只编译未跑模拟器**；
> Web `tsc -b` + `vitest 679` 绿。**两端均未手测**）**
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

## 已知坑 / 限制
- **`IMMediaPlaceholderTests testFrostedLandscapeScalesLongestSideTo48` 在高负载下会偶发失败（2026-08-30 首次观察）**：
  全量 `xcodebuild test`（含 UITests，`testLaunchPerformance` 跑 109s 占满机器）时，该用例作为某个
  clone 上的**第一条**执行、耗时 9.5s（正常 2.7s）后失败；单独重跑该类、以及
  `-only-testing:IMProgramTests` 全量（289 例）都稳定绿。判定为冷启动/负载下的抖动，**未定位**。
  与后端 `internal/gateway` 那条间歇失败同类，先记着；再复现请抓 XCTAssert 原文。
- **`runAfterKeyboardHidden:` 兜底待测（2026-08-05 记）**：依赖 `resignFirstResponder` 后必然收到 `UIKeyboardDidHideNotification`——软键盘正常成立；若实测硬件/外接键盘场景引用跳转不触发，加 `dispatch_after` 超时兜底。
- 相册导出期杀 App 消息消失（PHPicker 句柄一次性，属预期，微信同）；导出失败的行点 ↻ 提示副本丢失需重选。Files 面板 <8MB 小文件、相机**拍照**、粘贴图仍为 VC 锚定一次性上传（秒级；粘贴图已带预览条攒批）；
  相机**录像**已改走 `IMMediaSendService` 常驻队列（2026-08-29）。
- iOS 无双向分页（进会话全量载入本地 DB）；presence/typing 仅聊天页标题生效。dev-login 建的账号无法再走密码登录（测密码登录用「注册并登录」或清 `imserver.db`）。
- **查看器"正在播放中"视频 404 未接失效占位（2026-08-11 记）**：`IMMediaViewerViewController` 有 `item.status` KVO 但失败一律走「无法播放该视频」兜底，未把 404/410 翻 ⊘。窄路径（气泡/媒体库通常先探到→进查看器即短路），兜底不黑屏故可接受。补法：失败分支走 `IMMediaExpiryRegistry verifyExpiredForURL:` 定性→失效覆盖层 + mid-play teardown。
- **失效标记内存态不持久（刻意，2026-08-11 记）**：`IMMediaExpiryRegistry` 用进程内 Set，冷启动首帧重探一次换自愈；仅当服务端上自动 TTL 清理使失效变常态才上持久化。
- **系统按钮文案本地化（2026-08-12 修，未编译验证）**：`Info.plist` 补 `CFBundleLocalizations=[zh-Hans,en]` 让 QLPreview「Done」/UISearchBar「Cancel」等系统文案落中文；自有 UI 硬编码中文，将来做真·多语言再建 `.lproj`。
- **原图路径 JPEG 字节戴 `.heic` 帽子（2026-08-12 记，暂不改）**：`IMMediaPicker buildImageItem` 原图分支按 `UTTypeImage` 取字节（iOS 可能把 HEIC 转 JPEG 交付）但扩展名靠 `hasItemConformingToTypeIdentifier:UTTypeHEIC` 猜 → JPEG 内容 + `.heic` 名错配。Web 靠字节嗅探已能各自正确显示故非阻塞；计划换第三方相册选择器（任务4）后此坑自消。
- 测试只跑 `-only-testing:IMProgramTests`；改后端协议后需重启后端再测。
- **聊天页「从收藏发送」入口暂屏蔽/暂不支持（2026-08-19）**：`IMChatViewController` `attachItemTapped:` 的 `favorite` 分支仍走 `im_showComingSoon`（等效屏蔽）。设计已保留（`../IMServer/docs/FAVORITES_DESIGN.md` §5.5 标 ⏸），待收藏改造统一放开并接卡片式收藏选择器。

## 关联工程 / 常用命令
- 后端 `/Users/liying/IOSProject/IMServer`；Web `/Users/liying/IOSProject/im-web`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 测试编译 + 实跑：`xcodebuild build-for-testing ...` → 有 booted 模拟器则 `test-without-building ... -only-testing:IMProgramTests`。
- 真机日志：`xcrun devicectl device copy from --device iPhoneWork --domain-type appDataContainer --domain-identifier com.libeyond.IMProgram --source "Library/Caches/Logs/<file>.log" --destination <dst>`（list 用 `device info files`；崩溃报告 `--domain-type systemCrashLogs`）。
- 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
