# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md`（2026-10-02 瘦身前的全量快照在其顶部）+ `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点

**列表首行入口行对齐（LIST_ENTRY_ROW_DESIGN，iOS 2026-10-06 已提交、未推送）**：新增 `Common/IMEntryCell`（槽 40 + 间距 12 + 文字，自绘约束），替换通知例外「添加例外」、管理员页「添加管理员」、群资料成员页签四类前导行（行数/顺序/memberRowOffset 未动）；单测 `IMEntryCellTests`。模拟器只目测了通知例外页（insetGrouped 下左边距实测 20 非规格 16，文字左缘 72；与头像同 guide 故仍对齐）；管理员页 / 成员页签需有群数据，未目测。

**搜索入口收敛 + 设置项搜索（SEARCH_DESIGN §3.1，iOS 2026-10-05 已提交、未推送）**：底部「搜索」tab 与「我」范围已删（3 个 tab）；通讯录页顶点按式搜索框（`Common/IMSearchEntryHeader`，消息页共用）→ push 全局搜索 scope=Contacts；首页全局搜索新增「设置」分组（会话→联系人→聊天记录→设置→搜索用户），登记表 `Common/IMSettingsSearchRegistry`（纯逻辑，title+path 子串、title 命中优先）+ `Modules/Me/IMSettingsRouter`（route 逐级建页，`setViewControllers:` 一次铺栈）；单测 `IMSettingsSearchRegistryTests`。模拟器已验：3 tab、Wi-Fi›视频 三级铺栈逐级返回回「我」、通讯录搜索框 push。未验：中文关键词输入（axe 不能打中文）。`search.me.*` / `ios.tab.search` 文案键已无引用，键在 IMServer 的 strings.json（本次未动）。CLIENT_PARITY 对应单元格待 IMServer 仓维护者同步。

**iOS 单测欠账专项（清单与逐项进度见 `docs/TEST_DEBT.md`，覆盖率基线 21.8%）**：批 A/B 与 C1、C2 已做完，**全部未提交、待你复核**；剩 C3–C7 与批 D。改了产品行为的几处（A3 迟到 anchor=0、A9 `300208`、B2 删除返回值、B5 暂存路径、C2 开关回滚）在清单里逐条写明。已删死代码 `IMGroupInfoViewController`。**未做模拟器目测**（收消息/窗口裁剪/window_resp/msg_op 实时更新/群管理开关）。约定：测试由我逐个写，不派并行子代理改测试目标。

**2026-10-03 补（已推送）**：群资料页公告/简介改一行（Value1）；免打扰时长菜单改自绘底部弹层 `Common/IMActionListSheet`（`IMMuteDurationMenu` 沿用原签名，对齐 Android；iOS 26 模拟器实测，iOS 18 未对比）；别端退群关页 + 搜索页出现时拉最新会话。

**三端对齐小收口（2026-10-03，待审、未提交）**：① 待审入群申请页对齐 Android `JoinRequestsScreen`（验证消息空白整行不显、不再写默认文案；加载中显「加载中…」；审批中按钮禁用防连点；失败也重拉；纯属性 `IMJoinRequest.isPending/visibleHello/resultLabel` + 单测）；② 单聊资料页「备注名 / 用户名」改 Value1 一行（左标签右值，对齐 Android/Web；原 Subtitle 两行叠）；③ 文本气泡时间移到正文**下方**右对齐（对齐 Android；删除行内透明占位 `IMBubbleMetaPlaceholder`，`IMBubbleTextMetaLayoutTests` 钉位置）。未做模拟器目测；用户名为空时 iOS 仍显「未设置」行（Android/Web 整行隐藏）。

**C6 补齐（2026-10-02，待审、已提交）**：媒体库/查看器本地有缺口且在线时改服务端分页续拉（`IMMediaServerTimeline` + `IMMediaPaging` + 容器 `olderLoader`；查看器时间线 = 点中那条所在本地段 + 往更旧续拉；媒体库整个由服务端供给；离线只给「只能翻已加载的部分」提示；清空位点以内的丢掉）；资料页归档页签不再读 `messagesForConv:` 全表（`IMDatabase+Archive`）。置顶判定 iOS 原本就有（`IMPinnedTargetRecalled` + 本地库探测，服务端置顶列表剔除撤回）。资料页「媒体/文件/语音」页签同样并入服务端分页（`IMDetailServerArchive` + `IMChatDetailViewController+ServerArchive`，滚到底自动续拉；链接页签服务端无索引仍只看本地）。**模拟器已验**（10 万积压大群：媒体页签滚到 426 张末尾）。**查看器向「更新」方向**已补（`IMMediaServerTimeline loadNewer` + pager 末尾预取 + 服务端 `after=`，纯函数单测+变异；未做模拟器端到端）。**没做**：离线提示未在模拟器上验。

**本机清空位点 `cleared_up_to`（OFFLINE_BACKLOG_DESIGN §6.7，iOS 侧 2026-10-02 已实现，待审、未提交）**：
独立小表 `im_conv_clear_floor_local.cleared_up_to`（只增不减，不随会话行删除）；`clearMessagesForConv:` 改一个事务（删消息 + 清区间 + 抬位点 + 游标推到位点，实现在 `Database/IMDatabase+ClearFloor.m`）；
落库闸在 `writeIncomingMessage:`（sync 页 / window 页 / 实时一并挡）；有效可见下界 = `IMChatEffectiveFloor(服务端 historyFloor, 位点)`（纯函数在 `Common/IMChatWindowPlan.h`），
进会话 / 上滚 / 取最新一页 / ↓N / 跳最早 / 服务端搜索·日历都吃它；老库升级补列时一次性回填。测试：`IMClearFloorTests`（库层）+ `IMChatWindowPlanTests`（纯函数）。
对称兄弟：Android 已 ✅（`ClearFloor.kt`）；**Web 仍是「清空后重进会拉回」，待对齐**。`SYMMETRY.md` / `CLIENT_PARITY.md` / 设计文档 §6.7 状态由 IMServer 仓维护者同步（措辞建议见交付报告）。

更早的收口（细节见 archive 顶部与 `git log`）：2026-10-02 「我」页头部断网兜底 / 会话壳不再把 uid 当昵称；2026-10-01 通知显示发送人头像、别端已读清手机通知/角标、多选删除两档改批量接口（仅模拟器验证）。

## 下一步

1. **真机验证欠账**：通知 P1 批一（横幅）+ 批二（定时免打扰时长菜单）只过了模拟器编译，没真机跑过，清单见 `current_task.archive.md` 里最近的归档块；「设置 ▸ 最近通话」真机走一遍拨打→挂断→回本页看 `callEnd` 是否自动刷新、1v1 回拨、群聊行跳转；批量删除两档的 iOS 真机。
2. **核对 `IMServer/docs/CLIENT_PARITY.md` 的 M5 行是否已按 iOS/安卓/Web 拆状态**（`SYMMETRY.md` 的 `alertDecision` 四端已登记）；若没拆，补上。
3. **拆体量欠账（下次碰就必须先拆）**：`Network/IMSocketManager.m` 1596/1600（只准降不准升；方向按 CODING_STYLE §7 三档：帧编解码 / 重连退避 / 各业务 send-recv 分组各成协作对象或 category，新逻辑优先开 category）；`Database/IMDatabase.m` 1497/1500，给 `im_conversation_local`/`im_message_local` 加列前先拆（参考 `IMDatabase+MuteState.m` / `IMDatabase+ClearFloor.m`；`writeCachedConversations:` 的整行 INSERT 是下一块该搬走的）。
4. `IMChatViewController.m` 的 `peerDisplayName` 仍有 `fallback:peerID`（会在聊天页标题露内部 uid 的边缘路径），按 UI.md「末级不是 uid」改。
5. 小项：选好友页缺「全选」；`setupUI` 抽 `IMComposerBar`；「从收藏发送」入口开放；遗留 P2（听筒切换/接力连播停止条/Web 转文字/语音发送接入 `IMMediaSendService` 常驻队列等，细节见 archive）。

## 已知坑 / 限制

- **清空位点的取舍**：① 老库回填（`migrateClearedUpToColumnDB:`）按「synced 以内本地没有的那一截 = 当年清掉的」推位点，**对「本来就没下载全」的老会话会误判**成已清空（如游标在 1000、本地只有 300..1000 → 位点 299，之后 ≤299 永不再拉）；与 Android 迁移 15→16 同规则，设计文档拍板的口径。**误伤面更大的是 ranges 时代只下过窗口附近的会话（超级群 max_gap=0 尤甚）**：游标在 head、本地只有最近一两窗 → 位点被推到「本地最小 seq − 1」，窗口之下更早的历史此后一律当「用户清掉的」、不再拉；补列与回填同一事务（失败整体回滚、下次启动重试）。② 落库 / UI 投递 / 回执 / 提醒共用同一份保留集合：sync 页落库前先 `IMDropClearedMessages`，实时先 `incomingIsCleared:`，window 页跳过位点内的行（库里的落库闸是第二道防线）。③ 位点存独立小表 `im_conv_clear_floor_local`（不随会话行删除；会话行被「删除会话」/ 列表不再返回删掉后重建，`synced_conv_seq` 取 max(旧值, 位点)，不会 since=0 重拉）。旧的 `im_conversation_local.cleared_up_to` 列（早期实现）只在迁移时拷一次，之后不再读写、没有 DROP。iOS 没有「清账号」路径（登出不抹库，靠 owner_uid 隔离）。④ 清空不动会话未读数 / 读位点（沿用旧行为）。⑤ iOS 本机没有独立的「隐藏/删除墓碑」表（本地删除是物理删行），所以「墓碑不动」在 iOS 退化为「只动该会话的消息 / 区间 / 位点」。
- **冷启动通知路由极端情况**：全新会话的推送点击可能落空。
- **会话列表左滑「免打扰」** 在 `done(YES)` 之前 present `IMMuteDurationMenu`、**通知横幅点击进会话** 与自身 dismiss 动画并行：真机若两个动画叠加突兀，把 present/路由挪到 `done(YES)` / dismiss 完成回调里即可（一行改动）。
- **通讯录 `reload` 不防重入**：好友事件与切入请求并发时后发先至会让 `applyFriends:` 覆盖成较旧名单（短暂，下次刷新自愈）；补法是在途时只记「待重跑」。
- **`IMProgramUITests/IMContactsPerfUITests` 对 2000 好友账号会卡住**（XCUITest 给整棵无障碍树拍快照，`cells.count` 超时重试，App 本身不卡）：重跑前改成不查大表，效果看 `contacts_index_applied` / `contacts_cache_persist` 日志与 simctl 截图。
- **撤回消息的「重新编辑」可能在重拉后消失**：服务端撤回/删除正文不再随 `sync_resp`/`window_resp` 下发，`writeIncomingMessage` 的 `content=?` 无条件覆盖，重拉后本地正文可能被空串盖掉（优雅降级，不崩溃）。
- **`IMMediaPlaceholderTests testFrostedLandscapeScalesLongestSideTo48` 高负载偶发失败**（`scripts/test.sh` 的 `-only-testing:IMProgramTests` + 关并行基本规避，根因未定位）。
- **`runAfterKeyboardHidden:` 兜底待测**：依赖 `resignFirstResponder` 后必然收到 `UIKeyboardDidHideNotification`；外接键盘场景引用跳转不触发就加 `dispatch_after` 超时兜底。
- 相册导出期杀 App 消息消失（PHPicker 句柄一次性，预期）；Files <8MB 小文件、相机拍照、粘贴图仍是 VC 锚定一次性上传；iOS 无双向分页（进会话全量载入本地 DB）；presence/typing 仅聊天页标题生效。
- dev-login 建的账号无法再走密码登录（测密码登录用「注册并登录」或清 `imserver.db`）。
- 查看器「正在播放中」视频 404 未接失效占位（窄路径可接受）；失效标记是进程内 Set、冷启动首帧重探（刻意）；原图路径 JPEG 字节戴 `.heic` 帽子（Web 靠嗅探已能显示，暂不改）；系统按钮文案靠 `CFBundleLocalizations`，自有 UI 硬编码中文。
- 测试只跑 `-only-testing:IMProgramTests`；改后端协议后需重启后端再测。体量门禁扫整个 `IMProgram/`（测试 target 是兄弟目录，不在范围）。
- 聊天页「从收藏发送」暂不支持：`attachItemTapped:` 的 `favorite` 分支仍走 `im_showComingSoon`（`../IMServer/docs/FAVORITES_DESIGN.md` §5.5 标 ⏸）。

## 关联工程 / 常用命令

- 后端 `/Users/dev/IOSProject/im-client/IMServer`；Web `/Users/dev/IOSProject/im-client/im-web`；Android `/Users/dev/IOSProject/im-client/im-android`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 装真机（iPhoneWork `00008120-000131121E50C01E`）：`xcodebuild … -destination 'id=<udid>' -derivedDataPath <dir> -allowProvisioningUpdates build` → `xcrun devicectl device install app --device <udid> <dir>/Build/Products/Debug-iphoneos/IMProgram.app`。首次连后端要允许「查找并连接本地网络设备」，登录页填 Mac 当前 LAN IP。
- 测试：唯一入口 `./scripts/test.sh`（体量门禁 + 编译 + `IMProgramTests`；`BUILD_ONLY=1` / `ONLY=<Class>` / `ONLY=<Class>/<test>`，三个坑见 `CLAUDE.md`「构建 / 测试」）。
- 真机日志：`xcrun devicectl device copy from --device iPhoneWork --domain-type appDataContainer --domain-identifier com.libeyond.IMProgram --source "Library/Caches/Logs/<file>.log" --destination <dst>`；通知扩展日志 `idevicesyslog -u <udid>` grep IMNotificationService。
- 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
