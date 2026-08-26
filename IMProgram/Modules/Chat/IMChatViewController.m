//  IMChatViewController.m

#import "IMChatViewController.h"
#import "IMChatViewController+Private.h" // 私有类扩展（属性/协议）——与分文件 category 共享
#import "IMPasteImageTextField.h"     // 支持粘贴图片的输入框（#2）
#import "IMPendingMediaThumbnail.h"   // 本地待发媒体缩略图生成
#import "IMMainTabBarController.h" // im_refreshNavigationBar / kIMLiquidBarHeight
#import "IMChatBackgroundView.h"
#import "IMAlbumCell.h"
#import "IMBubbleCell.h"
#import "IMChatRecordCell.h"
#import "IMImageCell.h"
#import "IMLinkCardCell.h"
#import "IMSystemCell.h"
#import "Voice/IMVoiceBubbleCell.h" // P0 voice
#import "IMChatViewController+Voice.h"
#import "IMSocketManager.h"
#import "IMHTTPService.h"
#import "IMConversation.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMediaPlaceholder.h"   // 引用缩略 / 媒体库统一门控取图（真帧>thumb磨砂>图标）
#import "IMMediaViewerViewController.h"
#import "IMMediaPagerViewController.h"
#import "IMTextReaderViewController.h" // 超长文本全屏阅读器
#import "IMConversationMediaViewController.h"
#import "IMQRResultRouter.h" // 层3：本站邀请链接（/q/u、/q/g）App 内拦截走原生流程
#import "IMForwardPickerViewController.h"
#import "IMChatRecordViewController.h"
#import "IMMentionPickerViewController.h"
#import "IMReadReceiptViewController.h"
#import "IMMediaPicker.h"
#import "IMMediaExpiryRegistry.h" // 转发/保存失效守卫：曾可用媒体被服务端清理(404)→转出去对端必 404
#import "IMMediaUtil.h"
#import "IMMediaDownloadCoordinator.h" // 下载编排（门控/进度/落地，与详情页共用）
#import "IMDownloadProgress.h"
#import <QuickLook/QuickLook.h>
#import "IMPendingMediaStore.h"
#import "IMChunkedUploader.h"
#import "IMMediaSendService.h"
#import "IMFilePickerViewController.h"
#import "IMProtocol.h"
#import "IMMessageModel.h"
#import "IMUploadProgress.h"
#import "IMDatabase.h"
#import "IMMenuAction.h"
#import "IMPinnedMessage.h"
#import "IMChatBannerStack.h"
#import "UIViewController+IMToast.h"
#import "UIViewController+IMDeleteSheet.h" // 两档删除 sheet（与详情页共用）
#import "IMTheme.h"
#import "IMTimeUtil.h"
#import "IMAppearance.h"
#import "IMLog.h"
#import "IMGlass.h"
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <SafariServices/SafariServices.h>
#import "IMPopoverCard.h"

NSNotificationName const IMChatConversationClearedNotification = @"IMChatConversationClearedNotification";

#pragma mark - 聊天页

// 私有类扩展（属性/协议/指定初始化器）已移至 IMChatViewController+Private.h，
// 供本主实现文件与各分文件 category（+Media / +Menu / +Selection …）共享。

@implementation IMChatViewController {
    // push 到子页（如资料页）前保存输入框焦点态：回到本页时按需恢复，避免 iOS 在 push/pop
    // 交叠时段的 UIKeyboardWillChangeFrame 通知与自动 first-responder 恢复出现竞态，
    // 导致回来后键盘弹起但 inputBottom 停在 0（输入栏被键盘遮住）——该 bug 偶现于点头像去资料页再返回。
    BOOL _pushedWithKeyboardUp;
}

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID peerID:(NSString *)peerID
                     readSeq:(int64_t)readSeq unread:(NSInteger)unread peerReadSeq:(int64_t)peerReadSeq {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.hidesBottomBarWhenPushed = YES; // 进聊天页隐藏底部 TabBar（push 时全屏）
        _host = [host copy];
        _userID = [userID copy];
        _peerID = [peerID copy];
        _convID = IMConversationID(userID, peerID);
        IMDatabaseAccountContext *context = IMDatabase.sharedDatabase.currentAccountContext;
        if (![context.ownerUserID isEqualToString:userID]) {
            IMLogDatabase(@"聊天页账号与当前数据库上下文不一致 page_uid=%@ db_uid=%@",
                          userID, context.ownerUserID ?: @"(none)");
        }
        _databaseContext = [context.ownerUserID isEqualToString:userID] ? context : nil;
        _entryReadSeq = readSeq;
        _entryUnread = unread;
        _peerReadSeq = peerReadSeq;   // 进会话即用服务端已知对端已读位点播种（实时回执再往上推进）
        _maxReadReported = readSeq;   // 已读起点=进入前位点，仅在可见消息超过它时才上报
        _pendingReadSeq = readSeq;
        // 本地落库：进入即秒显历史。
        __block NSArray<IMMessageModel *> *cachedMessages = @[];
        NSString *convID = _convID; // 取局部，避免同步 block 隐式捕获 self（-Wimplicit-retain-self）
        [IMDatabase.sharedDatabase performWithAccountContext:_databaseContext block:^(IMDatabase *database) {
            cachedMessages = [database messagesForConv:convID];
        }];
        _messages = [cachedMessages mutableCopy];
        _seenConvSeqs = [NSMutableSet set];
        for (IMMessageModel *m in _messages) {
            if (m.convSeq > 0) { [_seenConvSeqs addObject:@(m.convSeq)]; }
        }
        _pendingPreviewLoading = [NSMutableSet set];
    }
    return self;
}

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID
                 groupConvID:(NSString *)convID groupName:(NSString *)name
                     readSeq:(int64_t)readSeq unread:(NSInteger)unread
                groupReadSeq:(int64_t)groupReadSeq {
    // 复用单聊指定初始化器（peerID 空），再覆写会话标识为群 topic_id。
    // 群聊没有单一对端，用「全员已读位点」播种 peerReadSeq：仅当 conv_seq ≤ 该位点（人人都读过）
    // 才显绿✓✓（双勾语义在群里的诚实版）。非实时——didReadConv 群聊分支直接 return，不靠回执推进。
    self = [self initWithHost:host userID:userID peerID:@"" readSeq:readSeq unread:unread peerReadSeq:groupReadSeq];
    if (self) {
        _isGroupChat = YES;
        _groupName = [name copy];
        _convID = [convID copy];
        // 指定初始化器按 IMConversationID(uid,"") 预载了错误会话，这里按群 convID 重载本地历史。
        __block NSArray<IMMessageModel *> *cachedMessages = @[];
        [IMDatabase.sharedDatabase performWithAccountContext:_databaseContext block:^(IMDatabase *database) {
            cachedMessages = [database messagesForConv:convID];
        }];
        _messages = [cachedMessages mutableCopy];
        [_seenConvSeqs removeAllObjects];
        for (IMMessageModel *m in _messages) {
            if (m.convSeq > 0) { [_seenConvSeqs addObject:@(m.convSeq)]; }
        }
    }
    return self;
}

/// 下载编排器懒加载：策略判定 / 门控态 / 点击路由 / 落地位置全在 `IMMediaDownloadCoordinator`
/// （与会话详情页共用同一份实现）。直接访问 _downloads ivar，故留在主实现文件（category 不可见 ivar）。
- (IMMediaDownloadCoordinator *)downloads {
    if (!_downloads) {
        _downloads = [[IMMediaDownloadCoordinator alloc] initWithHost:self.host
                                                             myUserID:self.userID
                                                              isGroup:self.isGroupChat];
        __weak typeof(self) ws = self;
        // 高频进度/门控内更新 → **就地**改可见 cell（绝不 reload）：这是"点下载页面卡死/列表跳变"的根因修复。
        _downloads.onProgress = ^(IMMessageModel *m, IMDownloadProgress *state) {
            [ws updateDownloadProgressForMessage:m state:state];
        };
        // 低频整条重配（下载完成/图片解除门控）→ reload 让 cellForRow 重跑，加载清晰图/▶/文件图标。
        _downloads.onStateChanged = ^(IMMessageModel *m) { [ws refreshRowForMessage:m]; };
    }
    return _downloads;
}

#pragma mark - 统一进会话入口（导航去重 + 折叠）

/// 计算「打开新聊天页」后的目标导航栈：截掉栈中**最底部**的聊天页及其之上的所有页（资料页等），
/// 把新聊天页接到它原来的位置——于是同一栈内至多一个聊天页，从聊天页返回直达其下方（通常是会话列表）。
/// 栈中无聊天页时即等价普通 push（返回原栈 + 新页）。isChatController 判定某页是否聊天页
/// （生产传 isKindOfClass:IMChatViewController；单测可注入假谓词，故抽为文件级纯函数便于回归）。
NSArray<UIViewController *> *IMChatCollapsedStack(NSArray<UIViewController *> *stack,
                                                 UIViewController *newChat,
                                                 BOOL (^isChatController)(UIViewController *vc)) {
    NSUInteger cut = NSNotFound;
    for (NSUInteger i = 0; i < stack.count; i++) {
        if (isChatController(stack[i])) { cut = i; break; }
    }
    NSMutableArray<UIViewController *> *result = [NSMutableArray array];
    [result addObjectsFromArray:(cut == NSNotFound ? stack : [stack subarrayWithRange:NSMakeRange(0, cut)])];
    if (newChat) { [result addObject:newChat]; }
    return result;
}

+ (nullable instancetype)existingChatForConvID:(NSString *)convID
                        inNavigationController:(nullable UINavigationController *)nav {
    if (convID.length == 0 || !nav) { return nil; }
    for (UIViewController *vc in nav.viewControllers.reverseObjectEnumerator) {
        if ([vc isKindOfClass:IMChatViewController.class]
            && [((IMChatViewController *)vc).convID isEqualToString:convID]) {
            return (IMChatViewController *)vc;
        }
    }
    return nil;
}

/// 统一去重/折叠核心：命中同会话则 pop 复用并刷新；否则折叠中间聊天页后落新页。
/// build 造新实例；seed 播种显示字段（复用与新建都调用，故对既有实例只覆盖 caller 提供的非空值，
/// 不清空已有好值）。位点参数（readSeq/unread/peerReadSeq…）在复用路径刻意忽略：旧实例自维护已读
/// 与位点，prepareForReuseEntry 会重锚到底部并标已读，比用可能过期的入参覆盖更可靠。
+ (nullable instancetype)openConvID:(NSString *)convID
              inNavigationController:(UINavigationController *)nav
                               build:(IMChatViewController *(^)(void))build
                                seed:(void (^)(IMChatViewController *chat))seed {
    if (!nav || convID.length == 0) { return nil; }
    IMChatViewController *existing = [self existingChatForConvID:convID inNavigationController:nav];
    if (existing) {
        seed(existing);
        // 命中的就是栈顶（如在群里点了本群的邀请链接）：用户已在目标会话且本页是活 delegate、数据实时，
        // 只补播种即可。不 pop（对栈顶是 no-op）也**不清定位标志**——此时 viewWillAppear 不会触发，
        // 清了标志会在下一次任意重布局/新消息时把正上翻历史的用户猛拉回底部。
        if (existing != nav.topViewController) {
            [existing prepareForReuseEntry];
            [nav popToViewController:existing animated:YES];
        }
        return existing;
    }
    IMChatViewController *chat = build();
    seed(chat);
    NSArray<UIViewController *> *target = IMChatCollapsedStack(nav.viewControllers, chat,
                                                              ^BOOL(UIViewController *vc) {
        return [vc isKindOfClass:IMChatViewController.class];
    });
    // 无聊天页可折叠 → 走标准 push（保留系统入场动画/手势）；否则整体替换栈（新页在顶，push 式动画）。
    if (target.count == nav.viewControllers.count + 1) {
        [nav pushViewController:chat animated:YES];
    } else {
        [nav setViewControllers:target animated:YES];
    }
    return chat;
}

+ (nullable instancetype)openInNavigationController:(nullable UINavigationController *)nav
                                               host:(NSString *)host
                                             userID:(NSString *)userID
                                             peerID:(NSString *)peerID
                                            readSeq:(int64_t)readSeq
                                             unread:(NSInteger)unread
                                        peerReadSeq:(int64_t)peerReadSeq
                                       peerNickname:(NSString *)peerNickname
                                      peerAvatarURL:(NSString *)peerAvatarURL {
    if (!nav || peerID.length == 0) { return nil; }
    return [self openConvID:IMConversationID(userID, peerID) inNavigationController:nav build:^{
        return [[self alloc] initWithHost:host userID:userID peerID:peerID
                                  readSeq:readSeq unread:unread peerReadSeq:peerReadSeq];
    } seed:^(IMChatViewController *chat) {
        // 单聊与群相反：非空即覆盖。聊天页对 peer 昵称/头像没有任何服务端刷新（页内值只来自
        // 更早的播种，可能过期），caller 的成员表/会话行快照永远 ≥ 页内值，覆盖才能修「对方改名」。
        if (peerNickname.length > 0) { chat.peerNickname = peerNickname; }
        if (peerAvatarURL.length > 0) { chat.peerAvatarURL = peerAvatarURL; }
    }];
}

+ (nullable instancetype)openInNavigationController:(nullable UINavigationController *)nav
                                               host:(NSString *)host
                                             userID:(NSString *)userID
                                        groupConvID:(NSString *)convID
                                          groupName:(NSString *)name
                                            readSeq:(int64_t)readSeq
                                             unread:(NSInteger)unread
                                       groupReadSeq:(int64_t)groupReadSeq
                                     groupAvatarURL:(NSString *)groupAvatarURL {
    if (!nav || convID.length == 0) { return nil; }
    return [self openConvID:convID inNavigationController:nav build:^{
        return [[self alloc] initWithHost:host userID:userID groupConvID:convID groupName:name
                                  readSeq:readSeq unread:unread groupReadSeq:groupReadSeq];
    } seed:^(IMChatViewController *chat) {
        // 群字段只填空缺、不覆盖：页内值可能已被 reloadGroupInfo 刷成服务端最新（caller 的会话行/群卡
        // 快照反而更旧，覆盖会把改过的群名退回旧名）；新实例初始化器已置名，fill-if-empty 语义等价。
        // 复用时的权威刷新交给 prepareForReuseEntry 里的 reloadGroupInfo。
        if (chat.groupName.length == 0 && name.length > 0) { chat.groupName = name; }
        if (chat.groupAvatarURL.length == 0 && groupAvatarURL.length > 0) { chat.groupAvatarURL = groupAvatarURL; }
    }];
}

/// 复用已在栈中的旧实例前的刷新（仅在实例非栈顶、即将真正 pop 时调用）：
/// ①按最新播种值重装标题/头像按钮（否则 seed 落在无人再读的属性上）；群聊再拉一次 reloadGroupInfo，
///   用服务端权威值纠正群名/头像/横幅（caller 快照与页内值都可能过期）；
/// ②清定位标志，让 pop 回来时像重新进入一样重锚到底部/未读，而非停在旧滚动位。
/// 被压期间错过的消息**不在这里合并**：pop 必触发 viewWillAppear，那里按 synced 游标守卫合并，
/// 避免此处无条件全量读库 + appear 再读一次的双重开销。
- (void)prepareForReuseEntry {
    if (self.isViewLoaded) {
        [self refreshDisplayIdentity];
        if (self.isGroupChat) { [self reloadGroupInfo]; }
    }
    self.didInitialPosition = NO;
    self.didInitialSettle = NO;
    // 重进语义=贴底：进入时的未读快照早已消化，清零让重锚走「无未读→精确贴底」分支；
    // 不清的话 firstUnreadRow 会拿冻结的 entryReadSeq 把用户锚回早已读过的旧「首条未读」。
    self.entryUnread = 0;
}

/// 按当前 peer*/group* 值重装标题与右上头像按钮（viewDidLoad 与复用刷新共用同一口径，避免漂移）。
- (void)refreshDisplayIdentity {
    [self updateTitle];
    if (self.isGroupChat) {
        [self installInfoAvatarButtonWithURL:self.groupAvatarURL seed:self.convID name:self.groupName action:@selector(groupInfoTapped)];
    } else {
        NSString *name = self.peerNickname.length ? self.peerNickname : self.peerID;
        [self installInfoAvatarButtonWithURL:self.peerAvatarURL seed:self.peerID name:name action:@selector(singleInfoTapped)];
    }
}

/// 从 SQLite 合并本会话里内存尚无的消息（按 conv_seq 去重，保留未上号的乐观发件 conv_seq==0）。
/// 仅在检测到落后时调用，避免每次 appear 全量重排。返回是否有新增。
- (BOOL)mergeMissedMessagesFromStore {
    NSString *convID = self.convID;
    __block NSArray<IMMessageModel *> *dbMessages = @[];
    if (![self performDatabaseOperation:^(IMDatabase *database) {
        dbMessages = [database messagesForConv:convID];
    }]) { return NO; }
    BOOL added = NO;
    for (IMMessageModel *m in dbMessages) {
        if (m.convSeq <= 0 || [self.seenConvSeqs containsObject:@(m.convSeq)]) { continue; }
        [self.seenConvSeqs addObject:@(m.convSeq)];
        [self.messages addObject:m];
        added = YES;
    }
    if (!added) { return NO; }
    [self sortMessagesInPlace];
    [self.tableView reloadData];
    // 合并的新消息可能落在视口外：重算 ↓N 徽标并推进可见位点已读（与 didReceiveMessage 同口径），
    // 否则用户停在历史位置时看不到任何「下面有新消息」的指示。
    [self markVisibleRowsRead];
    return YES;
}

/// 内存里已上号消息的最大 conv_seq（乐观发件 conv_seq==0 不计）。用于与 DB synced 游标比对判断是否落后。
- (int64_t)maxInMemoryConvSeq {
    int64_t maxSeq = 0;
    for (IMMessageModel *m in self.messages) {
        if (m.convSeq > maxSeq) { maxSeq = m.convSeq; }
    }
    return maxSeq;
}

- (BOOL)performDatabaseOperation:(void (^)(IMDatabase *database))operation {
    return [IMDatabase.sharedDatabase performWithAccountContext:self.databaseContext block:operation];
}

// 待发预览/进度归常驻发送服务持有（key=clientMsgID 全局唯一）：页面销毁重建后引用即接上状态。
- (NSMutableDictionary<NSString *, UIImage *> *)outboxPreviews { return IMMediaSendService.shared.previews; }
- (NSMutableDictionary<NSString *, IMUploadProgress *> *)outboxProgress { return IMMediaSendService.shared.progressMap; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    // 标题 + 右上头像按钮：与复用刷新共用 refreshDisplayIdentity 同一口径（列表透传的头像立即显真图、
    // 免闪首字母；群资料加载后再由 reloadGroupInfo 补正）。
    [self refreshDisplayIdentity];
    if (self.isGroupChat) {
        [self reloadGroupInfo];
        [self loadConvRemark]; // 群备注（G1）：进页拉一次，标题优先显备注
        // 群变更（邀请/移除/退群/转让/改名）→ 刷新标题/群资料；被移出 → 提示并退出本页。
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onGroupEvent:)
                                                   name:IMSocketDidReceiveGroupEventNotification object:nil];
        // 会话备注多端同步：本人在别处（本机详情页 / 其它端）改备注 → conv_update → 就地刷新标题。
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onConvUpdatedForRemark:)
                                                   name:IMSocketDidUpdateConversationNotification object:nil];
    }
    [self setupUI];
    // 系统通知会话（peerID=system）：进页即锁定输入栏（无群资料触发路径）。
    // 见 docs/SYSTEM_NOTICE_SESSION_DESIGN.md §5.2 / +PinnedBanner.m refreshComposerMuteState。
    if (!self.isGroupChat && [self.peerID isEqualToString:@"system"]) {
        [self refreshComposerMuteState];
    }
    [self reloadPinnedBanner]; // 置顶横幅（G0）：进会话拉一次，之后靠 msg_op 帧增量维护，不轮询
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appearanceChanged)
                                               name:IMAppearanceDidChangeNotification object:nil];
    [self observeKeyboard];
    // 消息操作（撤回/编辑/置顶，M4）：应用到本会话某条 → 就地刷新；我方操作被拒（超窗）→ 吐司。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMsgOpApplied:)
                                               name:IMSocketDidApplyMsgOpNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMsgOpRejected:)
                                               name:IMSocketDidRejectMsgOpNotification object:nil];
    // 任务2：消息被物理移除（为所有人删除 / 仅为我删除）→ 本会话则从列表删掉该条。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMessageRemoved:)
                                               name:IMSocketDidRemoveMessageNotification object:nil];
    // 任务2：返回按钮全局未读徽标——其它会话来新消息 / 已读位点变化时刷新数字（本会话已排除，不受影响）。
    // 走合并入口：消息成批到达时每条一次全表 SUM(unread) 是主线程阻塞浪费，0.12s 合并（同会话列表）。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scheduleBackUnreadBadgeRefresh)
                                               name:IMSocketDidReceiveMessageNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scheduleBackUnreadBadgeRefresh)
                                               name:IMSocketDidReceiveReadNotification object:nil];
    // 资料页清空聊天记录 → 本会话清空内存并刷新（否则返回聊天页仍显旧消息）。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onConversationCleared:)
                                               name:IMChatConversationClearedNotification object:nil];
    // 媒体/文件发送全程活在 IMMediaSendService（退出本页不中断）；本页只订阅它的通知渲染进度与结果。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMediaSendProgress:)
                                               name:IMMediaSendProgressDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMediaSendMetaChanged:)
                                               name:IMMediaSendMetaDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMediaSendDispatched:)
                                               name:IMMediaSendDidDispatchNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMediaSendFailed:)
                                               name:IMMediaSendDidFailNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMediaSendAck:)
                                               name:IMMediaSendAckNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMediaSendCancelled:)
                                               name:IMMediaSendDidCancelNotification object:nil];
}

#pragma mark - 生命周期 / 在线态

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 回前台抢回下载回调：一份共享下载任务只记一个回调对象，从详情页（看过同一文件）返回时回调可能被它接管，
    // 本页可见的下载进度条会停在旧值——这里让本页重新接管并就地刷新。
    if (_downloads) { [_downloads reattachActiveTasksForMessages:self.messages]; }
    IMSocketManager.sharedManager.delegate = self;
    // 同步当前真实连接态：socket 通常在会话列表页就已连上，进本页不会再触发 didChangeState，
    // 若不主动拉一次，connState 会停在默认值 → 标题误显「未连接」。
    self.connState = IMSocketManager.sharedManager.state;
    [self updateTitle];
    [self refreshBackUnreadBadge]; // 任务2：进页即显返回按钮全局未读徽标（全局总未读减当前会话）
    [IMSocketManager.sharedManager connectToHost:self.host userID:self.userID];
    // 登记本会话：以 SQLite 中“已连续同步完成”的位置为起点，不能用本地最大消息序号代替，
    // 否则只存有较新消息时会永久跳过前面的空洞。
    __block int64_t synced = 0;
    if (![self performDatabaseOperation:^(IMDatabase *database) {
        synced = [database syncedConvSeqForConv:self.convID];
    }]) { return; }
    [IMSocketManager.sharedManager trackConversation:self.convID syncedSeq:synced];
    // 跨 Tab 自愈：本页被压在别的 Tab 栈里期间，实时消息由网络层落库并推进本会话 synced 游标，但只投递给
    // 当时占用 delegate 的那个聊天页——本实例内存模型会落后。切回本 Tab 触发 appear 时，若 DB 游标已超过
    // 内存最大 conv_seq，就从库合并补齐（同栈已由折叠保证至多一个聊天页，此路径主要覆盖跨 Tab）。
    if (synced > [self maxInMemoryConvSeq]) { [self mergeMissedMessagesFromStore]; }
    // 在线态初始值改由 watch 回的 presence 快照提供（省掉每次进页一次 GET /users/{id}）：
    // watchUsers 注册即让服务端回一帧当前对端 presence，didChangePresenceForUser 渲染。首聊无会话也覆盖。
    // 兜底仍在：未连接时由 didChangeState 连上后补拉 + 重发 watch；对端离线时由 tick 每 2 分钟轮询。
    [self updatePeerWatch:YES];
    [self startPresenceTick];   // 在线态随时间推进（租约到期 / 「N 分钟前」递增），无事件可依赖
    [self reattachRunningUploads]; // 上传任务活在 uploader 单例里，回到本页要重新接管它的进度与完成回调
}

#pragma mark - 拉黑（微信式单向：拉黑者仍可发，故聊天页不拦输入；黑名单状态在通讯录管理）

// 微信式单向：拉黑者仍可给被拉黑者发消息（对方能收到），故聊天页不再拦输入/盖横幅。
// 是否拉黑、解除拉黑均在通讯录好友行（副标题"已拉黑" + 左滑"解除拉黑"）管理。

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // 在出现动画前、首次布局完成时即定位，避免"先显历史第一条→再滑到最新"的闪动。
    if (!self.didInitialPosition && self.messages.count > 0 && self.tableView.frame.size.height > 0) {
        [self positionInitialIfNeeded];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self positionInitialIfNeeded]; // 兜底：若 layout 时机未就绪（消息晚到），这里再定位一次
    // 进场动画结束、布局/safe-area inset 完全稳定后再校正一次定位（只做一次，#8）：
    // 无未读精确贴底、有未读重锚首条未读。不以 isNearBottom 为前提——估高偏差可超 80pt，
    // 首贴欠滚幅度恰恰会让该条件放弃修正；但必须只跑一次，否则从资料页等子页返回也会被强拉走。
    if (self.didInitialPosition && !self.didInitialSettle) {
        self.didInitialSettle = YES;
        NSInteger unreadRow = [self firstUnreadRow];
        if (unreadRow < 0) { [self scrollToAbsoluteBottom]; }
        else { [self anchorRowToTop:unreadRow]; }
    }
    // 可见即读：把定位后当前可见的消息标为已读（不滚动也算看到）。
    dispatch_async(dispatch_get_main_queue(), ^{ [self markVisibleRowsRead]; });
    // 从子页返回：如果离开前键盘是弹起态，回来后重新聚焦输入框——becomeFirstResponder 会触发
    // UIKeyboardWillChangeFrame 让 keyboardWillChange: 重新算 kbInset 并更新 inputBottom，
    // 保证输入栏跟着键盘一同抬起（而不是被键盘遮住）。放 viewDidAppear 而非 viewWillAppear：
    // 转场动画结束、self.view 已稳定在窗口坐标里，convertRect:fromView:nil 才能算对。
    if (_pushedWithKeyboardUp) {
        _pushedWithKeyboardUp = NO;
        [self.inputField becomeFirstResponder];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // 退出前同步落一次已读：可见即读的上报是 0.3s 节流的（scheduleReadFlush 用 weak 捕获，页面 pop 后
    // dealloc 会让待发窗口静默丢弃），若刚滚到新消息就退出，未到窗口的最终位点会漏报（DB 未推进、对端无回执）。
    // 这里同步补发（flushReadPosition 单调幂等，无新进展即 no-op）。
    [self flushReadPosition];
    [self dismissMentionPanel]; // 离开/推子页前收起内联 @面板，避免残留
    [self stopPresenceTick]; // 页面不可见就没必要重算；也避免 timer 拖住 VC 不释放
    // 推子页（资料页等）前先主动收键盘、离开时同步一次 inputBottom：iOS 在 push/pop 过渡期
    // 会自动 resign 又 restore first-responder，其间的 UIKeyboardWillChangeFrame 通知与本页
    // convertRect:fromView:nil 计算存在竞态——曾偶发「返回后键盘弹起但 inputBottom 停在 0，
    // 输入栏被键盘遮住」。这里强制清零，并按需在回来时恢复焦点，把行为收敛到确定路径。
    if (!self.isMovingFromParentViewController && self.inputField.isFirstResponder) {
        _pushedWithKeyboardUp = YES;
        [self.inputField resignFirstResponder];
    }
    if (self.isMovingFromParentViewController) {
        // 真正离开聊天页（非推子页）：退订对端在线态，服务端不再向本连接推它的 presence。
        // 推子页（资料页等）不退订——回来时 viewWillAppear 会幂等重发，中途保持关注更自然。
        [self updatePeerWatch:NO];
        // 不断开长连接：返回会话列表后仍需常驻接收新消息以实时刷新未读（见 IMConversationListViewController）。
        // 仅交还 delegate，避免离开后本页继续处理消息。
        if (IMSocketManager.sharedManager.delegate == self) {
            IMSocketManager.sharedManager.delegate = nil;
        }
    }
}

#pragma mark - UI

- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.allowsSelection = NO;
    // 点击引用消息 → 跳转原消息（M4-2）。tap 与滚动(pan)/长按共存；非引用消息点击无副作用。
    UITapGestureRecognizer *jumpTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleReplyJumpTap:)];
    jumpTap.cancelsTouchesInView = NO;
    [self.tableView addGestureRecognizer:jumpTap];
    self.tableView.estimatedRowHeight = 56; // 估高更准 → 进会话滚到底更稳，减少自适应高度引起的偏移
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundView = [IMChatBackgroundView new]; // Telegram 绿主题壁纸
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.tableView registerClass:IMBubbleCell.class forCellReuseIdentifier:@"bubble"];
    [self.tableView registerClass:IMSystemCell.class forCellReuseIdentifier:@"system"];
    [self.tableView registerClass:IMImageCell.class forCellReuseIdentifier:@"image"];
    [self.tableView registerClass:IMAlbumCell.class forCellReuseIdentifier:@"album"];        // 相册宫格（leader 行）
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"albumPad"]; // 相册从行（零高占位）
    [self.tableView registerClass:IMChatRecordCell.class forCellReuseIdentifier:@"record"];
    [self.tableView registerClass:IMLinkCardCell.class forCellReuseIdentifier:@"link"];
    [self.tableView registerClass:IMVoiceBubbleCell.class forCellReuseIdentifier:@"voice"]; // P0 voice
    [self.view addSubview:self.tableView];

    [self buildReplyBar]; // 引用/编辑预览条（两行版）——构造收在 +Compose（与其行为同处，兼顾主文件行数预算）

    // 粘贴图片预览条（引用条之下、输入栏之上；默认高度 0）：横向滚动的缩略图 chip，每张右上 ✕。
    self.pasteBar = [UIView new];
    self.pasteBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.pasteBar.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.pasteBar.clipsToBounds = YES;
    [self.view addSubview:self.pasteBar];
    UIScrollView *pasteScroll = [UIScrollView new];
    pasteScroll.translatesAutoresizingMaskIntoConstraints = NO;
    pasteScroll.showsHorizontalScrollIndicator = NO;
    [self.pasteBar addSubview:pasteScroll];
    self.pasteChipsStack = [UIStackView new];
    self.pasteChipsStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.pasteChipsStack.axis = UILayoutConstraintAxisHorizontal;
    self.pasteChipsStack.spacing = 10;
    self.pasteChipsStack.alignment = UIStackViewAlignmentCenter;
    [pasteScroll addSubview:self.pasteChipsStack];
    [NSLayoutConstraint activateConstraints:@[
        [pasteScroll.leadingAnchor constraintEqualToAnchor:self.pasteBar.leadingAnchor constant:12],
        [pasteScroll.trailingAnchor constraintEqualToAnchor:self.pasteBar.trailingAnchor constant:-12],
        [pasteScroll.topAnchor constraintEqualToAnchor:self.pasteBar.topAnchor],
        [pasteScroll.bottomAnchor constraintEqualToAnchor:self.pasteBar.bottomAnchor],
        [self.pasteChipsStack.leadingAnchor constraintEqualToAnchor:pasteScroll.contentLayoutGuide.leadingAnchor],
        [self.pasteChipsStack.trailingAnchor constraintEqualToAnchor:pasteScroll.contentLayoutGuide.trailingAnchor],
        [self.pasteChipsStack.topAnchor constraintEqualToAnchor:pasteScroll.contentLayoutGuide.topAnchor],
        [self.pasteChipsStack.bottomAnchor constraintEqualToAnchor:pasteScroll.contentLayoutGuide.bottomAnchor],
        [self.pasteChipsStack.heightAnchor constraintEqualToAnchor:pasteScroll.frameLayoutGuide.heightAnchor],
    ]];

    UIView *inputBar = [UIView new];
    self.inputBar = inputBar;
    inputBar.translatesAutoresizingMaskIntoConstraints = NO;
    inputBar.backgroundColor = UIColor.secondarySystemBackgroundColor;
    [self.view addSubview:inputBar];

    IMPasteImageTextField *pasteField = [IMPasteImageTextField new];
    __weak typeof(self) wsPaste = self;
    pasteField.onPasteImage = ^(UIImage *image) { [wsPaste appendPastedImage:image]; }; // 粘贴图片→预览条攒批→发送键统一发（#2）
    self.inputField = pasteField;
    self.inputField.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputField.placeholder = @"输入消息…";
    self.inputField.font = [UIFont systemFontOfSize:MAX(15, IMTheme.chatFontSize - 1)];
    self.inputField.returnKeyType = UIReturnKeySend;
    self.inputField.delegate = self;
    // 圆角胶囊输入框（Telegram 风格）。
    self.inputField.backgroundColor = UIColor.systemBackgroundColor;
    self.inputField.layer.cornerRadius = IMAppearance.shared.bubbleRadius;
    self.inputField.layer.borderWidth = 1;
    self.inputField.layer.borderColor = UIColor.separatorColor.CGColor;
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 0)];
    self.inputField.leftView = pad;
    self.inputField.leftViewMode = UITextFieldViewModeAlways;
    [self.inputField addTarget:self action:@selector(inputChanged) forControlEvents:UIControlEventEditingChanged];
    [inputBar addSubview:self.inputField];

    // Telegram 布局（v2.3 拍板）：＋（左）| 输入框（内嵌 😀 表情，rightView）| 🎙 / ➤（右缘，同槽互斥）。
    // 外部三键 ＋|框|🎙/➤ 覆盖"新增内容·打字·发出"，表情内嵌到输入框（输入方式切换）。
    UIImageSymbolConfiguration *barCfg = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightRegular];
    UIButton *voiceButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.voiceButton = voiceButton;
    voiceButton.translatesAutoresizingMaskIntoConstraints = NO;
    [voiceButton setImage:[UIImage systemImageNamed:@"waveform.circle" withConfiguration:barCfg] forState:UIControlStateNormal];
    voiceButton.tintColor = IMTheme.textSecondary;
    [voiceButton addTarget:self action:@selector(voiceTapped) forControlEvents:UIControlEventTouchUpInside];
    [inputBar addSubview:voiceButton];

    // 表情内嵌到输入框内右缘（UITextField.rightView）：24×24 面积，点击翻转 face↔keyboard 图标（无移位）。
    UIImageSymbolConfiguration *emojiCfg = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
    UIButton *emojiButton = [UIButton buttonWithType:UIButtonTypeSystem];
    emojiButton.frame = CGRectMake(0, 0, 32, 32); // rightView 大小；rightView 不参与 AutoLayout，须显式 frame
    [emojiButton setImage:[UIImage systemImageNamed:@"face.smiling" withConfiguration:emojiCfg] forState:UIControlStateNormal];
    emojiButton.tintColor = IMTheme.textSecondary;
    [emojiButton addTarget:self action:@selector(emojiTapped) forControlEvents:UIControlEventTouchUpInside];
    self.inputField.rightView = emojiButton;
    self.inputField.rightViewMode = UITextFieldViewModeAlways;

    UIButton *plusButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.plusButton = plusButton;
    plusButton.translatesAutoresizingMaskIntoConstraints = NO;
    [plusButton setImage:[UIImage systemImageNamed:@"plus.circle" withConfiguration:barCfg] forState:UIControlStateNormal];
    plusButton.tintColor = IMTheme.textSecondary;
    [plusButton addTarget:self action:@selector(toggleAttachPanel) forControlEvents:UIControlEventTouchUpInside];
    [inputBar addSubview:plusButton];

    // 圆形发送按钮（蓝底上箭头）。有内容时显示、与表情/加号互斥（#4）。
    UIButton *sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.sendButton = sendButton;
    sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightRegular];
    [sendButton setImage:[UIImage systemImageNamed:@"arrow.up.circle.fill" withConfiguration:cfg] forState:UIControlStateNormal];
    sendButton.tintColor = IMTheme.accent;
    [sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [inputBar addSubview:sendButton];

    // 右下角"↓N"悬浮跳转按钮（默认隐藏；滚离底部时出现，点按回到最新；CHAT_UX §7）。
    self.jumpButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.jumpButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *jcfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
    // 标准 Liquid Glass 圆钮（iOS26 原生玻璃自带按压放大；旧系统 gray() 降级）；不再手绘底色/阴影。
    UIButtonConfiguration *jumpConf = IMGlassButtonConfiguration();
    jumpConf.image = [UIImage systemImageNamed:@"chevron.down" withConfiguration:jcfg];
    jumpConf.cornerStyle = UIButtonConfigurationCornerStyleCapsule; // 40×40 frame → 圆形
    jumpConf.contentInsets = NSDirectionalEdgeInsetsZero;
    jumpConf.baseForegroundColor = IMTheme.textPrimary;
    self.jumpButton.configuration = jumpConf;
    self.jumpButton.hidden = YES;
    [self.jumpButton addTarget:self action:@selector(jumpTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.jumpButton];

    self.jumpBadge = [UILabel new];
    self.jumpBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.jumpBadge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.jumpBadge.textColor = UIColor.whiteColor;
    self.jumpBadge.backgroundColor = IMTheme.unreadBadge; // 与会话列表未读一致（蓝）
    self.jumpBadge.textAlignment = NSTextAlignmentCenter;
    self.jumpBadge.layer.cornerRadius = 9;
    self.jumpBadge.layer.masksToBounds = YES;
    self.jumpBadge.hidden = YES;
    [self.view addSubview:self.jumpBadge];

    // 顶部三横幅栈（G0 置顶 / G1 公告 / G3 入群申请）：浮在消息表之上、紧贴安全区顶（Glass 导航栏正下方）。
    // 视图/布局/高度→内边距/收起持久化全在 IMChatBannerStack；点击导航经 delegate 回本页。
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    self.bannerStack = [[IMChatBannerStack alloc] initWithHostView:self.view
                                                         topAnchor:guide.topAnchor
                                                          delegate:self
                                                           isGroup:self.isGroupChat
                                                            userID:self.userID
                                                            convID:self.convID];

    self.inputBottom = [inputBar.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[
        // 聊天背景和消息内容铺到状态栏下方；统一 Glass 导航栏叠加在内容之上。
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.replyBar.topAnchor],

        // 引用条：夹在消息区与粘贴条之间；默认高度 0（cancelReply/showReply 切换）。
        [self.replyBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.replyBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.replyBar.bottomAnchor constraintEqualToAnchor:self.pasteBar.topAnchor],
        (self.replyBarHeight = [self.replyBar.heightAnchor constraintEqualToConstant:0]),

        // 粘贴图预览条：夹在引用条与输入栏之间；默认高度 0（refreshPasteBar 切换）。
        [self.pasteBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.pasteBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.pasteBar.bottomAnchor constraintEqualToAnchor:inputBar.topAnchor],
        (self.pasteBarHeight = [self.pasteBar.heightAnchor constraintEqualToConstant:0]),

        [inputBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [inputBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.inputBottom,
        [inputBar.heightAnchor constraintEqualToConstant:56],

        // Telegram 布局（v2.3）：＋（最左）| 输入框（内嵌 😀，rightView）| 🎙 语音 / ➤ 发送（右缘，同槽互斥）。
        [plusButton.leadingAnchor constraintEqualToAnchor:inputBar.leadingAnchor constant:8],
        [plusButton.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [plusButton.widthAnchor constraintEqualToConstant:34],
        [plusButton.heightAnchor constraintEqualToConstant:36],
        [self.inputField.leadingAnchor constraintEqualToAnchor:plusButton.trailingAnchor constant:6],
        [self.inputField.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [self.inputField.heightAnchor constraintEqualToConstant:36],
        // 右缘：voice / send 同槽位（updateSendButtonVisibility 互斥切换 hidden）。
        [voiceButton.trailingAnchor constraintEqualToAnchor:inputBar.trailingAnchor constant:-8],
        [voiceButton.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [voiceButton.widthAnchor constraintEqualToConstant:36],
        [voiceButton.heightAnchor constraintEqualToConstant:36],
        [sendButton.trailingAnchor constraintEqualToAnchor:inputBar.trailingAnchor constant:-8],
        [sendButton.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [sendButton.widthAnchor constraintEqualToConstant:36],
        [sendButton.heightAnchor constraintEqualToConstant:36],

        [self.jumpButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.jumpButton.widthAnchor constraintEqualToConstant:36],  // 与搜索/多选玻璃钮一致 36pt
        [self.jumpButton.heightAnchor constraintEqualToConstant:36],
        [self.jumpBadge.centerXAnchor constraintEqualToAnchor:self.jumpButton.trailingAnchor constant:-5],
        [self.jumpBadge.centerYAnchor constraintEqualToAnchor:self.jumpButton.topAnchor constant:5],
        [self.jumpBadge.heightAnchor constraintEqualToConstant:18],
        [self.jumpBadge.widthAnchor constraintGreaterThanOrEqualToConstant:18],
    ]];
    // 向下钮底边=动态：默认贴 replyBar 顶；多选/搜索态改贴选择栏/搜索栏顶（堆叠不重叠，见 updateJumpButtonBottomAnchor）。
    self.jumpButtonBottom = [self.jumpButton.bottomAnchor constraintEqualToAnchor:self.replyBar.topAnchor constant:-12];
    self.jumpButtonBottom.active = YES;

    // Telegram 布局（v2.3）：输入框右缘恒贴右侧动作键（voice/send 同槽位），随空/非空切换。
    self.inputTrailToVoice = [self.inputField.trailingAnchor constraintEqualToAnchor:voiceButton.leadingAnchor constant:-4];
    self.inputTrailToSend = [self.inputField.trailingAnchor constraintEqualToAnchor:sendButton.leadingAnchor constant:-4];
    [self updateSendButtonVisibility]; // 初始（空）：显示 voice，隐藏 send

    // voice P0：把"按住语音钮 → 录音 → 松手发送 / 左滑取消"接线到 recorder + HUD（+Voice.m）。
    [self im_installVoicePressGesture];
    // voice P1：接力连播——一条语音自然播完后，自动播下一条未播的对方语音（同会话，遇非 voice 停）。
    [self im_installVoiceRelayObserver];
    [self im_installVoiceTranscriptObserver]; // 服务端转文字结果经 WS 回来（幂等）
}

/// Telegram 布局（v2.3）：输入框有内容 → 显示发送、隐藏语音；否则显示语音、隐藏发送。
/// ＋ 与 内嵌 😀 恒显（Telegram 一致）。注意：程序化改 text（回填/清空）不触发 EditingChanged，需在改后手动调用本方法。
- (void)updateSendButtonVisibility {
    BOOL hasContent = self.inputField.text.length > 0 || self.pendingPasteImages.count > 0;
    self.sendButton.hidden = !hasContent;
    self.voiceButton.hidden = hasContent; // voice/send 同槽位互斥
    self.inputTrailToVoice.active = !hasContent;
    self.inputTrailToSend.active = hasContent;
}

#pragma mark - 发送 / 接收

/// 输入变化 → 发「正在输入」（2s 节流，避免每次按键都发）。
- (void)inputChanged {
    [self updateSendButtonVisibility]; // 内容增删 → 切换发送/表情+加号（#4）
    [self maybePresentMentionPicker];  // 群聊键入 @ → 弹成员选择卡（M4-8）
    if (self.inputField.text.length == 0) { return; }
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (now - self.lastTypingSent > 2.0) {
        self.lastTypingSent = now;
        [IMSocketManager.sharedManager sendTypingForConv:self.convID];
    }
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendTapped];
    return NO;
}

#pragma mark - 辅助

/// 自己发送：刷新 + 始终贴底（贴底后 ↓N 自动隐藏）。
/// 用精确贴底而非 scrollToRow…Bottom：估高（56）下后者会停在真底部之上，
/// 发媒体/文件（真实行高远超估高）时表现为"没滚到最新消息"。
- (void)appendReloadAndScroll {
    // 自己发媒体/文件时，先插入乐观气泡（行高从估高 56 → 真实图/视频高，contentSize 骤增），
    // scrollToAbsoluteBottom 迭代收敛期间 scrollViewDidScroll 会以中间态偏移调用 updateJumpButton，
    // isNearBottom 短暂 false → ↓N 箭头闪一下、贴底后又消失。语义上"我自己发的消息"从不该触发"跳到底部"
    // 提示，这里给一个 0.5s 抑制窗口，让 updateJumpButton 在此期间保持隐藏。
    self.selfSendScrollGuardUntil = [NSDate timeIntervalSinceReferenceDate] + 0.5;
    [self.tableView reloadData];
    [self scrollToAbsoluteBottom];
    [self markVisibleRowsRead];
}


- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_presenceTickTimer invalidate]; // 兜底：正常路径已在 viewWillDisappear 停掉
}

@end
