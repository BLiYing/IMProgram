# Current Task — IMProgram（iOS）

> **活快照**：只记当前状态，**就地覆盖、不追加**。逐功能×端状态以 `../IMServer/docs/CLIENT_PARITY.md` 为唯一来源；
> 历史流水见 `current_task.archive.md`（2026-10-02 瘦身前的全量快照在其顶部）+ `git log`。关键约定见 `CLAUDE.md` / `ARCHITECTURE.md` / `CODING_STYLE.md`。

## 当前焦点
- **10-08 握手 401 先续期再判被踢**（`Network/IMSocketManager+AuthRecovery.{h,m}`，与 Android `ws/WakeAction.kt` 同表）：401 → 作废 10 分钟 token 缓存、立即重连（openSocket 内续期）；续期被拒走既有 `IMSocketDidRevokeSessionNotification`；续期后的新 token 还 401 才按被踢；didOpen 清「已续过」。起因：服务端换密钥重启，iPhoneWork 拿缓存旧 token 重连被送回登录页。模拟器（iPhone 17 Pro Max）× Pixel × OPPO 两轮换密钥重启均自动续上。test.sh 1047 绿；`IMSocketAuthRecoveryTests` 已看红。
- 10-08 接 im-rtc Kit tokenProvider，SDK 2.2.1（`remote 2.2.1`）：`IMRtcCall` 登录交给 Kit，通话记录先 `[_kit ensureReady:]`。
**聊天相册选择器：iOS 自建（对齐 Android `:media-picker`）——已合入 main，用户真机自测通过（2026-10-07）**（方案 `../IMServer/docs/design/MEDIA_PICKER_IOS_DESIGN.md` + 草图 `sketches/MEDIA_PICKER_UX_SKETCH.html`）。聊天「➕ → 照片」换成自建宫格（4 列 · 相册切换 · 编号多选 ≤9 · 底栏「原图 (总大小)」· 视频时长角标 · >2GB 置灰 · 长按预览）；缩略图 / 视频首帧走 `PHImageManager`，视频转码直接吃 `AVAsset`（不再先把整个视频拷出相册），根治「选完视频首帧空白几十秒」。权限三态同页处理（有限访问「管理」/ 拒绝=空状态+去设置，**无降级退路**）；旧「发送 / 发送原图」动作表与 `presentFromViewController:limit:` 已删。头像三处与「➕ → 文件 → 相册」仍用 PHPicker。新文件 `Common/IMMediaPick*.{h,m}` / `IMMediaPicker{Photos,Cell,Bars,BucketSheet,ViewController,Entry}` / `IMMediaPreviewViewController`；测试 `IMMediaPickLogicTests`（10 例，含转码结局判定，已看红过）。合入后收尾 5 项已做：被拒隐藏底栏、视频体积查询按 ID 去重、删不可达的「0 字节不可选」、转码回落单独告警 `video_transcode_fallback_original`。Android 同批已合入（去降级改空状态；另修发送方视频磨砂 / 先横后竖，见 im-android）。
**iOS 单测欠账专项**仍在进行（清单与逐项进度见 `docs/TEST_DEBT.md`；批 A/B、C1、C2 已做，剩 C3–C7 与批 D；约定：测试由我逐个写，不派并行子代理改测试目标）。

## 下一步

0. **相册选择器**：用户 2026-10-07 真机自测通过，无待办。**已知限制**：体积来自 `PHAssetResource` 的 `fileSize`（KVC），取不到时不置灰也不显总大小；无 VoiceOver 标签；Android/Web/桌面文案已重新生成（2026-10-07）。

1. **拆体量欠账（下次碰就必须先拆）**：`Network/IMSocketManager.m` 1589/1600（只准降不准升；方向按 CODING_STYLE §7 三档：帧编解码 / 重连退避 / 各业务 send-recv 分组各成协作对象或 category，新逻辑优先开 category）；`Database/IMDatabase.m` 1500/1500（已顶满，加列或新增前必须先拆），给 `im_conversation_local`/`im_message_local` 加列前先拆（参考 `IMDatabase+MuteState.m` / `IMDatabase+ClearFloor.m`；`writeCachedConversations:` 的整行 INSERT 是下一块该搬走的）。
2. `IMChatViewController.m` 的 `peerDisplayName` 仍有 `fallback:peerID`（会在聊天页标题露内部 uid 的边缘路径），按 UI.md「末级不是 uid」改。
3. 小项：`setupUI` 抽 `IMComposerBar`；遗留 P2（听筒切换/接力连播停止条/Web 转文字/语音发送接入 `IMMediaSendService` 常驻队列等，细节见 archive）。

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

## 关联工程 / 常用命令

- 后端 `/Users/dev/IOSProject/im-client/IMServer`；Web `/Users/dev/IOSProject/im-client/im-web`；Android `/Users/dev/IOSProject/im-client/im-android`。
- 构建：`xcodebuild -workspace IMProgram.xcworkspace -scheme IMProgram -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 装真机（iPhoneWork `00008120-000131121E50C01E`）：`xcodebuild … -destination 'id=<udid>' -derivedDataPath <dir> -allowProvisioningUpdates build` → `xcrun devicectl device install app --device <udid> <dir>/Build/Products/Debug-iphoneos/IMProgram.app`。首次连后端要允许「查找并连接本地网络设备」，登录页填 Mac 当前 LAN IP。
- 测试：唯一入口 `./scripts/test.sh`（体量门禁 + 编译 + `IMProgramTests`；`BUILD_ONLY=1` / `ONLY=<Class>` / `ONLY=<Class>/<test>`，三个坑见 `CLAUDE.md`「构建 / 测试」）。
- 真机日志：`xcrun devicectl device copy from --device iPhoneWork --domain-type appDataContainer --domain-identifier com.libeyond.IMProgram --source "Library/Caches/Logs/<file>.log" --destination <dst>`；通知扩展日志 `idevicesyslog -u <udid>` grep IMNotificationService。
- 完成定义 / 编码规范：见 `CLAUDE.md`、`CODING_STYLE.md`。
