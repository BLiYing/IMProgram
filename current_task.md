# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md`（2026-10-02 瘦身前的全量快照在其顶部）+ `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点
- **后台「系统设置」S2 客户端部分（2026-11-08，未提交）**：`Network/IMServerConfigStore` 解析 `GET /server-config` 新增六项（缺失→内置默认 120s/不限/9/100/30/500，0 仅在两个时间窗上=不限），**每次 Connected + 回前台**重拉（在途不重发 + 成功后 5s 内不再拉，合并两个时机）；撤回 / 编辑菜单显隐走 `IMChatCanShowRecall/Edit`（删掉 `kIMRecallWindowMs`）；转发选择页上限读 `forwardMaxTargets`（确认卡片网格超 4 行改内部滚动）；合并转发在选方式时按 `mergeForwardMax` 拦（复用「最多选择 N 条」吐司）；建群 / 改群名（弹窗说明行改为实时 `n/上限`）/ 群公告读两个长度上限。单测 `IMServerConfigStoreTests`。**未做**：`err.300202`「不超过 30 字」与 `group.ops.name_placeholder` 文案仍写死 30（改要动 `strings.json` 并重生成四端，本次按要求不碰 IMServer）；CLIENT_PARITY 未更新。
- **登录页长按 Logo 配地址（2026-11-06，仅 iOS）**：长按顶部图标弹窗改服务器地址和音视频地址（留空恢复默认）；登录按钮下方改为只读显示服务器地址，原折叠输入框已删。Release 内置默认 `47.250.219.159:8081`，音视频默认仍读 `IMRtcConfig.local.plist`（局域网地址），保存值优先（`IMRtcConfig.saveWSURLOverride:`，下次登录启动引擎时生效）。老安装保留 `im_last_host`，默认值只对没存过地址的安装生效。后台下发 `rtc_ws_url` 的方案用户未采纳。未解之谜：模拟器单测里 `im_last_host` 删除后持久域已空，`stringForKey:` 仍读到旧值，原因未查明；留空保存后杀 App 重开是否回到默认，以真机为准。
- **登录页改服务器地址时键盘盖住输入框（2026-11-06，未提交）**：登录页是一列堆叠、没有滚动容器，原先键盘处理只覆盖二步验证页。现在按当前获得焦点的输入框（地址 / 用户名 / 密码 / 昵称）算上移量，保证它的下沿在键盘上沿之上；同一键盘下切换输入框靠 `UIControlEventEditingDidBegin` 重算。纯函数 `IMLoginKeyboardLift`，测试 `IMLoginKeyboardTests`。**待真机目测**（小屏 + 中文输入法的候选栏高度）。
- **退出后不再收离线通知（2026-11-06，未提交）**：`Network/IMPendingLogoutQueue` 持久化待吊销凭据并重试，`IMSessionTeardown` 清已显示通知。设计与真机清单：`../IMServer/docs/design/LOGOUT_REVOKE_RETRY_DESIGN.md`。**Keychain 只能在签名真机验证**（`test.sh` 未签名，往返用例跳过）。
- **分享选择页：好友/群聊入口 + 底部已选栏 + 发送确认（2026-11-05，未提交）**：设计稿 `../IMServer/docs/design/sketches/SHARE_PICKER_UX_SKETCH.html`。`IMForwardPickerViewController` 加「我的好友 / 我的群聊」入口（子页 `Modules/Chat/SharePicker/IMShareContactListViewController`），选中集 `Common/IMShareSelection`（按 conv_id 去重、三处合计 9，好友 conv_id 用 `IMConversationID` 本地推导、合成 `IMConversation` 交回调用方——7 个分享入口零改动即可发给没聊过的好友 / 删过会话的群）；多选态底部常驻已选栏 `IMShareSelectionBar`（复用从建群页抽出的 `Common/IMSelectedChipStrip`）+ 确认面板 `IMShareConfirmViewController`（目标可删 + 内容预览）；主页搜索三源分组去重；二维码页「分享 → 发送给朋友 / 其他应用…」（名片码发名片、群码发邀请文本，排除该群本身）；分享名片排除名片主人；「添加例外」传 `showsContactEntries=NO` 保持原样。单测 `IMShareSelectionTests` 8 例（变异三处先红后绿）；模拟器 UI 自测脚本 `IMProgramUITests/IMSharePickerUITests`（默认跳过，`TEST_RUNNER_IM_SHARE_UITEST=1` 才跑，依赖开发库账号 user4982）。
- 近期功能（邮箱登录、两步验证、清除所有对话、删除会话统一口径、导出我的数据、自动删除 v2、会话列表编辑模式、注销账号、置顶面板、聊天文件夹、失效媒体口径等）均已落地并推送，详情见 `current_task.archive.md` 末段。
- 目测欠账：邮箱登录、删除会话统一口径、扫一扫「我的二维码」页、置顶面板、iOS 26 Tab 条染灰（未滚动实测）、聊天文件夹（桌面/iOS 26·18 导航栏边缘）、失效媒体口径（iOS 界面）。原文见 archive。

## 下一步

- **置顶面板收尾**：`../IMServer/docs/CLIENT_PARITY.md` 置顶面板 iOS 格待更新（本次按要求未改别的仓）；真机清单见「当前焦点」。二期（设计 §2.2）：图片 / 视频单条预览、语音就地播放。

0. **相册选择器**：用户 2026-10-07 真机自测通过，无待办。**已知限制**：体积来自 `PHAssetResource` 的 `fileSize`（KVC），取不到时不置灰也不显总大小；无 VoiceOver 标签；Android/Web/桌面文案已重新生成（2026-10-07）。

1. **拆体量欠账（下次碰就必须先拆）**：`Network/IMSocketManager.m` 1589/1600（只准降不准升；方向按 CODING_STYLE §7 三档：帧编解码 / 重连退避 / 各业务 send-recv 分组各成协作对象或 category，新逻辑优先开 category）；`Database/IMDatabase.m` 1500/1500（已顶满，加列或新增前必须先拆），给 `im_conversation_local`/`im_message_local` 加列前先拆（参考 `IMDatabase+MuteState.m` / `IMDatabase+ClearFloor.m`；`writeCachedConversations:` 的整行 INSERT 是下一块该搬走的）。
2. `IMChatViewController.m` 的 `peerDisplayName` 仍有 `fallback:peerID`（会在聊天页标题露内部 uid 的边缘路径），按 UI.md「末级不是 uid」改。
3. 小项：`setupUI` 抽 `IMComposerBar`；遗留 P2（听筒切换/接力连播停止条/Web 转文字/语音发送接入 `IMMediaSendService` 常驻队列等，细节见 archive）。

## 已知坑 / 限制
- **退出吊销重试**：未签名包 Keychain 报 `-34018`，退回内存队列，杀进程后凭据丢失；重试依赖 App 被再次打开；卸载后 Keychain 是否保留系统不保证。全部限制见 `LOGOUT_REVOKE_RETRY_DESIGN.md` §4。
- **`IMProfileEditKeyboardTests` 依赖模拟器里 App 已登录**：测试宿主即真 App，模拟器重启后停在登录页时，登录页输入框会抢走第一响应者，「键盘弹出_个性签名不被盖住」必红（2026-11-05 实测：登录后重跑即绿）。跑全量前先在模拟器里登录一次。
- **分享选择页**：群列表接口 `GET /groups` 不下发禁言/角色/人数，故「我的群聊」不做全员禁言置灰、不显人数（发往禁言群由服务端拒，与原转发页一致）；打开选择页即预取好友 + 群（主页搜索要用，三端同口径）；新增页面字号/圆角沿用写死数值（`IMTheme` 尚无字号/圆角令牌）。
- **置顶面板**：图 / 视频按下载策略门控时显 ↓ 占位但点了是「定位」（只读，不下载）；引用条不取被引用消息的缩略图（退回类型小图标）；相册成员置顶按单张图渲染（非宫格）；`IMSocketAckTests` 三条与 `IMMediaDownloadCoordinatorTests testImageNotGatedWhenPolicyOn` 在本机并发负载下全量跑偶发红、单类跑与重跑全绿（与本改动无关，未定位）。
- **新单聊壳行昵称/头像延后**：会话列表原无该 conv 时 new_msg 只建壳行（peer 由 convID 推、昵称空），名片与头像等下次 `/conversations`（列表在屏 0.4s 内、不在屏则等回到列表）才补；`IMDatabase.m` 恰 1500 行，该处不能再加行。

- **清空位点的取舍**：① 老库回填（`migrateClearedUpToColumnDB:`）按「synced 以内本地没有的那一截 = 当年清掉的」推位点，**对「本来就没下载全」的老会话会误判**成已清空（如游标在 1000、本地只有 300..1000 → 位点 299，之后 ≤299 永不再拉）；与 Android 迁移 15→16 同规则，设计文档拍板的口径。**误伤面更大的是 ranges 时代只下过窗口附近的会话（超级群 max_gap=0 尤甚）**：游标在 head、本地只有最近一两窗 → 位点被推到「本地最小 seq − 1」，窗口之下更早的历史此后一律当「用户清掉的」、不再拉；补列与回填同一事务（失败整体回滚、下次启动重试）。② 落库 / UI 投递 / 回执 / 提醒共用同一份保留集合：sync 页落库前先 `IMDropClearedMessages`，实时先 `incomingIsCleared:`，window 页跳过位点内的行（库里的落库闸是第二道防线）。③ 位点存独立小表 `im_conv_clear_floor_local`（不随会话行删除；会话行被「删除会话」/ 列表不再返回删掉后重建，`synced_conv_seq` 取 max(旧值, 位点)，不会 since=0 重拉）。旧的 `im_conversation_local.cleared_up_to` 列（早期实现）只在迁移时拷一次，之后不再读写、没有 DROP。iOS 没有「清账号」路径（登出不抹库，靠 owner_uid 隔离）。④ 清空不动会话未读数 / 读位点（沿用旧行为）。⑤ iOS 本机没有独立的「隐藏/删除墓碑」表（本地删除是物理删行），所以「墓碑不动」在 iOS 退化为「只动该会话的消息 / 区间 / 位点」。
- **冷启动通知路由极端情况**：全新会话的推送点击可能落空。
- **会话列表左滑「免打扰」** 在 `done(YES)` 之前 present `IMMuteDurationMenu`、**通知横幅点击进会话** 与自身 dismiss 动画并行：真机若两个动画叠加突兀，把 present/路由挪到 `done(YES)` / dismiss 完成回调里即可（一行改动）。
- **通讯录 `reload` 不防重入**：好友事件与切入请求并发时后发先至会让 `applyFriends:` 覆盖成较旧名单（短暂，下次刷新自愈）；补法是在途时只记「待重跑」。
- **`IMProgramUITests/IMContactsPerfUITests` 对 2000 好友账号会卡住**（XCUITest 给整棵无障碍树拍快照，`cells.count` 超时重试，App 本身不卡）：重跑前改成不查大表，效果看 `contacts_index_applied` / `contacts_cache_persist` 日志与 simctl 截图。
- **撤回消息的「重新编辑」可能在重拉后消失**：服务端撤回/删除正文不再随 `sync_resp`/`window_resp` 下发，`writeIncomingMessage` 的 `content=?` 无条件覆盖，重拉后本地正文可能被空串盖掉（优雅降级，不崩溃）。
- **`IMDeletedUserDisplayTests testAccountDeletedFramePostsNotification…` 偶发红已修**：测试宿主即真 App，模拟器有登录会话时 `SceneDelegate` 会响应手发的注销通知并 `disconnect`（`_manualClose=YES`）与读数竞态；测试内置 `IMSessionTeardown.accountDeletionInProgress=YES` 让路（不碰会话存储）。
- **`IMMediaPlaceholderTests testFrostedLandscapeScalesLongestSideTo48` 高负载偶发失败**（`scripts/test.sh` 的 `-only-testing:IMProgramTests` + 关并行基本规避，根因未定位）。
- **`runAfterKeyboardHidden:` 兜底待测**：依赖 `resignFirstResponder` 后必然收到 `UIKeyboardDidHideNotification`；外接键盘场景引用跳转不触发就加 `dispatch_after` 超时兜底。
- 相册导出期杀 App 消息消失（PHPicker 句柄一次性，预期）；Files <8MB 小文件、相机拍照、粘贴图仍是 VC 锚定一次性上传；iOS 无双向分页（进会话全量载入本地 DB）；presence/typing 仅聊天页标题生效。
- dev-login 建的账号无法再走密码登录（测密码登录用「注册并登录」或清 `imserver.db`）。
- 查看器「正在播放中」视频 404 未接失效占位（窄路径可接受）；失效标记是进程内 Set、冷启动首帧重探（刻意）；原图路径 JPEG 字节戴 `.heic` 帽子（Web 靠嗅探已能显示，暂不改）；系统按钮文案靠 `CFBundleLocalizations`，自有 UI 硬编码中文。
- 测试只跑 `-only-testing:IMProgramTests`；改后端协议后需重启后端再测。体量门禁扫整个 `IMProgram/`（测试 target 是兄弟目录，不在范围）。

## 关联工程 / 常用命令

- 后端 `/Users/dev/IOSProject/im-client/IMServer`；Web `/Users/dev/IOSProject/im-client/im-web`；Android `/Users/dev/IOSProject/im-client/im-android`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 装真机（iPhoneWork `00008120-000131121E50C01E`）：`xcodebuild … -destination 'id=<udid>' -derivedDataPath <dir> -allowProvisioningUpdates build` → `xcrun devicectl device install app --device <udid> <dir>/Build/Products/Debug-iphoneos/IMProgram.app`。首次连后端要允许「查找并连接本地网络设备」，登录页填 Mac 当前 LAN IP。
- 测试：唯一入口 `./scripts/test.sh`（体量门禁 + 编译 + `IMProgramTests`；`BUILD_ONLY=1` / `ONLY=<Class>` / `ONLY=<Class>/<test>`，三个坑见 `CLAUDE.md`「构建 / 测试」）。
- 真机日志：`xcrun devicectl device copy from --device iPhoneWork --domain-type appDataContainer --domain-identifier com.libeyond.IMProgram --source "Library/Caches/Logs/<file>.log" --destination <dst>`；通知扩展日志 `idevicesyslog -u <udid>` grep IMNotificationService。
- 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
